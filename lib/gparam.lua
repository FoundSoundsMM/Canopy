-- gparam.lua
-- the nine-parameter global page: what replaced the network view. E1 walks
-- the list, E2/E3 move the one under the cursor coarse/fine -- the same
-- shape voice.lua already gave the sound page (§5.5), just for macros that
-- reach every voice at once instead of one.
--
-- each entry stores in whatever unit is natural to it (0..1 for a plain
-- knob, real semitones/bpm for the ones that are), rather than forcing
-- everything through a normalised store the way voice.PARAMS does -- Scale
-- is a list index, Pitch and BPM are real units, and pretending otherwise
-- would just move the conversion into every get/set instead of removing it.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local gparam = {}

-- §4.1 E3 is the transport: the whole patch quantises against it at low
-- Rain, so it has to be reachable without diving into the list. norns' clock
-- reads its tempo from the clock_tempo param rather than from a setter, so
-- that is what gets written -- and it is guarded, because the offline test
-- harness has no params menu.
gparam.BPM_MIN, gparam.BPM_MAX = 20, 300

function gparam.set_bpm(v)
  state.global.bpm = util.clamp(v, gparam.BPM_MIN, gparam.BPM_MAX)
  if params and params.set then
    params:set("clock_tempo", state.global.bpm)
  end
  state.set_event(string.format("%.0f BPM", state.global.bpm), 0.8)
end

-- fixed for now; only the overall wet amount (Canopy) is exposed.
local CANOPY_SIZE, CANOPY_DAMP = 0.6, 0.5

-- Drops: semitones of extra per-strike detune range at full knob, on top of
-- the 0.02 st floor every strike has always had (grove.on_strike) -- that
-- floor is what an unpatched voice's "breathing" was before this param
-- existed, and it stays so Drops=0 sounds like today.
gparam.DROPS_MAX_ST = 1.5

-- global pitch: a straight transpose, both ways, wider than Tune's own span
-- since this is meant to move the whole patch rather than tune one voice.
gparam.PITCH_RANGE_ST = 24

local function voices()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "voice" then table.insert(ids, id) end
  end
  return ids
end

-- the nine, in E1 order ------------------------------------------------------
-- `frac` is the screen's bar position, 0..1, kept separate from `get` since
-- bpm/scale/pitch don't store in 0..1 themselves.

