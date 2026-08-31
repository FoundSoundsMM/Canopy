arg = {os.getenv("ROOT")}
local ROOT = os.getenv("ROOT")
dofile(os.getenv("SP") .. "/harness.lua")

-- norns' real include(), which Canopy.lua wraps
function include(file)
  return dofile(ROOT .. "/" .. file:gsub("^Canopy/", "") .. ".lua")
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

_canopy_mods = nil   -- as if this were a cold script load
dofile(ROOT .. "/Canopy.lua")
init()

local M = _canopy_mods
do
  local names, n = {}, 0
  for k in pairs(M) do table.insert(names, k) n = n + 1 end
  table.sort(names)
  check("all 17 modules memoised, one copy each", n == 17, table.concat(names, ","))
end

-- the whole point of the memo: one graph, seen by everyone
check("gridui and screenui share one patch graph",
      wl("patch") == M.patch and wl("state") == M.state)

check("three metros started", #metros == 3 and metros[1].running and metros[3].running,
      "#" .. #metros)

-- hold Knocker (7,4), tap Oak.Trig (2,1)
gridobj.key(7, 4, 1)
T = T + 0.05
gridobj.key(2, 1, 1)
T = T + 0.05
gridobj.key(2, 1, 0)
check("grid patching reaches the shared graph", M.patch.count() == 1,
      "count " .. M.patch.count())
check("event line records it", M.state.last_event:find("Knocker") ~= nil,
      M.state.last_event)

-- release Knocker, then let the scheduler run: Knocker is metric+rooted
gridobj.key(7, 4, 0)
for _ = 1, 5000 do T = T + M.rambler.TICK; M.rambler.tick() end
check("scheduler drives the engine end to end", #CALLS.strike > 0,
      "strikes " .. #CALLS.strike)

-- every screen view redraws without erroring, held and unheld
local ok, err = pcall(function()
  redraw()                                    -- the global param page
  gridobj.key(7, 4, 1); redraw()              -- cell view, a D cell
  gridobj.key(2, 1, 1); redraw()              -- edge view
  gridobj.key(2, 1, 0); gridobj.key(7, 4, 0)
  for _, id in ipairs({"oak", "oak.pitch", "s.beck", "h.wyrd", "f.cuckoo",
                       "r.trod", "c.moon"}) do
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
  gridobj.key(7, 4, 1)
  key(1, 1)
  for _ = 1, 3 do enc(2, 1) end
  key(1, 0)
  gridobj.key(7, 4, 0)
end)
check("keys and encoders survive", ok, tostring(err))
check("K1+E2 swapped Knocker's gait", M.rambler.info("d.knocker").gait ~= "metric",
      M.rambler.info("d.knocker").gait)

-- §5.5: tapping a voice cell opens its sound page and hands it the encoders;
-- tapping it again gives them back. Oak's cell is at (2,2).
do
  gridobj.key(2, 2, 1); T = T + 0.05; gridobj.key(2, 2, 0)
  check("tapping the voice cell opens its sound page",
        M.state.voice_edit == "oak", tostring(M.state.voice_edit))

  local before = M.state.get_vparam("oak", "tune", 0.5)
  enc(1, 0)                       -- stay on Tune
  enc(2, 10)                      -- coarse
  check("E2 moves the focused parameter",
        M.state.get_vparam("oak", "tune", 0.5) > before,
        tostring(M.state.get_vparam("oak", "tune", 0.5)))
  local coarse = M.state.get_vparam("oak", "tune", 0.5) - before
  local mid = M.state.get_vparam("oak", "tune", 0.5)
  enc(3, 10)                      -- fine
  local fine = M.state.get_vparam("oak", "tune", 0.5) - mid
  check("and E3 moves it less", fine > 0 and fine < coarse,
        string.format("%.5f vs %.5f", fine, coarse))

  enc(1, 1)
  check("E1 walks the nine", M.state.vparam_focus == 2,
        tostring(M.state.vparam_focus))

  ok, err = pcall(redraw)
  check("the sound page redraws", ok, tostring(err))

  gridobj.key(2, 2, 1); T = T + 0.05; gridobj.key(2, 2, 0)
  check("tapping it again closes it", M.state.voice_edit == nil,
        tostring(M.state.voice_edit))
end

-- §4.1/§5.2: the global param page has the encoders with nothing held.
-- BPM is gparam.PARAMS[1], so it's already focused from a fresh load.
do
  check("BPM is focused by default", M.state.gparam_focus == 1,
        tostring(M.state.gparam_focus))
  local before = M.state.global.bpm
  enc(2, 6)                       -- coarse: 1 bpm/detent
  check("E2 moves the tempo", M.state.global.bpm == before + 6,
        tostring(M.state.global.bpm))
  check("and the norns clock went with it", clock.get_tempo() == before + 6,
        tostring(clock.get_tempo()))

  local level = M.state.global.level
  key(1, 1)
  enc(3, 10)
  key(1, 0)
  check("K1+E3 moves the master level instead", M.state.global.level > level)
  check("and leaves the tempo alone", M.state.global.bpm == before + 6)
  enc(2, -6)

  enc(1, 1)
  check("E1 walks the nine global params", M.state.gparam_focus == 2,
        tostring(M.state.gparam_focus))
  enc(1, -1)
end

ok, err = pcall(cleanup)
check("cleanup", ok, tostring(err))

report()
