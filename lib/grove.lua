-- grove.lua
-- pitch. what decides the note every pitched cell on the panel actually
-- sounds, and the one place all of it is ever summed (grove.hz).
--
-- this file used to be the §2.6 pitch fields as well -- four F cells, eight
-- modes, a wandering degree per cell that voices were cabled into. that
-- family is gone: the seats are sample players now (§2.5), and what is left
-- here is the half of it every other family depended on.
--
-- why the fields went. a field was a melody generator you patched, and the
-- panel has grown two others that do the job better and more legibly: a
-- Turing machine (§2.3b) answers a clock with a number you can see the shape
-- of, hold, and set the length of, and the global Scale decides what that
-- number lands on. a field did the same thing through eight named modes,
-- none of which was visible on the grid as anything but a brightness, and
-- four of which were variations on "randomly". nothing that was reachable
-- with a field is unreachable with a register and a scale; what was lost was
-- four seats, and a family of soundscape players wanted them.
--
-- what is here now:
--
--   * the SCALES (§4.1), and grove.quantise_semitones -- the final global
--     quantisation stage every pitch passes through;
--   * grove.note_name, which is what every Pitch row on the panel reads;
--   * PITCHED: the three families whose pitch runs through here -- the four
--     modal voices and the two synth families -- and the three things that
--     differ between them;
--   * grove.hz: root + the cell's own Tune + whatever registers are cabled
--     in + the global transpose + this strike's own detune, quantised as a
--     whole;
--   * grove.on_strike and grove.strike_detune (§4.1c Plonks);
--   * the per-voice SC-side detune drift, which is a \woodland_voice LFO and
--     is only set from here.
--
-- dependency note: dispatch.lua requires this file at load, so this one must
-- not require dispatch or rambler at load. both are fetched lazily inside
-- the functions that need them.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local bridge   = wl("bridge")

local grove = {}

-- semitones of continuous SC-side detune drift a voice carries. it used to be
-- a floor with a ceiling, because a wide field cabled in pushed it up; with
-- the fields gone it is simply the number, and it is why even an unpatched
-- voice never repeats a note exactly. this is a \woodland_voice LFO
-- (driftDepth/driftRate) rather than anything Lua sends per note: a
-- continuous few-cents wander pushed over OSC would be both chatty and steppy.
local DRIFT_BASE = 0.06

-- each voice's drift runs at its own irrational-ish rate so no two voices
-- breathe in step. index matches topology's voice index - 1.
local DRIFT_RATES = {0.061, 0.083, 0.047, 0.113, 0.037, 0.071}

-- glide sent with a strike-driven retune: short enough to land on the attack
-- rather than swooping into it, long enough not to zipper.
local STRIKE_GLIDE = 0.012

local last_hz = {}      -- voice_id -> the Hz last sent
local last_glide = {}   -- voice_id -> the glide last sent

-- scale ---------------------------------------------------------------------

-- nearest tone of `scale` to `x` semitones, searching the octave it lands in
-- and the one above (so a note just under an octave snaps up to it, not back
-- down to the seventh).
local function snap_to(x, scale)
  local oct = math.floor(x / 12)
  local rem = x - oct * 12
  local best, bd = 0, math.huge
  for _, s in ipairs(scale) do
    local d = math.abs(rem - s)
    if d < bd then bd, best = d, s end
  end
  if math.abs(rem - 12) < bd then return (oct + 1) * 12 end
  return oct * 12 + best
end

