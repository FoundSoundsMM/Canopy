-- lib/grove.lua: pitch. what decides the note every pitched cell on the panel
-- actually sounds, and the one place all of it is summed.
--
-- this file used to be about the §2.6 pitch fields, because grove.lua used to
-- be. that family is gone -- its four seats are sample players now (§2.5) --
-- and what is checked here is the half of it every other family depended on:
-- that the SCALES quantise and that "free" does not, that a note prints as a
-- note rather than as hertz, that grove.hz sums the root, the cell's own Tune,
-- the registers cabled in and the global transpose and quantises the SUM,
-- that a strike carries Plonks and that a bare voice therefore never plays
-- the same note twice, that the SC-side drift is on for every modal voice and
-- for nothing else, and that pulling the last register cable hands a cell
-- back its own root.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("== grove ==")

local OAK_ROOT = 55

-- semitones between an emitted Hz and a cell's own fundamental
local function st(hz, root)
  return 12 * math.log(hz / (root or OAK_ROOT)) / math.log(2)
end

local function pitches_for(voice)
  local out = {}
  for _, c in ipairs(CALLS.voice_pitch) do
    if c.voice == voice then table.insert(out, c) end
  end
  return out
end

-- one D cell striking Oak, as fast as the metric gait will go, so a test can
-- get plenty of strikes out of a short virtual run.
local function knock_oak(M)
  M.rambler.set_gait("d.hob", "metric")
  M.patch.add("d.hob", "oak", 1.0)
  M.state.character["d.hob"] = 1.0  -- 4 x beat
end

