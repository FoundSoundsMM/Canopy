-- topology.lua §2.12 / lib/lfo.lua: the four LFO cells above the gusts.
--
-- covers: (1) four cells, one row, above the gust rows; (2) the Speed page
-- reaches the engine, log-mapped end to end; (3) it is a pure continuous
-- source -- cabled to a voice, an exciter, the heartwood, a gust or an
-- Output cell it lands on that cell's usual continuous bus, and a pulse
-- landing on it does nothing; (4) cellparam hands out the module's own page.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("== lfo ==")

print("\n-- four cells, indexed 0..3, one row above the gusts --")
do
  local M = fresh(1)
  local ids = M.lfo.each()
  check("there are four", #ids == 4, tostring(#ids))

  local seen = {}
  for _, id in ipairs(ids) do
    local cell = M.topology.get(id)
    seen[cell.index] = true
    check("row 6, above the top gust row", cell.coords[1][2] == 6,
          tostring(cell.coords[1][2]))
  end
  for i = 0, 3 do
    check("index " .. i .. " is used", seen[i] == true)
  end
end

print("\n-- Speed is log-mapped and reaches the engine --")
do
  local M = fresh(2)
  local id = "lfo.flood"
  local lo = M.lfo.rate_hz(id)
  check("centred at 0.5, well inside the range", lo > M.lfo.RATE_MIN
        and lo < M.lfo.RATE_MAX, tostring(lo))

  M.state.set_vparam(id, "rate", 0)
  check("all the way down, at the floor",
        math.abs(M.lfo.rate_hz(id) - M.lfo.RATE_MIN) < 1e-6,
        tostring(M.lfo.rate_hz(id)))

  M.state.set_vparam(id, "rate", 1)
  check("all the way up, at the ceiling",
        math.abs(M.lfo.rate_hz(id) - M.lfo.RATE_MAX) < 1e-6,
        tostring(M.lfo.rate_hz(id)))

  local page = M.cellparam.page(id)
  check("cellparam hands out the lfo page", page == M.lfo)
  check("it has four rows: Speed, Depth, Target, Param",
        page.PARAM_COUNT == 4, tostring(page.PARAM_COUNT))

  local before = #CALLS.lfo_rate
  local p = page.nudge(id, 1, 0.1)
  check("nudging Speed pushes the engine", #CALLS.lfo_rate > before)
  check("at this cell's own index",
        CALLS.lfo_rate[#CALLS.lfo_rate].index == M.topology.get(id).index,
        tostring(CALLS.lfo_rate[#CALLS.lfo_rate].index))
  check("and the rate it actually pushed", p.key == "rate")
end

print("\n-- init pushes every cell once --")
do
  local M = fresh(3)
  M.lfo.init()
  check("all four rates went out", #CALLS.lfo_rate == 4, tostring(#CALLS.lfo_rate))
end

print("\n-- a pure continuous source: no mod input, no reaction to a pulse --")
do
  local M = fresh(4)
  -- a D cell cabled straight to an LFO is a legal cable (dispatch.on_pulse
  -- falls through silently, same as a C or O cell), and must not error.
  M.patch.add("d.hob", "lfo.flood", 0.6)
  local ok = pcall(function() M.dispatch.on_pulse("d.hob", "lfo.flood",
    {id = -1, a = "d.hob", b = "lfo.flood", gain = 0.6}, 1.0) end)
  check("a pulse landing on an LFO does not error", ok)
end

print("\n-- wired to a voice: lands on the mod-path bus --")
do
  local M = fresh(5)
  M.patch.add("lfo.flood", "oak", 0.7)
  local l = M.topology.get("lfo.flood")
  local voice = M.topology.get("oak")
  local found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("lfo_out", l.index)
       and c.dst == M.bridge.bus("mod_in", voice.index - 1) then
      found = c
    end
  end
  check("a straight pass into the voice's mod path", found ~= nil)
  check("at the cable's own gain", found and math.abs(found.gain - 0.7) < 1e-9)
end

print("\n-- wired to an exciter: lands on colour_mod, same bus a gust uses --")
do
  local M = fresh(6)
  M.patch.add("lfo.ebb", "e.bracken", 0.5)
  local l = M.topology.get("lfo.ebb")
  local e = M.topology.get("e.bracken")
  local found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("lfo_out", l.index)
       and c.dst == M.bridge.bus("colour_mod", e.index) then
      found = c
    end
  end
  check("an ak spec into colour_mod", found ~= nil and found.kind == "ak",
        found and found.kind or "nil")
end

print("\n-- Target: which of the cabled cells it is aimed at --")
do
  local M = fresh(7)
  local L = "lfo.neap"
  check("no cables, no target", M.lfo.target(L) == nil)
  check("and Param falls back to signal",
        M.lfo.param_key(L) == M.lfo.SIGNAL, tostring(M.lfo.param_key(L)))

  M.patch.add(L, "gu.squall", 0.5)
  M.patch.add(L, "oak", 0.5)
  local dests = M.lfo.destinations(L)
  check("both cabled cells are destinations", #dests == 2, tostring(#dests))
  check("the first is the default target", M.lfo.target(L) == dests[1],
        tostring(M.lfo.target(L)))

  M.lfo.set_target(L, "oak")
  check("and a chosen one sticks", M.lfo.target(L) == "oak",
        tostring(M.lfo.target(L)))

  -- pulling that cable drops the target rather than leaving it pointed at
  -- something it no longer reaches.
  M.patch.remove(L, "oak")
  check("pulling the cable drops it", M.lfo.target(L) == "gu.squall",
        tostring(M.lfo.target(L)))
end

print("\n-- Param: which knob of the target it moves --")
do
  local M = fresh(17)
  local L = "lfo.flood"
  M.patch.add(L, "gu.gale", 0.5)
  M.lfo.set_target(L, "gu.gale")

  local keys = M.lfo.param_keys(L)
  check("signal is the first option", keys[1] == M.lfo.SIGNAL, tostring(keys[1]))
  check("and every row of the gust page is offered",
        #keys == M.gust.PARAM_COUNT + 1, tostring(#keys))

  check("signal is the default", M.lfo.param_key(L) == M.lfo.SIGNAL)
  check("and on signal it is not modulating anything",
        M.lfo.modulates(L, "gu.gale") == false)

  M.lfo.set_param_key(L, "timbre")
  check("a chosen key sticks", M.lfo.param_key(L) == "timbre",
        tostring(M.lfo.param_key(L)))
  check("and now it is modulating that cell",
        M.lfo.modulates(L, "gu.gale") == true)
  check("but only that cell", M.lfo.modulates(L, "gu.haar") == false)
end

print("\n-- apply(): it moves the knob and leaves the stored value alone --")
do
  local M = fresh(18)
  local L = "lfo.flood"
  M.patch.add(L, "gu.gale", 0.5)
  M.lfo.set_target(L, "gu.gale")
  M.lfo.set_param_key(L, "timbre")
  M.state.set_vparam(L, "depth", 0.4)
  M.state.set_vparam("gu.gale", "timbre", 0.5)

  local before = #CALLS.gust_timbre
  local seen = {}
  -- a quarter of a cycle at a time, so the sine is somewhere different on
  -- each of the four passes rather than all four landing on the same phase.
  M.state.set_vparam(L, "rate", 0.5)
  local hz = M.lfo.rate_hz(L)
  for _ = 1, 4 do
    M.lfo.apply()
    T = T + (0.25 / hz)
    table.insert(seen, CALLS.gust_timbre[#CALLS.gust_timbre].v)
  end

  check("it pushed the engine once per pass",
        #CALLS.gust_timbre - before == 4,
        tostring(#CALLS.gust_timbre - before))
  check("the pushed value actually moves", seen[1] ~= seen[2] or seen[2] ~= seen[3],
        table.concat({tostring(seen[1]), tostring(seen[2]), tostring(seen[3])}, " "))
  check("and it stays inside the knob's own range", (function()
    for _, v in ipairs(seen) do
      if v < 0 or v > 1 then return false end
    end
    return true
  end)())
  check("the stored value never moved",
        math.abs(M.state.get_vparam("gu.gale", "timbre", 0.5) - 0.5) < 1e-9,
        tostring(M.state.get_vparam("gu.gale", "timbre", 0.5)))

  -- and dropping back to "signal" puts the knob back where the player left
  -- it rather than leaving the engine at whatever the sine was at.
  M.lfo.set_param_key(L, M.lfo.SIGNAL)
  M.lfo.apply()
  local last = CALLS.gust_timbre[#CALLS.gust_timbre]
  check("leaving it restores the base value", math.abs(last.v - 0.5) < 1e-9,
        tostring(last.v))
end

print("\n-- a modulating LFO is not also an audio cable --")
do
  local M = fresh(19)
  local L = "lfo.flood"
  M.patch.add(L, "gu.gale", 0.5)
  local l = M.topology.get("lfo.flood")
  local gu = M.topology.get("gu.gale")
  local function live()
    local n = 0
    for _, c in ipairs(CALLS.patch_add) do
      if c.src == M.bridge.bus("lfo_out", l.index)
         and c.dst == M.bridge.bus("gust_mod", gu.index - 1) then n = n + 1 end
    end
    return n - #CALLS.patch_free
  end
  check("on signal, the audio cable exists", live() == 1, tostring(live()))

  M.lfo.set_target(L, "gu.gale")
  M.lfo.set_param_key(L, "timbre")
  check("aiming it at a knob frees that cable", #CALLS.patch_free >= 1,
        tostring(#CALLS.patch_free))

  local adds = #CALLS.patch_add
  M.lfo.set_param_key(L, M.lfo.SIGNAL)
  check("and coming back to signal rebuilds it", #CALLS.patch_add > adds,
        tostring(#CALLS.patch_add - adds))
end

print("\n-- wired to a gust: lands on its cross-mod input --")
do
  local M = fresh(8)
  M.patch.add("lfo.spring", "gu.squall", 0.5)
  local l = M.topology.get("lfo.spring")
  local gu = M.topology.get("gu.squall")
  local found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("lfo_out", l.index)
       and c.dst == M.bridge.bus("gust_mod", gu.index - 1) then
      found = c
    end
  end
  check("a straight pass into the gust's cross-mod sum", found ~= nil)
end

print("\n-- wired to an Output cell: heard directly --")
do
  local M = fresh(9)
  M.patch.add("lfo.flood", "o.1", 0.5)
  local l = M.topology.get("lfo.flood")
  local o = M.topology.get("o.1")
  local found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("lfo_out", l.index)
       and c.dst == M.bridge.bus("out", o.index) then
      found = c
    end
  end
  check("a straight pass onto that Output bus", found ~= nil)
end

print("\n-- brightness: cabled and open read brighter than idle --")
do
  local M = fresh(10)
  local id = "lfo.ebb"
  local idle = M.lfo.level_at(id, 2)
  M.patch.add("d.hob", id, 0.5)
  local cabled = M.lfo.level_at(id, 2)
  check("cabled is brighter than idle", cabled > idle, idle .. " -> " .. cabled)
  M.state.cell_edit = id
  local open = M.lfo.level_at(id, 2)
  check("an open page is brighter still", open > cabled, cabled .. " -> " .. open)
  M.state.cell_edit = nil
end

print("\n-- it pulsates: the level breathes through one sine cycle in real time --")
do
  local M = fresh(11)
  local id = "lfo.spring"
  M.state.set_vparam(id, "rate", 1.0)      -- RATE_MAX, so one cycle is quick
  local period = 1 / M.lfo.rate_hz(id)

  local lo, hi = 15, -1
  for i = 0, 20 do
    T = i * period / 20
    local lvl = M.lfo.level_at(id, 2)
    lo, hi = math.min(lo, lvl), math.max(hi, lvl)
  end
  check("it swings across its idle band over one cycle", hi > lo,
        lo .. ".." .. hi)

  -- a slower cell, sampled at a fixed real-time step, should visibly move --
  -- this is the one that would have caught a static "brighter while cabled"
  -- readout that never actually pulses.
  local M2 = fresh(12)
  local id2 = "lfo.flood"
  M2.patch.add("d.hob", id2, 0.5)
  local before = M2.lfo.level_at(id2, 2)
  T = T + (1 / M2.lfo.rate_hz(id2)) * 0.25   -- a quarter turn of its own cycle
  local after = M2.lfo.level_at(id2, 2)
  check("a quarter turn of its own cycle visibly moves the level",
        after ~= before, before .. " -> " .. after)
end

report()
