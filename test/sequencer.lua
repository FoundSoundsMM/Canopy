-- topology.lua §2.10 / lib/sequencer.lua: the Q4/Q6 step-sequencer lanes.
-- modeled directly on test/tm.lua's own shape, since sequencer.lua says of
-- itself that it is modeled on tm.lua: no phase of its own, no free clock --
-- the only thing that ever moves a lane is a pulse cabled in.
--
-- covers: (1) lane registration -- a 4-cell and a 6-cell group exist, with
-- the correct driver flags; (2) tap-toggling a step only affects that step;
-- (3) a pulse on a non-driver step fires it directly, independent of the
-- playhead; (4) a pulse on the driver cell advances the shared playhead and
-- fires whichever step it lands on, but only if that step is active; (5)
-- SEQ<->SEQ cabling is safe from runaway, the same bounded-loop shape
-- test/tm.lua's TM<->TM check has, since SEQ is in topology.PULSE_TYPES and
-- goes through the same one-tick inbox deferral.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local KNOCKER = "d.hob"

local function driver_gait(M, id, char)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = char or 1.0
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

print("\n-- lane registration: a 4-cell and a 6-cell group, correct driver flags --")
do
  local M = fresh(1)
  local q4, q6 = {}, {}
  for id, cell in M.topology.each() do
    if cell.type == "SEQ" then
      if cell.group == "q4" then table.insert(q4, id) end
      if cell.group == "q6" then table.insert(q6, id) end
    end
  end
  check("q4 has four cells", #q4 == 4, "#" .. #q4)
  check("q6 has six cells", #q6 == 6, "#" .. #q6)

  for i = 1, 4 do
    local cell = M.topology.get("q4." .. i)
    check("q4." .. i .. " step/len read right", cell.step == i and cell.len == 4,
          string.format("step=%s len=%s", tostring(cell.step), tostring(cell.len)))
    check("q4." .. i .. " driver flag is " .. tostring(i == 4),
          cell.driver == (i == 4), tostring(cell.driver))
  end
  for i = 1, 6 do
    local cell = M.topology.get("q6." .. i)
    check("q6." .. i .. " driver flag is " .. tostring(i == 6),
          cell.driver == (i == 6), tostring(cell.driver))
  end

  check("a SEQ cell is a pulse cell, same family as D, R and TM",
        M.topology.PULSE_TYPES.SEQ == true)
end

print("\n-- steps default active, and toggling one leaves its neighbours alone --")
do
  local M = fresh(1)
  check("q4.1 starts active", M.sequencer.is_active("q4.1") == true)
  check("q4.2 starts active too", M.sequencer.is_active("q4.2") == true)

  M.sequencer.toggle_step("q4.1")
  check("toggling q4.1 turns it off", M.sequencer.is_active("q4.1") == false)
  check("q4.2 is untouched", M.sequencer.is_active("q4.2") == true)
  check("q6.1 (a different lane entirely) is untouched too",
        M.sequencer.is_active("q6.1") == true)

  local now = M.sequencer.toggle_step("q4.1")
  check("toggling again flips it back, and returns the new state",
        now == true and M.sequencer.is_active("q4.1") == true)
end

print("\n-- a pulse on a non-driver step fires it directly, regardless of the playhead --")
do
  local M = fresh(1)
  M.patch.add("q4.2", "oak", 1.0)
  M.sequencer.pulse_in("q4.2", 1.0, nil, 0)
  check("an active non-driver step fires on its own pulse", #CALLS.strike == 1,
        "#" .. #CALLS.strike)
  check("the playhead never moved -- only the driver advances it",
        M.sequencer.playhead("q4") == 0, tostring(M.sequencer.playhead("q4")))

  local N = fresh(1)
  N.patch.add("q4.2", "oak", 1.0)
  N.sequencer.toggle_step("q4.2")   -- deactivate it
  N.sequencer.pulse_in("q4.2", 1.0, nil, 0)
  check("an inactive non-driver step stays silent", #CALLS.strike == 0,
        "#" .. #CALLS.strike)
end

print("\n-- a pulse on the driver advances the playhead and fires only if that step is active --")
do
  local M = fresh(1)
  M.patch.add("q4.3", "oak", 1.0)   -- the third step, the one the playhead will land on
  check("playhead starts at 0, before the lane has ever been driven",
        M.sequencer.playhead("q4") == 0)

  M.sequencer.pulse_in("q4.4", 1.0, nil, 0)   -- driver: playhead -> 1
  check("first driver pulse lands on step 1", M.sequencer.playhead("q4") == 1)
  M.sequencer.pulse_in("q4.4", 1.0, nil, 0)   -- -> 2
  M.sequencer.pulse_in("q4.4", 1.0, nil, 0)   -- -> 3, active and cabled
  check("playhead now sits on step 3", M.sequencer.playhead("q4") == 3)
  check("and it fired, because step 3 is active and cabled", #CALLS.strike == 1,
        "#" .. #CALLS.strike)

  M.sequencer.toggle_step("q4.1")             -- deactivate step 1
  M.sequencer.pulse_in("q4.4", 1.0, nil, 0)   -- -> 4 (not cabled; irrelevant here)
  M.sequencer.pulse_in("q4.4", 1.0, nil, 0)   -- wraps -> 1, now inactive
  check("playhead wraps from the last step back to the first", M.sequencer.playhead("q4") == 1)
  check("landing on a deactivated step adds no strike", #CALLS.strike == 1,
        "#" .. #CALLS.strike)
end

print("\n-- Q4 and Q6 keep entirely independent playheads --")
do
  local M = fresh(1)
  M.sequencer.pulse_in("q4.4", 1.0, nil, 0)
  check("driving q4 only moves q4's playhead",
        M.sequencer.playhead("q4") == 1 and M.sequencer.playhead("q6") == 0,
        string.format("q4=%d q6=%d", M.sequencer.playhead("q4"), M.sequencer.playhead("q6")))
end

print("\n-- info() reads out group/step/len/driver/active/playhead --")
do
  local M = fresh(1)
  local info = M.sequencer.info("q6.6")
  check("info names the driver cell correctly",
        info.group == "q6" and info.step == 6 and info.len == 6 and info.driver == true,
        string.format("%s %d/%d driver=%s", info.group, info.step, info.len, tostring(info.driver)))
  check("info returns nil for a non-SEQ id", M.sequencer.info("oak") == nil)
end

print("\n-- driven end to end through a D cell, on the scheduler --")
do
  local M = fresh(1)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver_gait(M, KNOCKER, 1.0)     -- 4 x beat = 8 Hz
  M.patch.add(KNOCKER, "q4.4", 1.0)
  M.patch.add("q4.1", "oak", 1.0)
  M.patch.add("q4.2", "rowan", 1.0)
  run(M, 3)
  check("the driver actually advanced the playhead", M.sequencer.playhead("q4") > 0,
        tostring(M.sequencer.playhead("q4")))
  check("and steps fired as it passed over them", #CALLS.strike > 0, "#" .. #CALLS.strike)
end

print("\n-- SEQ<->SEQ (and a chain through both lanes) stays bounded --")
do
  local M = fresh(3)
  driver_gait(M, KNOCKER, 1.0)
  M.patch.add(KNOCKER, "q4.4", 1.0)
  M.patch.add("q4.4", "q6.6", 0.9)   -- q4's driver feeds q6's driver
  M.patch.add("q6.6", "oak", 1.0)
  local t0 = os.clock()
  local ok = pcall(run, M, 20)
  local wall = os.clock() - t0
  check("terminates", ok)
  check("it is audibly doing something", #CALLS.strike > 0, "#" .. #CALLS.strike)
  check("20s of ticks in reasonable time", wall < 15, string.format("%.2fs", wall))
end

print("\n-- an unrelated lane cell is independent of a driven one --")
do
  local M = fresh(1)
  M.patch.add("q4.3", "oak", 1.0)
  local q6_active_before = M.sequencer.is_active("q6.3")
  for _ = 1, 5 do M.sequencer.pulse_in("q4.4", 1.0, nil, 0) end
  check("driving q4 leaves q6's own steps untouched",
        M.sequencer.is_active("q6.3") == q6_active_before)
end

report()
