arg = {os.getenv("ROOT")}
local ROOT = os.getenv("ROOT")
dofile(os.getenv("SP") .. "/harness.lua")

-- norns' real include(), which Woodland.lua wraps
function include(file)
  return dofile(ROOT .. "/" .. file:gsub("^Woodland/", "") .. ".lua")
end

local metros, gridobj = {}, nil
metro.init = function(f, t, c)
  local m = {callback = f, running = false}
  table.insert(metros, m)
  m.start = function() m.running = true end
  m.stop = function() m.running = false end
  return m
end
grid.connect = function()
  gridobj = {led = function() end, all = function() end, refresh = function() end}
  return gridobj
end

_woodland_mods = nil   -- as if this were a cold script load
dofile(ROOT .. "/Woodland.lua")
init()

local M = _woodland_mods
do
  local names, n = {}, 0
  for k in pairs(M) do table.insert(names, k) n = n + 1 end
  table.sort(names)
  check("all 14 modules memoised, one copy each", n == 14, table.concat(names, ","))
end

-- the whole point of the memo: one graph, seen by everyone
check("gridui and screenui share one patch graph",
      wl("patch") == M.patch and wl("state") == M.state)

check("three metros started", #metros == 3 and metros[1].running and metros[3].running,
      "#" .. #metros)

-- hold Knocker (5,3), tap Oak.Knock (2,1)
gridobj.key(5, 3, 1)
T = T + 0.05
gridobj.key(2, 1, 1)
T = T + 0.05
gridobj.key(2, 1, 0)
check("grid patching reaches the shared graph", M.patch.count() == 1,
      "count " .. M.patch.count())
check("event line records it", M.state.last_event:find("Knocker") ~= nil,
      M.state.last_event)

-- release Knocker, then let the scheduler run: Knocker is metric+rooted
gridobj.key(5, 3, 0)
for _ = 1, 5000 do T = T + M.rambler.TICK; M.rambler.tick() end
check("scheduler drives the engine end to end", #CALLS.strike > 0,
      "strikes " .. #CALLS.strike)

-- every screen view redraws without erroring, held and unheld
local views = {"network", "meters", "lexicon"}
local ok, err = pcall(function()
  for _, v in ipairs(views) do M.state.view = v; redraw() end
  gridobj.key(5, 3, 1); redraw()              -- cell view, a D cell
  gridobj.key(2, 1, 1); redraw()              -- edge view
  gridobj.key(2, 1, 0); gridobj.key(5, 3, 0)
  for _, id in ipairs({"oak", "oak.sway", "s.beck", "h.wyrd", "p.cuckoo"}) do
    local c = M.topology.get(id)
    gridobj.key(c.coords[1][1], c.coords[1][2], 1); redraw()
    gridobj.key(c.coords[1][1], c.coords[1][2], 0)
  end
end)
check("all screen views redraw", ok, tostring(err))

-- grid render, including the live D brightness path
ok, err = pcall(function() M.gridui = wl("gridui"); wl("gridui").grid_redraw(gridobj) end)
check("grid redraws", ok, tostring(err))

-- norns keys and encoders
ok, err = pcall(function()
  for n = 1, 3 do key(n, 1); key(n, 0) end
  for n = 1, 3 do enc(n, 1); enc(n, -1) end
  -- K1+E2 on a held D cell must swap the gait
  gridobj.key(5, 3, 1)
  key(1, 1)
  for _ = 1, 3 do enc(2, 1) end
  key(1, 0)
  gridobj.key(5, 3, 0)
end)
check("keys and encoders survive", ok, tostring(err))
check("K1+E2 swapped Knocker's gait", M.rambler.info("d.knocker").gait ~= "metric",
      M.rambler.info("d.knocker").gait)

-- §4.1: E3 is the transport with nothing held, master level under K1.
do
  local before = M.state.global.bpm
  enc(3, 6)
  check("E3 moves the tempo", M.state.global.bpm == before + 6,
        tostring(M.state.global.bpm))
  check("and the norns clock went with it", clock.get_tempo() == before + 6,
        tostring(clock.get_tempo()))
  local level = M.state.global.level
  key(1, 1)
  enc(3, 10)
  key(1, 0)
  check("K1+E3 moves the master level instead", M.state.global.level > level)
  check("and leaves the tempo alone", M.state.global.bpm == before + 6)
  enc(3, -6)
end

ok, err = pcall(cleanup)
check("cleanup", ok, tostring(err))

report()