print("\n-- the scale bank --")
do
  local M = fresh(1)
  check("a name for every scale",
        #M.grove.SCALE_NAMES == #M.grove.SCALES,
        #M.grove.SCALE_NAMES .. " names, " .. #M.grove.SCALES .. " scales")
  check("and every name fits the Scale row's five characters", (function()
    for _, n in ipairs(M.grove.SCALE_NAMES) do
      if #n > 5 then return false end
    end
    return true
  end)())

  -- degrees are SEMITONES, not MIDI notes, and several of them are not whole
  -- ones -- which is the whole reason the maqam and dastgah rows are here.
  check("every degree is inside one octave and ascending", (function()
    for _, scale in ipairs(M.grove.SCALES) do
      local last = -1
      for _, d in ipairs(scale) do
        if d < 0 or d >= 12 or d <= last then return false end
        last = d
      end
    end
    return true
  end)())
  check("and some of them are genuinely microtonal", (function()
    for _, scale in ipairs(M.grove.SCALES) do
      for _, d in ipairs(scale) do
        if d % 1 ~= 0 then return true end
      end
    end
    return false
  end)())
end

print("\n-- quantise: free is the identity, a scale is not --")
do
  local M = fresh(2)
  M.state.global.scale_i = 0
  check("free passes anything through",
        M.grove.quantise_semitones(3.7) == 3.7,
        tostring(M.grove.quantise_semitones(3.7)))

  -- minor pentatonic: 0 3 5 7 10. 3.7 is not a degree of it.
  M.state.global.scale_i = 2
  local q = M.grove.quantise_semitones(3.7)
  check("a scale pulls a value onto a degree", (function()
    local rem = q % 12
    for _, d in ipairs(M.grove.SCALES[2]) do
      if math.abs(rem - d) < 1e-9 then return true end
    end
    return false
  end)(), tostring(q))
  check("and to the nearest one", math.abs(q - 3) < 1e-9, tostring(q))

  -- a value just under an octave snaps UP to it rather than back down to the
  -- seventh, which is the whole of snap_to's second half.
  check("just under an octave snaps up to it",
        math.abs(M.grove.quantise_semitones(11.9) - 12) < 1e-9,
        tostring(M.grove.quantise_semitones(11.9)))
end

print("\n-- §5.2e a pitch reads as a note, not as hertz --")
do
  local M = fresh(3)
  check("A4 is A4", M.grove.note_name(440) == "A4",
        tostring(M.grove.note_name(440)))
  check("and the panel's own reference is A1",
        M.grove.note_name(55) == "A1", tostring(M.grove.note_name(55)))
  check("middle C is C4", M.grove.note_name(261.6256) == "C4",
        tostring(M.grove.note_name(261.6256)))
  check("sharps, not flats", M.grove.note_name(466.16) == "A#4",
        tostring(M.grove.note_name(466.16)))

  -- a quarter-tone off gets a mark rather than being rounded onto a note it
  -- is not on: the microtonal scales land genuinely between two. 40 cents
  -- rather than exactly 50, which is the boundary itself and belongs to
  -- whichever of the two names rounding picks.
  check("a quarter-tone sharp says so",
        M.grove.note_name(440 * (2 ^ (0.4 / 12))) == "A4+",
        tostring(M.grove.note_name(440 * (2 ^ (0.4 / 12)))))
  check("and a quarter-tone flat too",
        M.grove.note_name(440 * (2 ^ (-0.4 / 12))) == "A4-",
        tostring(M.grove.note_name(440 * (2 ^ (-0.4 / 12)))))
  -- a couple of cents off is still the note. every strike carries a detune,
  -- so a reading that flickered a mark on and off would be unreadable.
  check("a couple of cents off is still the note",
        M.grove.note_name(440 * (2 ^ (0.05 / 12))) == "A4",
        tostring(M.grove.note_name(440 * (2 ^ (0.05 / 12)))))

  check("nothing in, nothing out", M.grove.note_name(nil) == nil)
  -- every name has to fit the value line, which is five or six characters.
  check("and no name is longer than four characters", (function()
    for midi = 12, 120 do
      local n = M.grove.note_name(440 * (2 ^ ((midi - 69) / 12)))
      if not n or #n > 4 then return false end
    end
    return true
  end)())
end

print("\n-- which cells have a pitch at all --")
do
  local M = fresh(4)
  local want = {voice = true, FM = true, VA = true}
  check("the four modal voices and the two synth families, and nothing else",
        (function()
          for _, cell in M.topology.each() do
            local is = M.grove.is_pitched(cell)
            if is ~= (want[cell.type] or false) then return false end
          end
          return true
        end)())
  check("and a nil cell is not one", M.grove.is_pitched(nil) == false)
end

print("\n-- grove.hz sums the whole thing and quantises the sum --")
do
  local M = fresh(5)
  M.state.global.scale_i = 0
  M.state.global.pitch_offset = 0
  check("at rest a voice sits on its own root",
        math.abs(M.grove.hz("oak") - OAK_ROOT) < 1e-9,
        tostring(M.grove.hz("oak")))

  -- the sound page's Tune knob, in semitones. it is asymmetric (two octaves
  -- up, three down), so the step is taken off the half it is moving into.
  M.state.set_vparam("oak", "tune", 0.5 + 1 / (2 * M.voice.TUNE_UP_ST))
  check("Tune moves it by exactly that many semitones",
        math.abs(st(M.grove.hz("oak")) - 1) < 1e-6,
        string.format("%.4f st", st(M.grove.hz("oak"))))

  -- and the global transpose on top of it.
  M.state.global.pitch_offset = 12
  check("and the global Pitch macro transposes it further",
        math.abs(st(M.grove.hz("oak")) - 13) < 1e-6,
        string.format("%.4f st", st(M.grove.hz("oak"))))
  M.state.global.pitch_offset = 0

  -- the Scale has the last word, and has it on the SUM rather than on any one
  -- term: 1 st is not a degree of minor pentatonic and comes back as 0.
  M.state.global.scale_i = 2
  check("with a Scale on, the sum is quantised",
        math.abs(st(M.grove.hz("oak"))) < 1e-6,
        string.format("%.4f st", st(M.grove.hz("oak"))))

  -- a cell with no pitch of its own answers nothing rather than guessing.
  check("an unpitched cell has no Hz", M.grove.hz("e.bracken") == nil)
  check("nor does a cell that does not exist", M.grove.hz("nope") == nil)
end

print("\n-- §4.1c Plonks: every strike lands a little off --")
do
  local M = fresh(6)
  M.state.global.drops = 0
  local floor_max = 0
  for _ = 1, 400 do
    floor_max = math.max(floor_max, math.abs(M.grove.strike_detune()))
  end
  -- the floor is what an unpatched voice's breathing has always been. it does
  -- not fall to zero the way a drum head's does (gvoice.strike_detune): a
  -- modal voice was never dead still.
  check("at Plonks 0 there is still a floor", floor_max > 0 and floor_max <= 0.02,
        string.format("%.4f st", floor_max))

  M.state.global.drops = 1
  local wide_max = 0
  for _ = 1, 400 do
    wide_max = math.max(wide_max, math.abs(M.grove.strike_detune()))
  end
  check("and at Plonks 1 it widens to the macro's own range",
        wide_max > 1.0 and wide_max <= 0.02 + M.gparam.DROPS_MAX_ST,
        string.format("%.4f st", wide_max))
  M.state.global.drops = 0
