-- build phase 6: the §2.7 weave. that a pulse put through an R cell comes out
-- changed in the way the rule says, that a chain of them stays bounded, and
-- that the cells reset cleanly when the rule underneath them is swapped.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local KNOCKER, HOB = "d.knocker", "d.hob"
local TROD, GINNEL, SNICKET = "r.trod", "r.ginnel", "r.snicket"
local BECK, LOAM = "s.beck", "s.loam"

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
  M.patch.add(TROD, BECK, 1.0)
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
  M.patch.add(TROD, BECK, 1.0)
  M.patch.add(TROD, LOAM, 1.0)
  run(M, 20)
  local b = M.topology.get(BECK).index
  local l = M.topology.get(LOAM).index
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
  -- every multiplying rule there is, in series, ending on a voice, plus a
  -- loop back into the chain from the voice's own out socket.
  local rules = {"mult", "echo", "roll", "flam", "ghost", "fill", "accent"}
  M.patch.add(KNOCKER, rs[1], 1.0)
  for i, rule in ipairs(rules) do
    M.weave.set_rule(rs[i], rule)
    if i < #rules then M.patch.add(rs[i], rs[i + 1], 0.9) end
  end
  M.patch.add(rs[#rules], "oak.trig", 0.9)
  M.patch.add("oak.out", rs[1], 0.8)
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

report()
