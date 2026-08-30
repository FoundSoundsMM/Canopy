-- build phase 5: the §2.5 diffusion lattice. the discrete side (a pulse
-- entering at one node and emerging from the others at different times and
-- amplitudes), conductance's two ranges, H<->H shortcuts, and the continuous
-- side's bus resolution through the §6 matrix.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local TAPROOT, MYCEL, WYRD, LEY = "h.taproot", "h.mycel", "h.wyrd", "h.ley"
local HEARTH, HOLLOWAY, WARREN, BARROW = "h.hearth", "h.holloway", "h.warren", "h.barrow"

-- advance the virtual clock through the scheduler without needing a D cell:
-- the lattice's in-flight pulses are stepped by rambler.tick like everything
-- else, so `run` is the only clock there is.
local function settle(M, seconds) run(M, seconds) end

print("\n-- a pulse injected at one node emerges from the others --")
do
  local M = fresh(1)
  -- cable four nodes spread round the ring to trigger sockets, so an arrival
  -- is visible as a strike on a distinct voice.
  M.patch.add(TAPROOT, "oak.trig", 1.0)     -- engine voice 0
  M.patch.add(WYRD, "hazel.trig", 1.0)     -- engine voice 1
  M.patch.add(HEARTH, "alder.trig", 1.0)   -- engine voice 2, four hops away
  M.patch.add(BARROW, "rowan.trig", 1.0)   -- engine voice 3
  for _, id in ipairs({TAPROOT, MYCEL, WYRD, LEY, HEARTH, HOLLOWAY, WARREN, BARROW}) do
    M.state.character[id] = 0.8 -- a good conductor: short hops, little loss
  end

  M.heartwood.inject(TAPROOT, 1.0, "test")
  settle(M, 3)

  local hit = {}
  for _, s in ipairs(CALLS.strike) do hit[s.voice] = (hit[s.voice] or 0) + 1 end
  check("the injected node fires immediately", hit[0] and hit[0] > 0)
  check("the far side of the ring fires too", hit[1] and hit[2] and hit[3],
        "voices hit: " .. tostring(hit[0]) .. "/" .. tostring(hit[1])
        .. "/" .. tostring(hit[2]) .. "/" .. tostring(hit[3]))

  -- "emerging from the other nodes at different times and amplitudes" (§2.5)
  local first_t, far_t
  for _, s in ipairs(CALLS.strike) do
    if s.voice == 0 and not first_t then first_t = s.t end
    if s.voice == 2 and not far_t then far_t = s.t end  -- Hearth, 4 hops away
  end
  check("later the further away it is", far_t > first_t,
        string.format("%.3f vs %.3f", first_t, far_t))

  local loudest_near, loudest_far = 0, 0
  for _, s in ipairs(CALLS.strike) do
    if s.voice == 0 then loudest_near = math.max(loudest_near, s.force) end
    if s.voice == 2 then loudest_far = math.max(loudest_far, s.force) end
  end
  check("and quieter", loudest_far < loudest_near,
        string.format("%.3f vs %.3f", loudest_far, loudest_near))
end

