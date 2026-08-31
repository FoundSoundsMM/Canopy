-- build phase 5c/6b: the Swing/Scatter groove (§4.1, lib/quantise.lua). that at
-- 0 every gait -- however it free-runs -- is heard on the grid, that Swing
-- ramps in and puts the off-beats late without ever touching the grid error,
-- that a burst is triggered on the beat with its ratchet on grid lines, and
-- that Scatter lets go of all of it until nothing is held at 1 -- independently
-- of whatever Swing is doing.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local KNOCKER, GRIM, SHUCK = "d.hob", "d.grim", "d.shuck"
local BOGGART, GABRIEL = "d.boggart", "d.gabriel"
local KNOCK = "oak"

-- every division the quantiser can pick is a whole number of 64th notes, so
-- "on the grid" is one test whatever grid a given cell ended up on.
local SIXTYFOURTH = 0.0625

local function beats_of(call) return call.t * TEMPO / 60 end

-- how far a strike sits from the nearest 64th line, in 64ths. a wrap is only
-- seen at the first 2ms tick after it happens, so a perfectly quantised
-- strike still lands up to a tick late -- 0.03 of a 64th at 120bpm.
local function grid_error(call)
  local x = beats_of(call) / SIXTYFOURTH
  return math.abs(x - math.floor(x + 0.5))
end

local function worst_grid_error()
  local worst = 0
  for _, s in ipairs(CALLS.strike) do worst = math.max(worst, grid_error(s)) end
  return worst
end

local function mean_grid_error()
  if #CALLS.strike == 0 then return 0 end
  local sum = 0
  for _, s in ipairs(CALLS.strike) do sum = sum + grid_error(s) end
  return sum / #CALLS.strike
end

-- an emission is placed exactly on its line and then fires on the first tick
-- at or after it, so the whole error budget is that one tick: 2ms is 0.064
-- of a 64th at 120bpm, and less at any slower tempo.
local TOLERANCE = 0.1

print("\n-- the divisions themselves --")
do
  local M = fresh(1)
  local q = M.quantise
  -- 120bpm: a beat is 0.5s. the grid is the coarsest division that still
  -- fits inside one cycle of the cell asking.
  check("a 1-second cycle gets 8ths", q.grid_beats(1.0) == 0.5)
  check("a half-second cycle gets 8ths", q.grid_beats(0.5) == 0.5)
  check("a 0.2s cycle gets 16ths", q.grid_beats(0.2) == 0.25,
        tostring(q.grid_beats(0.2)))
  check("an 0.08s cycle gets 32nds", q.grid_beats(0.08) == 0.125,
        tostring(q.grid_beats(0.08)))
  check("anything faster than a 64th still gets 64ths",
        q.grid_beats(0.001) == 0.0625)
  check("a reactive gait, with no rate at all, gets 16ths",
        q.grid_beats(nil) == 0.25)

  -- and the tempo is what those divisions are measured against: 0.3s is
  -- 0.6 of a beat at 120bpm and only 0.3 of one at 60, so the same cell
  -- drops from 8ths to 16ths when the transport slows down.
  check("0.3s is an 8th at 120bpm", q.grid_beats(0.3) == 0.5,
        tostring(q.grid_beats(0.3)))
  TEMPO = 60
  check("and a 16th at 60bpm", q.grid_beats(0.3) == 0.25,
        tostring(q.grid_beats(0.3)))
  TEMPO = 120

  check("a ratchet of 2 sits on 16ths", q.ratchet_gap(2) == 0.25)
  check("a ratchet of 7 packs onto 32nds", q.ratchet_gap(7) == 0.125,
        tostring(q.ratchet_gap(7)))
  check("and a ratchet always finishes inside its beat",
        q.ratchet_gap(5) * 4 < 1, tostring(q.ratchet_gap(5)))
end

