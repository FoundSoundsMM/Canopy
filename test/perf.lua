arg = {os.getenv("ROOT")}
dofile(os.getenv("SP") .. "/harness.lua")
-- the re-cut's population: 16 O + 4 voice + 8 D + 4 TM + 4 C(clock) + 4 H +
-- 4 F(grove) + 6 R + 6 GVOICE + 6 E + 10 SEQ = 72 live cells (Climate, and
-- its 8 cells, are gone entirely).
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
-- the lattice is the one thing that adds work to the tick without a D cell
-- doing anything, so it gets its own row. Heartwood trimmed from a ring of 8
-- to a chain of 4 -- still every node cabled, fed continuously, at full
-- conductance.
bench("heartwood, full conductance", function(M)
  local hs = {}
  for id, c in M.topology.each() do
    if c.type == "H" then
      table.insert(hs, id)
      M.state.character[id] = 1.0
    end
  end
  M.patch.add("d.gabriel", hs[1], 1.0)
  M.patch.add("d.hunt", hs[3], 1.0)
  M.patch.add(hs[2], "oak", 0.8)
  M.patch.add(hs[4], "rowan", 0.8)
  M.patch.add(hs[1], hs[4], 0.6) -- a shortcut across the chain
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

-- the step sequencers are the other new thing: two lanes, ten cells between
-- them, a driver in each firing the shared playhead at the fastest rate a D
-- cell can push it.
bench("sequencer, both lanes driven", function(M)
  M.patch.add("d.gabriel", "q4.4", 0.9)  -- q4's driver
  M.patch.add("d.hunt", "q6.6", 0.9)     -- q6's driver
  M.patch.add("q4.4", "oak", 0.8)
  M.patch.add("q6.6", "rowan", 0.8)
end)
