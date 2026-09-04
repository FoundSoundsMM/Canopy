arg = {os.getenv("ROOT")}
dofile(os.getenv("SP") .. "/harness.lua")
-- the population: 16 O + 4 voice + 8 D + 4 TM + 4 C(clock) + 4 SMP +
-- 4 F(grove) + 6 R + 6 GVOICE + 6 E + 12 GUST + 4 LFO = 78 live cells
-- (Climate and its 8 cells are gone entirely; the ten cells that were the
-- Q4/Q6 step lanes are the gusts now, §2.11; and the heartwood lattice's four
-- seats are the sample cells, §2.5).
local function bench(label, setup, scatter)
  local M = fresh(2)
  if scatter then M.state.global.scatter = scatter end
  setup(M)
  local t0 = os.clock()
  run(M, 60)
  local wall = os.clock() - t0
  print(string.format("%-28s %.3fs cpu for 60s wall  (%.2f%% of one core here)",
        label, wall, wall / 60 * 100))
end
bench("idle, no cables", function() end)
bench("modest patch (6 cables)", function(M)
  M.patch.add("d.hob", "oak", 0.8)
  M.patch.add("d.grim", "rowan", 0.8)
  M.patch.add("d.hob", "d.grim", 0.5)
  M.patch.add("d.gabriel", "d.hunt", -0.7)
  M.patch.add("d.gabriel", "hazel", 0.6)
  M.patch.add("d.shuck", "alder", 0.9)
end)
-- the four LFOs, each aimed at a knob rather than at a bus: this is the one
-- family that does real Lua work per frame (lfo.apply reads, sets, pushes and
-- restores one parameter per cell), and it is worth knowing what four of them
-- pointed at four different pages costs. driven here at the tick rather than
-- at Canopy.lua's 40 Hz metro, so this is a deliberate overestimate.
bench("LFOs, all four modulating a knob", function(M)
  local pairs_ = {
    {"lfo.flood", "gu.gale", "timbre"},
    {"lfo.ebb", "oak", "damp"},
    {"lfo.neap", "e.bracken", "character"},
    {"lfo.spring", "gv.yaffle", "tone"},
  }
  for _, p in ipairs(pairs_) do
    M.patch.add(p[1], p[2], 0.8)
    M.lfo.set_target(p[1], p[2])
    M.lfo.set_param_key(p[1], p[3])
    M.state.set_vparam(p[1], "rate", 0.4)
  end
  -- the scheduler tick is the only clock this harness runs, so hang the
  -- modulation off it.
  local base = M.rambler.tick
  M.rambler.tick = function(...) M.lfo.apply(); return base(...) end
end)

-- the grove's continuous half is the other thing that costs something with
-- no D cell involved. trimmed from 8 fields to 4 -- still every one of them
-- cabled to a voice and to each other, at full range.
bench("grove, all 4 fields cabled", function(M)
  local ps, voices = {}, {}
  for id, c in M.topology.each() do
    if c.type == "F" then table.insert(ps, id); M.state.character[id] = 1.0 end
    if c.type == "voice" then table.insert(voices, id) end
  end
  for i, id in ipairs(ps) do
    M.patch.add(id, voices[((i - 1) % #voices) + 1], 0.8)
    M.patch.add(id, ps[(i % #ps) + 1], 0.6)
  end
  M.patch.add("d.gabriel", "oak", 0.9)
end)

bench("saturated (all 8 D ringed)", function(M)
  local ds = {}
  for id, c in M.topology.each() do if c.type == "D" then table.insert(ds, id) end end
  for i, id in ipairs(ds) do M.patch.add(id, ds[(i % #ds) + 1], 0.9) end
  for i = 1, 6 do M.patch.add(ds[i], ds[((i + 4) % #ds) + 1], 0.5) end
  M.patch.add(ds[1], "oak", 0.9)
end)

-- the quantised path is the one added in phase 5c: at Scatter=0 every emission
-- is placed on a grid line and rides the scheduled queue for up to a grid
-- interval instead of going out on the tick it was made. this is the same
-- saturated ring as the row above, run at both ends of the Scatter knob, so
-- the cost of holding the whole patch in time is visible next to the cost of
-- letting it go.
local function saturated(M)
  local ds = {}
  for id, cell in M.topology.each() do
    if cell.type == "D" then table.insert(ds, id) end
  end
  for i, id in ipairs(ds) do M.patch.add(id, ds[(i % #ds) + 1], 0.9) end
  M.patch.add(ds[1], "oak", 0.9)
  M.patch.add(ds[6], "rowan", 0.9)
  M.patch.add(ds[8], "hazel", 0.9)
end
bench("saturated, quantised (Scatter=0)", saturated, 0)
bench("saturated, mid (Scatter=0.5)", saturated, 0.5)
bench("saturated, loose (Scatter=1)", saturated, 1.0)

-- the weave is the other thing the re-cut added to the tick: each cell
-- capable of putting more taps in the queue than it took out. trimmed from
-- 14 to 6 -- this is still the worst case on purpose -- one fast gait
-- feeding a chain of the multiplying rules across all six survivors, landing
-- on a voice.
bench("weave, a chain of six", function(M)
  local rs = {}
  for id, c in M.topology.each() do if c.type == "R" then table.insert(rs, id) end end
  local rules = {"mult", "echo", "roll", "flam", "ghost"}
  M.patch.add("d.gabriel", rs[1], 0.9)
  for i, rule in ipairs(rules) do
    M.weave.set_rule(rs[i], rule)
    M.patch.add(rs[i], rs[i + 1], 0.8)
  end
  M.weave.set_rule(rs[#rs], "accent")
  M.patch.add(rs[#rs], "oak", 0.9)
end)

-- Climate is gone entirely; the letter is reused for the new Clock cells,
-- which cost nothing per pulse and a little per tick, same shape Climate
-- used to. all four of them at the fastest ratio, reaching every D and E
-- cell they can.
bench("clock, all 4 at full rate", function(M)
  local cs, targets = {}, {}
  for id, c in M.topology.each() do
    if c.type == "C" then table.insert(cs, id); M.state.character[id] = 1.0 end
    if c.type == "D" or c.type == "E" then table.insert(targets, id) end
  end
  for i, id in ipairs(cs) do
    M.patch.add(id, targets[i], 0.8)
    M.patch.add(id, targets[i + 4], 0.6)
  end
  M.patch.add("d.gabriel", "oak", 0.9)
end)

-- the gusts are the other new thing (§2.11). the expensive case is not one
-- of them playing -- that is an OSC message and nothing else -- but a chain
-- of them driven fast, since each one that sounds answers with a pulse of
-- its own, and cross-mod cables between them are live SC synths the Lua side
-- has to keep in step. so: two fast triggers into four gusts, wired into
-- each other and back out to a voice.
bench("gusts, four driven and cross-modulating", function(M)
  M.patch.add("d.gabriel", "gu.sough", 0.9)
  M.patch.add("d.hunt", "gu.squall", 0.9)
  M.patch.add("gu.sough", "gu.eddy", 0.7)
  M.patch.add("gu.squall", "gu.flurry", 0.7)
  M.patch.add("gu.eddy", "gu.flurry", 0.5)
  M.patch.add("gu.flurry", "oak", 0.8)
end)