print("\n-- a pulse does not bounce straight back out of its own cable --")
do
  local M = fresh(1)
  for _, id in ipairs({TAPROOT, MYCEL, WYRD, LEY, HEARTH, HOLLOWAY, WARREN, BARROW}) do
    M.state.character[id] = 1.0
  end
  M.patch.add(TAPROOT, "oak.trig", 1.0)
  -- injected *through* that same cable, as a D->H cable's pulse would be
  M.heartwood.inject(TAPROOT, 1.0, "oak.trig")

  settle(M, 0.15)
  check("silent while it is still going round", #CALLS.strike == 0,
        "got " .. #CALLS.strike)
  settle(M, 1.5)
  check("but the lattice hands it back after a lap", #CALLS.strike > 0,
        "got " .. #CALLS.strike)
end

print("\n-- conductance: low dies within a hop, high circulates --")
do
  local function arrivals(cond)
    local M = fresh(1)
    for _, id in ipairs({TAPROOT, MYCEL, WYRD, LEY, HEARTH, HOLLOWAY, WARREN, BARROW}) do
      M.state.character[id] = cond
    end
    -- one tap on the far side of the ring, so nothing counted here is the
    -- injection itself -- only what actually travelled.
    M.patch.add(HEARTH, "oak.trig", 1.0)
    M.heartwood.inject(TAPROOT, 1.0, "test")
    settle(M, 8)
    return #CALLS.strike
  end

  local dead, live = arrivals(0.0), arrivals(1.0)
  check("low conductance: nothing reaches the far side", dead == 0, "got " .. dead)
  check("high conductance: it does", live > 0, "got " .. live)
end

print("\n-- an H<->H cable is a shortcut across the lattice --")
do
  local function hops_to(shortcut)
    local M = fresh(1)
    for _, id in ipairs({TAPROOT, MYCEL, WYRD, LEY, HEARTH, HOLLOWAY, WARREN, BARROW}) do
      M.state.character[id] = 0.8
    end
    M.patch.add(HEARTH, "oak.trig", 1.0)
    if shortcut then M.patch.add(TAPROOT, HEARTH, 1.0) end
    M.heartwood.inject(TAPROOT, 1.0, "test")
    settle(M, 4)
    return CALLS.strike[1] and CALLS.strike[1].t or math.huge
  end

  local long, short = hops_to(false), hops_to(true)
  check("the cable gets there sooner than the ring does", short < long,
        string.format("%.3f vs %.3f", short, long))
end

print("\n-- a one-way H<->H cable only conducts one way --")
do
  local M = fresh(1)
  for _, id in ipairs({TAPROOT, HEARTH}) do M.state.character[id] = 0.9 end
  -- taproot -> hearth, one-way, and hearth's own conductance floored so the
  -- ring can't carry anything back round behind the test's back.
  for _, id in ipairs({MYCEL, WYRD, LEY, HOLLOWAY, WARREN, BARROW}) do
    M.state.character[id] = 0.0
  end
  M.patch.add(TAPROOT, HEARTH, 1.0, true)

  local specs = 0
  for _, c in ipairs(CALLS.patch_add) do specs = specs + 1 end
  check("one continuous link, not two", specs == 1, "got " .. specs)
  check("and it points the way the cable was drawn",
        CALLS.patch_add[1].src == M.bridge.bus("heart_out", M.topology.get(TAPROOT).index)
        and CALLS.patch_add[1].dst == M.bridge.bus("heart_in", M.topology.get(HEARTH).index))
end

print("\n-- conductance forwards to the engine --")
do
  local M = fresh(1)
  M.heartwood.init()
  check("all eight pushed at init", #CALLS.heart_conductance == 8,
        "got " .. #CALLS.heart_conductance)
  M.state.character[WARREN] = 0.23
  M.state.notify_character_change(WARREN)
  local last = CALLS.heart_conductance[#CALLS.heart_conductance]
  check("and live on E2", last.index == M.topology.get(WARREN).index and last.v == 0.23,
        tostring(last.index) .. " " .. tostring(last.v))
end

print("\n-- S -> H and H -> node resolve to the lattice buses --")
do
  local M = fresh(1)
  local BECK = "s.beck"
  local beck, mycel, oak = M.topology.get(BECK), M.topology.get(MYCEL), M.topology.get("oak")

  M.patch.add(BECK, MYCEL, 0.5)
  check("two synths: injection and the colour it sends back", #CALLS.patch_add == 2,
        #CALLS.patch_add)
  local inj, back
  for _, c in ipairs(CALLS.patch_add) do
    if c.kind == "aa" then inj = c else back = c end
  end
  check("stream goes into the lattice",
        inj and inj.src == M.bridge.bus("exc", beck.index)
        and inj.dst == M.bridge.bus("heart_in", mycel.index))
  check("what emerges modulates the exciter's colour",
        back and back.src == M.bridge.bus("heart_out", mycel.index)
        and back.dst == M.bridge.bus("colour_mod", beck.index))

  M.patch.add(MYCEL, "oak.mod", 0.4)
  local tap = CALLS.patch_add[#CALLS.patch_add]
  check("H -> the M socket taps the emergence bus into the voice",
        tap.kind == "aa" and tap.src == M.bridge.bus("heart_out", mycel.index)
        and tap.dst == M.bridge.bus("mod_in", oak.index - 1), tostring(tap.dst))

  M.patch.remove(MYCEL, "oak.mod")
  M.patch.remove(BECK, MYCEL)
  check("all freed on remove", #CALLS.patch_free == 3, #CALLS.patch_free)
end

print("\n-- D -> H -> D closes a loop without running away --")
do
  local M = fresh(3)
  local GABRIEL, PUCK = "d.gabriel", "d.spriggan"
  for _, id in ipairs({TAPROOT, MYCEL, WYRD, LEY, HEARTH, HOLLOWAY, WARREN, BARROW}) do
    M.state.character[id] = 1.0 -- the most conductive lattice there is
  end
  -- every heartwood node cabled to something, and the lattice feeding a D
  -- cell that feeds it straight back in.
  M.patch.add(GABRIEL, TAPROOT, 1.0)
  M.patch.add(HEARTH, PUCK, 1.0)
  M.patch.add(PUCK, WARREN, 1.0)
  M.patch.add(MYCEL, "oak.trig", 0.8)
  M.patch.add(HOLLOWAY, "alder.trig", 0.8)
  M.patch.add(LEY, "s.bracken", 0.8)

  local ok = pcall(run, M, 20)
  check("survives 20s", ok)
  check("in-flight queue stays bounded",
        M.heartwood.pending_count() <= M.heartwood.MAX_PENDING,
        "pending " .. M.heartwood.pending_count())
  check("and it is still audibly doing something", #CALLS.strike > 0,
        "strikes " .. #CALLS.strike)
end

print("\n-- Still freezes signals in flight --")
do
  local M = fresh(1)
  for _, id in ipairs({TAPROOT, MYCEL, WYRD, LEY, HEARTH, HOLLOWAY, WARREN, BARROW}) do
    M.state.character[id] = 0.8
  end
  M.patch.add(HEARTH, "oak.trig", 1.0)
  M.heartwood.inject(TAPROOT, 1.0, "test")

  M.state.global.still = true
  settle(M, 5)
  check("nothing emerges while Still", #CALLS.strike == 0, "got " .. #CALLS.strike)
  check("but it is still in flight", M.heartwood.pending_count() > 0)

  M.state.global.still = false
  settle(M, 3)
  check("and arrives once released", #CALLS.strike > 0, "got " .. #CALLS.strike)
end

report()
