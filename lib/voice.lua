-- voice.lua
-- voice state / param mapping, and the eight-parameter sound editor behind
-- §5.5's voice page. it also forwards the two voice sockets that have a
-- continuous engine-side meaning -- M's balance and O's tap level -- so
-- gridui never has to know which cell type talks to which command.
--
-- the old Grain macro is gone. it morphed structure/damp/bright/drive
-- together behind one knob because there was nowhere to put four knobs; the
-- voice page is that somewhere, and a drum you can only shape through a
-- macro is a drum you cannot actually tune.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local lexicon  = wl("lexicon")

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
end

-- how far off its root this voice is tuned, in semitones. grove.lua adds
-- whatever the cabled fields are doing on top of this.
function voice.tune_semitones(id)
  return (state.get_vparam(id, "tune", 0.5) - 0.5) * 48
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
    key = "tune", label = "Tune", default = 0.5,
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
    key = "decay", label = "Decay", default = 0.5,
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
    key = "body", label = "Body", default = 0.5,
    get = vp_get("body", 0.5), set = vp_set("body"),
    -- harmonic at 0, free-free bar at 1: the difference between a drum with a
    -- pitch and a drum with a clang.
    text = function(id) return string.format("%.2f", voice.structure(id)) end,
    push = function(id)
      bridge.voice_structure(topology.get(id).index - 1, voice.structure(id))
    end,
  },
  {
    key = "damp", label = "Damp", default = 0.5,
    get = vp_get("damp", 0.5), set = vp_set("damp"),
    text = function(id) return string.format("%.2f", voice.damp(id)) end,
    push = function(id)
      bridge.voice_damp(topology.get(id).index - 1, voice.damp(id))
    end,
  },
  {
    key = "bright", label = "Bright", default = 0.5,
    get = vp_get("bright", 0.5), set = vp_set("bright"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "bright", 0.5)) end,
    push = function(id)
      bridge.voice_bright(topology.get(id).index - 1, state.get_vparam(id, "bright", 0.5))
    end,
  },
  {
    key = "drive", label = "Drive", default = 0.25,
    get = vp_get("drive", 0.25), set = vp_set("drive"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "drive", 0.25)) end,
    push = function(id)
      bridge.voice_drive(topology.get(id).index - 1, state.get_vparam(id, "drive", 0.25))
    end,
  },
  {
    key = "strike", label = "Strike", default = 0.3,
    get = vp_get("strike", 0.3), set = vp_set("strike"),
    -- where on the bar the mallet lands: comb-notches whichever modes have a
    -- node there, which is most of what separates a rim from a centre hit.
    text = function(id) return string.format("%.2f", voice.position(id)) end,
    push = function(id)
      bridge.voice_pos(topology.get(id).index - 1, voice.position(id))
    end,
  },
  {
    key = "level", label = "Level", default = 0.7,
    get = vp_get("level", 0.7), set = vp_set("level"),
    text = function(id) return string.format("%.2f", voice.level(id)) end,
    push = function(id)
      bridge.voice_amp(topology.get(id).index - 1, voice.level(id))
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

-- the two sockets with a continuous engine-side meaning ---------------------

local function push_node(id, cell)
  local v = topology.get(cell.voice).index - 1
  local ch = lexicon.character(id)
  local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
  local value = state.get_character(id, cell, lo, hi)
  if cell.role == "mod" then
    bridge.voice_mod(v, value)
  elseif cell.role == "out" then
    bridge.voice_tap(v, value)
  end
  -- trig's hardness and pitch's depth are read at the moment they are used
  -- (dispatch's strike, grove's offset) rather than pushed, so there is
  -- nothing to forward for those two.
end

function voice.init()
  for id, cell in topology.each() do
    if cell.type == "voice" then
      voice.push_all(id)
    elseif cell.type == "node" then
      push_node(id, cell)
    end
  end
end

state.on_character_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "node" then push_node(id, cell) end
end)

state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "voice" then
    bridge.voice_decay(cell.index - 1, voice.decay_seconds(id))
  end
end)

return voice
