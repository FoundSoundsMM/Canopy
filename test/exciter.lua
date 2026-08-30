-- build phase 4: S-cell lazy alloc/gating/colour, D->S grain firing, and the
-- continuous S<->Sap/Sway/Moss and S<->S patch matrix (§2.4, §6).
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("\n-- exciter lazy alloc --")
do
  local M = fresh(1)
  local BECK = "s.beck"
  check("off at start", #CALLS.exciter_on == 0)
  M.patch.add(BECK, "oak.sap", 0.6)
  check("turned on when cabled", #CALLS.exciter_on == 1
        and CALLS.exciter_on[1].index == M.topology.get(BECK).index)
  M.patch.remove(BECK, "oak.sap")
  check("turned off when last cable removed", #CALLS.exciter_off == 1)
end

print("\n-- exciter colour (E2) --")
do
  local M = fresh(1)
  local BECK = "s.beck"
  M.state.character[BECK] = 0.2 -- dialled in while still unpatched
  M.patch.add(BECK, "oak.sap", 0.6)
  check("colour pushed on alloc", CALLS.exciter_colour[#CALLS.exciter_colour].v == 0.2)
  M.state.character[BECK] = 0.9
  M.state.notify_character_change(BECK)
  check("colour forwarded live", CALLS.exciter_colour[#CALLS.exciter_colour].v == 0.9)
end

print("\n-- gated flag tracks incoming D cables --")
do
  local M = fresh(1)
  local BECK, KNOCKER = "s.beck", "d.knocker"
  M.patch.add(BECK, "oak.sap", 0.6)
  local first = CALLS.exciter_gated[#CALLS.exciter_gated]
  check("not gated with only an S-node cable", first.flag == 0, tostring(first.flag))

  M.patch.add(BECK, KNOCKER, 0.7)
  local gated = CALLS.exciter_gated[#CALLS.exciter_gated]
  check("gated once a D cable is added", gated.flag == 1, tostring(gated.flag))

  M.patch.remove(BECK, KNOCKER)
  local ungated = CALLS.exciter_gated[#CALLS.exciter_gated]
  check("ungated once the D cable is removed", ungated.flag == 0, tostring(ungated.flag))
end

print("\n-- D -> S fires a grain --")
do
  local M = fresh(2)
  local KNOCKER, BECK = "d.knocker", "s.beck"
  M.rambler.set_gait(KNOCKER, "metric")
  M.state.character[KNOCKER] = 0.5
  M.state.rooted[KNOCKER] = true
  M.rambler.get(KNOCKER).rooted = true
  M.patch.add(KNOCKER, BECK, 0.9)
  run(M, 5)
  check("gate fired", #CALLS.exciter_gate > 0, "got " .. #CALLS.exciter_gate)
  check("targeted the right exciter",
        #CALLS.exciter_gate > 0 and CALLS.exciter_gate[1].index == M.topology.get(BECK).index)
end

print("\n-- S -> Sap/Sway/Moss patch matrix --")
do
  local M = fresh(1)
  local BECK = "s.beck"
  local beck = M.topology.get(BECK)
  local oak = M.topology.get("oak")

  M.patch.add(BECK, "oak.sap", 0.5)
  local add = CALLS.patch_add[#CALLS.patch_add]
  check("aa kind", add.kind == "aa", tostring(add.kind))
  check("src is Beck's exciter bus", add.src == M.bridge.bus("exc", beck.index))
  check("dst is Oak's Sap-sum bus", add.dst == M.bridge.bus("exc_in", oak.index - 1))
  check("gain matches edge gain", add.gain == 0.5)

  local eid = M.patch.has(BECK, "oak.sap")
  M.patch.set_gain(eid, 0.9)
  local g = CALLS.patch_gain[#CALLS.patch_gain]
  check("gain update sent", g.id == add.id and g.gain == 0.9, g.id .. " " .. tostring(g.gain))

  M.patch.remove(BECK, "oak.sap")
  check("freed on remove", #CALLS.patch_free == 1 and CALLS.patch_free[1].id == add.id)
end

print("\n-- S <-> S colour cross-modulation --")
do
  local M = fresh(1)
  local BRACKEN, BECK = "s.bracken", "s.beck"
  local bracken, beck = M.topology.get(BRACKEN), M.topology.get(BECK)

  M.patch.add(BRACKEN, BECK, 0.4)
  check("two patch synths for one S<->S cable", #CALLS.patch_add == 2, #CALLS.patch_add)

  local kinds_ok = CALLS.patch_add[1].kind == "ak" and CALLS.patch_add[2].kind == "ak"
  check("both ak (amplitude-follow)", kinds_ok)

  local found_a, found_b = false, false
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("exc", bracken.index) and c.dst == M.bridge.bus("colour_mod", beck.index) then
      found_a = true
    end
    if c.src == M.bridge.bus("exc", beck.index) and c.dst == M.bridge.bus("colour_mod", bracken.index) then
      found_b = true
    end
  end
  check("both directions present", found_a and found_b)

  M.patch.remove(BRACKEN, BECK)
  check("both freed on remove", #CALLS.patch_free == 2, #CALLS.patch_free)
end

print("\n-- node<->node is still a safe no-op (no node taps built yet) --")
do
  local M = fresh(1)
  local ok = pcall(function() M.patch.add("oak.sway", "oak.moss", 0.5) end)
  check("cabling still works", ok and M.patch.has("oak.sway", "oak.moss") ~= nil)
  check("but produces no patch synth", #CALLS.patch_add == 0, #CALLS.patch_add)
end

report()