-- §4.1 Scale: a final, global quantisation stage every pitched cell's total
-- pitch passes through (grove.hz below), applied to the SUM -- root, Tune,
-- registers, transpose and this strike's own detune together -- rather than
-- to any one term of it, and unconditionally whenever a scale is selected.
-- index 0 is "free": the tuning is whatever it already was.
--
-- the first four were pentatonic only, on purpose: every one of them is a
-- five-note anhemitonic set, so nothing quantised to one could land a
-- semitone against itself. E.Pn1 and E.Pn2 are the two distinct 12-TET
-- roundings of a true five-equal-step (slendro-style) division of the octave
-- that aren't already major or minor pentatonic under some rotation.
--
-- the eight after them are not pentatonic and several are not in 12-TET at
-- all, which is the whole point of adding them. a degree here is a number of
-- SEMITONES, not a MIDI note, and nothing downstream ever rounded it -- so a
-- 3.5 is three and a half semitones and always was; the table simply never
-- had a fractional entry in it before. that is what lets the maqam and
-- dastgah rows carry their real neutral seconds and thirds (the koron/
-- half-flat degrees, three quarter-tones off the natural) rather than a
-- 12-TET impression of them, and it is what lets Slendro and Pelog be the
-- actual Javanese step sizes instead of the two roundings above.
--
-- the cost, stated plainly: a seven-note scale with a semitone in it CAN put
-- two voices a semitone apart, which the original four could not. that is a
-- fair trade for being able to play in Hijaz, and the four pentatonics are
-- still first in the list for anyone who wants the old guarantee.
--
--   Hijaz   the Arabic/Turkish jins with the augmented second -- 12-TET,
--           because Hijaz's own second degree is a genuine semitone
--   Rast    the central Arabic maqam: neutral third and neutral seventh
--   Bayat   Bayati/Shur -- neutral second, the commonest Persian colour
--   Sikah   built on the neutral third itself
--   Homay   Homayoun, the Persian dastgah: neutral second, major third
--   Slen    slendro, five equal steps of 240 cents
--   Pelog   the Javanese seven-tone set, its common five-note selection
--   Anchi   Anchihoye, an Ethiopian qenet -- a semitone above the root and
--           a semitone below the fifth's octave, which is what gives it its
--           particular lean
--
-- the names are abbreviations rather than words, and deliberately so: the
-- Scale row draws with `word` (lib/glyph.lua), whose box is 26px wide -- five
-- characters of norns' font. "Pent Maj" was clipped to "Pent " there, which
-- named the family and hid the only part that differed between the four. so
-- the shared half is the one that gets abbreviated, and every name below fits
-- five characters whole; index 0 stays the word "free".
grove.SCALE_NAMES = {
  "P.Maj", "P.Min", "E.Pn1", "E.Pn2",
  "Hijaz", "Rast", "Bayat", "Sikah", "Homay", "Slen", "Pelog", "Anchi",
}
grove.SCALES = {
  {0, 2, 4, 7, 9},                -- major pentatonic
  {0, 3, 5, 7, 10},               -- minor pentatonic
  {0, 2, 5, 7, 9},                -- equidistant pentatonic, rounding A
  {0, 2, 5, 8, 10},               -- equidistant pentatonic, rounding B
  {0, 1, 4, 5, 7, 8, 11},         -- Hijaz
  {0, 2, 3.5, 5, 7, 9, 10.5},     -- Rast: neutral 3rd and 7th
  {0, 1.5, 3, 5, 7, 8, 10},       -- Bayati / Shur: neutral 2nd
  {0, 1.5, 4, 5.5, 7, 9, 10.5},   -- Sikah: rooted on the neutral 3rd
  {0, 1.5, 4, 5, 7, 8, 11},       -- Homayoun
  {0, 2.4, 4.8, 7.2, 9.6},        -- slendro: five equal 240-cent steps
  {0, 1.2, 2.7, 6.7, 7.85},       -- pelog, the common five-note selection
  {0, 1, 5, 7, 8},                -- Anchihoye (Ethiopian qenet)
}

function grove.quantise_semitones(x)
  local i = state.global.scale_i or 0
  if i <= 0 then return x end
  local scale = grove.SCALES[i]
  if not scale then return x end
  return snap_to(x, scale)
end

-- note names (§5.2e) --------------------------------------------------------
-- every Pitch row on the panel used to print hertz. hertz is the number the
-- engine wants and the wrong number to read off a page: "329.6 Hz" and
-- "349.2 Hz" are a semitone apart and look nothing like it, and nobody
-- decides where to put a drone by comparing three-digit numbers. these are
-- notes, quantised to the Scale by the time they get here, so they are
-- printed as notes.
--
-- sharps rather than flats, and no key awareness: the panel's scales include
-- five that are not in 12-TET at all, so a spelling that tried to be correct
-- in a key would be inventing one. what the reading has to do is say which
-- note, unambiguously, in the four characters the value line has room for.
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

-- middle C is C4, so MIDI 60 is C4 and MIDI 0 is C-1 -- the scientific
-- convention norns' own params use.
local A4_HZ, A4_MIDI = 440.0, 69

