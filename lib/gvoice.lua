-- gvoice.lua
-- §2.7b: state / param mapping and the six-parameter sound page for the six
-- percussion cells. same shape as voice.lua's eight-parameter editor, and
-- deliberately not merged into it -- these are simple pinged/noise drums,
-- not the six-mode resonator bank the corner voices run, and a G cell has no
-- sockets at all, so there is nothing here to parallel Bend, Body, Damp,
-- Bright or Strike position with.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local voice    = wl("voice")

local gvoice = {}

-- same shape as voice.DECAY_OCTAVES: 0.5 is the cell's own default ring/
-- envelope time (topology's `decay`), the knob sweeps two octaves of ratio
-- either side of it, and the global Decay macro (§4.1) rides on top just
-- like it does for the four corner voices -- "every voice" in that macro's
-- own description was never meant to stop at four.
gvoice.DECAY_OCTAVES = 2

function gvoice.decay_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "GVOICE" then return nil end
  local d = state.get_decay(id)
  return cell.decay * (2 ^ ((d - 0.5) * 2 * gvoice.DECAY_OCTAVES))
             * voice.decay_mult_ratio()
end

-- Pitch: ±2 octaves off the cell's own root/cutoff (topology's `root`),
-- straight semitones -> Hz, no separate glide -- there is no field able to
-- reach a G cell to make one matter.
gvoice.PITCH_RANGE_ST = 24

function gvoice.pitch_hz(id)
  local cell = topology.get(id)
  local v = state.get_vparam(id, "pitch", 0.5)
  local st = (v - 0.5) * 2 * gvoice.PITCH_RANGE_ST
  return (cell and cell.root or 440) * (2 ^ (st / 12))
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
    text = function(id)
      local v = state.get_vparam(id, "pitch", 0.5)
      return string.format("%+.1f st", (v - 0.5) * 2 * gvoice.PITCH_RANGE_ST)
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
