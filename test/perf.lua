arg = {os.getenv("ROOT")}
dofile(os.getenv("SP") .. "/harness.lua")
local function bench(label, setup, weather)
  local M = fresh(2)
  if weather then M.state.global.weather = weather end
  setup(M)
  local t0 = os.clock()
  run(M, 60)
  local wall = os.clock() - t0
  print(string.format("%-28s %.3fs cpu for 60s wall  (%.2f%% of one core here)",
        label, wall, wall / 60 * 100))
end
bench("idle, no cables", function() end)
bench("modest patch (6 cables)", function(M)
  M.patch.add("d.knocker", "oak.knock", 0.8)
  M.patch.add("d.hob", "rowan.knock", 0.8)
  M.patch.add("d.knocker", "d.hob", 0.5)
  M.patch.add("d.gabriel", "d.hunt", -0.7)
  M.patch.add("d.gabriel", "ash.knock", 0.6)
  M.patch.add("d.shuck", "yew.knock", 0.9)
end)
-- the lattice is the one thing that adds work to the tick without a D cell
-- doing anything, so it gets its own row: eight nodes at full conductance,
-- every one of them cabled, fed continuously.
bench("heartwood, full conductance", function(M)
  local hs = {}
  for id, c in M.topology.each() do
    if c.type == "H" then
      table.insert(hs, id)
      M.state.character[id] = 1.0
    end
  end
  M.patch.add("d.gabriel", hs[1], 1.0)
  M.patch.add("d.hunt", hs[5], 1.0)
  M.patch.add(hs[2], "oak.knock", 0.8)
  M.patch.add(hs[4], "rowan.knock", 0.8)
  M.patch.add(hs[6], "yew.knock", 0.8)
  M.patch.add(hs[8], "s.bracken", 0.8)
  M.patch.add(hs[1], hs[5], 0.6) -- a shortcut across the ring
end)

-- the grove's continuous half is the other thing that costs something with
-- no D cell involved: eight fields, all cabled to voices and to each other,
-- every one of them at full range.
bench("grove, all 8 fields cabled", function(M)
  local ps, voices = {}, {}
  for id, c in M.topology.each() do
    if c.type == "P" then table.insert(ps, id); M.state.character[id] = 1.0 end
    if c.type == "voice" then table.insert(voices, id) end
  end
  for i, id in ipairs(ps) do
    M.patch.add(id, voices[((i - 1) % #voices) + 1] .. ".sway", 0.8)
    M.patch.add(id, ps[(i % #ps) + 1], 0.6)
  end
  M.patch.add("d.gabriel", "oak.knock", 0.9)
end)

bench("saturated (all 10 D ringed)", function(M)
  local ds = {}
  for id, c in M.topology.each() do if c.type == "D" then table.insert(ds, id) end end
  for i, id in ipairs(ds) do M.patch.add(id, ds[(i % #ds) + 1], 0.9) end
  for i = 1, 6 do M.patch.add(ds[i], ds[((i + 4) % #ds) + 1], 0.5) end
  M.patch.add(ds[1], "oak.knock", 0.9)
end)

-- the quantised path is the one added in phase 5c: at W=0 every emission is
-- placed on a grid line and rides the scheduled queue for up to a grid
-- interval instead of going out on the tick it was made. this is the same
-- saturated ring as the row above, run at both ends of the Weather knob, so
-- the cost of holding the whole patch in time is visible next to the cost of
-- letting it go.
local function saturated(M)
  local ds = {}
  for id, cell in M.topology.each() do
    if cell.type == "D" then table.insert(ds, id) end
  end
  for i, id in ipairs(ds) do M.patch.add(id, ds[(i % #ds) + 1], 0.9) end
  M.patch.add(ds[1], "oak.knock", 0.9)
  M.patch.add(ds[6], "rowan.knock", 0.9)
  M.patch.add(ds[9], "ash.moss", 0.9)
end
bench("saturated, quantised (W=0)", saturated, 0)
bench("saturated, swung (W=0.5)", saturated, 0.5)
bench("saturated, loose (W=1)", saturated, 1.0)
