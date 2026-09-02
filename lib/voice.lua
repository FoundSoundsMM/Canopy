-- voice.lua
-- voice state / param mapping, and the sound editor behind §5.5's voice
-- page. the grid overhaul's socket collapse folded the old T/P/M sockets'
-- own knobs (hardness, depth, balance) in here as three more rows -- there
-- is no socket left to carry them, and the sound page is where every other
-- cell type without one keeps its parameters.
--
-- the old Grain macro is gone. it morphed structure/damp/bright/drive
-- together behind one knob because there was nowhere to put four knobs; the
-- voice page is that somewhere, and a drum you can only shape through a
-- macro is a drum you cannot actually tune.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local voice = {}

-- §5.5 E3 (and E2) on the voice page: this sound's decay. 0.5 is the voice's
-- own default ring time (topology's `decay`, mirroring the SC voiceDefs
-- table); the knob sweeps two octaves of ratio either side of it, so Oak can
-- be cut down to a knock and Hazel stretched out into a bell without either
-- losing the spectrum that makes it itself -- the mode bank's
-- frequency-dependent damping still shortens the high modes relative to
-- whatever this sets.
voice.DECAY_OCTAVES = 2

-- seconds, for the engine and for the readouts.
function voice.decay_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "voice" then return nil end
  local d = state.get_decay(id)
  return cell.decay * (2 ^ ((d - 0.5) * 2 * voice.DECAY_OCTAVES))
             * voice.decay_mult_ratio()
end

-- §4.1 the global Decay macro: the same bipolar-octave shape as the per-voice
-- knob above, applied on top of every voice at once. 0.5 is x1 (no change).
function voice.decay_mult_ratio()
  local d = state.global.decay_mult or 0.5
  return 2 ^ ((d - 0.5) * 2 * voice.DECAY_OCTAVES)
end

-- how far off its root this voice is tuned, in semitones. grove.lua adds
-- whatever the cabled fields are doing on top of this.
--
-- the range is asymmetric: up tops out at two octaves, same as it always
-- has, but down now reaches three -- Oak's 55 Hz root can fall to well
-- under 10 Hz, deep enough to sit under a kick rather than just below a
-- bass note. only the down side moved, so a knob already parked above
-- centre sounds exactly as it did before.
voice.TUNE_UP_ST = 24
voice.TUNE_DOWN_ST = 36

function voice.tune_semitones(id)
  local v = state.get_vparam(id, "tune", 0.5)
  local span = (v >= 0.5) and voice.TUNE_UP_ST or voice.TUNE_DOWN_ST
  return (v - 0.5) * 2 * span
end

-- the eight, in E1 order --------------------------------------------------
-- each entry maps its stored 0..1 knob to a real unit, pushes that at the
-- engine, and prints itself. `get`/`set` exist because Decay does not live in
-- the vparam table -- it is the same number the E3-with-nothing-focused
-- gesture on a socket moves, and there must be exactly one of it.

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

