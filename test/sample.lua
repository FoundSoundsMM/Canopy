-- topology.lua §2.5 / lib/sample.lua: the four Sample cells -- one row above
-- the gusts, on the seats the LFOs used to hold before they spread onto the
-- two diagonals (§2.12).
--
-- what this file is actually checking, in order: that four cells took that
-- row and that nothing of type "H" or "F" is left anywhere on the panel;
-- that the folder is scanned into a File row and that the row moves a cell
-- from one recording to another without disturbing its other knobs; that one
-- shot and loop mean what they say and that the loop toggles; that init loads
-- one buffer per cell and pushes its whole page; that the envelope knobs and
-- the global Decay macro reach the engine in seconds and stay inside the
-- family's own limits; that a pulse down a cable plays one and that -- unlike
-- a drum or a gust -- it answers with nothing, so a cable loop through one
-- cannot run away; and that these cells are heard WITHOUT an Output cable,
-- which is the one thing about them a player is most likely to disbelieve.

dofile((os.getenv("SP") or "test") .. "/harness.lua")

print("== sample ==")

-- these four kept their spellings from the original set of eight (the other
-- four -- Fen, Mire, Carr, Holt -- gave their diagonal to the LFOs, §2.12),
-- so saved patches cabled to them still load. the names on the panel are
-- Sample 1..4, in registration order.
local RAIN, CICADA, THUNDER, SEA =
  "smp.rain", "smp.cicada", "smp.thunder", "smp.sea"

local function ids_of(M)
  local ids = {}
  for id, cell in M.topology.each() do
    if cell.type == "SMP" then table.insert(ids, id) end
  end
  return ids
end

