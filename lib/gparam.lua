-- gparam.lua
-- the global page: what replaced the network view. E1 walks the list, E2/E3
-- move the one under the cursor coarse/fine -- the same shape voice.lua
-- already gave the sound page (§5.5), just for macros that reach every voice
-- at once instead of one.
--
-- eight rows, one page. seven knobs that reach every voice at once, and one
-- switch (Drums) that decides how far three of them reach.
--
-- it was ten for a while, because the gusts' shared delay line had nowhere
-- better to be: three rows about ONE family, sitting next to BPM and Scale
-- and pushing this list onto a second page. the gusts have a page of their
-- own now (lib/gust.lua's MACROS, K3 from here), the delay went with it, and
-- what is left fits the screen exactly -- eight widgets, no page dots.
--
-- two of these rows are renamed and nothing else about them changed. Scatter
-- is Rain: it is the knob that makes everything land a little off the grid
-- and then a lot, which is what weather does to a rhythm, and "scatter" was
-- a word about the mechanism rather than about the sound. Drops is Plonks,
-- for the same reason -- it is the per-strike detune, and what you hear when
-- you turn it up is notes plonking down slightly off where you left them.
--
-- each entry stores in whatever unit is natural to it (0..1 for a plain
-- knob, real semitones/bpm for the ones that are), rather than forcing
-- everything through a normalised store the way voice.PARAMS does -- Scale
-- is a list index, Pitch and BPM are real units, and pretending otherwise
-- would just move the conversion into every get/set instead of removing it.

local topology = wl("topology")
local state    = wl("state")

local gparam = {}

-- §4.1 E3 is the transport: the whole patch quantises against it at low
-- Rain, so it has to be reachable without diving into the list. norns' clock
-- reads its tempo from the clock_tempo param rather than from a setter, so
-- that is what gets written -- and it is guarded, because the offline test
-- harness has no params menu.
gparam.BPM_MIN, gparam.BPM_MAX = 20, 300

-- §4.3: with an external clock source selected (MIDI, Link or crow), the
-- tempo is not ours to set -- norns derives it from whatever is coming in,
-- and writing clock_tempo would either be ignored or fight the source. so
-- BPM becomes a readout: `set` refuses, and `text` says where the number is
-- coming from. norns' own clock_source param is the authority; the guard is
-- for the offline harness, which has no params menu.
function gparam.external_clock()
  if not (params and params.get) then return false end
  local ok, src = pcall(function() return params:get("clock_source") end)
  return ok and type(src) == "number" and src > 1
end

function gparam.set_bpm(v)
  if gparam.external_clock() then
    state.set_event("tempo is external", 0.8)
    return
  end
  state.global.bpm = util.clamp(v, gparam.BPM_MIN, gparam.BPM_MAX)
  if params and params.set then
    params:set("clock_tempo", state.global.bpm)
  end
  state.set_event(string.format("%.0f BPM", state.global.bpm), 0.8)
end

-- what the transport is actually running at, whoever is deciding it. an
-- external source moves clock.get_tempo() without ever calling set_bpm, so
-- the readout has to come from the clock rather than from our own copy.
function gparam.tempo()
  if gparam.external_clock() then
    return clock.get_tempo() or state.global.bpm or 120
  end
  return state.global.bpm or 120
end

-- Plonks: semitones of extra per-strike detune range at full knob, on top of
-- the 0.02 st floor every strike has always had (grove.on_strike) -- that
-- floor is what an unpatched voice's "breathing" was before this param
-- existed, and it stays, so Plonks=0 sounds like it always did.
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

-- the global Decay macro (below) reaches the GVOICE, GUST and SMP cells too
-- -- each of their decay_seconds() already folds voice.decay_mult_ratio() in,
-- same as voice.lua's own does, so this is the only other place that needs
-- to know they exist as well as the four corner voices.
local DECAY_MACRO_TYPES = {voice = true, GVOICE = true, GUST = true, SMP = true}

local function sounding_cells()
  local ids = {}
  for id, cell in topology.each() do
    if DECAY_MACRO_TYPES[cell.type] then table.insert(ids, id) end
  end
  return ids
end

-- the eight, in E1 order -----------------------------------------------------
-- `frac` is the screen's bar position, 0..1, kept separate from `get` since
-- bpm/scale/pitch don't store in 0..1 themselves.

gparam.PARAMS = {
  {
    key = "bpm", label = "BPM", glyph = "fader", coarse = 1, fine = 0.1,
    get = function() return gparam.tempo() end,
    set = function(v) gparam.set_bpm(v) end,
    text = function()
      if gparam.external_clock() then
        return string.format("%.0f ext", gparam.tempo())
      end
      return string.format("%.0f", gparam.tempo())
    end,
    frac = function()
      return (gparam.tempo() - gparam.BPM_MIN)
             / (gparam.BPM_MAX - gparam.BPM_MIN)
    end,
    push = function() end, -- set_bpm already pushes on every change
  },
  {
    key = "swing", label = "Swing", glyph = "swing", coarse = 1 / 80, fine = 1 / 500,
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
    -- (quantise.lua's reading of it). also scales the rhythm/field wildness
    -- rambler.lua and grove.lua used to read off Weather directly. the state
    -- key stays `scatter` -- it is read in five other files and the rename
    -- is a rename of the word on the panel, not of the mechanism.
    key = "scatter", label = "Rain", glyph = "rain", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.scatter or 0 end,
    set = function(v) state.global.scatter = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.scatter or 0) end,
    frac = function() return state.global.scatter or 0 end,
    push = function() end,
  },
  {
    key = "scale", label = "Scale", glyph = "word", coarse = 1, fine = 1,
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
    -- §5.2c: the boxed reading says "dorian"; the ticks under it say there
    -- are eleven of them and this is the fourth, which the box never could.
    glyph_data = function()
      return {idx = state.global.scale_i or 0, total = #wl("grove").SCALES + 1}
    end,
    push = function()
      -- a scale change is audible on every voice a field or Tune is
      -- currently holding off the root, so re-push them all immediately
      -- rather than waiting for the next strike/step.
      local grove = wl("grove")
      for _, id in ipairs(voices()) do grove.push_voice_now(id) end
      -- §2.11: a gust's note is quantised to this scale too, and unlike a
      -- voice it is not retuned by the next strike -- it is holding a pitch
      -- right now. so all ten are re-pushed rather than left stale.
      wl("gust").repush_pitch()
    end,
  },
  {
    key = "drops", label = "Plonks", glyph = "dots", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.drops or 0 end,
    set = function(v) state.global.drops = util.clamp(v, 0, 1) end,
    text = function() return string.format("%.2f", state.global.drops or 0) end,
    frac = function() return state.global.drops or 0 end,
    push = function()
      -- a voice needs nothing pushed here: grove.on_strike reads this live
      -- and re-tunes on every strike whatever it is set to, because a voice's
      -- detune has a floor (0.02 st) and so always has something to send.
      --
      -- a drum's does not. gvoice.strike_detune falls all the way to zero, so
      -- turning Plonks back down would otherwise leave the six heads sitting
      -- at whatever random pitch their last detuned strike put them on, with
      -- nothing to move them off it until something else pushed. six messages
      -- per detent, and only while the Drums row is on -- with it off there
      -- is nothing stale to correct.
      local gvoice = wl("gvoice")
      if gvoice.follows_global() then gvoice.repush_pitch() end
    end,
  },
  {
    key = "decay", label = "Decay", glyph = "ramp", coarse = 1 / 80, fine = 1 / 500,
    min = 0, max = 1,
    get = function() return state.global.decay_mult or 0.5 end,
    set = function(v) state.global.decay_mult = util.clamp(v, 0, 1) end,
    text = function() return string.format("x%.2f", wl("voice").decay_mult_ratio()) end,
    frac = function() return state.global.decay_mult or 0.5 end,
    push = function()
      -- reuse voice.lua's/gvoice.lua's own listeners rather than duplicating
      -- their bridge.voice_decay/g_decay calls here.
      for _, id in ipairs(sounding_cells()) do state.notify_decay_change(id) end
    end,
  },
  {
    key = "pitch", label = "Pitch", glyph = "marker", coarse = 1, fine = 0.1,
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
      -- a gust holds its pitch between presses rather than being retuned on
      -- the next strike, so a transpose has to be pushed to all ten now.
      wl("gust").repush_pitch()
      -- and, when the Drums row below is on, the six percussion cells hold
      -- theirs the same way -- nothing re-pushes a drum's pitch except this.
      wl("gvoice").repush_pitch()
    end,
  },
  {
    -- §4.1c the eighth row, and the one that is not a knob. three of the
    -- macros above -- Plonks, Decay, Pitch -- were written for the four
    -- corner voices, and Decay quietly grew to reach the drums, the gusts
    -- and the sample cells because a decay multiplier means the same thing
    -- to all of them. Plonks and Pitch never did, for a good reason: a kit
    -- that transposes with the tune and detunes on every hit is a particular
    -- musical choice rather than the obvious one, and making it the default
    -- would have taken the drums away from anyone using them as drums.
    --
    -- so it is a switch, and this is its seat -- the slot the gusts' delay
    -- line left when it went to its own page. on, the six G cells follow the
    -- global Plonks, Decay and Pitch exactly as the four voices do: struck
    -- notes land a little off, the whole kit transposes, and the Decay
    -- multiplier rides on their envelopes. off, they are as they were, which
    -- includes Decay -- gvoice.decay_seconds drops the multiplier with the
    -- other two rather than keeping one of the three attached, since a row
    -- that says "the globals reach the drums" and leaves one of them
    -- permanently on is a row that lies about what it does.
    key = "drums", label = "Drums", glyph = "flag",
    coarse = 1, fine = 1, min = 0, max = 1,
    get = function() return state.global.drum_macro and 1 or 0 end,
    set = function(v) state.global.drum_macro = (v >= 0.5) end,
    text = function() return state.global.drum_macro and "on" or "off" end,
    frac = function() return state.global.drum_macro and 1 or 0 end,
    push = function()
      -- both of the two things this flag changes without a strike: every
      -- drum's ring time (through the shared decay listener, same as the
      -- Decay row) and every drum's pitch.
      local gvoice = wl("gvoice")
      for id, cell in topology.each() do
        if cell.type == "GVOICE" then state.notify_decay_change(id) end
      end
      gvoice.repush_pitch()
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

-- §4.3: an external source has changed the tempo under us. keep our own copy
-- in step so that switching the clock source back to internal carries on from
-- what was last heard rather than snapping back to whatever was set before.
function gparam.adopt_tempo()
  local t = clock.get_tempo()
  if t then
    state.global.bpm = util.clamp(t, gparam.BPM_MIN, gparam.BPM_MAX)
  end
end

return gparam
