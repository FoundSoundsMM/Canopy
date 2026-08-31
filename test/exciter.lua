-- S-cell lazy alloc/gating/colour, pulse-driven grain firing, and the
-- continuous S -> M socket and S<->S patch matrix (§2.4, §6).
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("\n-- exciter lazy alloc --")
do
  local M = fresh(1)
  local BRACKEN = "e.bracken"
  check("off at start", #CALLS.exciter_on == 0)
  M.patch.add(BRACKEN, "oak", 0.6)
  check("turned on when cabled", #CALLS.exciter_on == 1
        and CALLS.exciter_on[1].index == M.topology.get(BRACKEN).index)
  M.patch.remove(BRACKEN, "oak")
  check("turned off when last cable removed", #CALLS.exciter_off == 1)
end

print("\n-- exciter colour (E2) --")
do
  local M = fresh(1)
  local BRACKEN = "e.bracken"
  M.state.character[BRACKEN] = 0.2 -- dialled in while still unpatched
  M.patch.add(BRACKEN, "oak", 0.6)
  check("colour pushed on alloc", CALLS.exciter_colour[#CALLS.exciter_colour].v == 0.2)
  M.state.character[BRACKEN] = 0.9
  M.state.notify_character_change(BRACKEN)
  check("colour forwarded live", CALLS.exciter_colour[#CALLS.exciter_colour].v == 0.9)
end

print("\n-- gated flag tracks incoming pulse cables --")
do
  local M = fresh(1)
  local BRACKEN, HOB = "e.bracken", "d.hob"
  M.patch.add(BRACKEN, "oak", 0.6)
  local first = CALLS.exciter_gated[#CALLS.exciter_gated]
  check("not gated with only a voice cable", first.flag == 0, tostring(first.flag))

  M.patch.add(BRACKEN, HOB, 0.7)
  local gated = CALLS.exciter_gated[#CALLS.exciter_gated]
  check("gated once a D cable is added", gated.flag == 1, tostring(gated.flag))

  M.patch.remove(BRACKEN, HOB)
  local ungated = CALLS.exciter_gated[#CALLS.exciter_gated]
  check("ungated once the D cable is removed", ungated.flag == 0, tostring(ungated.flag))
end

print("\n-- D -> E fires a grain --")
do
  local M = fresh(2)
  local HOB, BRACKEN = "d.hob", "e.bracken"
  M.rambler.set_gait(HOB, "metric")
  M.state.character[HOB] = 0.5
  M.state.rooted[HOB] = true
  M.rambler.get(HOB).rooted = true
  M.patch.add(HOB, BRACKEN, 0.9)
  run(M, 5)
  check("gate fired", #CALLS.exciter_gate > 0, "got " .. #CALLS.exciter_gate)
  check("targeted the right exciter",
        #CALLS.exciter_gate > 0 and CALLS.exciter_gate[1].index == M.topology.get(BRACKEN).index)
end

print("\n-- E <-> a voice, through the patch matrix --")
do
  -- a voice/E cable carries two different meanings at once, one per
  -- direction: the exciter's stream drives the voice's mod path (kind
  -- "aa"), and the voice's own audio colours the exciter (kind "ak") --
  -- both specs exist for one ordinary (non-oneway) cable, the same way a
  -- voice<->voice cable carries both directions' meaning on one wire.
  local M = fresh(1)
  local BRACKEN = "e.bracken"
  local bracken = M.topology.get(BRACKEN)
  local oak = M.topology.get("oak")

  M.patch.add(BRACKEN, "oak", 0.5)
  check("two patch synths for one E<->voice cable", #CALLS.patch_add == 2, tostring(#CALLS.patch_add))

  local ak, aa
  for _, add in ipairs(CALLS.patch_add) do
    if add.kind == "ak" then ak = add elseif add.kind == "aa" then aa = add end
  end
  check("an ak spec exists (voice colours the exciter)", ak ~= nil)
  check("its src is Oak's own voice-out bus", ak and ak.src == M.bridge.bus("voice_out", oak.index - 1))
  check("its dst is Bracken's colour-mod bus", ak and ak.dst == M.bridge.bus("colour_mod", bracken.index))
  check("an aa spec exists (the exciter drives the voice's mod path)", aa ~= nil)
  check("its src is Bracken's own exciter bus", aa and aa.src == M.bridge.bus("exc", bracken.index))
  check("its dst is Oak's own mod-path bus", aa and aa.dst == M.bridge.bus("mod_in", oak.index - 1))
  check("both carry the edge's own gain", ak and aa and ak.gain == 0.5 and aa.gain == 0.5)

  local eid = M.patch.has(BRACKEN, "oak")
  M.patch.set_gain(eid, 0.9)
  check("gain update sent for both", #CALLS.patch_gain == 2,
        "got " .. #CALLS.patch_gain)
  local all09 = true
  for _, g in ipairs(CALLS.patch_gain) do if g.gain ~= 0.9 then all09 = false end end
  check("both updates carry the new gain", all09)

  M.patch.remove(BRACKEN, "oak")
  check("both freed on remove", #CALLS.patch_free == 2, tostring(#CALLS.patch_free))
end

print("\n-- E -> a voice only (one-way cable) --")
do
  -- a one-way cable a->b only sends from a (§3): only the exciter's own
  -- half of the pairing should exist, not the voice's colouring half.
  local M = fresh(1)
  M.patch.add("e.bracken", "oak", 0.6, true)
  check("only one patch synth for a one-way E->voice cable",
        #CALLS.patch_add == 1, tostring(#CALLS.patch_add))
  check("it is the aa spec (exciter feeding the voice)",
        #CALLS.patch_add == 1 and CALLS.patch_add[1].kind == "aa")
end

print("\n-- voice -> E only (one-way cable) --")
do
  local M = fresh(1)
  M.patch.add("oak", "e.bracken", 0.6, true)
  check("only one patch synth for a one-way voice->E cable",
        #CALLS.patch_add == 1, tostring(#CALLS.patch_add))
  check("it is the ak spec (voice colouring the exciter)",
        #CALLS.patch_add == 1 and CALLS.patch_add[1].kind == "ak")
end

print("\n-- E <-> E colour cross-modulation --")
do
  local M = fresh(1)
  local BRACKEN, EMBER = "e.bracken", "e.ember"
  local bracken, ember = M.topology.get(BRACKEN), M.topology.get(EMBER)

  M.patch.add(BRACKEN, EMBER, 0.4)
  check("two patch synths for one E<->E cable", #CALLS.patch_add == 2, #CALLS.patch_add)

  local kinds_ok = CALLS.patch_add[1].kind == "ak" and CALLS.patch_add[2].kind == "ak"
  check("both ak (amplitude-follow)", kinds_ok)

  local found_a, found_b = false, false
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("exc", bracken.index) and c.dst == M.bridge.bus("colour_mod", ember.index) then
      found_a = true
    end
    if c.src == M.bridge.bus("exc", ember.index) and c.dst == M.bridge.bus("colour_mod", bracken.index) then
      found_b = true
    end
  end
  check("both directions present", found_a and found_b)

  M.patch.remove(BRACKEN, EMBER)
  check("both freed on remove", #CALLS.patch_free == 2, #CALLS.patch_free)
end

print("\n-- two Output cells wired together are a legal cable with no continuous meaning --")
do
  -- the socket collapse removed the old P<->M "neither" pairing this test used
  -- to probe; an O<->O cable is the same shape now -- both endpoints are pure
  -- destinations, so the cable is legal but dispatch.lua's specs_for has
  -- nothing to say about it, and no pulse ever lands on an O cell either.
  local M = fresh(1)
  local ok = pcall(function() M.patch.add("o.1", "o.2", 0.5) end)
  check("cabling still works", ok and M.patch.has("o.1", "o.2") ~= nil)
  check("but produces no patch synth", #CALLS.patch_add == 0, #CALLS.patch_add)
end

report()
