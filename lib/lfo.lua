-- lfo.lua
-- §2.12: the four LFO cells -- a free-running sine source per cell, and the
-- settings page for one.
--
-- an LFO is the plainest thing on the panel: a sine, always running, with one
-- knob (Speed). it has no sound of its own -- cabling it to a voice, an
-- exciter, the heartwood or a gust bends that cell's pitch/colour/core the
-- same way any other continuous stream would (dispatch.lua), and cabling it
-- to an Output cell makes it audible as a tone once Speed is turned up into
-- the audio range. "pick a destination" is nothing new: it is the same
-- hold/tap cable gesture every other cell uses, and the cable's own gain
-- (E3 on the held pair) is the depth. that leaves this module with exactly
-- one row to define.
--
-- the page is the same shape voice.lua/gvoice.lua/gust.lua expose -- PARAMS
-- with get/set/text/push, plus nudge/param/PARAM_COUNT -- so cellparam.lua
-- hands it to screenui and gridui through the one code path they already
-- have.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local lfo = {}

-- a genuine low-frequency range: slow enough at the bottom to move a sound
-- over the course of a whole phrase, fast enough at the top to sit in
-- tremolo/audio-rate cross-mod territory -- and, cabled straight to an
-- Output cell, to be heard as a plain sine tone.
lfo.RATE_MIN, lfo.RATE_MAX = 0.02, 20.0

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

-- log-mapped across the whole range: most of a slow modulator's useful travel
-- is in its bottom octave or two, same reasoning as gust's attack/decay.
function lfo.rate_hz(id)
  local v = state.get_vparam(id, "rate", 0.5)
  return lfo.RATE_MIN * ((lfo.RATE_MAX / lfo.RATE_MIN) ^ v)
end

lfo.PARAMS = {
  {
    key = "rate", label = "Speed", default = 0.5,
    get = vp_get("rate", 0.5), set = vp_set("rate"),
    text = function(id) return string.format("%.2f Hz", lfo.rate_hz(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.lfo_rate(cell.index, lfo.rate_hz(id))
    end,
  },
}

lfo.PARAM_COUNT = #lfo.PARAMS

function lfo.param(i)
  return lfo.PARAMS[util.clamp(i, 1, #lfo.PARAMS)]
end

function lfo.nudge(id, i, delta)
  local p = lfo.param(i)
  p.set(id, util.clamp(p.get(id) + delta, 0, 1))
  p.push(id)
  return p
end

function lfo.push_all(id)
  for _, p in ipairs(lfo.PARAMS) do p.push(id) end
end

function lfo.each()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "LFO" then table.insert(ids, id) end
  end
  return ids
end

-- §5.1: unlike every other family's indicator, an LFO has no discrete event
-- to flash on -- what it does instead is never stop, so the grid shouldn't
-- either. each cell keeps its own running phase, advanced in real time by
-- its own Speed every time anything asks to see it (gridui polls this at
-- grid_metro's rate, ~30 Hz) -- so the LED breathes through one full sine
-- cycle exactly as often as the audio does, at whatever rate the player has
-- it set to.
local last_t = {}
local phase = {}

function lfo.phase(id)
  local now = util.time()
  local t0 = last_t[id]
  if t0 == nil then
    phase[id] = 0
  else
    -- a clock that has gone backwards (a reload, the test harness rewinding
    -- its virtual time) reads as "no time passed" rather than winding the
    -- phase back through a negative turn.
    local dt = math.max(now - t0, 0)
    phase[id] = (phase[id] + lfo.rate_hz(id) * dt) % 1.0
  end
  last_t[id] = now
  return phase[id]
end

-- three non-overlapping bands (idle / cabled / open) so "cabled reads
-- brighter than idle" and "open brighter than cabled" hold at every point in
-- the cycle, not just at the peak -- and within each band, the sine itself is
-- what moves the LED, trough to peak and back, once per cycle.
local function pulse(lo, hi, swing)
  return util.clamp(math.floor(lo + swing * (hi - lo) + 0.5), 0, 15)
end

function lfo.level_at(id, base)
  base = base or 2
  local swing = (math.sin(lfo.phase(id) * 2 * math.pi) + 1) / 2
  if state.cell_edit == id then
    return pulse(11, 15, swing)
  elseif wl("patch").degree(id) > 0 then
    return pulse(base + 5, base + 8, swing)
  else
    return pulse(base, base + 2, swing)
  end
end

function lfo.init()
  for _, id in ipairs(lfo.each()) do
    lfo.push_all(id)
  end
end

return lfo