gparam.PARAMS = {
  {
    key = "bpm", label = "BPM", coarse = 1, fine = 0.1,
    get = function() return state.global.bpm or 120 end,
    set = function(v) gparam.set_bpm(v) end,
    text = function() return string.format("%.0f", state.global.bpm or 120) end,
    frac = function()
      return ((state.global.bpm or 120) - gparam.BPM_MIN)
             / (gparam.BPM_MAX - gparam.BPM_MIN)
    end,
    push = function() end, -- set_bpm already pushes on every change
  },
  {
    key = "swing", label = "Swing", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.swing or 0 end,
    set = function(v) state.global.swing = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.swing or 0) end,
    frac = function() return state.global.swing or 0 end,
    push = function() end, -- quantise.lua reads it live; nothing to forward
  },
  {
    -- §4.1's old Weather knob, upper half: how much a pulse's landing is
    -- displaced from the grid, growing to "nothing is held at all" at 1
    -- (quantise.lua's "rain" reading). also scales the rhythm/field
    -- wildness rambler.lua and grove.lua used to read off Weather directly.
    key = "rain", label = "Rain", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.rain or 0 end,
    set = function(v) state.global.rain = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.rain or 0) end,
    frac = function() return state.global.rain or 0 end,
    push = function() end,
  },
  {
    key = "scale", label = "Scale", coarse = 1, fine = 1,
    get = function() return state.global.scale_i or 0 end,
    set = function(v)
      local grove = wl("grove")
      state.global.scale_i = util.clamp(math.floor(v + 0.5), 0, #grove.SCALES)
    end,
    text = function()
      local i = state.global.scale_i or 0
      if i == 0 then return "free" end
      return wl("grove").SCALE_NAMES[i] or tostring(i)
    end,
    frac = function()
      local n = #wl("grove").SCALES
      return (n > 0) and ((state.global.scale_i or 0) / n) or 0
    end,
    push = function()
      -- a scale change is audible on every voice a field or Tune is
      -- currently holding off the root, so re-push them all immediately
      -- rather than waiting for the next strike/step.
      local grove = wl("grove")
      for _, id in ipairs(voices()) do grove.push_voice_now(id) end
    end,
  },
  {
    key = "drops", label = "Drops", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.drops or 0 end,
    set = function(v) state.global.drops = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.drops or 0) end,
    frac = function() return state.global.drops or 0 end,
    push = function() end, -- read live by grove.on_strike
  },
  {
    key = "decay", label = "Decay", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.decay_mult or 0.5 end,
    set = function(v) state.global.decay_mult = util.clamp(v, 0, 1) end,
    text = function() return string.format("x%.2f", wl("voice").decay_mult_ratio()) end,
    frac = function() return state.global.decay_mult or 0.5 end,
    push = function()
      -- reuse voice.lua's own listener rather than duplicating its
      -- bridge.voice_decay call here.
      for _, id in ipairs(voices()) do state.notify_decay_change(id) end
    end,
  },
  {
    key = "pitch", label = "Pitch", coarse = 1, fine = 0.1,
    get = function() return state.global.pitch_offset or 0 end,
    set = function(v)
      state.global.pitch_offset =
        util.clamp(v, -gparam.PITCH_RANGE_ST, gparam.PITCH_RANGE_ST)
    end,
    text = function() return string.format("%+.1f st", state.global.pitch_offset or 0) end,
    frac = function()
      return ((state.global.pitch_offset or 0) + gparam.PITCH_RANGE_ST)
             / (2 * gparam.PITCH_RANGE_ST)
    end,
    push = function()
      local grove = wl("grove")
      for _, id in ipairs(voices()) do grove.push_voice_now(id) end
    end,
  },
  {
    key = "compressor", label = "Comp", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.compressor or 0 end,
    set = function(v) state.global.compressor = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.compressor or 0) end,
    frac = function() return state.global.compressor or 0 end,
    push = function() bridge.compressor(state.global.compressor or 0) end,
  },
  {
    key = "canopy", label = "Canopy", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.canopy or 0 end,
    set = function(v) state.global.canopy = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.canopy or 0) end,
    frac = function() return state.global.canopy or 0 end,
    push = function()
      bridge.canopy(CANOPY_SIZE, CANOPY_DAMP, state.global.canopy or 0)
    end,
  },
}

gparam.PARAM_COUNT = #gparam.PARAMS

function gparam.param(i)
  return gparam.PARAMS[util.clamp(i, 1, #gparam.PARAMS)]
end

-- Scale is a list index, not a continuum, so it steps like gridui's rule
-- swap does (RULE_DETENTS there, gridui.lua:20-21): accumulate raw ticks and
-- move one entry per SCALE_DETENTS of them, so a normal flick moves one
-- scale rather than skipping past several.
local SCALE_DETENTS = 3
local scale_acc = 0

-- scale and bpm/pitch are real units or list indices, not 0..1 knobs, so
-- `coarse`/`fine` above are the actual step size in that param's own units
-- rather than a fraction of a normalised range -- unlike voice.nudge, this
-- clamps with each param's own min/max (nil meaning "no clamp", for bpm and
-- pitch which clamp themselves in `set`).
function gparam.nudge(i, delta, is_coarse)
  local p = gparam.param(i)
  if p.key == "scale" then
    scale_acc = scale_acc + delta
    while math.abs(scale_acc) >= SCALE_DETENTS do
      local step = (scale_acc > 0) and 1 or -1
      scale_acc = scale_acc - step * SCALE_DETENTS
      p.set(p.get() + step)
      p.push()
    end
    return p
  end
  local step = (is_coarse and p.coarse or p.fine) or p.coarse
  local v = p.get() + delta * step
  if p.min then v = util.clamp(v, p.min, p.max) end
  p.set(v)
  p.push()
  return p
end

function gparam.push_all()
  for _, p in ipairs(gparam.PARAMS) do p.push() end
end

-- adopt whatever tempo the clock is already on, so BPM starts from there
-- rather than snapping the transport to state.lua's default on load, then
-- push everything else at the engine.
function gparam.init()
  state.global.bpm = util.clamp(clock.get_tempo() or 120, gparam.BPM_MIN, gparam.BPM_MAX)
  gparam.push_all()
end

return gparam
