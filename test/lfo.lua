-- topology.lua §2.12 / lib/lfo.lua: the four LFO cells above the gusts.
--
-- covers: (1) four cells, one row, above the gust rows; (2) the Speed page
-- reaches the engine, log-mapped end to end; (3) it is a pure continuous
-- source -- cabled to a voice, an exciter, a gust or an Output cell it lands
-- on that cell's usual continuous bus, and a pulse landing on it does
-- nothing; (4) cellparam hands out the module's own page; (5) the four
-- destination slots are independent, and (6) the eight shapes are the eight
-- the engine knows, in the same order.
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
  -- the free half of the row: a cell comes up synced (lfo.SYNC_DEFAULT), and
  -- what is under test here is the Hz sweep, so this one is set free first.
  M.lfo.set_synced(id, false)
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
  check("it has seven rows: Speed, Sync, Shape, Slot, Target, Param, Depth",
        page.PARAM_COUNT == 7, tostring(page.PARAM_COUNT))
  local keys = {}
  for i, p in ipairs(page.PARAMS) do keys[i] = p.key end
  check("in that order",
        table.concat(keys, ",") == "rate,sync,shape,slot,target,param,depth",
        table.concat(keys, ","))

  local before = #CALLS.lfo_rate
  local p = page.nudge(id, 1, 0.1)
  check("nudging Speed pushes the engine", #CALLS.lfo_rate > before)
  check("at this cell's own index",
        CALLS.lfo_rate[#CALLS.lfo_rate].index == M.topology.get(id).index,
        tostring(CALLS.lfo_rate[#CALLS.lfo_rate].index))
  check("and the rate it actually pushed", p.key == "rate")
end

print("\n-- §2.12b Sync: the same knob, measured against the transport --")
do
  local M = fresh(20)
  local id = "lfo.flood"
  local page = M.cellparam.page(id)
  local row = page.PARAMS[1]

  -- §2.12b synced is the default: everything else on the panel is in time
  -- and a modulator that is not is the exception, not the norm.
  check("a fresh cell is synced", M.lfo.synced(id) == true)

  -- free and synced keep separate knobs, so flipping back and forth is
  -- lossless.
  M.lfo.set_synced(id, false)
  M.state.set_vparam(id, "rate", 0.9)
  local free_hz = M.lfo.rate_hz(id)
  M.lfo.set_synced(id, true)
  check("Sync flips", M.lfo.synced(id) == true)
  M.state.set_vparam(id, "ratio", 0.0)
  M.lfo.set_synced(id, false)
  check("the free Speed survived the trip",
        math.abs(M.lfo.rate_hz(id) - free_hz) < 1e-9, tostring(M.lfo.rate_hz(id)))
  M.lfo.set_synced(id, true)
  local r = select(1, M.lfo.ratio(id))
  check("and so did the ratio", math.abs(r - M.clockcell.RATIOS[1][1]) < 1e-9,
        tostring(r))

  -- the ladder is the Clock cell's own, ends and centre.
  M.state.set_vparam(id, "ratio", 0.5)
  local rr, name = M.lfo.ratio(id)
  check("the middle detent is 1 x", rr == 1 and name == "1 x", name)
  M.state.set_vparam(id, "ratio", 1.0)
  rr, name = M.lfo.ratio(id)
  check("the top is the fastest multiple",
        rr == M.clockcell.RATIOS[#M.clockcell.RATIOS][1], name)
  M.state.set_vparam(id, "ratio", 0.0)
  rr, name = M.lfo.ratio(id)
  check("the bottom is the deepest division",
        rr == M.clockcell.RATIOS[1][1], name)

  -- a rate in the transport's terms, not the wall clock's.
  M.state.set_vparam(id, "ratio", 0.5)          -- 1 x
  check("1 x at 120 BPM is 2 Hz", math.abs(M.lfo.rate_hz(id) - 2.0) < 1e-9,
        tostring(M.lfo.rate_hz(id)))
  params:set("clock_tempo", 60)
  check("and 1 Hz at 60", math.abs(M.lfo.rate_hz(id) - 1.0) < 1e-9,
        tostring(M.lfo.rate_hz(id)))
  params:set("clock_tempo", 120)
  M.state.set_vparam(id, "ratio", M.clockcell.char_for_ratio(1/4))
  check("a ratio of 1/4 is one cycle every four beats",
        math.abs(M.lfo.rate_hz(id) - 0.5) < 1e-9, tostring(M.lfo.rate_hz(id)))
  M.state.set_vparam(id, "ratio", 0.5)

  -- the row prints the unit it is actually in.
  check("synced, the row names the ratio", row.text(id) == "1 x", row.text(id))
  check("and its label says so",
        M.cellparam.label_of(row, id) == "Ratio", M.cellparam.label_of(row, id))
  M.lfo.set_synced(id, false)
  check("free, it prints hertz", row.text(id):match("Hz") ~= nil, row.text(id))
  check("and is called Speed",
        M.cellparam.label_of(row, id) == "Speed", M.cellparam.label_of(row, id))
end

print("\n-- a synced LFO reads its phase off the transport --")
do
  local M = fresh(21)
  local a, b = "lfo.flood", "lfo.ebb"
  for _, id in ipairs({a, b}) do
    M.lfo.set_synced(id, true)
    M.state.set_vparam(id, "ratio", 0.5)      -- 1 x: one cycle a beat
  end

  -- exactly on a beat, exactly at the start of the cycle. wall time never
  -- enters into it, so this holds at any point in the run rather than only
  -- at the first call.
  T = 60 / TEMPO * 8                          -- eight beats in
  check("on the beat, the cycle is at zero", math.abs(M.lfo.phase(a)) < 1e-9,
        tostring(M.lfo.phase(a)))
  T = T + (60 / TEMPO) * 0.25
  check("a quarter beat later, a quarter through",
        math.abs(M.lfo.phase(a) - 0.25) < 1e-9, tostring(M.lfo.phase(a)))

  -- two cells at the same ratio are in step with each other, which is the
  -- thing a matched Hz cannot promise.
  check("and the other cell is exactly with it",
        math.abs(M.lfo.phase(a) - M.lfo.phase(b)) < 1e-9)

  -- a division is slower by exactly that much: at 1/4 the cycle is a bar.
  M.state.set_vparam(b, "ratio", M.clockcell.char_for_ratio(1/4))
  T = 60 / TEMPO * 2                          -- two beats: half a bar
  check("at 1/4, two beats is half a cycle",
        math.abs(M.lfo.phase(b) - 0.5) < 1e-9, tostring(M.lfo.phase(b)))

  -- a free cell is unaffected by any of this: it still integrates wall time.
  local c = "lfo.eddy"
  M.lfo.set_synced(c, false)
  M.state.set_vparam(c, "rate", 0.5)
  local p0 = M.lfo.phase(c)
  T = T + 0.5
  local p1 = M.lfo.phase(c)
  check("a free cell still runs off the wall clock", p1 ~= p0)
end

print("\n-- a tempo change moves the engine's rate with nothing touched --")
do
  local M = fresh(22)
  local id = "lfo.flood"
  M.lfo.set_synced(id, true)
  M.state.set_vparam(id, "ratio", 0.5)        -- 1 x
  -- lfo.apply reconciles all four cells, so pick this one's out of the batch
  -- rather than trusting whichever happened to go last.
  local idx = M.topology.get(id).index
  local function last_for(i)
    for k = #CALLS.lfo_rate, 1, -1 do
      if CALLS.lfo_rate[k].index == i then return CALLS.lfo_rate[k] end
    end
  end

  M.lfo.apply()
  local first = last_for(idx)
  check("the synced rate went out", first and math.abs(first.hz - 2.0) < 1e-9,
        first and tostring(first.hz))

  local n = #CALLS.lfo_rate
  M.lfo.apply()
  check("and is not sent again while nothing moves", #CALLS.lfo_rate == n,
        tostring(#CALLS.lfo_rate))

  params:set("clock_tempo", 90)
  M.lfo.apply()
  local last = last_for(idx)
  check("a tempo change alone re-sends it",
        #CALLS.lfo_rate > n and math.abs(last.hz - 1.5) < 1e-9,
        last and tostring(last.hz))
  check("and a free cell's rate did not move with it",
        math.abs(last_for(M.topology.get("lfo.ebb").index).hz
                 - M.lfo.rate_hz("lfo.ebb")) < 1e-9)
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
  -- something it no longer reaches. it goes IDLE rather than sliding onto
  -- whatever else happens to be cabled: the player named a destination, and
  -- silently re-aiming a modulator at a different one is worse than stopping.
  M.patch.remove(L, "oak")
  check("pulling the cable drops it", M.lfo.target(L) == nil,
        tostring(M.lfo.target(L)))

  -- an untouched slot 1 does still follow the cables, which is what keeps a
  -- freshly patched LFO working without opening its page at all.
  local M2 = fresh(20)
  M2.patch.add("lfo.neap", "gu.squall", 0.5)
  check("an untouched slot aims itself at the one cable",
        M2.lfo.target("lfo.neap") == "gu.squall",
        tostring(M2.lfo.target("lfo.neap")))
end

print("\n-- four slots, each with its own target, param and depth --")
do
  local M = fresh(21)
  local L = "lfo.flood"
  check("four of them", M.lfo.SLOTS == 4, tostring(M.lfo.SLOTS))
  M.patch.add(L, "gu.gale", 0.5)
  M.patch.add(L, "oak", 0.5)

  M.lfo.set_target(L, "gu.gale", 1)
  M.lfo.set_param_key(L, "timbre", 1)
  M.lfo.set_depth(L, 0.5, 1)
  M.lfo.set_target(L, "oak", 2)
  M.lfo.set_param_key(L, "bright", 2)
  M.lfo.set_depth(L, 0.1, 2)

  check("slot 1 holds its own pair", M.lfo.target(L, 1) == "gu.gale"
        and M.lfo.param_key(L, 1) == "timbre")
  check("slot 2 holds a different one", M.lfo.target(L, 2) == "oak"
        and M.lfo.param_key(L, 2) == "bright")
  check("with their own depths", math.abs(M.lfo.depth(L, 1) - 0.5) < 1e-9
        and math.abs(M.lfo.depth(L, 2) - 0.1) < 1e-9,
        M.lfo.depth(L, 1) .. " " .. M.lfo.depth(L, 2))
  check("slots 3 and 4 are off", M.lfo.target(L, 3) == nil
        and M.lfo.target(L, 4) == nil)
  check("and it counts as modulating both cells",
        M.lfo.modulates(L, "gu.gale") and M.lfo.modulates(L, "oak"))

  -- one pass moves both, from the same value of the shape.
  local timbre_before = #CALLS.gust_timbre
  local bright_before = #CALLS.voice_bright
  M.lfo.apply()
  check("one pass pushes both destinations",
        #CALLS.gust_timbre > timbre_before and #CALLS.voice_bright > bright_before)
  check("and neither stored value moved",
        math.abs(M.state.get_vparam("gu.gale", "timbre", 0.35) - 0.35) < 1e-9
        and math.abs(M.state.get_vparam("oak", "bright", 0.5) - 0.5) < 1e-9)

  -- the Slot row is what the page's Target/Param/Depth rows follow.
  M.state.set_vparam(L, "slot", 0)
  check("the page starts on slot 1", M.lfo.slot(L) == 1, tostring(M.lfo.slot(L)))
  check("and Target with no slot given reads slot 1",
        M.lfo.target(L) == "gu.gale", tostring(M.lfo.target(L)))
  M.state.set_vparam(L, "slot", 0.3)
  check("moving the row moves to slot 2", M.lfo.slot(L) == 2,
        tostring(M.lfo.slot(L)))
  check("and Target follows it", M.lfo.target(L) == "oak",
        tostring(M.lfo.target(L)))
end

print("\n-- eight shapes, and the engine is told which --")
do
  local M = fresh(22)
  local L = "lfo.ebb"
  check("eight of them", #M.lfo.SHAPES == 8, tostring(#M.lfo.SHAPES))
  check("sine first, follow last",
        M.lfo.SHAPES[1] == "sine" and M.lfo.SHAPES[8] == "follow",
        M.lfo.SHAPES[1] .. ".." .. M.lfo.SHAPES[8])

  -- every position on the knob reads back as itself, and pushes the index the
  -- engine expects: 0-based, in the table's own order.
  for i = 1, #M.lfo.SHAPES do
    M.state.set_vparam(L, "shape", (i - 0.5) / #M.lfo.SHAPES)
    check("position " .. i .. " is " .. M.lfo.SHAPES[i],
          M.lfo.shape_index(L) == i and M.lfo.shape(L) == M.lfo.SHAPES[i],
          tostring(M.lfo.shape_index(L)))
  end

  local before = #CALLS.lfo_shape
  M.lfo.param(3).push(L)
  check("pushing Shape reaches the engine", #CALLS.lfo_shape > before)
  local c = CALLS.lfo_shape[#CALLS.lfo_shape]
  check("0-based, at this cell's index",
        c.n == #M.lfo.SHAPES - 1 and c.index == M.topology.get(L).index,
        c.index .. " " .. c.n)

  -- every shape stays inside -1..+1 across a whole cycle, which is what lets
  -- Depth mean the same thing whichever one is running.
  M.state.set_vparam(L, "rate", 1.0)
  local period = 1 / M.lfo.rate_hz(L)
  for i = 1, #M.lfo.SHAPES do
    M.state.set_vparam(L, "shape", (i - 0.5) / #M.lfo.SHAPES)
    local lo, hi = 2, -2
    for k = 0, 24 do
      T = T + period / 25
      local v = M.lfo.value(L)
      lo, hi = math.min(lo, v), math.max(hi, v)
    end
    check(M.lfo.SHAPES[i] .. " stays bipolar and bounded",
          lo >= -1.0001 and hi <= 1.0001,
          string.format("%.3f..%.3f", lo, hi))
  end

  -- the oscillator shapes actually move; the follower with nothing cabled
  -- sits still at the bottom, which is the honest reading of a silent patch.
  for i = 1, 7 do
    M.state.set_vparam(L, "shape", (i - 0.5) / #M.lfo.SHAPES)
    -- eleven samples over two cycles rather than five over one: a
    -- sample-and-hold only changes at the wrap, and a five-sample window can
    -- put the wrap on its first sample and read flat for the rest.
    local seen = {}
    for k = 1, 11 do
      T = T + period / 5
      seen[k] = M.lfo.value(L)
    end
    local moved = false
    for k = 2, 11 do if seen[k] ~= seen[1] then moved = true end end
    check(M.lfo.SHAPES[i] .. " moves over a cycle", moved)
  end
  M.state.set_vparam(L, "shape", 7.5 / 8)
  check("follow reads the outputs, and sits at rest with none cabled",
        M.lfo.shape(L) == "follow" and M.lfo.value(L) == -1,
        tostring(M.lfo.value(L)))
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

print("\n-- it reaches an SFX loop's Level, which is a cable, not a special case --")
do
  local M = fresh(31)
  local L, SM = "lfo.flood", "smp.rain"
  M.patch.add(L, SM, 1.0)
  check("a sample cell is a legal target", M.lfo.target(L) == SM,
        tostring(M.lfo.target(L)))
  -- the four SFX loops were the one family with nothing an LFO could move:
  -- they had no knob on a bus, so an LFO cable did nothing at all. every
  -- row of every page is reachable now, Level included.
  local keys = {}
  for _, k in ipairs(M.lfo.param_keys(L)) do keys[k] = true end
  check("and its Level is one of the knobs on offer", keys["level"] == true,
        table.concat(M.lfo.param_keys(L), ","))

  M.lfo.set_param_key(L, "level")
  M.state.set_vparam(L, "depth", 0.25)
  M.state.set_vparam(SM, "level", 0.5)
  M.state.set_vparam(L, "rate", 0.5)
  local hz = M.lfo.rate_hz(L)
  local before = #CALLS.smp_level
  local seen = {}
  for _ = 1, 4 do
    M.lfo.apply()
    T = T + (0.25 / hz)
    table.insert(seen, CALLS.smp_level[#CALLS.smp_level].v)
  end
  check("it pushed the sample's level once per pass",
        #CALLS.smp_level - before == 4, tostring(#CALLS.smp_level - before))
  check("and the pushed value actually moves",
        seen[1] ~= seen[2] or seen[2] ~= seen[3],
        table.concat({tostring(seen[1]), tostring(seen[2])}, " "))
  check("while the stored Level never moved",
        math.abs(M.sample.level(SM) - 0.5) < 1e-9, tostring(M.sample.level(SM)))
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
