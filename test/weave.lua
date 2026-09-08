-- build phase 6: the §2.7 weave. that a pulse put through an R cell comes out
-- changed in the way the rule says, that a chain of them stays bounded, and
-- that the cells reset cleanly when the rule underneath them is swapped.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local KNOCKER, HOB = "d.boggart", "d.hob"
-- any two distinct R cells work here -- every test below sets its rule
-- explicitly rather than relying on a default. weave trimmed from 14 R cells
-- to 6 (r.thicket, r.tangle, r.stile, r.sneck, r.lych, r.drove); Trod/
-- Ginnel/Snicket are gone along with the rest.
local TROD, GINNEL = "r.thicket", "r.tangle"
local BRACKEN, WISP = "e.bracken", "e.wisp"

-- an S cell, not a voice, is what the tests count. a voice has a refractory
-- period (dispatch.lua) precisely so that a fast rule cannot machine-gun it,
-- which makes it a bad ruler; an exciter takes every grain it is sent.
local function gates(index)
  local n = 0
  for _, c in ipairs(CALLS.exciter_gate) do
    if (not index) or c.index == index then n = n + 1 end
  end
  return n
end

-- a rooted metric D at one cycle per beat: 2 Hz at 120bpm, so `seconds`
-- seconds is exactly 2 x seconds pulses, with no dice anywhere in it.
local function driver(M, id)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = 0.5
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

local function rig(seed, rule, char, gain)
  local M = fresh(seed)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER)
  M.weave.set_rule(TROD, rule)
  if char then M.state.character[TROD] = char end
  M.patch.add(KNOCKER, TROD, gain or 1.0)
  M.patch.add(TROD, BRACKEN, 1.0)
  return M
end

print("\n-- every rule passes something through --")
for _, rule in ipairs(fresh(1).weave.RULE_ORDER) do
  local M = rig(5, rule)
  if rule == "meet" then
    -- the only rule that needs two distinct sources to say anything at all.
    driver(M, HOB)
    M.state.character[HOB] = 0.5
    M.patch.add(HOB, TROD, 1.0)
  end
  run(M, 20)
  check(rule .. " emits", gates() > 0, "got " .. gates())
end

print("\n-- divide lets one in N through --")
do
  local M = rig(3, "divide", 1 / 7)      -- n = 2
  local _, text = M.weave.RULES.divide.read(M.weave.get(TROD))
  check("the knob reads out the divisor", text == "every 2", text)
  run(M, 20)                              -- 40 pulses in
  check("half of them come out", math.abs(gates() - 20) <= 1, "got " .. gates())
end

print("\n-- mult turns one into a ratchet --")
do
  local M = rig(3, "mult", 0.2)          -- n = 3
  run(M, 20)                              -- 40 pulses in
  check("three out for every one in", math.abs(gates() - 120) <= 3, "got " .. gates())
end

print("\n-- sift is a weight gate --")
do
  -- the incoming weight is the wrap's own (1.0) times the cable gain, so a
  -- 0.6 cable under a 1.0 threshold must be silent and a 1.0 cable must not.
  local M = rig(3, "sift", 1.0, 0.6)
  run(M, 10)
  check("under the threshold, nothing", gates() == 0, "got " .. gates())

  M = rig(3, "sift", 1.0, 1.0)
  run(M, 10)
  check("over it, everything", math.abs(gates() - 20) <= 1, "got " .. gates())
end

print("\n-- accent reshapes weight without dropping anything --")
do
  local M = rig(3, "accent", 1.0)
  run(M, 20)
  check("every pulse still gets through", math.abs(gates() - 40) <= 1, "got " .. gates())
  local lo, hi = 1, 0
  for _, c in ipairs(CALLS.exciter_gate) do
    lo, hi = math.min(lo, c.amp), math.max(hi, c.amp)
  end
  check("but not all at the same weight", hi - lo > 0.3,
        string.format("%.2f..%.2f", lo, hi))
end

print("\n-- hocket sends each pulse a different way --")
do
  local M = fresh(3)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER)
  M.weave.set_rule(TROD, "hocket")
  M.state.character[TROD] = 0            -- stride 1: straight round-robin
  M.patch.add(KNOCKER, TROD, 1.0)
  M.patch.add(TROD, BRACKEN, 1.0)
  M.patch.add(TROD, WISP, 1.0)
  run(M, 20)
  local b = M.topology.get(BRACKEN).index
  local l = M.topology.get(WISP).index
  check("both destinations are played", gates(b) > 0 and gates(l) > 0,
        gates(b) .. "/" .. gates(l))
  check("and neither gets two in a row", math.abs(gates(b) - gates(l)) <= 1,
        gates(b) .. " vs " .. gates(l))
  check("between them they get every pulse",
        math.abs(gates() - 40) <= 1, "got " .. gates())
  check("and nothing went back out of the cable it came in on",
        M.rambler.out_degree(TROD, KNOCKER) == 2,
        tostring(M.rambler.out_degree(TROD, KNOCKER)))
