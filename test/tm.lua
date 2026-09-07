-- §2.3b: the four TM cells (lib/tm.lua). that they're registered right,
-- flanking the D-cell block on row 4; that a TM cell never moves on its own
-- -- only a pulse cabled into it ever steps the register; that Deja=1/
-- Drift=0 is a pure rotation of the register (so its evolution is fully
-- predictable, which is what the rest of these tests lean on); that it emits
-- NO pulse of its own any more, whatever the register is doing (the Marbles
-- rework -- the trigger half of the module is gone, and the panel's other
-- four pulse families do that job); that cabling a TM cell directly to a
-- voice feeds its pitch the same way a field does (the socket collapse means
-- there is no separate P socket left to require), and Spread/Bias/Steps push
-- it live; and that the Steps ladder walks from continuous to locked.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local PADFOOT, BARGHEST = "tm.padfoot", "tm.barghest"
local PUCK, TATTERFOAL = "tm.puck", "tm.tatterfoal"
local KNOCKER = "d.hob"
local BECK = "e.bracken"

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

print("\n-- four TM cells, flanking the D-cell block on row 4 --")
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
  -- row 4 now reads: F . . TM TM C T T T T C TM TM . . H (topology.lua §2)
  check("Padfoot and Barghest sit left of it, at (4,4)/(5,4)",
        at["4,4"] and at["5,4"],
        "4,4=" .. tostring(at["4,4"]) .. " 5,4=" .. tostring(at["5,4"]))
  check("Puck and Tatterfoal sit right of it, at (12,4)/(13,4)",
        at["12,4"] and at["13,4"],
        "12,4=" .. tostring(at["12,4"]) .. " 13,4=" .. tostring(at["13,4"]))
  check("a TM cell is a pulse cell, same family as D and R",
        M.topology.PULSE_TYPES.TM == true)
  check("six parameters: Length, Deja, Drift, Spread, Bias, Steps",
        M.tm.PARAM_COUNT == 6, tostring(M.tm.PARAM_COUNT))
  local keys = {}
  for _, p in ipairs(M.tm.PARAMS) do keys[p.key] = true end
  check("Tap is gone with the trigger half of the module", keys.tap == nil)
  check("and so is its Level", keys.level == nil)
end

print("\n-- nothing moves it but a trigger --")
do
  local M = fresh(2)
  M.patch.add(PADFOOT, "oak", 1.0)
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

print("\n-- Deja=1, Drift=0 is a pure rotation, and it repeats --")
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

print("\n-- it answers with a note and never with a pulse --")
do
  local M = fresh(3)
  set_length(M, PADFOOT, 4)
  M.state.set_vparam(PADFOOT, "prob", 1.0)
  M.state.set_vparam(PADFOOT, "drift", 0.0)
  -- an exciter is the cheapest witness for "did a pulse leave this cell":
  -- one grain per pulse, counted by `gates()`. every bit of this register is
  -- high on half its steps, so the old Tap-gated output would have fired
  -- twice over these four clocks.
  M.patch.add(PADFOOT, BECK, 1.0)

  for _ = 1, 4 do M.tm.pulse_in(PADFOOT, 1, nil, nil) end
  check("four clock edges and not one outgoing pulse", gates() == 0,
        "got " .. gates())

  -- and the same through the scheduler, where an emitted pulse would be
  -- queued on the inbox rather than delivered inline.
  local M2 = fresh(13)
  driver(M2, KNOCKER, 1.0)
  M2.patch.add(KNOCKER, PADFOOT, 1.0)
  M2.patch.add(PADFOOT, BECK, 1.0)
  run(M2, 5)
  check("nor when it is clocked by a running trigger", gates() == 0,
        "got " .. gates())
end

print("\n-- K1+tap clocks the register rather than firing a pulse out of it --")
do
  local M = fresh(14)
  set_length(M, PADFOOT, 8)
  M.state.set_vparam(PADFOOT, "prob", 0)
  M.patch.add(PADFOOT, "oak", 1.0)
  M.patch.add(PADFOOT, BECK, 1.0)
  M.state.set_vparam(PADFOOT, "steps", 0)   -- "free", so every step reads out
                                            -- as a different number
  -- and the global Scale off: that is a final quantiser downstream of
  -- everything (grove.hz), and with it on it would round the register's own
  -- output back onto the same note however far Steps let it move.
  M.state.global.scale_i = 0
  local before = #pitches_for(0)
  local gridui = wl("gridui")
  for _ = 1, 6 do gridui.act(PADFOOT, M.topology.get(PADFOOT)) end
  check("the cabled voice was retuned", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))
  check("and the exciter heard nothing", gates() == 0, "got " .. gates())
end

print("\n-- a pulse arriving from elsewhere is deferred a tick, same as an R cell --")
do
  local M = fresh(4)
  driver(M, KNOCKER, 1.0) -- 4 x beat, rooted
  M.patch.add(KNOCKER, PADFOOT, 1.0)
  M.patch.add(PADFOOT, "oak", 1.0)
  local before = #pitches_for(0)
  run(M, 5)
  check("the register did step from Knocker's pulses", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))
end

print("\n-- cabling a TM cell to a voice is a pitch source, same shape as a field --")
do
  local M = fresh(5)
  set_length(M, PADFOOT, 8)
  M.state.set_vparam(PADFOOT, "prob", 0) -- fresh coin every step: guaranteed movement
  M.patch.add(PADFOOT, "oak", 1.0)
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

