arg = {os.getenv("ROOT")}
dofile(os.getenv("SP") .. "/harness.lua")
local function bench(label, setup)
  local M = fresh(2)
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
bench("saturated (all 10 D ringed)", function(M)
  local ds = {}
  for id, c in M.topology.each() do if c.type == "D" then table.insert(ds, id) end end
  for i, id in ipairs(ds) do M.patch.add(id, ds[(i % #ds) + 1], 0.9) end
  for i = 1, 6 do M.patch.add(ds[i], ds[((i + 4) % #ds) + 1], 0.5) end
  M.patch.add(ds[1], "oak.knock", 0.9)
end)
