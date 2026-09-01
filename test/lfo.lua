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
  check("it has exactly one row", page.PARAM_COUNT == 1,
        tostring(page.PARAM_COUNT))

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

print("\n-- wired to the heartwood: pours into heart_in --")
do
  local M = fresh(7)
  M.patch.add("lfo.neap", "h.taproot", 0.5)
  local l = M.topology.get("lfo.neap")
  local h = M.topology.get("h.taproot")
  local found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("lfo_out", l.index)
       and c.dst == M.bridge.bus("heart_in", h.index) then
      found = c
    end
  end
  check("a straight pass into the lattice", found ~= nil)
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
