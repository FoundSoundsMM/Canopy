-- §2.3b: the four TM cells (lib/tm.lua). that they're registered right,
-- above Hob/Grim and below Spriggan/Gabriel; that a TM cell never moves on
-- its own -- only a pulse cabled into it ever steps the register; that
-- Prob=1/Drift=0 is a pure rotation of the register (so its evolution is
-- fully predictable, which is what the rest of these tests lean on); that Tap
-- gates the outgoing pulse to exactly the steps where that bit reads high;
-- that a P-socket cable feeds a voice's pitch the same way a field does, and
-- Range/Bits push it live; and that TM<->TM stays bounded.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local PADFOOT, BARGHEST = "tm.padfoot", "tm.barghest"
local PUCK, TATTERFOAL = "tm.puck", "tm.tatterfoal"
local KNOCKER = "d.knocker"
local BECK = "s.beck"

local function gates(index)
  local n = 0
  for _, c in ipairs(CALLS.exciter_gate) do
    if (not index) or c.index == index then n = n + 1 end
  end
  return n
end

local function driver(M, id, char)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = char or 1.0
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

local function st(hz, root)
  return 12 * math.log(hz / (root or 55)) / math.log(2)
end

local function pitches_for(voice)
  local out = {}
  for _, c in ipairs(CALLS.voice_pitch) do
    if c.voice == voice then table.insert(out, c) end
  end
  return out
end

-- Length maps a 0..1 knob onto 2..16 steps; this is the inverse, so tests can
-- ask for an exact register size without hand-deriving the fraction.
local function set_length(M, id, n)
  M.state.set_vparam(id, "length", (n - 2) / 14)
end

