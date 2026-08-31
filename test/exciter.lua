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
  -- NOTE: dispatch.lua's specs_for checks `ordered("voice", "E")` (the voice
  -- colours the exciter, kind "ak") before it ever reaches `ordered("E",
  -- "voice")` (e_to_voice_spec, kind "aa", the stream landing on the voice's
  -- own point) -- and since ordered() matches a voice/E pair the same way
  -- regardless of which side the cable was drawn from, the "E","voice" branch
  -- and e_to_voice_spec are unreachable dead code. this test asserts the
  -- actual (shadowed) behaviour rather than the one the file's own comments
  -- describe; see the final report for the flagged lib/dispatch.lua issue.
  local M = fresh(1)
  local BRACKEN = "e.bracken"
  local bracken = M.topology.get(BRACKEN)
  local oak = M.topology.get("oak")

  M.patch.add(BRACKEN, "oak", 0.5)
  local add = CALLS.patch_add[#CALLS.patch_add]
  check("ak kind (voice colours the exciter, not the reverse)", add.kind == "ak", tostring(add.kind))
  check("src is Oak's own voice-out bus", add.src == M.bridge.bus("voice_out", oak.index - 1))
  check("dst is Bracken's colour-mod bus", add.dst == M.bridge.bus("colour_mod", bracken.index))
  check("gain matches edge gain", add.gain == 0.5)

  local eid = M.patch.has(BRACKEN, "oak")
  M.patch.set_gain(eid, 0.9)
  local g = CALLS.patch_gain[#CALLS.patch_gain]
  check("gain update sent", g.id == add.id and g.gain == 0.9, g.id .. " " .. tostring(g.gain))

  M.patch.remove(BRACKEN, "oak")
  check("freed on remove", #CALLS.patch_free == 1 and CALLS.patch_free[1].id == add.id)
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
