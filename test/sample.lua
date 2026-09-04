-- topology.lua §2.5 / lib/sample.lua: the four Sample cells that replaced the
-- heartwood lattice -- Rain, Cicada, Thunder and Sea.
--
-- what this file is actually checking, in order: that the four cells took the
-- heartwood's seats and that nothing of type "H" is left anywhere on the
-- panel; that init loads one buffer per cell and pushes its whole page; that
-- the envelope knobs and the global Decay macro reach the engine in seconds
-- and stay inside the family's own limits; that a pulse down a cable plays
-- one and that -- unlike a drum or a gust -- it answers with nothing, so a
-- cable loop through one cannot run away; and that these cells are heard
-- without an Output cable, which is the one thing about them a player is
-- most likely to disbelieve.

dofile((os.getenv("SP") or "test") .. "/harness.lua")

print("== sample ==")

local RAIN, CICADA, THUNDER, SEA =
  "smp.rain", "smp.cicada", "smp.thunder", "smp.sea"

print("\n-- four cells, on the seats the heartwood had --")
do
  local M = fresh(1)
  local ids = {}
  for id, cell in M.topology.each() do
    if cell.type == "SMP" then table.insert(ids, id) end
  end
  check("there are four of them", #ids == 4, tostring(#ids))

  check("no H cell is left on the panel", (function()
    for _, cell in M.topology.each() do
      if cell.type == "H" then return false end
    end
    return true
  end)())

  -- the diagonal in from the right edge: (16,4), (15,5), (14,6), (13,7).
  local want = {{16, 4}, {15, 5}, {14, 6}, {13, 7}}
  check("on the same diagonal the lattice sat on", (function()
    for i, id in ipairs(ids) do
      local c = M.topology.get(id).coords[1]
      if c[1] ~= want[i][1] or c[2] ~= want[i][2] then return false end
    end
    return true
  end)())

  check("indexed 0..3 in that order", (function()
    for i, id in ipairs(ids) do
      if M.topology.get(id).index ~= i - 1 then return false end
    end
    return true
  end)())

  check("named for their recordings",
        M.topology.get(RAIN).name == "Rain"
        and M.topology.get(CICADA).name == "Cicada"
        and M.topology.get(THUNDER).name == "Thunder"
        and M.topology.get(SEA).name == "Sea")

  -- pan is the cell's own and the player cannot move it, exactly like a
  -- gust's -- so it has to be spread rather than all four in one place.
  local pans = {}
  for _, id in ipairs(ids) do table.insert(pans, M.topology.get(id).pan) end
  check("panned apart, right to left",
        pans[1] > pans[2] and pans[2] > pans[3] and pans[3] > pans[4],
        table.concat({pans[1], pans[2], pans[3], pans[4]}, " "))
  check("and every one of them is inside the field", (function()
    for _, p in ipairs(pans) do
      if p < -1 or p > 1 then return false end
    end
    return true
  end)())
end

print("\n-- init loads one buffer per cell and pushes its page --")
do
  local M = fresh(2)
  M.sample.init("/tmp/audio/")

  check("four loads", #CALLS.smp_load == 4, tostring(#CALLS.smp_load))
  check("each with its own file", (function()
    local want = {"/tmp/audio/Rain.wav", "/tmp/audio/Cicada.wav",
                  "/tmp/audio/Thunder.wav", "/tmp/audio/Sea.wav"}
    for i, c in ipairs(CALLS.smp_load) do
      if c.index ~= i - 1 or c.path ~= want[i] then return false end
    end
    return true
  end)())

  check("four pans, pushed once each", #CALLS.smp_pan == 4,
        tostring(#CALLS.smp_pan))
  check("and every knob on the page reached the engine",
        #CALLS.smp_attack == 4 and #CALLS.smp_decay == 4
        and #CALLS.smp_speed == 4 and #CALLS.smp_level == 4,
        table.concat({#CALLS.smp_attack, #CALLS.smp_decay,
                      #CALLS.smp_speed, #CALLS.smp_level}, " "))
end

print("\n-- the envelope: slow, and slower than a gust's --")
do
  local M = fresh(3)
  local cell = M.topology.get(THUNDER)

  -- 0.5 is "this cell's own default", the same contract every other envelope
  -- on the panel has.
  check("attack at centre is the cell's own",
        math.abs(M.sample.attack_seconds(THUNDER) - cell.attack) < 1e-6,
        tostring(M.sample.attack_seconds(THUNDER)))
  check("decay at centre is the cell's own",
        math.abs(M.sample.decay_seconds(THUNDER) - cell.decay) < 1e-6,
        tostring(M.sample.decay_seconds(THUNDER)))

  -- the knob sweeps ATTACK_OCTAVES either side of the cell's own default, so
  -- the ends are that ratio away from it rather than at the family's hard
  -- limits -- which is the point: a cell keeps its character at both ends.
  local span = 2 ^ M.sample.ATTACK_OCTAVES
  M.state.set_vparam(THUNDER, "attack", 1)
  check("all the way up is its default times the full span",
        math.abs(M.sample.attack_seconds(THUNDER) - cell.attack * span) < 1e-6,
        tostring(M.sample.attack_seconds(THUNDER)))
  M.state.set_vparam(THUNDER, "attack", 0)
  check("all the way down is its default divided by it",
        math.abs(M.sample.attack_seconds(THUNDER) - cell.attack / span) < 1e-6,
        tostring(M.sample.attack_seconds(THUNDER)))
  check("and both ends stay inside the family's own limits",
        M.sample.attack_seconds(THUNDER) >= M.sample.ATTACK_MIN
        and cell.attack * span <= M.sample.ATTACK_MAX)

  M.state.decay[THUNDER] = 1
  check("and the fall runs longer than any gust's",
        M.sample.decay_seconds(THUNDER) > M.gust.DECAY_MAX,
        tostring(M.sample.decay_seconds(THUNDER)))

  -- the point of the whole family: an attack measured in seconds, not
  -- milliseconds, at the middle of the knob.
  check("every cell swells in over a second or more at centre", (function()
    local M2 = fresh(4)
    for _, id in ipairs(M2.sample.each()) do
      if M2.sample.attack_seconds(id) < 0.7 then return false end
    end
    return true
  end)())
end

print("\n-- the global Decay macro reaches them --")
do
  local M = fresh(5)
  M.sample.init("/tmp/audio/")
  local before = M.sample.decay_seconds(SEA)

  local i
  for k = 1, M.gparam.PARAM_COUNT do
    if M.gparam.param(k).key == "decay" then i = k end
  end
  local pushed = #CALLS.smp_decay
  M.gparam.nudge(i, 40, true)

  check("it pushed every sample cell", #CALLS.smp_decay - pushed >= 4,
        tostring(#CALLS.smp_decay - pushed))
  check("and the fall actually got longer",
        M.sample.decay_seconds(SEA) > before,
        tostring(M.sample.decay_seconds(SEA)) .. " vs " .. tostring(before))
end

print("\n-- Speed is a plain ratio, centred on the recording's own --")
do
  local M = fresh(6)
  check("centre is unity", math.abs(M.sample.speed_ratio(RAIN) - 1) < 1e-9,
        tostring(M.sample.speed_ratio(RAIN)))
  M.state.set_vparam(RAIN, "speed", 1)
  check("up is faster", M.sample.speed_ratio(RAIN) > 2,
        tostring(M.sample.speed_ratio(RAIN)))
  M.state.set_vparam(RAIN, "speed", 0)
  check("down is slower", M.sample.speed_ratio(RAIN) < 0.5,
        tostring(M.sample.speed_ratio(RAIN)))
end

print("\n-- a pulse plays it, and it answers with nothing --")
do
  local M = fresh(7)
  M.patch.add("d.hob", CICADA, 0.9)
  M.rambler.set_rooted("d.hob", true)

  run(M, 6)
  check("the cable played it", #CALLS.smp_note > 0, tostring(#CALLS.smp_note))
  check("at the right slot", CALLS.smp_note[1].index == 1,
        tostring(CALLS.smp_note[1].index))
  check("and at a force the cable's gain decided",
        CALLS.smp_note[1].force > 0 and CALLS.smp_note[1].force <= 1,
        tostring(CALLS.smp_note[1].force))

  -- unlike a drum or a gust it emits no pulse of its own, so a cell cabled to
  -- one of these and back again cannot build a loop.
  local M2 = fresh(8)
  M2.patch.add("d.hob", SEA, 0.9)
  M2.patch.add(SEA, "oak", 0.9)
  M2.rambler.set_rooted("d.hob", true)
  run(M2, 6)
  check("nothing comes back out of it", #CALLS.strike == 0,
        tostring(#CALLS.strike))
end

print("\n-- K1+tap fires one, and does not warn about a missing output --")
do
  local M = fresh(9)
  local gridui = wl("gridui")
  gridui.act(THUNDER, M.topology.get(THUNDER))
  check("it sounded", #CALLS.smp_note == 1, tostring(#CALLS.smp_note))
  check("and said so without complaining about routing",
        M.state.last_event:find("no output") == nil, M.state.last_event)
end

print("\n-- the page is the same object every other cell type exposes --")
do
  local M = fresh(10)
  local page = M.cellparam.page(RAIN)
  check("cellparam hands out the sample page", page == M.sample)
  check("four rows: Attack, Decay, Speed, Level", page.PARAM_COUNT == 4,
        tostring(page.PARAM_COUNT))

  for i = 1, page.PARAM_COUNT do
    local p = page.param(i)
    check("row " .. i .. " (" .. p.label .. ") reads back in 0..1",
          type(p.get(RAIN)) == "number" and p.get(RAIN) >= 0 and p.get(RAIN) <= 1,
          tostring(p.get(RAIN)))
    check("row " .. i .. " prints something",
          type(p.text(RAIN)) == "string" and #p.text(RAIN) > 0)
  end

  local before = #CALLS.smp_level
  page.nudge(RAIN, 4, 0.1)
  check("nudging Level pushes the engine", #CALLS.smp_level > before)
end

print("\n-- the refractory swallows a double trigger, not a real one --")
do
  local M = fresh(11)
  check("the first lands", M.sample.play(RAIN, 1) == true)
  check("an immediate second does not", M.sample.play(RAIN, 1) == false)
  T = T + M.sample.REFRACTORY * 2
  check("but one a moment later does", M.sample.play(RAIN, 1) == true)
end

report()