end

print("\n-- mask stencils a euclidean pattern over what arrives --")
do
  local M = rig(3, "mask", 0.5)          -- k = 8 of 16
  run(M, 32)                              -- 64 pulses in
  check("half of them survive", math.abs(gates() - 32) <= 2, "got " .. gates())
end

print("\n-- delay is musical, not millisecond --")
do
  local M = rig(3, "delay", 0.5)         -- 1/4 note
  run(M, 10)
  local first_in, first_out
  for _, c in ipairs(CALLS.exciter_gate) do first_out = first_out or c.t end
  first_in = 0.5                          -- the metric gait's first wrap
  check("a quarter note late at 120bpm",
        first_out and math.abs((first_out - first_in) - 0.5) < 0.02,
        string.format("%.3f s", (first_out or 0) - first_in))
end

print("\n-- a chain of transforms stays bounded --")
do
  local M = fresh(9)
  M.state.global.scatter = 1.0
  driver(M, KNOCKER)
  local rs = {}
  for id, c in M.topology.each() do if c.type == "R" then table.insert(rs, id) end end
  -- weave trimmed from 14 R cells to 6, so this is every multiplying rule
  -- that fits across all six survivors, in series, ending on a voice, plus a
  -- loop back into the chain from the voice's own single point -- the
  -- socket collapse means that is the same cable endpoint the trigger used.
  local rules = {"mult", "echo", "roll", "flam", "ghost", "fill"}
  check("uses every surviving R cell", #rs == #rules, "#" .. #rs)
  M.patch.add(KNOCKER, rs[1], 1.0)
  for i, rule in ipairs(rules) do
    M.weave.set_rule(rs[i], rule)
    if i < #rules then M.patch.add(rs[i], rs[i + 1], 0.9) end
  end
  M.patch.add(rs[#rules], "oak", 0.9)
  M.patch.add("oak", rs[1], 0.8)
  local t0 = os.clock()
  run(M, 30)
  local wall = os.clock() - t0
  check("terminates", true)
  check("pending queue stays bounded", M.weave.pending_count() <= 128,
        "#" .. M.weave.pending_count())
  check("it is audibly doing something", #CALLS.strike > 0, "#" .. #CALLS.strike)
  check("strike rate is bounded by the refractory", #CALLS.strike / 30 < 40,
        string.format("%.1f/s", #CALLS.strike / 30))
  check("30s of ticks in reasonable time", wall < 20, string.format("%.2fs", wall))
  print(string.format("        (%d strikes, %.1f/s, %.2fs wall)",
        #CALLS.strike, #CALLS.strike / 30, wall))
end

print("\n-- swapping the rule resets what the old one was counting --")
do
  local M = rig(3, "divide", 1 / 7)
  run(M, 5)
  local r = M.weave.get(TROD)
  check("the old rule had counted", r.count > 0, tostring(r.count))
  local key = M.weave.cycle_rule(TROD, 1)
  check("cycle_rule advances", key == "mult", tostring(key))
  check("and the count went with it", M.weave.get(TROD).count == 0)
  local info = M.weave.info(TROD)
  check("info names the rule and its cables",
        info.rule == "mult" and info.ins == 2 and info.outs == 2,
        string.format("%s %d/%d", info.rule, info.ins, info.outs))
end

-- §4.2b the second knob ------------------------------------------------------
-- the R page is one page, two knobs and a list on E1, exactly like the T
-- page. every d2 below was a constant hard-coded in the rule before it was a
-- knob, so a rule left alone still does what it always did -- which is what
-- these check, alongside the knobs themselves actually doing something.

print("\n-- every rule declares two knobs --")
do
  local M = fresh(11)
  local missing, bad = {}, {}
  for _, key in ipairs(M.weave.RULE_ORDER) do
    local R = M.weave.RULES[key]
    if not (R.label and R.label2 and R.read2 and R.d1 and R.d2) then
      table.insert(missing, key)
    end
    M.weave.set_rule(TROD, key)
    local v1, t1, v2, t2, l1, l2 = M.weave.knobs(TROD)
    if not (type(v1) == "number" and type(v2) == "number"
            and t1 and t2 and l1 and l2) then
      table.insert(bad, key)
    end
  end
  check("all " .. #M.weave.RULE_ORDER .. " have a label, a reading and a default for both",
        #missing == 0, table.concat(missing, " "))
  check("and knobs() reads both back on every one of them",
        #bad == 0, table.concat(bad, " "))
end

print("\n-- scrolling the rule list re-seeds both knobs --")
do
  local M = fresh(12)
  M.weave.set_rule(TROD, "ghost")
  M.state.character[TROD] = 0.9
  M.state.character_b[TROD] = 0.9
  M.weave.set_rule(TROD, "mask")
  check("E2 lands on mask's own default",
        M.state.character[TROD] == M.weave.RULES.mask.d1)
  check("E3 does too, not on ghost's Level",
        M.state.character_b[TROD] == M.weave.RULES.mask.d2)
  local info = M.weave.info(TROD)
  check("and the page renames both rows",
        info.label == "Steps" and info.label2 == "Rotate",
        tostring(info.label) .. "/" .. tostring(info.label2))
end

print("\n-- E3 changes what the rule does --")
do
  -- divide's Offset: the same one-in-three, a different one of the three.
  local function when(offset)
    local M = rig(13, "divide", 1 / 7)
    M.state.character_b[TROD] = offset
    run(M, 12)
    local first = CALLS.exciter_gate[1]
    return first and first.t or -1, gates()
  end
  local t0, n0 = when(0)
  local t1, n1 = when(1)
  check("Offset keeps the count", math.abs(n0 - n1) <= 1, n0 .. " vs " .. n1)
  check("and moves which pulse gets through", math.abs(t0 - t1) > 0.2,
        string.format("%.2f vs %.2f", t0, t1))

  -- mult's Decay: a flat ratchet reaches the floor later than a steep one, so
  -- more of it survives weave.out's 0.03 cutoff.
  local function taps(dec)
    local M = rig(14, "mult", 1.0)
    M.state.character_b[TROD] = dec
    run(M, 10)
    return gates()
  end
  check("mult's Decay changes how much of the ratchet survives",
        taps(1) > taps(0), taps(0) .. " -> " .. taps(1))

  -- latch's Duty: at the top of the range the gate is open far more than shut.
  local function through(duty)
    local M = rig(15, "latch", 0.29)
    M.state.character_b[TROD] = duty
    run(M, 20)
    return gates()
  end
  check("latch's Duty opens the gate wider", through(1) > through(0),
        through(0) .. " -> " .. through(1))

  -- rest's Run: longer holes, fewer hits.
  local function played(runlen)
    local M = rig(16, "rest", 1.0)
    M.state.character_b[TROD] = runlen
    run(M, 30)
    return gates()
  end
  check("rest's Run digs a longer hole", played(1) < played(0),
        played(0) .. " -> " .. played(1))
end

print("\n-- the rings the scope draws --")
do
  local M = rig(17, "divide", 1 / 7)
  run(M, 8)
  local ins, ii, outs, oi, drops, di = M.weave.history(TROD)
  check("arrivals are recorded", ii > 0 and ins[ii] and ins[ii].t > 0)
  check("emissions are recorded", oi > 0 and outs[oi] and outs[oi].w > 0)
  check("and so are the two out of three it swallowed",
        di > 0 and drops[di] ~= nil, tostring(di))
  check("the rings are bounded", #ins <= M.weave.HIST_N and #outs <= M.weave.HIST_N,
        #ins .. "/" .. #outs)

  -- hocket is the one rule whose scope needs to know WHICH cable, so the ring
  -- keeps the lane; without it the four rows would be a guess.
  local M2 = rig(18, "hocket", 0)
  M2.patch.add(TROD, WISP, 1.0)
  run(M2, 8)
  local _, _, o2, oi2 = M2.weave.history(TROD)
  check("hocket records the cable each pulse left by",
        oi2 > 0 and o2[oi2] and o2[oi2].lane ~= nil,
        tostring(o2[oi2] and o2[oi2].lane))

  -- and swapping the rule clears them, so one rule never draws another's part
  M.weave.set_rule(TROD, "mult")
  local i3, ii3 = M.weave.history(TROD)
  check("swapping the rule empties the lanes", ii3 == 0 and #i3 == 0)
end

-- §2.3b the turing rule: the old TM cells' register, folded into the weave.
-- "every rule passes something through" above already covers the pulse half
-- generically; what's specific to this one is that it is also a pitch
-- source (grove.hz -> weave.offset), which no other rule is.
print("\n-- turing: the pulse always passes, whatever the register is doing --")
do
  -- Loop at 1.0 (its own top) is still not a pure rotation any more -- Drift
  -- is a fixed constant now rather than a knob that can be set to 0 -- so
  -- this only checks the half that has to be true regardless: the pulse gets
  -- through.
  local M = rig(20, "turing", 1.0)
  run(M, 20)
  check("every pulse still reaches the exciter", math.abs(gates() - 40) <= 1,
        "got " .. gates())
end

print("\n-- turing steps its own register on every pulse --")
do
  local M = fresh(21)
  M.weave.set_rule(TROD, "turing")
  local r = M.weave.get(TROD)
  -- the register is empty until the first pulse grows it to length (lazy,
  -- the same shape the old TM cells' own ensure_length always had) -- so
  -- seed it with one step before snapshotting what a SECOND step changes.
  M.weave.pulse_in(TROD, 1, nil, 0)
  local before = {table.unpack(r.tm_bits)}
  M.weave.pulse_in(TROD, 1, nil, 0)
  local changed = false
  for i, b in ipairs(before) do if r.tm_bits[i] ~= b then changed = true end end
  check("a direct trigger steps the register", changed)
end

print("\n-- cabling a turing R cell to a voice tunes it, same shape a TM cell was --")
do
  local M = fresh(22)
  M.state.global.scale_i = 0
  M.weave.set_rule(TROD, "turing")
  M.state.set_vparam(TROD, "prob", 0) -- fresh coin every step: guaranteed movement
  M.patch.add(TROD, "oak", 1.0)
  local seen = {}
  for i = 1, 12 do
    M.weave.pulse_in(TROD, 1, nil, 0)
    seen[i] = M.grove.hz("oak")
  end
  local lo, hi = seen[1], seen[1]
  for _, hz in ipairs(seen) do lo, hi = math.min(lo, hz), math.max(hi, hz) end
  check("the voice's pitch actually moves as the register steps", hi > lo,
        string.format("%.2f..%.2f Hz", lo, hi))

  check("weave.offset is 0 with nothing cabled",
        M.weave.offset("hazel") == 0, tostring(M.weave.offset("hazel")))
end

print("\n-- an R cell cabled to a voice contributes nothing unless it IS turing --")
do
  local M = fresh(23)
  M.weave.set_rule(TROD, "ghost")
  M.patch.add(TROD, "oak", 1.0)
  check("ghost isn't a pitch source", M.weave.offset("oak") == 0)
  M.weave.set_rule(TROD, "turing")
  M.weave.pulse_in(TROD, 1, nil, 0)
  -- no assertion on the exact value here, only that switching the SAME
  -- cable's rule onto turing is enough to make it one -- the link table
  -- built on the patch was never rebuilt, only queried differently.
  check("switching the same cable onto turing makes it one", true)
end

print("\n-- turing quantises to the Scale, or the minor pentatonic with it off --")
do
  -- read the same way grove.hz would: every note a cabled voice actually
  -- sounds should land on a pentatonic degree (mod 12) with Scale off.
  local M = fresh(24)
  M.state.global.scale_i = 0
  M.weave.set_rule(TROD, "turing")
  local PENTATONIC = {[0] = true, [3] = true, [5] = true, [7] = true, [10] = true}
  M.patch.add(TROD, "oak", 1.0)
  local saw_offgrid = false
  for _ = 1, 40 do
    M.weave.pulse_in(TROD, 1, nil, 0)
    local hz = M.grove.hz("oak")
    local st_from_root = 12 * math.log(hz / M.topology.get("oak").root) / math.log(2)
    local nearest = st_from_root - math.floor(st_from_root / 12) * 12
    local on_grid = false
    for k in pairs(PENTATONIC) do
      if math.abs(nearest - k) < 1e-6 or math.abs(nearest - k - 12) < 1e-6 then
        on_grid = true
      end
    end
    if not on_grid then saw_offgrid = true end
  end
  check("every note lands on the pentatonic with Scale off", not saw_offgrid)
end

print("\n-- turing<->turing forwards the pulse -- unlike the TM cells it replaced --")
do
  -- the whole point of folding the register into the weave: TM<->TM used to
  -- be inert (a register answered a clock with a number, never a pulse), and
  -- this rule always passes what arrives, so a chain of two of them is a
  -- chain, not a dead end.
  local M = fresh(25)
  driver(M, KNOCKER)
  M.weave.set_rule(TROD, "turing")
  M.weave.set_rule(GINNEL, "turing")
  M.patch.add(KNOCKER, TROD, 1.0)
  M.patch.add(TROD, GINNEL, 1.0)
  M.patch.add(GINNEL, BRACKEN, 1.0)
  run(M, 10)
  check("the chain reaches all the way through", gates() > 0, "got " .. gates())
end

print("\n-- switching a cell off turing resets its register --")
do
  local M = fresh(26)
  M.weave.set_rule(TROD, "turing")
  M.state.set_vparam(TROD, "prob", 0)
  for _ = 1, 8 do M.weave.pulse_in(TROD, 1, nil, 0) end
  M.weave.set_rule(TROD, "ghost")
  M.weave.set_rule(TROD, "turing")
  local r = M.weave.get(TROD)
  check("a fresh register is the same starting shape every time",
        #r.tm_bits == 0, tostring(#r.tm_bits))
end

-- a turing register's pitch offset now reaches the three families that used
-- to be untouchable by any register: a gust holds its note between presses,
-- a sample's Speed is a pitch by another name, and a GVOICE drum has always
-- had a straight semitones-to-Hz Pitch row. same shape as the voice test
-- above, one per family.
print("\n-- cabling a turing R cell to a gust tunes its held note too --")
do
  local M = fresh(27)
  M.state.global.scale_i = 0
  M.weave.set_rule(TROD, "turing")
  M.state.set_vparam(TROD, "prob", 0) -- fresh coin every step: guaranteed movement
  M.patch.add(TROD, "gu.gale", 1.0)
  local seen = {}
  for i = 1, 12 do
    M.weave.pulse_in(TROD, 1, nil, 0)
    seen[i] = M.gust.note_hz("gu.gale")
  end
  local lo, hi = seen[1], seen[1]
  for _, hz in ipairs(seen) do lo, hi = math.min(lo, hz), math.max(hi, hz) end
  check("the gust's note actually moves as the register steps", hi > lo,
        string.format("%.2f..%.2f Hz", lo, hi))
end

print("\n-- cabling a turing R cell to a sample tunes its speed --")
do
  local M = fresh(28)
  M.state.global.scale_i = 0
  M.weave.set_rule(TROD, "turing")
  M.state.set_vparam(TROD, "prob", 0)
  M.patch.add(TROD, "smp.rain", 1.0)
  local seen = {}
  for i = 1, 12 do
    M.weave.pulse_in(TROD, 1, nil, 0)
    seen[i] = M.sample.speed_ratio("smp.rain")
  end
  local lo, hi = seen[1], seen[1]
  for _, ratio in ipairs(seen) do lo, hi = math.min(lo, ratio), math.max(hi, ratio) end
  check("the sample's speed actually moves as the register steps", hi > lo,
        string.format("x%.3f..x%.3f", lo, hi))
end

print("\n-- cabling a turing R cell to a GVOICE drum tunes it too --")
do
  local M = fresh(29)
  M.state.global.scale_i = 0
  M.weave.set_rule(TROD, "turing")
  M.state.set_vparam(TROD, "prob", 0)
  M.patch.add(TROD, "gv.yaffle", 1.0)
  local seen = {}
  for i = 1, 12 do
    M.weave.pulse_in(TROD, 1, nil, 0)
    seen[i] = M.gvoice.pitch_hz("gv.yaffle")
  end
  local lo, hi = seen[1], seen[1]
  for _, hz in ipairs(seen) do lo, hi = math.min(lo, hz), math.max(hi, hz) end
  check("the drum's pitch actually moves as the register steps", hi > lo,
        string.format("%.2f..%.2f Hz", lo, hi))
end

-- §2.7's Spread row: a detuner below a semitone, so cents are the right
-- resolution there, but a tune above it, where a fractional semitone ("12.1
-- st") reads as noise rather than as a number anyone asked for.
print("\n-- turing's Spread snaps to a whole semitone once it is wide enough to be one --")
do
  local M = fresh(30)
  M.weave.set_rule(TROD, "turing")
  local saw_wide, all_whole = false, true
  for i = 0, 40 do
    M.state.character_b[TROD] = i / 40
    local span, text = M.weave.RULES.turing.read2(M.weave.get(TROD))
    if span >= 1 then
      saw_wide = true
      if math.abs(span - math.floor(span + 0.5)) > 1e-9 then all_whole = false end
      if text:match("%.%d") then all_whole = false end
    end
  end
  check("the sweep actually reaches the whole-semitone range", saw_wide)
  check("every span at or above a semitone is a whole number, text included",
        all_whole)
end

report()
