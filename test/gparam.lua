-- build phase 6b/7: the global param page (§4.1, §5.2, lib/gparam.lua). that
-- E1/nudge/push behave like the sound page's own E1/E2/E3 (§5.5), that Scale
-- steps one entry per flick and quantises pitch only when it isn't free, and
-- that Drops and the global Decay/Pitch macros actually reach the engine.
-- Rain and Excite used to live here too; the four soundscape loops that
-- replaced them are test/mixer.lua's, and Excite has no successor at all.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local OAK = "oak"

local function last(list, pred)
  local out
  for _, c in ipairs(list) do if (not pred) or pred(c) then out = c end end
  return out
end

print("\n-- E1 walks the list, clamped at both ends --")
do
  local M = fresh(1)
  local n = M.gparam.PARAM_COUNT
  -- eight, which is exactly one screen of widgets (screenui's 4x2 grid). the
  -- gusts' three delay rows used to make it ten and push it onto a second
  -- page; they are on the gusts' own page now (test/gust.lua checks that end)
  -- and the seat they left is the Drums switch.
  check("eight params, one screen", n == 8, "#" .. n)
  check("bpm is first", M.gparam.PARAMS[1].key == "bpm")
  check("pitch is seventh", M.gparam.PARAMS[7].key == "pitch")
  check("and Drums closes the page", M.gparam.PARAMS[8].key == "drums",
        M.gparam.PARAMS[8].key)
  check("no soundscape rows are left here",
        (function()
          for _, p in ipairs(M.gparam.PARAMS) do
            if p.key:match("^rain") then return false end
          end
          return true
        end)())
end

print("\n-- BPM: coarse is 1/detent, fine is a tenth of that --")
do
  local M = fresh(3)
  local before = M.state.global.bpm
  M.gparam.nudge(1, 5, true)             -- coarse
  check("coarse moves it by whole bpm", M.state.global.bpm == before + 5,
        tostring(M.state.global.bpm))
  local mid = M.state.global.bpm
  M.gparam.nudge(1, 5, false)            -- fine
  check("fine moves it a tenth as far", math.abs(M.state.global.bpm - (mid + 0.5)) < 1e-9,
        tostring(M.state.global.bpm))
  M.gparam.nudge(1, -10000, true)
  check("clamped at the floor", M.state.global.bpm == M.gparam.BPM_MIN)
  M.gparam.nudge(1, 10000, true)
  check("clamped at the ceiling", M.state.global.bpm == M.gparam.BPM_MAX)
  check("and the norns clock followed it",
        clock.get_tempo() == M.state.global.bpm, tostring(clock.get_tempo()))
end

print("\n-- Swing/Scatter/Drops/Decay are plain 0..1 knobs --")
do
  local M = fresh(5)
  local keys = {"swing", "scatter", "drops", "decay"}
  for i, p in ipairs(M.gparam.PARAMS) do
    local want
    for _, k in ipairs(keys) do if p.key == k then want = true end end
    if want then
      M.gparam.nudge(i, 10000, true)
      check(p.key .. " clamps at 1", p.get() == 1, tostring(p.get()))
      M.gparam.nudge(i, -10000, true)
      check(p.key .. " clamps at 0", p.get() == 0, tostring(p.get()))
    end
  end
end

print("\n-- Scale starts on P.Maj, steps one entry per flick, and 0 is free --")
do
  local M = fresh(7)
  local scale_i = 4  -- Scale is BPM, Swing, Scatter, Scale
  check("starts on the major pentatonic, not free", M.state.global.scale_i == 1,
        tostring(M.state.global.scale_i))
  check("and that is what the row says", M.gparam.param(scale_i).text() == "P.Maj",
        M.gparam.param(scale_i).text())
  -- SCALE_DETENTS is 3 in gparam.lua; two ticks of 3 should not move it yet
  M.gparam.nudge(scale_i, -2, true)
  check("under one detent's worth: still P.Maj", M.state.global.scale_i == 1,
        tostring(M.state.global.scale_i))
  M.gparam.nudge(scale_i, -1, true)
  check("the third tick down lands on free", M.state.global.scale_i == 0,
        tostring(M.state.global.scale_i))
  check("which the row spells out", M.gparam.param(scale_i).text() == "free",
        M.gparam.param(scale_i).text())
  M.gparam.nudge(scale_i, 3, true)
  check("and a flick the other way returns to P.Maj", M.state.global.scale_i == 1,
        tostring(M.state.global.scale_i))
  M.gparam.nudge(scale_i, -300, true)
  check("clamped at 0, not negative", M.state.global.scale_i == 0)
  M.gparam.nudge(scale_i, 300, true)
  check("clamped at the last scale", M.state.global.scale_i == #M.grove.SCALES,
        tostring(M.state.global.scale_i))
  check("every scale name fits the `word` box", (function()
    for _, n in ipairs(M.grove.SCALE_NAMES) do
      if #n > 5 then return false end
    end
    return true
  end)())
end

print("\n-- Scale quantises grove.hz only when it isn't free --")
do
  local M = fresh(9)
  M.voice.init()
  local root = M.topology.get(OAK).root
  -- voice.tune_semitones: (v - 0.5) * 2 * TUNE_UP_ST(24) = 1.5 semitones at
  -- v = 0.5 + 1.5/48 -- unambiguously closer to the major pentatonic's 2 than
  -- its 0, unlike a round 1 semitone which ties between them.
  M.state.set_vparam(OAK, "tune", 0.5 + (1.5 / 48))
  M.state.global.scale_i = 0
  local free_hz = M.grove.hz(OAK)
  check("1.5 semitones up, unquantised",
        math.abs(free_hz - root * 2 ^ (1.5 / 12)) < 1e-6, string.format("%.3f", free_hz))

  -- major pentatonic is SCALES[1]: {0,2,4,7,9}. 1.5 semitones off the root
  -- snaps to the nearest scale tone, which is 2 (a whole tone up).
  M.state.global.scale_i = 1
  local snapped_hz = M.grove.hz(OAK)
  check("quantised, it snaps to the nearest scale tone",
        math.abs(snapped_hz - root * 2 ^ (2 / 12)) < 1e-6, string.format("%.3f", snapped_hz))
end

print("\n-- Drops widens the per-strike detune range --")
do
  -- on_strike's detune only shows up in what actually reaches the engine
  -- (grove.hz(id) with no explicit `extra` doesn't see it), so this reads
  -- CALLS.voice_pitch rather than recomputing grove.hz itself.
  local function strike_span(drops, seed)
    local M = fresh(11)
    M.voice.init()
    M.state.global.drops = drops
    math.randomseed(seed)
    CALLS.voice_pitch = {}
    for _ = 1, 60 do M.grove.on_strike(OAK) end
    local lo, hi = math.huge, -math.huge
    for _, c in ipairs(CALLS.voice_pitch) do
      if c.voice == 0 then lo, hi = math.min(lo, c.hz), math.max(hi, c.hz) end
    end
    local root = M.topology.get(OAK).root
    return (hi - lo) / root
  end

  local span0 = strike_span(0, 2)
  local span1 = strike_span(1.0, 2)
  check("Drops=1 spreads strikes wider than Drops=0", span1 > span0,
        string.format("%.4f vs %.4f", span0, span1))
end

print("\n-- global Decay multiplies every voice's ring time --")
do
  local M = fresh(13)
  M.voice.init()
  local base = M.voice.decay_seconds(OAK)
  check("0.5 is x1", math.abs(M.gparam.PARAMS[6].get() - 0.5) < 1e-9)
  M.state.global.decay_mult = 1.0
  check("all the way up is x4", math.abs(M.voice.decay_seconds(OAK) - base * 4) < 1e-6,
        string.format("%.3f s", M.voice.decay_seconds(OAK)))
  M.state.global.decay_mult = 0.0
  check("all the way down is x0.25", math.abs(M.voice.decay_seconds(OAK) - base / 4) < 1e-6,
        string.format("%.3f s", M.voice.decay_seconds(OAK)))
  M.state.global.decay_mult = 0.5

  -- the push side: nudging it re-pushes every voice via the existing
  -- decay-change listener rather than a duplicate bridge call -- and, since
  -- the re-cut's re-cut, every G cell too (§2.7b).
  M.gvoice.init()
  CALLS.voice_decay = {}
  CALLS.g_decay = {}
  M.gparam.nudge(6, 10, true)
  check("decay push reached the engine for all four voices",
        #CALLS.voice_decay >= 4, "#" .. #CALLS.voice_decay)
  check("and for all six G cells",
        #CALLS.g_decay >= 6, "#" .. #CALLS.g_decay)
end

print("\n-- global Pitch transposes every voice, and pushes immediately --")
do
  local M = fresh(17)
  M.voice.init()
  local root = M.topology.get(OAK).root
  check("0 is a no-op", math.abs(M.grove.hz(OAK) - root) < 1e-6)
  CALLS.voice_pitch = {}
  M.gparam.nudge(7, 12, true)             -- +12 semitones, one octave
  check("an octave up doubles the Hz",
        math.abs(M.state.global.pitch_offset - 12) < 1e-9,
        tostring(M.state.global.pitch_offset))
  check("and it reached the engine without a strike",
        last(CALLS.voice_pitch, function(c) return c.voice == 0 end) ~= nil)
  local c = last(CALLS.voice_pitch, function(c) return c.voice == 0 end)
  check("at the doubled frequency", math.abs(c.hz - root * 2) < 1e-3,
        string.format("%.3f", c.hz))
end

-- §4.3 --------------------------------------------------------------------

print("\n-- an external clock source makes BPM a readout --")
do
  local M = fresh(21)
  M.gparam.nudge(1, 5, true)
  local set_internally = M.state.global.bpm
  check("internal: the row moves the tempo", set_internally == 125,
        tostring(set_internally))
  check("and says so plainly", M.gparam.PARAMS[1].text() == "125",
        M.gparam.PARAMS[1].text())

  params:set("clock_source", 2)          -- MIDI
  check("gparam notices", M.gparam.external_clock())
  M.gparam.nudge(1, 40, true)
  check("the row no longer moves the tempo", clock.get_tempo() == 125,
        tostring(clock.get_tempo()))
  check("and our own copy is untouched too", M.state.global.bpm == 125,
        tostring(M.state.global.bpm))
  check("the readout says where the number comes from",
        M.gparam.PARAMS[1].text() == "125 ext", M.gparam.PARAMS[1].text())

  -- the source moves the tempo under us
  TEMPO = 90
  check("and reads the clock, not the stored copy", M.gparam.tempo() == 90,
        tostring(M.gparam.tempo()))
  M.gparam.adopt_tempo()
  check("adopting it keeps the stored copy in step", M.state.global.bpm == 90,
        tostring(M.state.global.bpm))

  params:set("clock_source", 1)
  check("back on internal, the row moves again",
        (function() M.gparam.nudge(1, 5, true); return M.state.global.bpm end)() == 95,
        tostring(M.state.global.bpm))
end

-- §4.1c --------------------------------------------------------------------

print("\n-- Drums: whether the global macros reach the six percussion cells --")
do
  local M = fresh(23)
  local DRUMS = 8
  local KNAP = (function()
    for id, cell in M.topology.each() do
      if cell.type == "GVOICE" then return id end
    end
  end)()

  check("off by default", M.state.global.drum_macro == false,
        tostring(M.state.global.drum_macro))
  check("and the row says so", M.gparam.param(DRUMS).text() == "off",
        M.gparam.param(DRUMS).text())

  -- Pitch: with the row off a drum ignores the global transpose entirely.
  local root = M.topology.get(KNAP).root
  M.state.global.pitch_offset = 12
  check("off: a drum ignores the global transpose",
        math.abs(M.gvoice.pitch_hz(KNAP) - root) < 1e-6,
        string.format("%.3f vs %.3f", M.gvoice.pitch_hz(KNAP), root))

  -- Decay: same. decay_mult away from its x1 centre must not move a drum
  -- while the row is off -- which is the half of this switch that is a
  -- behaviour CHANGE rather than an addition, since Decay used to reach the
  -- drums unconditionally.
  local base_d = M.gvoice.decay_seconds(KNAP)
  M.state.global.decay_mult = 1.0
  check("off: a drum ignores the global Decay macro",
        math.abs(M.gvoice.decay_seconds(KNAP) - base_d) < 1e-9,
        string.format("%.4f vs %.4f", M.gvoice.decay_seconds(KNAP), base_d))

  -- Plonks: no per-strike detune, and -- just as important -- no message.
  M.state.global.drops = 1.0
  check("off: no per-strike detune", M.gvoice.strike_detune() == 0)
  CALLS.g_pitch = {}
  M.gvoice.on_strike(KNAP)
  check("off: and a strike sends no pitch at all", #CALLS.g_pitch == 0,
        "#" .. #CALLS.g_pitch)

  -- now turn it on, through the row rather than the flag, so the row's own
  -- set/push are what is under test.
  CALLS.g_pitch = {}
  CALLS.g_decay = {}
  M.gparam.nudge(DRUMS, 1, true)
  check("a turn to the right switches it on", M.state.global.drum_macro == true)
  check("and the row says so", M.gparam.param(DRUMS).text() == "on")
  check("switching it on re-pushes every drum's pitch", #CALLS.g_pitch == 6,
        "#" .. #CALLS.g_pitch)
  check("and every drum's decay", #CALLS.g_decay == 6, "#" .. #CALLS.g_decay)

  check("on: an octave up doubles a drum's Hz",
        math.abs(M.gvoice.pitch_hz(KNAP) - root * 2) < 1e-6,
        string.format("%.3f", M.gvoice.pitch_hz(KNAP)))
  check("on: the global Decay macro is x4 at the top",
        math.abs(M.gvoice.decay_seconds(KNAP) - base_d * 4) < 1e-6,
        string.format("%.4f", M.gvoice.decay_seconds(KNAP)))

  -- Plonks, on: a spread of strikes lands on a spread of pitches, and every
  -- one of them is within the knob's own range of where the drum sits.
  CALLS.g_pitch = {}
  local lo, hi = math.huge, -math.huge
  for _ = 1, 60 do M.gvoice.on_strike(KNAP) end
  check("on: every strike retunes the head", #CALLS.g_pitch == 60,
        "#" .. #CALLS.g_pitch)
  for _, c in ipairs(CALLS.g_pitch) do
    lo, hi = math.min(lo, c.hz), math.max(hi, c.hz)
  end
  check("on: and they are not all the same pitch", hi > lo)
  local nominal = M.gvoice.pitch_hz(KNAP)
  local max_st = M.gparam.DROPS_MAX_ST
  check("on: within the Plonks range either side",
        lo >= nominal * 2 ^ (-max_st / 12) - 1e-6
        and hi <= nominal * 2 ^ (max_st / 12) + 1e-6,
        string.format("%.2f..%.2f around %.2f", lo, hi, nominal))

  -- Plonks turned back down: no per-strike message any more (there is
  -- nothing to say), but the heads must not be left sitting on whatever
  -- random pitch the last detuned strike put them on -- so the Plonks row
  -- itself re-pushes all six on the way down.
  CALLS.g_pitch = {}
  M.gparam.nudge(5, -10000, true)        -- Plonks, all the way to 0
  check("turning Plonks down re-pushes every drum", #CALLS.g_pitch == 6,
        "#" .. #CALLS.g_pitch)
  -- repush_pitch walks every G cell, so pick this one's out of the six by
  -- its engine index rather than assuming it is last.
  local knap_i = M.topology.get(KNAP).index - 1
  local knap_push
  for _, c in ipairs(CALLS.g_pitch) do
    if c.index == knap_i then knap_push = c end
  end
  check("back at the nominal pitch, not the last random one",
        knap_push ~= nil
        and math.abs(knap_push.hz - M.gvoice.pitch_hz(KNAP)) < 1e-9,
        knap_push and string.format("%.4f vs %.4f", knap_push.hz,
                                    M.gvoice.pitch_hz(KNAP)) or "not pushed")
  CALLS.g_pitch = {}
  M.gvoice.on_strike(KNAP)
  check("and a strike sends nothing while it is at 0", #CALLS.g_pitch == 0,
        "#" .. #CALLS.g_pitch)

  -- a turn to the left switches it back off, and the drums go back to
  -- exactly where they were.
  M.gparam.nudge(DRUMS, -1, true)
  check("a turn to the left switches it off", M.state.global.drum_macro == false)
  check("and the drum is back at its own pitch",
        math.abs(M.gvoice.pitch_hz(KNAP) - root) < 1e-6)
  check("and its own decay",
        math.abs(M.gvoice.decay_seconds(KNAP) - base_d) < 1e-9)
end

print("\n-- Swing arrives at zero --")
do
  local M = fresh(25)
  check("a fresh patch is straight", M.state.global.swing == 0,
        tostring(M.state.global.swing))
  check("which quantise reads as no swing", M.quantise.swing() == 0,
        tostring(M.quantise.swing()))
end

report()
