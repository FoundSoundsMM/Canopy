local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local KNOCKER, HOB, GRIM = "d.knocker", "d.hob", "d.grim"
local GABRIEL, HUNT = "d.gabriel", "d.hunt"
local KNOCK = "oak.knock"

print("\n-- every gait produces pulses --")
local REACTIVE = {divider = true, echo = true, coincidence = true}
for _, gait in ipairs({"metric","euclidean","divider","slow","burst",
                       "drifter","coincidence","echo","stochastic","accelerando"}) do
  local M = fresh(7)
  M.state.global.weather = 0.4
  M.rambler.set_gait(KNOCKER, gait)
  M.patch.add(KNOCKER, KNOCK, 0.8)
  if REACTIVE[gait] then
    -- reactive gaits only speak when spoken to: give them two drivers so
    -- coincidence has two distinct sources to coincide.
    M.rambler.set_gait(HOB, "metric")
    M.rambler.set_gait(GRIM, "metric")
    M.state.character[HOB] = 0.75
    M.state.character[GRIM] = 0.78
    M.patch.add(HOB, KNOCKER, 1.0)
    M.patch.add(GRIM, KNOCKER, 1.0)
  end
  run(M, 20)
  local n = #CALLS.strike
  check(gait .. " strikes", n > 0, "got " .. n)
end

print("\n-- rooted metric locks to the transport --")
do
  local M = fresh(3)
  M.rambler.set_gait(KNOCKER, "metric")
  M.state.character[KNOCKER] = 0.5     -- 1 x beat
  M.state.rooted[KNOCKER] = true
  M.rambler.get(KNOCKER).rooted = true
  M.patch.add(KNOCKER, KNOCK, 1.0)
  run(M, 20)
  -- 120bpm, 1 cycle per beat -> 2 Hz -> ~40 strikes in 20s
  check("rate", math.abs(#CALLS.strike - 40) <= 1, "got " .. #CALLS.strike)
  local worst = 0
  for _, s in ipairs(CALLS.strike) do
    local beat = s.t * 2
    worst = math.max(worst, math.abs(beat - math.floor(beat + 0.5)))
  end
  check("aligned to the beat", worst < 0.01, "worst offset " .. worst .. " beats")
end

print("\n-- euclidean k:n --")
do
  local M = fresh(3)
  M.rambler.set_gait(KNOCKER, "euclidean")
  M.state.character[KNOCKER] = 0.625   -- k = 5 of 8
  M.state.rooted[KNOCKER] = true
  M.rambler.get(KNOCKER).rooted = true
  M.patch.add(KNOCKER, KNOCK, 1.0)
  -- 2 steps/beat at 120bpm = 4 steps/s; 16s = 64 steps; 5 of every 8 = 40
  run(M, 16)
  check("5 of every 8 steps", math.abs(#CALLS.strike - 40) <= 1, "got " .. #CALLS.strike)
end

print("\n-- Kuramoto coupling --")
local function phase_gap(M)
  local a = M.rambler.get(GABRIEL).phase
  local b = M.rambler.get(HUNT).phase
  local d = math.abs(a - b) % 1
  return math.min(d, 1 - d)
end
local function two_drifters(seed, gain, weather, seconds)
  local M = fresh(seed)
  M.state.global.weather = weather
  M.rambler.set_gait(GABRIEL, "drifter")
  M.rambler.set_gait(HUNT, "drifter")
  M.state.character[GABRIEL] = 0.20    -- 2.0 Hz
  M.state.character[HUNT]    = 0.28    -- 2.6 Hz
  if gain then M.patch.add(GABRIEL, HUNT, gain) end
  run(M, 20)                           -- settle
  local lo, hi = 1, 0
  for _ = 1, math.floor((seconds or 5) * 500) do
    run(M, 1 / 500)
    local g = phase_gap(M)
    lo, hi = math.min(lo, g), math.max(hi, g)
  end
  return lo, hi
end

-- Weather 0 zeroes the drift random walk, so these are deterministic.
-- K = 2.0 * 0.15 * 2.5 (drifter's multiplier) = 0.75 Hz against a 0.6 Hz
-- detune; locking theory puts the standing offset at asin(0.6/1.5)/2pi = 0.066.
do
  local lo, hi = two_drifters(11, 1.0, 0)
  check("positive gain locks in phase", hi < 0.10, string.format("gap %.3f..%.3f", lo, hi))
  lo, hi = two_drifters(11, -1.0, 0)
  -- anti-phase sits at 0.5 minus the same standing offset, +/- the nudge
  check("negative gain locks anti-phase", lo > 0.35, string.format("gap %.3f..%.3f", lo, hi))
  lo, hi = two_drifters(11, nil, 0)
  check("uncabled cells sweep freely", hi > 0.45 and lo < 0.05,
        string.format("gap %.3f..%.3f", lo, hi))
  lo, hi = two_drifters(11, 1.0, 0.5)
  check("still locks with Weather up", hi < 0.15, string.format("gap %.3f..%.3f", lo, hi))
end

print("\n-- Still freezes everything --")
do
  local M = fresh(5)
  M.rambler.set_gait(KNOCKER, "metric")
  M.patch.add(KNOCKER, KNOCK, 1.0)
  run(M, 5)
  local before = #CALLS.strike
  M.state.global.still = true
  run(M, 5)
  check("no strikes while Still", #CALLS.strike == before, "grew by " .. (#CALLS.strike - before))
  M.state.global.still = false
  run(M, 5)
  check("resumes", #CALLS.strike > before)
end

print("\n-- a densely cross-patched graph stays bounded --")
do
  local M = fresh(9)
  M.state.global.weather = 1.0
  local ds = {}
  for id, cell in M.topology.each() do
    if cell.type == "D" then table.insert(ds, id) end
  end
  -- ring every D cell together, plus chords: cycles everywhere, on purpose
  for i, id in ipairs(ds) do
    M.patch.add(id, ds[(i % #ds) + 1], 0.9)
  end
  M.patch.add(ds[1], ds[5], -0.8)
  M.patch.add(ds[2], ds[7], 0.7)
  M.rambler.set_gait(ds[3], "echo")
  M.rambler.set_gait(ds[4], "burst")
  M.rambler.set_gait(ds[8], "echo")
  M.patch.add(ds[1], KNOCK, 0.9)
  M.patch.add(ds[6], "rowan.knock", 0.9)
  M.patch.add(ds[9], "ash.moss", 0.9)
  local t0 = os.clock()
  run(M, 30)
  local wall = os.clock() - t0
  local rate = #CALLS.strike / 30
  check("terminates", true)
  check("strike rate bounded", rate < 400, string.format("%.1f/s", rate))
  check("chokes fired", #CALLS.choke > 0, "got " .. #CALLS.choke)
  check("30s of ticks in reasonable time", wall < 20, string.format("%.2fs", wall))
  print(string.format("        (%d strikes, %d chokes, %.1f/s, %.2fs wall for 15000 ticks)",
        #CALLS.strike, #CALLS.choke, rate, wall))
end

print("\n-- gait swap and rooted toggle --")
do
  local M = fresh(4)
  local k = M.rambler.cycle_gait(KNOCKER, 1)
  check("cycle_gait advances", k == "euclidean", tostring(k))
  check("rooted toggles on a metric gait", M.rambler.toggle_rooted(KNOCKER) ~= nil)
  M.rambler.set_gait(KNOCKER, "drifter")
  check("rooted refused on a wild-only gait", M.rambler.toggle_rooted(KNOCKER) == nil)
  local info = M.rambler.info(KNOCKER)
  check("info reports the gait", info.gait == "drifter" and info.phased == true)
end

report()
