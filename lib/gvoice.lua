-- gvoice.lua
-- §2.7b: state / param mapping and the six-parameter sound page for the six
-- percussion cells. same shape as voice.lua's eight-parameter editor, and
-- deliberately not merged into it -- these are simple pinged/noise drums,
-- not the six-mode resonator bank the corner voices run, and a G cell has no
-- sockets at all, so there is nothing here to parallel Bend, Body, Damp,
-- Bright or Strike position with.
--
-- §4.1c added the other thing that reaches these six: the global Plonks,
-- Decay and Pitch macros, behind the Drums switch on the global page. see
-- gvoice.follows_global below for what that switch means and why it is one
-- switch rather than three.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local voice    = wl("voice")

local gvoice = {}

-- §4.1c whether the three global macros written for the corner voices --
-- Plonks, Decay and Pitch -- reach these six as well. it is the Drums row on
-- the global page (lib/gparam.lua), off by default, and it is deliberately
-- one switch over all three rather than three: a drum kit that follows the
-- patch's tuning and breathing is one idea, and picking it apart into three
-- rows would have made the common case ("make the kit part of the instrument")
-- three gestures instead of one.
--
-- Decay is included, which means turning this OFF shortens nothing and
-- lengthens nothing at the default -- decay_mult sits at 0.5, which is x1 --
-- but does detach the drums from the macro at any other setting. that is the
-- honest reading of a switch labelled "Drums: off"; the alternative, leaving
-- one of the three permanently attached, is a row that does not do what it
-- says.
function gvoice.follows_global()
  return state.global.drum_macro and true or false
end

-- same shape as voice.DECAY_OCTAVES: 0.5 is the cell's own default ring/
-- envelope time (topology's `decay`), and the knob sweeps two octaves of
-- ratio either side of it. the global Decay macro (§4.1) rides on top only
-- when the Drums row is on.
gvoice.DECAY_OCTAVES = 2

function gvoice.decay_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "GVOICE" then return nil end
  local d = state.get_decay(id)
  local mult = gvoice.follows_global() and voice.decay_mult_ratio() or 1
  return cell.decay * (2 ^ ((d - 0.5) * 2 * gvoice.DECAY_OCTAVES)) * mult
end

-- Pitch: ±2 octaves off the cell's own root/cutoff (topology's `root`),
-- straight semitones -> Hz, no separate glide -- there is no field able to
-- reach a G cell to make one matter. `extra` is the per-strike detune
-- (Plonks) when there is one; the global transpose is folded in here rather
-- than at the call site so every path to the engine carries it.
gvoice.PITCH_RANGE_ST = 24

function gvoice.pitch_hz(id, extra)
  local cell = topology.get(id)
  local v = state.get_vparam(id, "pitch", 0.5)
  local st = (v - 0.5) * 2 * gvoice.PITCH_RANGE_ST + (extra or 0)
  if gvoice.follows_global() then
    st = st + (state.global.pitch_offset or 0)
  end
  return (cell and cell.root or 440) * (2 ^ (st / 12))
end

-- one strike's worth of Plonks, in semitones, or nothing when the Drums row
-- is off. the same shape grove.on_strike gives a voice -- a bipolar random
-- offset whose width is the Plonks knob -- but without that function's 0.02 st
-- floor: a voice's floor is the "breathing" it has always had, and a drum
-- head that was dead still before this row existed has to stay dead still
-- with the row off, which means the whole thing has to fall to zero.
function gvoice.strike_detune()
  if not gvoice.follows_global() then return 0 end
  local drops = state.global.drops or 0
  if drops <= 0 then return 0 end
  return (math.random() * 2 - 1) * drops * wl("gparam").DROPS_MAX_ST
end

-- a pulse (or a K1+tap) has landed on this drum: retune it for this one hit,
-- then let the caller strike it. only actually sends anything when there is
-- something to send -- with the Drums row off, or Plonks at zero, a drum's
-- pitch has not moved since the last push and a second identical message per
-- strike is pure traffic.
function gvoice.on_strike(id)
  local d = gvoice.strike_detune()
  if d == 0 then return end
  local cell = topology.get(id)
  if cell then bridge.g_pitch(cell.index - 1, gvoice.pitch_hz(id, d)) end