print("\n-- four TM cells, above Hob/Grim and below Spriggan/Gabriel --")
do
  local M = fresh(1)
  local ids = {}
  for id, cell in M.topology.each() do
    if cell.type == "TM" then table.insert(ids, id) end
  end
  check("four of them", #ids == 4, "#" .. #ids)
  local at = {}
  for _, id in ipairs(ids) do
    local c = M.topology.get(id)
    at[c.coords[1][1] .. "," .. c.coords[1][2]] = id
  end
  check("above Hob (8,4) and Grim (9,4)", at["8,3"] and at["9,3"],
        "8,3=" .. tostring(at["8,3"]) .. " 9,3=" .. tostring(at["9,3"]))
  check("below Spriggan (8,5) and Gabriel (9,5)", at["8,6"] and at["9,6"],
        "8,6=" .. tostring(at["8,6"]) .. " 9,6=" .. tostring(at["9,6"]))
  check("a TM cell is a pulse cell, same family as D and R",
        M.topology.PULSE_TYPES.TM == true)
  check("eight parameters", M.tm.PARAM_COUNT == 8, tostring(M.tm.PARAM_COUNT))
end

print("\n-- nothing moves it but a trigger --")
do
  local M = fresh(2)
  M.patch.add(PADFOOT, "oak.pitch", 1.0)
  local before = #pitches_for(0)
  run(M, 10) -- ten seconds of scheduler ticks, nothing cabled to PADFOOT itself
  check("no further pitch pushes without a trigger", #pitches_for(0) == before,
        before .. " -> " .. #pitches_for(0))
  local r = M.tm.get(PADFOOT)
  local snapshot = {table.unpack(r.bits)}
  M.tm.pulse_in(PADFOOT, 1, nil, 0)
  local changed = false
  for i, b in ipairs(snapshot) do if r.bits[i] ~= b then changed = true end end
  check("but a direct trigger does step it", changed)
end

print("\n-- Prob=1, Drift=0 is a pure rotation, and it repeats --")
do
  local M = fresh(3)
  set_length(M, PADFOOT, 4)
  M.state.set_vparam(PADFOOT, "prob", 1.0)
  M.state.set_vparam(PADFOOT, "drift", 0.0)
  check("length reads 4", M.tm.length(PADFOOT) == 4, tostring(M.tm.length(PADFOOT)))

  local r = M.tm.get(PADFOOT)
  local start = {r.bits[1], r.bits[2], r.bits[3], r.bits[4]}
  for _ = 1, 4 do M.tm.pulse_in(PADFOOT, 1, nil, 0) end
  check("four steps of a pure rotation return to where it started",
        r.bits[1] == start[1] and r.bits[2] == start[2]
        and r.bits[3] == start[3] and r.bits[4] == start[4],
        table.concat(r.bits, ","))
end

print("\n-- Tap gates the outgoing pulse to exactly the steps where that bit is high --")
do
  local M = fresh(3)
  set_length(M, PADFOOT, 4)
  M.state.set_vparam(PADFOOT, "prob", 1.0)
  M.state.set_vparam(PADFOOT, "drift", 0.0)
  M.state.set_vparam(PADFOOT, "tap", 0) -- bit 1
  M.patch.add(PADFOOT, BECK, 1.0)

  for _ = 1, 4 do M.tm.pulse_in(PADFOOT, 1, nil, nil) end
  check("half the steps of this alternating loop tap high",
        gates() == 2, "got " .. gates())
end

print("\n-- a pulse arriving from elsewhere is deferred a tick, same as an R cell --")
do
  local M = fresh(4)
  driver(M, KNOCKER, 1.0) -- 4 x beat, rooted
  M.patch.add(KNOCKER, PADFOOT, 1.0)
  M.patch.add(PADFOOT, "oak.pitch", 1.0)
  local before = #pitches_for(0)
  run(M, 5)
  check("the register did step from Knocker's pulses", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))
end

print("\n-- a P-socket cable is a pitch source, same shape as a field --")
do
  local M = fresh(5)
  set_length(M, PADFOOT, 8)
  M.state.set_vparam(PADFOOT, "prob", 0) -- fresh coin every step: guaranteed movement
  M.patch.add(PADFOOT, "oak.pitch", 1.0)
  local seen = {}
  for i = 1, 12 do
    M.tm.pulse_in(PADFOOT, 1, nil, 0)
    local ps = pitches_for(0)
    seen[i] = st(ps[#ps].hz)
  end
  local lo, hi = seen[1], seen[1]
  for _, v in ipairs(seen) do lo, hi = math.min(lo, v), math.max(hi, v) end
  check("the pitch actually moves as the register steps", hi - lo > 0.1,
        string.format("%.2f..%.2f st", lo, hi))
end

print("\n-- Range and Bits push the cabled voice live; the sequencing knobs do not --")
do
  local M = fresh(6)
  -- the default Length (8) and its starting alternating pattern give a mixed
  -- register, so both knobs below actually have something to move -- and the
  -- nudges are large on purpose, so the snapped degree is guaranteed to cross
  -- into a different scale tone rather than landing near a boundary.
  M.state.set_vparam(PADFOOT, "range", 0)
  M.patch.add(PADFOOT, "oak.pitch", 1.0)

  local before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 5, 0.9) -- Range, narrow -> wide
  check("Range pushes immediately", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))

  M.state.set_vparam(PADFOOT, "bits", 0)
  before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 6, 0.9) -- Bits, 1 -> 7
  check("so does Bits", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))

  before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 2, 0.1) -- Prob
  M.tm.nudge(PADFOOT, 1, 0.1) -- Length
  check("Prob/Length wait for the next trigger instead",
        #pitches_for(0) == before, before .. " -> " .. #pitches_for(0))
end

print("\n-- TM<->TM stays bounded --")
do
  local M = fresh(7)
  driver(M, KNOCKER, 1.0)
  M.patch.add(KNOCKER, PADFOOT, 1.0)
  M.patch.add(PADFOOT, BARGHEST, 0.9)
  M.patch.add(BARGHEST, BECK, 1.0)
  local t0 = os.clock()
  run(M, 20)
  local wall = os.clock() - t0
  check("terminates", true)
  check("it is audibly doing something", gates() > 0, "#" .. gates())
  check("20s of ticks in reasonable time", wall < 15, string.format("%.2fs", wall))
end

print("\n-- an unrelated pair (Puck/Tatterfoal) is independent of Padfoot/Barghest --")
do
  local M = fresh(8)
  set_length(M, PUCK, 4)
  set_length(M, TATTERFOAL, 4)
  local b = M.tm.get(TATTERFOAL)
  local b_before = {table.unpack(b.bits)}
  M.tm.pulse_in(PUCK, 1, nil, 0)
  local same = true
  for i, v in ipairs(b_before) do if b.bits[i] ~= v then same = false end end
  check("stepping one TM cell leaves an uncabled sibling alone", same,
        table.concat(b_before, ",") .. " -> " .. table.concat(b.bits, ","))
end

report()