voice.PARAMS = {
  {
    key = "tune", label = "Tune", glyph = "marker", default = 0.5,
    get = vp_get("tune", 0.5), set = vp_set("tune"),
    text = function(id) return string.format("%+.1f st", voice.tune_semitones(id)) end,
    push = function(id)
      -- pitch is grove's to send: it is the sum of this offset and every
      -- field cabled into the voice's P socket, and only grove knows the
      -- second half of that.
      wl("grove").push_voice_now(id)
    end,
  },
  {
    -- a short pitch drop on top of Tune, like a struck string starting
    -- sharp and settling, or (turned all the way up) an 808's own glide
    -- from a couple of octaves up down to the fundamental. 0 is a no-op --
    -- Tune alone still gives you the plain pitched hit it always has.
    key = "bend", label = "Bend", glyph = "bipolar", default = 0,
    get = vp_get("bend", 0), set = vp_set("bend"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "bend", 0)) end,
    push = function(id)
      bridge.voice_bend(topology.get(id).index - 1, state.get_vparam(id, "bend", 0))
    end,
  },
  {
    key = "decay", label = "Decay", glyph = "ramp", default = 0.5,
    get = function(id) return state.get_decay(id) end,
    set = function(id, v)
      state.decay[id] = util.clamp(v, 0, 1)
      return state.decay[id]
    end,
    text = function(id) return string.format("%.2f s", voice.decay_seconds(id)) end,
    push = function(id)
      bridge.voice_decay(topology.get(id).index - 1, voice.decay_seconds(id))
    end,
  },
  {
    key = "body", label = "Body", glyph = "peak", default = 0.5,
    get = vp_get("body", 0.5), set = vp_set("body"),
    -- harmonic at 0, free-free bar at 1: the difference between a drum with a
    -- pitch and a drum with a clang.
    text = function(id) return string.format("%.2f", voice.structure(id)) end,
    push = function(id)
      bridge.voice_structure(topology.get(id).index - 1, voice.structure(id))
    end,
  },
  {
    key = "damp", label = "Damp", glyph = "combs", default = 0.5,
    get = vp_get("damp", 0.5), set = vp_set("damp"),
    text = function(id) return string.format("%.2f", voice.damp(id)) end,
    push = function(id)
      bridge.voice_damp(topology.get(id).index - 1, voice.damp(id))
    end,
  },
  {
    key = "bright", label = "Bright", glyph = "tilt", default = 0.5,
    get = vp_get("bright", 0.5), set = vp_set("bright"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "bright", 0.5)) end,
    push = function(id)
      bridge.voice_bright(topology.get(id).index - 1, state.get_vparam(id, "bright", 0.5))
    end,
  },
  {
    key = "drive", label = "Drive", glyph = "knee", default = 0.25,
    get = vp_get("drive", 0.25), set = vp_set("drive"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "drive", 0.25)) end,
    push = function(id)
      bridge.voice_drive(topology.get(id).index - 1, state.get_vparam(id, "drive", 0.25))
    end,
  },
  {
    key = "strike", label = "Strike", glyph = "spike", default = 0.3,
    get = vp_get("strike", 0.3), set = vp_set("strike"),
    -- where on the bar the mallet lands: comb-notches whichever modes have a
    -- node there, which is most of what separates a rim from a centre hit.
    text = function(id) return string.format("%.2f", voice.position(id)) end,
    push = function(id)
      bridge.voice_pos(topology.get(id).index - 1, voice.position(id))
    end,
  },
  {
    key = "level", label = "Level", glyph = "fader", default = 0.7,
    get = vp_get("level", 0.7), set = vp_set("level"),
    text = function(id) return string.format("%.2f", voice.level(id)) end,
    push = function(id)
      bridge.voice_amp(topology.get(id).index - 1, voice.level(id))
    end,
  },
  {
    -- the collapsed point's strike-side knob: mallet hardness, read live at
    -- strike time (dispatch.lua) rather than pushed -- the same "takes
    -- effect on the next event" shape a TM cell's Prob/Drift/Bias rows use.
    -- used to live on the T socket's own character knob; there is no socket
    -- left to carry it, so it moved here.
    key = "hardness", label = "Hard", glyph = "spike", default = 0.5,
    get = vp_get("hardness", 0.5), set = vp_set("hardness"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "hardness", 0.5)) end,
    push = function() end,
  },
  {
    -- how far a field or a TM cell moves this voice's pitch -- the old P
    -- socket's own knob, 0..2 so the player can flatten the melody to
    -- nothing or double how wide it reads.
    key = "depth", label = "Depth", glyph = "span", default = 0.5,
    get = vp_get("depth", 0.5), set = vp_set("depth"),
    text = function(id) return string.format("%.2f", voice.depth(id)) end,
    push = function(id) wl("grove").push_voice_now(id) end,
  },
  {
    -- the old M socket's balance knob: 0 injects a cabled stream into the
    -- resonator as excitation, 1 lands it on the body as damping/brightness/
    -- structure bend, and everything between is a mix of the two.
    key = "balance", label = "Balance", glyph = "link", default = 0.5,
    get = vp_get("balance", 0.5), set = vp_set("balance"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "balance", 0.5)) end,
    push = function(id)
      bridge.voice_mod(topology.get(id).index - 1, state.get_vparam(id, "balance", 0.5))
    end,
  },
}

voice.PARAM_COUNT = #voice.PARAMS

-- real-unit mappings, shared by the push functions and the readouts --------

function voice.structure(id)
  local cell = topology.get(id)
  local base = (cell and cell.struct) or 0.5
  return util.clamp(base + (state.get_vparam(id, "body", 0.5) - 0.5) * 0.8, 0, 1.3)
end

function voice.damp(id)
  local cell = topology.get(id)
  local base = (cell and cell.damp) or 0.8
  return util.clamp(base + (state.get_vparam(id, "damp", 0.5) - 0.5) * 1.0, 0.2, 1.8)
end

function voice.position(id)
  return 0.02 + state.get_vparam(id, "strike", 0.3) * 0.48
end

-- the Depth knob in real units: 0..2, a plain multiplier on everything a
-- cabled field or TM cell does to this voice's pitch (grove.offset,
-- grove.hz). 0.5 on the stored 0..1 knob is 1x -- unchanged from what a
-- freshly patched voice always did.
function voice.depth(id)
  return state.get_vparam(id, "depth", 0.5) * 2
end

function voice.level(id)
  return state.get_vparam(id, "level", 0.7) * 1.4
end

function voice.param(i)
  return voice.PARAMS[util.clamp(i, 1, #voice.PARAMS)]
end

-- move one parameter by `delta` (in knob units) and push it.
function voice.nudge(id, i, delta)
  local p = voice.param(i)
  p.set(id, util.clamp(p.get(id) + delta, 0, 1))
  p.push(id)
  return p
end

function voice.push_all(id)
  for _, p in ipairs(voice.PARAMS) do p.push(id) end
end

function voice.init()
  for id, cell in topology.each() do
    if cell.type == "voice" then
      voice.push_all(id)
    end
  end
end

state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "voice" then
    bridge.voice_decay(cell.index - 1, voice.decay_seconds(id))
  end
end)

return voice