end

-- the global Pitch macro, or the Drums row itself, has moved: a drum holds
-- its pitch between strikes the way a gust holds its note, so all six have
-- to be re-pushed rather than left until something hits them.
function gvoice.repush_pitch()
  for id, cell in topology.each() do
    if cell.type == "GVOICE" then
      bridge.g_pitch(cell.index - 1, gvoice.pitch_hz(id))
    end
  end
end

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

gvoice.PARAMS = {
  {
    key = "pitch", label = "Pitch", glyph = "marker", default = 0.5,
    get = vp_get("pitch", 0.5), set = vp_set("pitch"),
    -- the transpose this cell is actually sounding at, which with the Drums
    -- row on is the knob plus the global Pitch macro rather than the knob
    -- alone. same rule the gust page's Pitch row follows: the reading is
    -- where the cell has landed, not where the knob was left.
    text = function(id)
      local v = state.get_vparam(id, "pitch", 0.5)
      local st = (v - 0.5) * 2 * gvoice.PITCH_RANGE_ST
      if gvoice.follows_global() then
        st = st + (state.global.pitch_offset or 0)
      end
      return string.format("%+.1f st", st)
    end,
    push = function(id)
      local cell = topology.get(id)
      bridge.g_pitch(cell.index - 1, gvoice.pitch_hz(id))
    end,
  },
  {
    key = "decay", label = "Decay", glyph = "ramp", default = 0.5,
    get = function(id) return state.get_decay(id) end,
    set = function(id, v)
      state.decay[id] = util.clamp(v, 0, 1)
      return state.decay[id]
    end,
    text = function(id) return string.format("%.2f s", gvoice.decay_seconds(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.g_decay(cell.index - 1, gvoice.decay_seconds(id))
    end,
  },
  {
    -- ping: the mix-in of a detuned second partial (0 = pure fundamental).
    -- noise: brown <-> white colour and bandwidth (0 = dark and narrow).
    key = "tone", label = "Tone", glyph = "tilt", default = 0.5,
    get = vp_get("tone", 0.5), set = vp_set("tone"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "tone", 0.5)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.g_tone(cell.index - 1, state.get_vparam(id, "tone", 0.5))
    end,
  },
  {
    -- how much of the strike is transient: a harder, shorter click/attack at
    -- 1, a softer, slower one at 0.
    key = "punch", label = "Punch", glyph = "spike", default = 0.3,
    get = vp_get("punch", 0.3), set = vp_set("punch"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "punch", 0.3)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.g_punch(cell.index - 1, state.get_vparam(id, "punch", 0.3))
    end,
  },
  {
    key = "drive", label = "Drive", glyph = "knee", default = 0.2,
    get = vp_get("drive", 0.2), set = vp_set("drive"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "drive", 0.2)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.g_drive(cell.index - 1, state.get_vparam(id, "drive", 0.2))
    end,
  },
  {
    key = "level", label = "Level", glyph = "fader", default = 0.7,
    get = vp_get("level", 0.7), set = vp_set("level"),
    text = function(id) return string.format("%.2f", gvoice.level(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.g_amp(cell.index - 1, gvoice.level(id))
    end,
  },
}

gvoice.PARAM_COUNT = #gvoice.PARAMS

function gvoice.level(id)
  return state.get_vparam(id, "level", 0.7) * 1.4
end

function gvoice.param(i)
  return gvoice.PARAMS[util.clamp(i, 1, #gvoice.PARAMS)]
end

function gvoice.nudge(id, i, delta)
  local p = gvoice.param(i)
  p.set(id, util.clamp(p.get(id) + delta, 0, 1))
  p.push(id)
  return p
end

function gvoice.push_all(id)
  for _, p in ipairs(gvoice.PARAMS) do p.push(id) end
end

function gvoice.init()
  for id, cell in topology.each() do
    if cell.type == "GVOICE" then gvoice.push_all(id) end
  end
end

state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "GVOICE" then
    bridge.g_decay(cell.index - 1, gvoice.decay_seconds(id))
  end
end)

return gvoice
