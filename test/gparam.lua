-- build phase 6b/7: the global param page (§4.1, §5.2, lib/gparam.lua). that
-- E1/nudge/push behave like the sound page's own E1/E2/E3 (§5.5), that Scale
-- steps one entry per flick and quantises pitch only when it isn't free, that
-- Drops and the global Decay/Pitch macros actually reach the engine, and that
-- Rain and Excite forward what they're told to.
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
  check("nine params", n == 9, "#" .. n)
  check("bpm is first", M.gparam.PARAMS[1].key == "bpm")
  check("excite is last", M.gparam.PARAMS[n].key == "rain_excite")
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

print("\n-- Swing/Scatter/Drops/Decay/Rain/Excite are plain 0..1 knobs --")
do
  local M = fresh(5)
  local keys = {"swing", "scatter", "drops", "decay", "rain_volume", "rain_excite"}
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

print("\n-- Scale steps one entry per flick, and 0 is free --")
do
  local M = fresh(7)
  local scale_i = 4  -- Scale is BPM, Swing, Scatter, Scale
  check("starts free", M.state.global.scale_i == 0)
  -- SCALE_DETENTS is 3 in gparam.lua; two ticks of 3 should not move it yet
  M.gparam.nudge(scale_i, 2, true)
  check("under one detent's worth: still free", M.state.global.scale_i == 0,
        tostring(M.state.global.scale_i))
  M.gparam.nudge(scale_i, 1, true)
  check("the third tick lands on the first scale", M.state.global.scale_i == 1,
        tostring(M.state.global.scale_i))
  M.gparam.nudge(scale_i, -3, true)
  check("and a flick the other way returns to free", M.state.global.scale_i == 0,
        tostring(M.state.global.scale_i))
  M.gparam.nudge(scale_i, -300, true)
  check("clamped at 0, not negative", M.state.global.scale_i == 0)
  M.gparam.nudge(scale_i, 300, true)
  check("clamped at the last scale", M.state.global.scale_i == #M.grove.SCALES,
        tostring(M.state.global.scale_i))
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
  -- decay-change listener rather than a duplicate bridge call.
  CALLS.voice_decay = {}
  M.gparam.nudge(6, 10, true)
  check("decay push reached the engine for all four voices",
        #CALLS.voice_decay >= 4, "#" .. #CALLS.voice_decay)
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

print("\n-- Rain and Excite forward to the engine --")
do
  local M = fresh(19)
  M.gparam.nudge(8, 500, true)            -- Rain (volume)
  check("rain volume reached the engine",
        last(CALLS.rain_volume) and math.abs(last(CALLS.rain_volume).v - 1.0) < 1e-6,
        tostring(last(CALLS.rain_volume) and last(CALLS.rain_volume).v))
  M.gparam.nudge(9, 500, true)            -- Excite
  check("rain excite reached the engine",
        last(CALLS.rain_excite) and math.abs(last(CALLS.rain_excite).v - 1.0) < 1e-6,
        tostring(last(CALLS.rain_excite) and last(CALLS.rain_excite).v))
end

report()