-- how far off an equal-tempered note a pitch has to sit before the reading
-- says so. the microtonal scales (Rast's neutral third, slendro's 240-cent
-- step) land genuinely between two notes, and printing the nearer of the two
-- as though it were the note would be a reading that lies; a quarter-tone
-- mark after the name says "between here and the next one up" in one
-- character, which is all the room there is.
local QUARTER_TONE_C = 20

-- hz -> "A#3", or "E3+" for a pitch a quarter-tone sharp of one (and "-" for
-- flat). nil in, nil out, so a caller can hand this a pitch that does not
-- exist yet and print its own dash.
function grove.note_name(hz)
  if not hz or hz <= 0 then return nil end
  local midi = A4_MIDI + 12 * math.log(hz / A4_HZ) / math.log(2)
  local n = math.floor(midi + 0.5)
  local cents = (midi - n) * 100
  local name = NOTE_NAMES[(n % 12) + 1] .. tostring(math.floor(n / 12) - 1)
  if cents > QUARTER_TONE_C then return name .. "+" end
  if cents < -QUARTER_TONE_C then return name .. "-" end
  return name
end

-- engine forwarding --------------------------------------------------------------

-- §2.13 the pitched families, and what each of them answers to. this file
-- used to say "voice" everywhere and mean it; the two new synth families run
-- their pitch through exactly the same route -- a register cabled in tunes
-- them, the global transpose moves them, the global Scale has the last word
-- -- so the route is written once and the three differences per family are
-- in here.
--
-- `tune` is the cell's own pitch knob in semitones, `depth` the multiplier it
-- puts on whatever the cabled registers are doing, and `push` how
-- the Hz reaches the engine. `glide` and `drift` are optional and only a
-- modal voice has them: a mode bank's pitch moves under a note that is
-- already ringing, so portamento and a few cents of continuous wander are
-- part of what it is. an oscillator has no such need and gets neither.
local PITCHED = {
  voice = {
    tune  = function(id) return wl("voice").tune_semitones(id) end,
    depth = function(id) return wl("voice").depth(id) end,
    push  = function(cell, hz) bridge.voice_pitch(cell.index - 1, hz) end,
    glide = function(cell, secs) bridge.voice_glide(cell.index - 1, secs) end,
    drift = function(cell, depth, rate, seed)
      bridge.voice_drift(cell.index - 1, depth, rate, seed)
    end,
  },
  FM = {
    tune  = function(id) return wl("synth").tune_semitones(id) end,
    depth = function(id) return wl("synth").depth(id) end,
    push  = function(cell, hz) bridge.fm_pitch(cell.index - 1, hz) end,
  },
  VA = {
    tune  = function(id) return wl("synth").tune_semitones(id) end,
    depth = function(id) return wl("synth").depth(id) end,
    push  = function(cell, hz) bridge.va_pitch(cell.index - 1, hz) end,
  },
}

grove.PITCHED = PITCHED

-- is this a cell a register can tune? asked by tm.lua's own link rebuild and
-- by everything that walks the panel looking for something to push.
function grove.is_pitched(cell)
  return (cell and PITCHED[cell.type]) and true or false
end


-- the sound page's own Depth knob (the old P socket's knob, before the socket
-- collapse -- see voice.lua) is a multiplier on everything a cabled register
-- does to this voice: at 0 the cables are still there and still drawn, and the
-- voice sits on its root anyway; at 2 a narrow register reads as a wide one.
-- it is the per-voice answer to "that is too much melody".
function grove.depth(voice_id)
  local cell = topology.get(voice_id)
  local kind = cell and PITCHED[cell.type]
  return kind and kind.depth(voice_id) or 1
end

-- root, plus the sound editor's Tune (§5.5), plus whatever the TM cells
-- (§2.3b, lib/tm.lua) cabled to this cell are doing -- scaled by the same
-- depth knob the old P socket had -- plus the global Pitch macro, plus
-- whatever per-strike detune the caller passes in, and then, if Scale has
-- selected one, quantised AS A WHOLE. voice.lua owns Tune; this is the only
-- place all of them are ever summed, and quantising the sum rather than any
-- term of it is what makes the Scale the last word on the note.
function grove.hz(voice_id, extra_semitones)
  local cell = topology.get(voice_id)
  if not cell or not cell.root then return nil end
  local kind = PITCHED[cell.type]
  if not kind then return nil end
  local st = wl("tm").offset(voice_id) * grove.depth(voice_id)
             + kind.tune(voice_id)
             + (state.global.pitch_offset or 0) + (extra_semitones or 0)
  st = grove.quantise_semitones(st)
  return cell.root * (2 ^ (st / 12))