end

print("\n-- a bare voice still never plays the same note twice --")
do
  local M = fresh(17)
  -- a global scale would quantise every one of these sub-semitone draws onto
  -- the same tone, which is what the Scale row is FOR and not what this test
  -- is about.
  M.state.global.scale_i = 0
  knock_oak(M)
  run(M, 4)
  local p = pitches_for(0)
  -- not exactly one per strike: the odd draw lands within a third of a cent
  -- of the last one and push_voice drops it as inaudible.
  check("a bare voice is retuned on all but the odd strike",
        #p >= #CALLS.strike * 0.7,
        #p .. " pitches for " .. #CALLS.strike .. " strikes")

  local same, lo, hi = 0, math.huge, -math.huge
  for i = 2, #p do
    if p[i].hz == p[i - 1].hz then same = same + 1 end
  end
  for _, c in ipairs(p) do
    local s = st(c.hz)
    lo, hi = math.min(lo, s), math.max(hi, s)
  end
  check("no two strikes land on the same pitch", same == 0, "repeats: " .. same)
  check("but it is a detune, not a transposition", math.max(-lo, hi) < 0.2,
        string.format("%.3f st", math.max(-lo, hi)))
end

print("\n-- the SC-side drift is on for every modal voice, and only those --")
do
  local M = fresh(19)
  M.grove.init()
  local depth = {}
  for _, c in ipairs(CALLS.voice_drift) do depth[c.voice] = c.depth end
  local n = 0
  for _ in pairs(depth) do n = n + 1 end
  check("every voice gets a drift depth at init", n == 4, "#" .. n)
  check("and it is small enough to read as wood, not as out of tune",
        (depth[0] or 0) > 0 and (depth[0] or 1) < 0.1,
        string.format("%.3f st", depth[0] or -1))

  -- it used to deepen under a wide field cabled in. there are no fields, so
  -- it is a constant -- and the four voices share it rather than each being
  -- given a number of its own.
  check("all four are on the same depth", (function()
    for v = 1, 3 do
      if math.abs((depth[v] or -1) - depth[0]) > 1e-9 then return false end
    end
    return true
  end)())

  -- §2.13 the FM and VA cells are oscillators: a portamento and a continuous
  -- few-cents wander are part of what a bank of ringing resonators is, and
  -- not part of what an oscillator is.
  check("and neither synth family gets one", (function()
    for _, c in ipairs(CALLS.voice_drift) do
      if c.voice > 3 then return false end
    end
    return true
  end)())
end

print("\n-- pulling the cable hands the cell back its own root --")
do
  local M = fresh(29)
  M.state.global.scale_i = 0
  -- a register is the pitch source now -- an R cell on the weave's turing
  -- rule (§2.3b), which always quantises to the Scale, or the minor
  -- pentatonic with Scale off, exactly like the TM cells it replaced.
  M.weave.set_rule("r.thicket", "turing")
  local edge = M.patch.add("r.thicket", "oak", 1.0)
  local moved = false
  for _ = 1, 12 do
    M.weave.pulse_in("r.thicket", 1, nil, 0)
    if math.abs(M.grove.hz("oak") - OAK_ROOT) > 1e-6 then moved = true end
  end
  check("the register has the voice somewhere else", moved,
        string.format("%.2f Hz", M.grove.hz("oak")))

  M.patch.remove_edge(edge.id)
  check("and severing it returns the voice to its fundamental",
        math.abs(M.grove.hz("oak") - OAK_ROOT) < 1e-9,
        string.format("%.3f Hz", M.grove.hz("oak")))
  check("and the engine was told, rather than left on the old note",
        math.abs(CALLS.voice_pitch[#CALLS.voice_pitch].hz - OAK_ROOT) < 1e-9,
        tostring(CALLS.voice_pitch[#CALLS.voice_pitch].hz))
end

report()
