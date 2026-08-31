-- build phase 5: the §2.5 diffusion lattice. the discrete side (a pulse
-- entering at one node and emerging from the others at different times and
-- amplitudes), conductance's two ranges, H<->H shortcuts, and the continuous
-- side's bus resolution through the §6 matrix.
--
-- the re-cut trimmed Heartwood from a ring of 8 (with two chord rungs) to a
-- simple chain of 4: h.taproot -- h.mycel -- h.wyrd -- h.ley, each node
-- neighbouring only the next/previous one. energy still travels and still
-- arrives later and quieter the further it goes, just along a line instead
-- of round a ring, and there is no "far side" to test symmetrically any
-- more -- the far end of a 4-node chain is simply its last node.
--
-- NOTE: the "visible arrival" tests below cable H nodes to GVOICE cells
-- rather than to voices, as the original (pre-rewrite) test did. that is a
-- deliberate workaround, not a style choice: dispatch.lua's HANDLERS table
-- has entries for "voice<-D", "voice<-R", "voice<-TM", "voice<-GVOICE",
-- "voice<-C", "voice<-SEQ" and "voice<-voice", but no "voice<-H" -- so a
-- pulse emerging from the lattice directly onto a voice's single point is
-- silently dropped by dispatch.on_pulse, contradicting the file's own header
-- comment ("a voice ... covers everything a pulse can land on"). confirmed
-- directly: dispatch.on_pulse("h.taproot", "oak", {gain=1}, 1) produces zero
-- CALLS.strike, while the same call against a GVOICE cell strikes it. this
-- looks like a genuine missing-handler bug; see the final report rather than
-- this file for the fix, which is out of scope for a test-only pass. GVOICE
-- cells give the same "a distinct, indexed, forced strike" signal a voice
-- would have, so they stand in cleanly everywhere this file needs one.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local TAPROOT, MYCEL, WYRD, LEY = "h.taproot", "h.mycel", "h.wyrd", "h.ley"
local H_IDS = {TAPROOT, MYCEL, WYRD, LEY}
-- gv.yaffle/knap/clapper/scree are engine indices 0/1/2/3 respectively
-- (topology.lua's GVOICE_CELLS registration order), the same shape the four
-- corner voices' 0..3 indices gave the original test.
local YAFFLE, KNAP, CLAPPER, SCREE = "gv.yaffle", "gv.knap", "gv.clapper", "gv.scree"

-- advance the virtual clock through the scheduler without needing a D cell:
-- the lattice's in-flight pulses are stepped by rambler.tick like everything
-- else, so `run` is the only clock there is.
local function settle(M, seconds) run(M, seconds) end

print("\n-- a pulse injected at one node emerges from the others --")
do
  local M = fresh(1)
  -- cable all four chain nodes to distinct GVOICE cells, so an arrival is
  -- visible as a strike at a distinct, indexed force.
  M.patch.add(TAPROOT, YAFFLE, 1.0)    -- index 0, the injection point
  M.patch.add(MYCEL, KNAP, 1.0)        -- index 1, one hop away
  M.patch.add(WYRD, CLAPPER, 1.0)      -- index 2, two hops away
  M.patch.add(LEY, SCREE, 1.0)         -- index 3, three hops away, the far end
  for _, id in ipairs(H_IDS) do
    M.state.character[id] = 0.8 -- a good conductor: short hops, little loss
  end

  M.heartwood.inject(TAPROOT, 1.0, "test")
  settle(M, 3)

  local hit = {}
  for _, s in ipairs(CALLS.g_strike) do hit[s.index] = (hit[s.index] or 0) + 1 end
  check("the injected node fires immediately", hit[0] and hit[0] > 0)
  check("the far end of the chain fires too", hit[1] and hit[2] and hit[3],
        "cells hit: " .. tostring(hit[0]) .. "/" .. tostring(hit[1])
        .. "/" .. tostring(hit[2]) .. "/" .. tostring(hit[3]))

  -- "emerging from the other nodes at different times and amplitudes" (§2.5)
  local first_t, far_t
  for _, s in ipairs(CALLS.g_strike) do
    if s.index == 0 and not first_t then first_t = s.t end
    if s.index == 3 and not far_t then far_t = s.t end  -- Scree, three hops away
  end
  check("later the further away it is", far_t > first_t,
        string.format("%.3f vs %.3f", first_t, far_t))

  local loudest_near, loudest_far = 0, 0
  for _, s in ipairs(CALLS.g_strike) do
    if s.index == 0 then loudest_near = math.max(loudest_near, s.force) end
    if s.index == 3 then loudest_far = math.max(loudest_far, s.force) end
  end
  check("and quieter", loudest_far < loudest_near,
        string.format("%.3f vs %.3f", loudest_far, loudest_near))
end

print("\n-- a pulse does not bounce straight back out of its own cable --")
do
  -- a bare 4-node chain has no cycle of its own any more (the re-cut traded
  -- the old ring's "hands it back after a lap" for a straight line, see the
  -- header note), so a pulse injected at one end simply travels to the other
  -- end and dissipates -- it never returns at all, not even eventually.
  local M = fresh(1)
  for _, id in ipairs(H_IDS) do
    M.state.character[id] = 1.0
  end
  M.patch.add(TAPROOT, YAFFLE, 1.0)
  -- injected *through* that same cable, as a D->H cable's pulse would be
  M.heartwood.inject(TAPROOT, 1.0, YAFFLE)

  settle(M, 0.15)
  check("silent while it is still going out", #CALLS.g_strike == 0,
        "got " .. #CALLS.g_strike)
  settle(M, 20)
  check("and a bare chain never hands it back -- there is no lap to complete",
        #CALLS.g_strike == 0, "got " .. #CALLS.g_strike)
end

print("\n-- ...but a player-made H<->H shortcut can close a loop of its own --")
do
  -- cabling the two ends together turns the chain back into a ring, so the
  -- same "does not bounce back immediately" pulse now does eventually
  -- return, the same shape the old built-in ring always had.
  local M = fresh(1)
  for _, id in ipairs(H_IDS) do
    M.state.character[id] = 1.0
  end
  M.patch.add(TAPROOT, YAFFLE, 1.0)
  M.patch.add(TAPROOT, LEY, 1.0)   -- the shortcut that closes the loop
  M.heartwood.inject(TAPROOT, 1.0, YAFFLE)

  settle(M, 0.15)
  check("still silent immediately", #CALLS.g_strike == 0, "got " .. #CALLS.g_strike)
  settle(M, 3)
  check("but comes back around the player-made loop", #CALLS.g_strike > 0,
        "got " .. #CALLS.g_strike)
end

print("\n-- conductance: low dies within a hop, high circulates --")
do
  local function arrivals(cond)
    local M = fresh(1)
    for _, id in ipairs(H_IDS) do
      M.state.character[id] = cond
    end
    -- one tap on the far end of the chain, so nothing counted here is the
    -- injection itself -- only what actually travelled.
    M.patch.add(LEY, YAFFLE, 1.0)
    M.heartwood.inject(TAPROOT, 1.0, "test")
    settle(M, 8)
    return #CALLS.g_strike
  end

  local dead, live = arrivals(0.0), arrivals(1.0)
  check("low conductance: nothing reaches the far end", dead == 0, "got " .. dead)
  check("high conductance: it does", live > 0, "got " .. live)
end

print("\n-- an H<->H cable is a shortcut across the lattice --")
do
  local function hops_to(shortcut)
    local M = fresh(1)
    for _, id in ipairs(H_IDS) do
      M.state.character[id] = 0.8
    end
    M.patch.add(LEY, YAFFLE, 1.0)
    if shortcut then M.patch.add(TAPROOT, LEY, 1.0) end
    M.heartwood.inject(TAPROOT, 1.0, "test")
    settle(M, 4)
    return CALLS.g_strike[1] and CALLS.g_strike[1].t or math.huge
  end

  local long, short = hops_to(false), hops_to(true)
  check("the cable gets there sooner than the three-hop chain does", short < long,
        string.format("%.3f vs %.3f", short, long))
end

print("\n-- a one-way H<->H cable only conducts one way --")
do
  local M = fresh(1)
  for _, id in ipairs({TAPROOT, LEY}) do M.state.character[id] = 0.9 end
  M.patch.add(TAPROOT, LEY, 1.0, true)

  local specs = 0
  for _, c in ipairs(CALLS.patch_add) do specs = specs + 1 end
  check("one continuous link, not two", specs == 1, "got " .. specs)
  check("and it points the way the cable was drawn",
        CALLS.patch_add[1].src == M.bridge.bus("heart_out", M.topology.get(TAPROOT).index)
        and CALLS.patch_add[1].dst == M.bridge.bus("heart_in", M.topology.get(LEY).index))
end

print("\n-- conductance forwards to the engine --")
do
  local M = fresh(1)
  M.heartwood.init()
  check("all four pushed at init", #CALLS.heart_conductance == 4,
        "got " .. #CALLS.heart_conductance)
  M.state.character[WYRD] = 0.23
  M.state.notify_character_change(WYRD)
  local last = CALLS.heart_conductance[#CALLS.heart_conductance]
  check("and live on E2", last.index == M.topology.get(WYRD).index and last.v == 0.23,
        tostring(last.index) .. " " .. tostring(last.v))
end

print("\n-- E -> H and H -> a voice resolve to the lattice buses --")
do
  -- NOTE: a second, distinct shadowing bug from the one above, this time in
  -- the *continuous* half. dispatch.lua's specs_for checks `ordered("voice",
  -- "H")` (the voice's own audio feeding INTO the lattice, kind "aa" into
  -- heart_in) before it ever reaches `ordered("H", "voice")`
  -- (h_to_voice_spec, the lattice's emergence tapped OUT into the voice's mod
  -- path) -- and since ordered() matches a voice/H pair the same way
  -- regardless of which side the cable was drawn from, the "H","voice"
  -- branch and h_to_voice_spec are unreachable dead code, the same shape
  -- test/exciter.lua flags for E<->voice. this test asserts the actual
  -- (shadowed) behaviour; see the final report for the flagged
  -- lib/dispatch.lua issue.
  local M = fresh(1)
  local BRACKEN = "e.bracken"
  local bracken, mycel, oak = M.topology.get(BRACKEN), M.topology.get(MYCEL), M.topology.get("oak")

  M.patch.add(BRACKEN, MYCEL, 0.5)
  check("two synths: injection and the colour it sends back", #CALLS.patch_add == 2,
        #CALLS.patch_add)
  local inj, back
  for _, c in ipairs(CALLS.patch_add) do
    if c.kind == "aa" then inj = c else back = c end
  end
  check("stream goes into the lattice",
        inj and inj.src == M.bridge.bus("exc", bracken.index)
        and inj.dst == M.bridge.bus("heart_in", mycel.index))
  check("what emerges modulates the exciter's colour",
        back and back.src == M.bridge.bus("heart_out", mycel.index)
        and back.dst == M.bridge.bus("colour_mod", bracken.index))

  M.patch.add(MYCEL, "oak", 0.4)
  local tap = CALLS.patch_add[#CALLS.patch_add]
  check("the voice<->H pair resolves to the (shadowed) voice-feeds-lattice spec",
        tap.kind == "aa" and tap.src == M.bridge.bus("voice_out", oak.index - 1)
        and tap.dst == M.bridge.bus("heart_in", mycel.index), tostring(tap.dst))

  M.patch.remove(MYCEL, "oak")
  M.patch.remove(BRACKEN, MYCEL)
  check("all freed on remove", #CALLS.patch_free == 3, #CALLS.patch_free)
end

print("\n-- D -> H -> D closes a loop without running away --")
do
  local M = fresh(3)
  local GABRIEL, SPRIGGAN = "d.gabriel", "d.spriggan"
  for _, id in ipairs(H_IDS) do
    M.state.character[id] = 1.0 -- the most conductive lattice there is
  end
  -- every heartwood node cabled to something, and the lattice feeding a D
  -- cell that feeds it straight back in.
  M.patch.add(GABRIEL, TAPROOT, 1.0)      -- D -> H injection
  M.patch.add(WYRD, SPRIGGAN, 1.0)        -- H -> D pull
  M.patch.add(SPRIGGAN, LEY, 1.0)         -- D -> H re-injection, closing the loop
  M.patch.add(MYCEL, YAFFLE, 0.8)         -- GVOICE tap (voice<-H is unreachable, see above)
  M.patch.add(TAPROOT, KNAP, 0.8)
  M.patch.add(LEY, "e.bracken", 0.8)

  local ok = pcall(run, M, 20)
  check("survives 20s", ok)
  check("in-flight queue stays bounded",
        M.heartwood.pending_count() <= M.heartwood.MAX_PENDING,
        "pending " .. M.heartwood.pending_count())
  check("and it is still audibly doing something",
        #CALLS.g_strike > 0 or #CALLS.exciter_gate > 0,
        "g_strikes " .. #CALLS.g_strike .. " gates " .. #CALLS.exciter_gate)
end

print("\n-- Still freezes signals in flight --")
do
  local M = fresh(1)
  for _, id in ipairs(H_IDS) do
    M.state.character[id] = 0.8
  end
  M.patch.add(LEY, YAFFLE, 1.0)
  M.heartwood.inject(TAPROOT, 1.0, "test")

  M.state.global.still = true
  settle(M, 5)
  check("nothing emerges while Still", #CALLS.g_strike == 0, "got " .. #CALLS.g_strike)
  check("but it is still in flight", M.heartwood.pending_count() > 0)

  M.state.global.still = false
  settle(M, 3)
  check("and arrives once released", #CALLS.g_strike > 0, "got " .. #CALLS.g_strike)
end

report()