end

-- push one cell's pitch, if it actually moved. `glide` is the portamento to
-- ask for; nil means none -- a register steps, so a strike-driven retune wants
-- to land on the attack rather than swoop into it.
local function push_voice(voice_id, glide, extra)
  local cell = topology.get(voice_id)
  if not cell or not cell.root then return end
  local kind = PITCHED[cell.type]
  if not kind then return end

  -- only a modal voice has one: see PITCHED above.
  if kind.glide then
    glide = glide or 0
    if last_glide[voice_id] ~= glide then
      last_glide[voice_id] = glide
      kind.glide(cell, glide)
    end
  end

  local hz = grove.hz(voice_id, extra)
  if not hz then return end
  local prev = last_hz[voice_id]
  -- about a third of a cent: under what anyone can hear on a mode bank, so
  -- this drops redundant sends without ever throttling a real glide into a
  -- staircase.
  if prev and math.abs(hz - prev) < prev * 0.0002 then return end
  last_hz[voice_id] = hz
  kind.push(cell, hz)
end

-- the SC-side detune drift, pushed once per voice at init and never again:
-- it is a constant now (DRIFT_BASE) where it used to rise with the range of
-- whatever field was cabled in, and with the fields gone there is nothing
-- left to move it. it stays because it is the reason a bare, unpatched patch
-- does not sound like a sample being retriggered.
local function push_drift(voice_id)
  local cell = topology.get(voice_id)
  if not cell or not cell.root then return end
  -- only a modal voice has a drift: see PITCHED above.
  local kind = PITCHED[cell.type]
  if not kind or not kind.drift then return end
  kind.drift(cell, DRIFT_BASE, DRIFT_RATES[cell.index] or 0.07, cell.index)
end

-- strikes --------------------------------------------------------------------

-- §4.1c one strike's worth of Plonks, in semitones: a bipolar random offset
-- whose width is the global knob, on top of the 0.02 st floor every strike
-- has always had. that floor is what an unpatched voice's "breathing" was
-- before the Plonks row existed, which is why it is here and not zero the way
-- gvoice.strike_detune's is -- a drum head that was dead still has to stay
-- dead still, and a modal voice never was.
--
-- its own function because three families now want it: a modal voice
-- (on_strike, below), and the FM and VA cells, which sound their note with an
-- explicit Hz of their own and so cannot pick a detune up off a pitch push
-- (synth.play).
function grove.strike_detune()
  local drops = wl("gparam").DROPS_MAX_ST
  return (math.random() * 2 - 1) * (0.02 + (state.global.drops or 0) * drops)
end

-- called by dispatch immediately before a strike lands: retune the cell for
-- this one hit, so the note that sounds is the detuned one rather than the
-- one before it. STRIKE_GLIDE rather than zero on the modal voices, because a
-- bank of resonators re-tuned in one sample clicks.
function grove.on_strike(voice_id)
  push_voice(voice_id, STRIKE_GLIDE, grove.strike_detune())
end

-- voice.lua's Tune knob moved, so this voice's Hz did even though no field
-- did: the same path as everything else, entered from the sound editor.
function grove.push_voice_now(voice_id)
  push_voice(voice_id)
end

-- init and graph changes ------------------------------------------------------

-- push every pitched cell's pitch, glide and drift once at startup: a freshly
-- booted engine is at its SynthDef defaults and knows nothing about where the
-- knobs were left.
function grove.init()
  for id, cell in topology.each() do
    if grove.is_pitched(cell) then
      push_drift(id)
      push_voice(id)
    end
  end
end

-- a cable moved. tm.lua rebuilds its own links off the same hook and pushes
-- on its own steps, but nothing there re-pushes a cell whose LAST register
-- cable has just been pulled -- so this is what returns it to its root.
patch.on_change(function()
  for id, cell in topology.each() do
    if grove.is_pitched(cell) then push_voice(id) end
  end
end)

return grove
