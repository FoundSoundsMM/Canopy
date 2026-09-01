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
  -- what a cold load of the real Canopy.lua actually pulls in. an exact list
  -- rather than a count, because a count hides exactly the mistake it is
  -- there to catch: mixer.lua arriving and lexicon.lua dropping out of the
  -- load (screenui stopped requiring it when the cell page lost its
  -- description line -- cellparam still fetches it lazily, on the first cell
  -- page drawn) both happened at once, and left the total unchanged at 21.
  local WANT = {
    "bridge", "cellparam", "clockcell", "dispatch", "exciter", "gparam",
    "gridui", "grove", "gust", "gvoice", "heartwood", "mixer", "patch", "quantise",
    "rambler", "screenui", "state", "tm", "topology", "voice",
    "weave",
  }
  check("exactly the expected modules, one copy each",
        table.concat(names, ",") == table.concat(WANT, ","),
        table.concat(names, ","))
  check("and no module was loaded twice", n == #WANT, tostring(n))
end

-- the whole point of the memo: one graph, seen by everyone
check("gridui and screenui share one patch graph",
      wl("patch") == M.patch and wl("state") == M.state)

check("three metros started", #metros == 3 and metros[1].running and metros[3].running,
      "#" .. #metros)

-- hold Hob (7,4) -- Knocker's old coordinates, now Hob's -- and tap Oak
-- (2,2) directly: the socket collapse means there is no more .trig socket
-- to reach for, so a tap on the voice's own cell is the cable endpoint.
gridobj.key(7, 4, 1)
T = T + 0.05
gridobj.key(2, 2, 1)
T = T + 0.05
gridobj.key(2, 2, 0)
check("grid patching reaches the shared graph", M.patch.count() == 1,
      "count " .. M.patch.count())
check("event line records it", M.state.last_event:find("Hob") ~= nil,
      M.state.last_event)

-- release Hob, then let the scheduler run. no D cell defaults to rooted any
-- more, but Hob's own default gait (euclidean) still free-runs and fires on
-- its own, so this still proves the scheduler drives the engine end to end.
gridobj.key(7, 4, 0)
for _ = 1, 5000 do T = T + M.rambler.TICK; M.rambler.tick() end
check("scheduler drives the engine end to end", #CALLS.strike > 0,
      "strikes " .. #CALLS.strike)

-- every screen view redraws without erroring, held and unheld
local ok, err = pcall(function()
  redraw()                                    -- the global param page
  gridobj.key(7, 4, 1); redraw()              -- cell view, a D cell
  gridobj.key(2, 2, 1); redraw()              -- edge view
  gridobj.key(2, 2, 0); gridobj.key(7, 4, 0)
  -- one representative of every current cell type, including the ones the
  -- re-cut added (O, GVOICE/E rename, C-as-clock) and the gusts (§2.11) that
  -- replaced the step-sequencer lanes -- one from each of their two rows.
  for _, id in ipairs({"oak", "d.hob", "tm.padfoot", "clk.toll", "h.wyrd",
                       "f.cuckoo", "r.thicket", "gv.yaffle", "e.bracken",
                       "o.1", "gu.sough", "gu.squall"}) do
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
  -- a gait is a named row on the held cell's page now (Gait, row 2), not a
  -- K1+E2 modifier: hold the cell, E1 to the row, E2 to move it.
  gridobj.key(7, 4, 1)
  enc(1, 1)                       -- Rate -> Gait
  for _ = 1, 4 do enc(2, 1) end
  gridobj.key(7, 4, 0)
end)
check("keys and encoders survive", ok, tostring(err))
check("the Gait row swapped Hob's gait", M.rambler.info("d.hob").gait ~= "euclidean",
      M.rambler.info("d.hob").gait)

-- tapping ANY cell opens its settings page and hands it the encoders; tapping
-- it again gives them back. Oak's cell is at (2,2).
do
  gridobj.key(2, 2, 1); T = T + 0.05; gridobj.key(2, 2, 0)
  check("tapping the voice cell opens its sound page",
        M.state.cell_edit == "oak", tostring(M.state.cell_edit))

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
  check("E1 walks the twelve", M.state.vparam_focus == 2,
        tostring(M.state.vparam_focus))
  M.state.vparam_focus = 1

  ok, err = pcall(redraw)
  check("the sound page redraws", ok, tostring(err))

  gridobj.key(2, 2, 1); T = T + 0.05; gridobj.key(2, 2, 0)
  check("tapping it again closes it", M.state.cell_edit == nil,
        tostring(M.state.cell_edit))
end

-- §4.1/§5.2: the global param page has the encoders with nothing held.
-- BPM is gparam.PARAMS[1], so it's already focused from a fresh load.
do
  -- the blind key sweep above pressed K3, which is the mixer now (§4.1b), so
  -- this is on the mixer page rather than the global one. that is the new
  -- behaviour working, not an accident -- assert it, then come back the way
  -- a player would.
  check("the key sweep left us on the mixer", M.state.view == "mixer",
        tostring(M.state.view))
  key(2, 1); key(2, 0)
  check("and K2 came back", M.state.view == "global", tostring(M.state.view))

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
  check("E1 walks the global params", M.state.gparam_focus == 2,
        tostring(M.state.gparam_focus))
  enc(1, -1)
end

ok, err = pcall(cleanup)
check("cleanup", ok, tostring(err))

report()