print("\n-- Swing=Scatter=0: a wild gait is heard on the grid --")
do
  local M = fresh(3)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  M.rambler.set_gait(KNOCKER, "drifter")   -- free-running, nothing to root to
  M.state.character[KNOCKER] = 0.20        -- 2.0 Hz, no relation to the beat
  M.patch.add(KNOCKER, KNOCK, 1.0)
  run(M, 20)
  check("it still speaks", #CALLS.strike > 20, "#" .. #CALLS.strike)
  check("and every strike is on a grid line", worst_grid_error() < TOLERANCE,
        string.format("worst %.3f of a 64th", worst_grid_error()))
end

print("\n-- Swing=Scatter=0: unrelated gaits cohere onto one grid --")
do
  local M = fresh(5)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  -- three cells with nothing in common: a triplet division, a free drifter
  -- and a slow one, none of them rooted.
  M.rambler.set_gait(KNOCKER, "metric")
  M.state.character[KNOCKER] = 0.125       -- 1/3 x beat: deliberately off-grid
  M.rambler.set_gait(GRIM, "drifter")
  M.state.character[GRIM] = 0.63            -- 5.2 Hz
  M.rambler.set_gait(SHUCK, "slow")
  M.state.character[SHUCK] = 0.7           -- 0.36 Hz
  M.patch.add(KNOCKER, KNOCK, 1.0)
  M.patch.add(GRIM, "rowan", 1.0)
  M.patch.add(SHUCK, "hazel", 1.0)
  run(M, 20)

  local voices = {}
  for _, s in ipairs(CALLS.strike) do voices[s.voice] = true end
  local n = 0
  for _ in pairs(voices) do n = n + 1 end
  check("all three are sounding", n == 3, "voices struck: " .. n)
  check("and all three land on the same grid", worst_grid_error() < TOLERANCE,
        string.format("worst %.3f of a 64th", worst_grid_error()))
end

print("\n-- swing warps the beat line, and leaves the beats alone --")
do
  local M = fresh(6)
  local q = M.quantise
  -- full swing: the pair of 8ths becomes 3:1 rather than 1:1
  check("the beat itself never moves", math.abs(q.warp(1.0, 1) - 1.0) < 1e-9,
        tostring(q.warp(1.0, 1)))
  check("the off-8th lands three quarters through",
        math.abs(q.warp(0.5, 1) - 0.75) < 1e-9, tostring(q.warp(0.5, 1)))
  check("the triplet 2:1 feel sits two thirds up the knob",
        math.abs(q.warp(0.5, 2/3) - (2/3)) < 1e-9, tostring(q.warp(0.5, 2/3)))
  -- a 16th inside the stretched half rides it rather than fighting it
  check("finer divisions ride the swung 8th they sit in",
        math.abs(q.warp(0.25, 1) - 0.375) < 1e-9, tostring(q.warp(0.25, 1)))
  check("and the warp never runs backwards", q.warp(0.9, 1) > q.warp(0.8, 1))
  check("straight is the identity", math.abs(q.warp(0.3, 0) - 0.3) < 1e-9)
end

print("\n-- Swing ramps in, independently of Scatter --")
local function offbeat_positions(swing)
  local M = fresh(7)
  M.state.global.swing = swing
  M.state.global.scatter = 0
  M.rambler.set_gait(KNOCKER, "metric")
  M.state.character[KNOCKER] = 0.75        -- 2 x beat -> an 8th-note grid
  M.state.rooted[KNOCKER] = true
  M.rambler.get(KNOCKER).rooted = true
  M.patch.add(KNOCKER, KNOCK, 1.0)
  run(M, 16)
  -- where inside each beat the strikes land, on the beat and off it
  local on, off = {}, {}
  for _, s in ipairs(CALLS.strike) do
    local pos = beats_of(s) % 1
    if pos < 0.25 or pos > 0.9 then table.insert(on, pos) else table.insert(off, pos) end
  end
  local sum = 0
  for _, p in ipairs(off) do sum = sum + p end
  return #CALLS.strike, #off > 0 and (sum / #off) or 0
end

do
  local n0, off0 = offbeat_positions(0)
  local nh, offh = offbeat_positions(0.5)
  local nf, offf = offbeat_positions(1.0)
  check("straight at Swing=0: the off-beat is the half-beat",
        math.abs(off0 - 0.5) < 0.02, string.format("%.3f", off0))
  check("swung at Swing=0.5: it has moved late",
        offh > off0 + 0.04, string.format("%.3f -> %.3f", off0, offh))
  check("fully swung at Swing=1: three quarters of the way through the beat",
        math.abs(offf - 0.75) < 0.03, string.format("%.3f", offf))
  check("and swinging costs no pulses", n0 == nf, n0 .. " vs " .. nf)
  check("full swing with Scatter=0 is still exactly on the grid",
        worst_grid_error() < TOLERANCE,
        string.format("worst %.3f of a 64th", worst_grid_error()))
end

print("\n-- a burst is triggered on the beat --")
do
  local M = fresh(13)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  M.rambler.set_gait(BOGGART, "burst")
  M.state.character[BOGGART] = 0.3
  M.patch.add(BOGGART, KNOCK, 1.0)
  run(M, 20)
  check("the burst fires", #CALLS.strike > 10, "#" .. #CALLS.strike)

  -- Scatter=0 means a ratchet of 2 on 16ths, so a burst is a beat-aligned pair:
  -- the trigger on the beat, the tap a 16th later.
  local on_beat, on_tap, stray = 0, 0, 0
  for _, s in ipairs(CALLS.strike) do
    local pos = beats_of(s) % 1
    if pos < 0.03 or pos > 0.97 then on_beat = on_beat + 1
    elseif math.abs(pos - 0.25) < 0.03 then on_tap = on_tap + 1
    else stray = stray + 1 end
  end
  check("every trigger lands on a beat", on_beat > 5, "#" .. on_beat)
  check("and its ratchet on the subdivision", on_tap > 5, "#" .. on_tap)
  check("with nothing off the grid at all", stray == 0, "#" .. stray)
end

print("\n-- Scatter lets go, independently of Swing --")
do
  local function looseness(scatter, swing, seed)
    local M = fresh(seed or 17)
    M.state.global.scatter = scatter
    M.state.global.swing = swing or 0
    M.rambler.set_gait(KNOCKER, "drifter")
    M.state.character[KNOCKER] = 0.20
    M.patch.add(KNOCKER, KNOCK, 1.0)
    run(M, 20)
    return mean_grid_error(), #CALLS.strike
  end

  local e0 = looseness(0)
  local e75 = looseness(0.75)
  local e100, n100 = looseness(1.0)
  check("Scatter=0 is locked", e0 < 0.05, string.format("%.3f", e0))
  check("Scatter=0.75 has come off the grid", e75 > e0 + 0.05,
        string.format("%.3f -> %.3f", e0, e75))
  check("Scatter=1 is loose -- a mean error near the 0.25 of pure chance",
        e100 > 0.15, string.format("%.3f", e100))
  check("and it is scattered, not silent", n100 > 20, "#" .. n100)

  -- Swing and Scatter used to be one knob, split at its midpoint; now they are
  -- independent, so full Swing with Scatter still at 0 must stay locked.
  local e0_swung = looseness(0, 1.0)
  check("Scatter=0 stays locked even at full Swing", e0_swung < 0.05,
        string.format("%.3f", e0_swung))
end

print("\n-- swing() and chaos() read Swing and Scatter directly --")
do
  local M = fresh(19)
  local q = M.quantise
  M.state.global.swing, M.state.global.scatter = 0, 0
  check("both zero", q.swing() == 0 and q.chaos() == 0)
  M.state.global.swing, M.state.global.scatter = 0.8, 0.3
  check("read back independently, no midpoint split",
        q.swing() == 0.8 and q.chaos() == 0.3,
        string.format("swing %.2f chaos %.2f", q.swing(), q.chaos()))

  M.state.global.swing, M.state.global.scatter = 0, 0
  M.rambler.set_gait(KNOCKER, "drifter")
  M.state.character[KNOCKER] = 0.20
  check("and the cell view names its grid",
        M.rambler.info(KNOCKER).grid == "1/8", tostring(M.rambler.info(KNOCKER).grid))
  M.state.global.scatter = 1.0
  check("and drops it once Scatter has let go",
        M.rambler.info(KNOCKER).grid == nil, tostring(M.rambler.info(KNOCKER).grid))
end

print("\n-- the grid follows the transport --")
do
  local M = fresh(23)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  TEMPO = 75
  M.rambler.set_gait(KNOCKER, "drifter")
  M.state.character[KNOCKER] = 0.20
  M.patch.add(KNOCKER, KNOCK, 1.0)
  run(M, 20)
  check("strikes still land on the grid at 75bpm", worst_grid_error() < TOLERANCE,
        string.format("worst %.3f of a 64th", worst_grid_error()))
  -- and the lines really did move: at 75bpm a 64th is 50ms, not 31.25ms
  local spacing_ok = true
  for _, s in ipairs(CALLS.strike) do
    local x = (s.t / (60 / 120)) / SIXTYFOURTH   -- measured against 120bpm
    if math.abs(x - math.floor(x + 0.5)) > TOLERANCE then spacing_ok = false end
  end
  check("against the new tempo, not the old one", not spacing_ok)
  TEMPO = 120
end

print("\n-- Still still freezes it --")
do
  local M = fresh(29)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  M.rambler.set_gait(KNOCKER, "drifter")
  M.state.character[KNOCKER] = 0.20
  M.patch.add(KNOCKER, KNOCK, 1.0)
  run(M, 5)
  local before = #CALLS.strike
  check("running", before > 0, "#" .. before)
  M.state.global.still = true
  run(M, 5)
  -- a quantised emission is a scheduled one, so this also proves the queue
  -- freezes with the gaits rather than flushing the moment Still lifts.
  check("nothing lands while Still, queued or not", #CALLS.strike == before,
        "grew by " .. (#CALLS.strike - before))
  M.state.global.still = false
  run(M, 5)
  check("and it picks up again", #CALLS.strike > before)
end

report()