print("\n-- four cells, in a row above the gusts --")
do
  local M = fresh(1)
  local ids = ids_of(M)
  check("there are four of them", #ids == 4, tostring(#ids))

  check("no H cell is left on the panel", (function()
    for _, cell in M.topology.each() do
      if cell.type == "H" then return false end
    end
    return true
  end)())

  -- §2.6 the grove went with this change: the left-hand diagonal is where its
  -- four F cells were.
  check("and no F cell either", (function()
    for _, cell in M.topology.each() do
      if cell.type == "F" then return false end
    end
    return true
  end)())

  -- the row the four LFOs used to hold, right above the gusts.
  local want = {{7, 6}, {8, 6}, {9, 6}, {10, 6}}
  check("the row the LFOs left behind", (function()
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

  -- named by number, not by a recording: a seat does not own one any more.
  check("named Sample 1..4",
        M.topology.get(RAIN).name == "Sample 1"
        and M.topology.get(SEA).name == "Sample 4",
        M.topology.get(RAIN).name .. " / " .. M.topology.get(SEA).name)

  -- this family mixes itself, but carries no pan of its own -- every cell
  -- centred, whichever seat it sits in.
  check("every cell is centred, no pan of its own", (function()
    for _, id in ipairs(ids) do
      if M.topology.get(id).pan ~= 0 then return false end
    end
    return true
  end)())
end

print("\n-- the folder is a knob: the File row --")
do
  local M = fresh(2)
  M.sample.init("/tmp/audio/")

  -- only the playable files, sorted, with the directory entry and the .txt
  -- left out.
  local files = M.sample.files()
  check("four playable files out of six entries", #files == 4, tostring(#files))
  check("sorted by name, so the row's order is stable across loads",
        files[1].name == "Cicada.wav" and files[4].name == "Thunder.wav",
        files[1].name .. " .. " .. files[4].name)
  check("and the row prints them without their extension",
        files[1].label == "Cicada", files[1].label)

  -- the four seats spread across whatever is in the folder rather than all
  -- landing on the first entry -- one seat per file, with four of each.
  local seen = {}
  for _, id in ipairs(ids_of(M)) do
    seen[M.sample.file_name(id)] = (seen[M.sample.file_name(id)] or 0) + 1
  end
  check("the four cells spread across the four files", (function()
    local n = 0
    for _, count in pairs(seen) do
      n = n + 1
      if count ~= 1 then return false end
    end
    return n == 4
  end)())

  -- moving the row loads a different buffer, and only when it lands on one.
  -- three detents is one entry: cellparam.DETENTS_PER_STEP, the same feel a
  -- gait bank and a Clock cell's ratio ladder have, and the reason a folder
  -- of four files is not twenty detents an entry.
  local before = #CALLS.smp_load
  local page = M.cellparam.page(RAIN)
  local was = M.sample.file_name(RAIN)
  for _ = 1, 3 do page.nudge(RAIN, 1, 1 / 80) end
  check("three detents move it one entry along",
        M.sample.file_name(RAIN) ~= was,
        tostring(was) .. " -> " .. tostring(M.sample.file_name(RAIN)))
  check("and loaded exactly that one, once",
        #CALLS.smp_load == before + 1
        and CALLS.smp_load[#CALLS.smp_load].path
            == "/tmp/audio/" .. M.sample.file_name(RAIN),
        tostring(#CALLS.smp_load - before))

  -- a Buffer.read frees and restarts the cell's synth, so a row that re-sent
  -- the same path every detent would be re-reading a 12 MB file per click.
  local at = #CALLS.smp_load
  page.nudge(RAIN, 1, 1 / 8000)
  check("and does not re-load the one it is already holding",
        #CALLS.smp_load == at, tostring(#CALLS.smp_load - at))

  -- §8.6 the trim is the RECORDING's, so it follows the row rather than the
  -- cell: a seat holding Rain is trimmed like Rain wherever that seat is.
  local M2 = fresh(21)
  M2.sample.init("/tmp/audio/")
  local rain_i, cicada_i
  for i, f in ipairs(M2.sample.files()) do
    if f.name == "Rain.wav" then rain_i = i end
    if f.name == "Cicada.wav" then cicada_i = i end
  end
  M2.state.set_vparam(RAIN, "file", (rain_i - 0.5) / 4)
  local on_rain = M2.sample.amp(RAIN)
  M2.state.set_vparam(RAIN, "file", (cicada_i - 0.5) / 4)
  check("the trim follows the recording, not the seat",
        M2.sample.amp(RAIN) > on_rain,
        on_rain .. " -> " .. M2.sample.amp(RAIN))
end

print("\n-- a folder that cannot be read falls back to what ships --")
do
  local was = SCANDIR_FILES
  SCANDIR_FILES = nil
  local M = fresh(22)
  M.sample.init("/tmp/audio/")
  check("the four shipped recordings stand in", #M.sample.files() == 4,
        tostring(#M.sample.files()))
  check("and every cell still has something to load",
        #CALLS.smp_load == 4, tostring(#CALLS.smp_load))
  SCANDIR_FILES = was
end

print("\n-- one shot or loop --")
do
  local M = fresh(23)
  M.sample.init("/tmp/audio/")

  check("one shot is the default", M.sample.looping(RAIN) == false)
  check("and the engine was told so",
        (function()
          for k = #CALLS.smp_loop, 1, -1 do
            if CALLS.smp_loop[k].index == M.topology.get(RAIN).index then
              return CALLS.smp_loop[k].on == 0
            end
          end
        end)())

  -- a one-shot cell plays and that is the whole gesture: no gate either way.
  local gates = #CALLS.smp_gate
  check("a one-shot arrival plays it", M.sample.play(RAIN, 1) == true)
  check("and opens no gate", #CALLS.smp_gate == gates)

  -- a looping cell toggles instead.
  M.sample.set_looping(CICADA, true)
  local idx = M.topology.get(CICADA).index
  check("the first arrival opens the gate", M.sample.play(CICADA, 1) == true)
  check("and it is held", M.sample.is_held(CICADA) == true)
  check("the engine saw the gate go up",
        CALLS.smp_gate[#CALLS.smp_gate].index == idx
        and CALLS.smp_gate[#CALLS.smp_gate].on == 1)
  -- ...and a note, so the buffer starts from the top rather than wherever it
  -- happened to be.
  check("and the buffer was started from the top",
        CALLS.smp_note[#CALLS.smp_note].index == idx)

  T = T + M.sample.REFRACTORY * 2
  check("the next arrival lets it go", M.sample.play(CICADA, 1) == true)
  check("and it is no longer held", M.sample.is_held(CICADA) == false)
  check("the engine saw the gate come down",
        CALLS.smp_gate[#CALLS.smp_gate].on == 0)

  -- turning the row back to one shot while it is running has to stop it, or
  -- the toggle that would have stopped it is the row that has just gone.
  T = T + M.sample.REFRACTORY * 2
  M.sample.play(CICADA, 1)
  check("held again", M.sample.is_held(CICADA) == true)
  local page = M.cellparam.page(CICADA)
  page.PARAMS[2].set(CICADA, 0)
  check("switching back to one shot releases it",
        M.sample.is_held(CICADA) == false)
  check("and the gate came down with it",
        CALLS.smp_gate[#CALLS.smp_gate].on == 0)
end

print("\n-- it is heard with no cable at all, and a cable is still a cable --")
do
  local M = fresh(3)
  M.sample.init("/tmp/audio/")

  -- the automatic route: one pan per cell, pushed once, from its seat.
  check("every cell's pan reached the engine", #CALLS.smp_pan == 4,
        tostring(#CALLS.smp_pan))

  -- K1+tap an uncabled one and nothing warns, because nothing is wrong: this
  -- family and the gusts are the two that route themselves.
  local gridui = wl("gridui")
  gridui.act(THUNDER, M.topology.get(THUNDER))
  check("K1+tap sounds it", #CALLS.smp_note == 1, tostring(#CALLS.smp_note))
  check("and does not warn about an output cable",
        M.state.last_event:find("no output") == nil, M.state.last_event)

  -- a cable to an Out cell is still allowed and still places a second copy.
  local before = #CALLS.patch_add
  M.patch.add(RAIN, "o.4", 0.8)
  M.dispatch.resync_matrix()
  check("cabling one to an Out cell builds an audio patch",
        #CALLS.patch_add == before + 1, tostring(#CALLS.patch_add - before))
  local spec = CALLS.patch_add[#CALLS.patch_add]
  check("audio-rate, off this cell's own tap", spec.kind == "aa"
        and spec.src == M.bridge.bus("smp_out", M.topology.get(RAIN).index),
        tostring(spec.kind) .. " " .. tostring(spec.src))
  check("and into that Out cell's bus",
        spec.dst == M.bridge.bus("out", M.topology.get("o.4").index),
        tostring(spec.dst))
end

print("\n-- init loads one buffer per cell and pushes its page --")
do
  local M = fresh(4)
  M.sample.init("/tmp/audio/")

  check("four loads", #CALLS.smp_load == 4, tostring(#CALLS.smp_load))
  check("one per slot, each on its own default file", (function()
    for i, c in ipairs(CALLS.smp_load) do
      if c.index ~= i - 1 then return false end
      if not c.path:match("^/tmp/audio/") then return false end
    end
    return true
  end)())

  check("and every knob on the page reached the engine",
        #CALLS.smp_attack == 4 and #CALLS.smp_decay == 4
        and #CALLS.smp_speed == 4 and #CALLS.smp_loop == 4
        -- Level goes out twice per cell: the File row pushes it too, because
        -- the trim it carries belongs to the recording.
        and #CALLS.smp_level == 8,
        table.concat({#CALLS.smp_attack, #CALLS.smp_decay, #CALLS.smp_speed,
                      #CALLS.smp_loop, #CALLS.smp_level}, " "))
end

print("\n-- the envelope: slow, and slower than a gust's --")
do
  local M = fresh(5)
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
    local M2 = fresh(6)
    for _, id in ipairs(M2.sample.each()) do
      if M2.sample.attack_seconds(id) < 0.7 then return false end
    end
    return true
  end)())
end

print("\n-- the global Decay macro reaches them --")
do
  local M = fresh(7)
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
  local M = fresh(8)
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
  local M = fresh(9)
  M.patch.add("d.hob", CICADA, 0.9)
  M.rambler.set_rooted("d.hob", true)

  run(M, 6)
  check("the cable played it", #CALLS.smp_note > 0, tostring(#CALLS.smp_note))
  check("at the right slot",
        CALLS.smp_note[1].index == M.topology.get(CICADA).index,
        tostring(CALLS.smp_note[1].index))
  check("and at a force the cable's gain decided",
        CALLS.smp_note[1].force > 0 and CALLS.smp_note[1].force <= 1,
        tostring(CALLS.smp_note[1].force))

  -- unlike a drum or a gust it emits no pulse of its own, so a cell cabled to
  -- one of these and back again cannot build a loop.
  local M2 = fresh(10)
  M2.patch.add("d.hob", SEA, 0.9)
  M2.patch.add(SEA, "oak", 0.9)
  M2.rambler.set_rooted("d.hob", true)
  run(M2, 6)
  check("nothing comes back out of it", #CALLS.strike == 0,
        tostring(#CALLS.strike))
end

print("\n-- the page is the same object every other cell type exposes --")
do
  local M = fresh(11)
  M.sample.init("/tmp/audio/")
  local page = M.cellparam.page(RAIN)
  check("cellparam hands out the sample page", page == M.sample)
  check("seven rows: File, Mode, Attack, Decay, Speed, Level, Send",
        page.PARAM_COUNT == 7, tostring(page.PARAM_COUNT))
  check("and File is the first of them", page.param(1).key == "file",
        tostring(page.param(1).key))
  check("and Send the last", page.param(7).key == "send",
        tostring(page.param(7).key))

  for i = 1, page.PARAM_COUNT do
    local p = page.param(i)
    check("row " .. i .. " (" .. p.label .. ") reads back in 0..1",
          type(p.get(RAIN)) == "number" and p.get(RAIN) >= 0 and p.get(RAIN) <= 1,
          tostring(p.get(RAIN)))
    check("row " .. i .. " prints something",
          type(p.text(RAIN)) == "string" and #p.text(RAIN) > 0)
  end

  local before = #CALLS.smp_level
  local level_i
  for i = 1, page.PARAM_COUNT do
    if page.param(i).key == "level" then level_i = i end
  end
  page.nudge(RAIN, level_i, 0.1)
  check("nudging Level pushes the engine", #CALLS.smp_level > before)
end

print("\n-- the refractory swallows a double trigger, not a real one --")
do
  local M = fresh(12)
  check("the first lands", M.sample.play(RAIN, 1) == true)
  check("an immediate second does not", M.sample.play(RAIN, 1) == false)
  T = T + M.sample.REFRACTORY * 2
  check("but one a moment later does", M.sample.play(RAIN, 1) == true)
end

print("\n-- §8.6 the level match: the trim reaches the engine, square-rooted --")
do
  local M = fresh(41)
  M.sample.init("/tmp/audio/")
  for _, id in ipairs(M.sample.each()) do
    local cell = M.topology.get(id)
    local trim = M.sample.FILE_TRIM[M.sample.file_name(id)] or 1
    -- the engine squares `level`, so the trim goes in as its square root and
    -- comes out the far side as a plain gain.
    local want = M.sample.level(id) * math.sqrt(trim)
    local got
    for k = #CALLS.smp_level, 1, -1 do
      if CALLS.smp_level[k].index == cell.index then got = CALLS.smp_level[k].v break end
    end
    check(id .. " goes out trimmed", got and math.abs(got - want) < 1e-9,
          got and string.format("%.4f vs %.4f", got, want))
    -- what that square root buys: the knob cannot be pushed past the engine's
    -- own clip at any position, all the way to the top of the fader.
    check(id .. " stays inside the engine's clip at full fader",
          1.0 * math.sqrt(trim) <= 1.0)
  end
  -- a file nobody measured is left alone: guessing at a trim for a recording
  -- the player dropped in would be worse than not having one.
  check("an unknown recording gets no trim",
        (M.sample.FILE_TRIM["something-of-mine.wav"] or 1) == 1)
end

report()