print("\n-- Spread/Bias/Steps push the cabled voice live; the loop knobs do not --")
do
  local M = fresh(6)
  -- the default Length (8) and its starting alternating pattern give a mixed
  -- register, so every knob below actually has something to move -- and the
  -- nudges are large on purpose, so the snapped degree is guaranteed to cross
  -- into a different scale tone rather than landing near a boundary. the
  -- global Scale is off for the same reason it is off in the Steps test
  -- below: it is a final quantiser downstream of all three of these knobs.
  M.state.global.scale_i = 0
  M.state.set_vparam(PADFOOT, "range", 0)
  M.patch.add(PADFOOT, "oak", 1.0)

  local before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 4, 0.9) -- Spread, narrow -> wide
  check("Spread pushes immediately", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))

  before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 5, 0.3) -- Bias
  check("so does Bias", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))

  before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 6, -0.4) -- Steps, "scale" -> "free"
  check("and so does Steps", #pitches_for(0) > before,
        before .. " -> " .. #pitches_for(0))

  before = #pitches_for(0)
  M.tm.nudge(PADFOOT, 2, 0.1) -- Deja
  M.tm.nudge(PADFOOT, 1, 0.1) -- Length
  check("Deja/Length wait for the next clock edge instead",
        #pitches_for(0) == before, before .. " -> " .. #pitches_for(0))
end

print("\n-- Bias moves the whole line, Spread only widens it --")
do
  local M = fresh(15)
  set_length(M, PADFOOT, 8)
  M.state.set_vparam(PADFOOT, "steps", 0)      -- "free": no snap, so the
                                               -- numbers below are exact
  M.state.set_vparam(PADFOOT, "range", 0.5)

  M.state.set_vparam(PADFOOT, "bias", 0.5)
  local centred = M.tm.degree(PADFOOT)
  M.state.set_vparam(PADFOOT, "bias", 1.0)
  local raised = M.tm.degree(PADFOOT)
  check("full Bias lifts the same register by an octave",
        math.abs((raised - centred) - 12) < 1e-6,
        string.format("%+.3f -> %+.3f", centred, raised))

  M.state.set_vparam(PADFOOT, "bias", 0.0)
  check("and the other way, symmetrically",
        math.abs((M.tm.degree(PADFOOT) - centred) + 12) < 1e-6,
        tostring(M.tm.degree(PADFOOT)))
end

print("\n-- Steps walks from continuous to one note --")
do
  local M = fresh(16)
  set_length(M, PADFOOT, 8)
  M.state.set_vparam(PADFOOT, "range", 1.0)   -- two octaves, so a grid bites
  M.state.set_vparam(PADFOOT, "bias", 0.5)

  local names = {}
  for i = 1, #M.tm.STEP_MODES do
    -- the middle of position i, so the floor() lands squarely on it
    M.state.set_vparam(PADFOOT, "steps", (i - 0.5) / #M.tm.STEP_MODES)
    check("position " .. i .. " reads back as itself",
          M.tm.step_mode(PADFOOT) == i, tostring(M.tm.step_mode(PADFOOT)))
    names[i] = M.tm.step_name(PADFOOT)
  end
  check("the ladder runs free .. lock",
        names[1] == "free" and names[#names] == "lock",
        table.concat(names, ","))

  -- "lock" is the end of the ladder and means one note, whatever the
  -- register and however wide the Spread.
  M.state.set_vparam(PADFOOT, "steps", 1.0)
  local locked = true
  for _ = 1, 12 do
    M.tm.pulse_in(PADFOOT, 1, nil, 0)
    if math.abs(M.tm.degree(PADFOOT)) > 1e-9 then locked = false end
  end
  check("locked, the register runs and the pitch does not move", locked)

  -- "free" is the other end: no grid at all, so a wide Spread lands on
  -- values that are not whole semitones.
  M.state.set_vparam(PADFOOT, "steps", 0)
  local fractional = false
  for _ = 1, 24 do
    M.tm.pulse_in(PADFOOT, 1, nil, 0)
    local d = M.tm.degree(PADFOOT)
    if math.abs(d - math.floor(d + 0.5)) > 1e-6 then fractional = true end
  end
  check("free, it lands between the notes", fractional)
end

print("\n-- TM<->TM is inert, and a chain through one costs nothing --")
do
  local M = fresh(7)
  driver(M, KNOCKER, 1.0)
  M.patch.add(KNOCKER, PADFOOT, 1.0)
  M.patch.add(PADFOOT, BARGHEST, 0.9)
  M.patch.add(BARGHEST, BECK, 1.0)
  local b = M.tm.get(BARGHEST)
  local before = table.concat(b.bits, ",")
  local t0 = os.clock()
  run(M, 20)
  local wall = os.clock() - t0
  check("terminates", true)
  -- the whole point of the rework: a register cabled downstream of another
  -- register is not a sequencer chain any more. Padfoot is clocked, Barghest
  -- is not, and the exciter past it hears nothing at all.
  check("the second register never got clocked",
        table.concat(b.bits, ",") == before,
        before .. " -> " .. table.concat(b.bits, ","))
  check("and nothing downstream of it fired", gates() == 0, "#" .. gates())
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
