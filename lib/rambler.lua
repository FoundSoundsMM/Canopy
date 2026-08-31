-- rambler.lua
-- D-cell gaits, the phase-coupling scheduler, and the shared pulse bus every
-- other pulse source on the panel rides on (§2.3, §7.2).
--
-- a "rambler" is one D cell's free-running phase oscillator; the gait is the
-- rule that decides how the phase advances and whether a wrap actually emits.
-- since the re-cut every gait in here is *phased*: the reactive ones (divide,
-- echo, meet) moved out to the weave (§2.7, lib/weave.lua), which is what
-- they always were -- transforms of somebody else's pulse rather than gaits.
--
-- three kinds of thing emit a pulse now, and all three go out through the
-- same door (`emit_from`) so that trails, fan-out caps and the one-tick
-- deferral that makes cycles safe are written exactly once:
--
--   * a D cell wrapping                       (this file)
--   * an R cell passing something on          (weave.lua)
--   * a voice being struck, out of its O socket (dispatch.lua)
--
-- §7.2 says "one clock.run coroutine at a 2ms tick"; this uses a metro
-- instead, deliberately -- clock.sleep() inside clock.run is tempo-relative
-- (beats, not seconds) in norns, and D-cell rates are genuine Hz, not
-- tempo-scaled, so a wall-clock metro is what "2ms tick" actually needs.
-- rooted gaits (§2.3) get their tempo relation back by reading
-- clock.get_beats() directly rather than by integrating a rate, which locks
-- them to the transport exactly instead of approximately.
--
-- quantise.lua sits between every *gait* and its output: a gait free-runs at
-- whatever rate it likes, but when it is heard is Swing/Scatter's call. what the
-- weave and the voice outs emit is deliberately NOT re-quantised -- those
-- pulses are derived from one that was already placed, and snapping a flam or
-- a swung off-beat back onto the grid would undo the only thing it does.

local topology  = wl("topology")
local patch     = wl("patch")
local state     = wl("state")
local dispatch  = wl("dispatch")
local heartwood = wl("heartwood")
local grove     = wl("grove")
local quantise  = wl("quantise")
local weave     = wl("weave")
local climate   = wl("climate")
local tm        = wl("tm")

local rambler = {}

rambler.TICK = 1 / 500
rambler.FLASH_DECAY = 0.12  -- §5.1 "flash 15 on pulse, decay ~120 ms"

local TICK = rambler.TICK

-- Kuramoto coupling constant, in Hz of phase pull at unity edge gain (§2.3).
-- scaled by Scatter and by each gait's own coupling multiplier.
local K_BASE = 2.0

-- runaway guards. a patch is a graph with cycles in it by design -- and since
-- the O socket landed, a cycle can now run through the audible voices -- so
-- the fan-out per tick and the scheduled-tap backlog are both hard-capped.
local MAX_EMITS_PER_TICK = 64
local MAX_SCHEDULED = 192

-- how far an arriving pulse shoves a free-running neighbour's phase (§6's
-- "mutual triggering", the discrete half of a D<->D cable). deliberately
-- small: §2.3 calls the coupling "the whole rhythm engine", so the nudge is
-- a flavour on top of it, not a rival.
local PULSE_NUDGE = 0.05

local ramblers = {}    -- d_id -> rambler
local order = {}       -- d_ids, stable iteration order
local snapshot = {}    -- d_id -> phase, sampled once per tick so coupling is
                       -- simultaneous rather than order-dependent
local scheduled = {}   -- {t=, r=, w=} future taps (burst ratchets)
local inbox = {}       -- {id=, w=, src=} pulse-cell traffic, delivered next tick
local sources = {}     -- {id=, w=} deferred emissions from non-pulse cells
local emits_this_tick = 0

local function char(r)
  return state.get_character(r.id, r.cell, 0, 1)
end
rambler.char = char

local function bps()
  return (clock.get_tempo() or 120) / 60
end

-- gaits --------------------------------------------------------------------
-- each gait declares:
--   rooted_ok       can it lock to the norns clock (§2.3)?
--   coupling        multiplier on K for this gait
--   drift           multiplier on the chaos-driven rate drift (§4.1)
--   read(r)         -> value, display text   (E2, the one knob per §4.2)
--   rate(r)         -> Hz                    (wild)
--   cycles_per_beat -> multiplier            (rooted)
--   wrap(r)         -> weight, or nil to swallow this cycle

local GAITS = {}

rambler.GAIT_ORDER = {
  "metric", "euclidean", "figure", "slow",
  "burst", "stochastic", "drifter", "accelerando",
}

-- metric: locks to the norns clock, integer division.
local DIVS = {
  {1/4, "1/4"}, {1/3, "1/3"}, {1/2, "1/2"}, {2/3, "2/3"}, {1, "1"},
  {3/2, "3/2"}, {2, "2"}, {3, "3"}, {4, "4"},
}
GAITS.metric = {
  rooted_ok = true, coupling = 0.8, drift = 0.2,
  read = function(r)
    local i = util.clamp(math.floor(char(r) * (#DIVS - 1) + 0.5), 0, #DIVS - 1) + 1
    return DIVS[i][1], DIVS[i][2] .. " x beat"
  end,
  cycles_per_beat = function(r) return (GAITS.metric.read(r)) end,
  rate = function(r) return (GAITS.metric.read(r)) * bps() end,
  wrap = function(r) return 1.0 end,
}

-- euclidean: k pulses spread across n steps. steps run at 2/beat, so the
-- 8-step pattern is one bar long when rooted.
local EUCLID_N = 8
GAITS.euclidean = {
  rooted_ok = true, coupling = 0.8, drift = 0.2,
  read = function(r)
    local k = util.clamp(math.floor(char(r) * EUCLID_N + 0.5), 0, EUCLID_N)
    return k, k .. ":" .. EUCLID_N
  end,
  cycles_per_beat = function(r) return 2 end,
  rate = function(r) return 2 * bps() end,
  wrap = function(r)
    -- Bresenham euclidean: step i fires when (i*k) mod n < k.
    local k = GAITS.euclidean.read(r)
    if ((r.cycle % EUCLID_N) * k) % EUCLID_N < k then return 1.0 end
    return nil
  end,
}

-- figure: a bank of sixteen-step patterns, on the clock. euclidean gives you
-- an even spread of k in n and nothing else; this is where the crooked ones
-- live -- the claves and the tresillo, the figures that are asymmetrical on
-- purpose and are most of what a drum machine is actually made of.
local FIGURES = {
  {"four",     "1000100010001000"},
  {"backbeat", "0000100000001000"},
  {"offbeat",  "0010001000100010"},
  {"tresillo", "1001001010010010"},
  {"son",      "1001001000101000"},
  {"rumba",    "1001000100101000"},
  {"bossa",    "1001001000100100"},
  {"shiko",    "1000101000101000"},
}
GAITS.figure = {
  rooted_ok = true, coupling = 0.8, drift = 0.1,
  read = function(r)
    local i = util.clamp(math.floor(char(r) * (#FIGURES - 1) + 0.5), 0, #FIGURES - 1) + 1
    return i, FIGURES[i][1]
  end,
  cycles_per_beat = function(r) return 4 end,
  rate = function(r) return 4 * bps() end,
  wrap = function(r)
    local pat = FIGURES[(GAITS.figure.read(r))][2]
    local step = (r.cycle % 16) + 1
    if pat:sub(step, step) ~= "1" then return nil end
    -- the ones that land on a beat are the ones you feel; the rest are the
    -- ones that make it a figure rather than a pulse.
    return ((step - 1) % 4 == 0) and 1.0 or 0.72
  end,
}

-- slow: very low rate, high weight.
GAITS.slow = {
  rooted_ok = false, coupling = 1.4, drift = 0.5,
  read = function(r)
    local hz = 0.03 + char(r) * 0.47
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r) return (GAITS.slow.read(r)) end,
  wrap = function(r) return 1.0 end,
}

-- burst: one wrap fires a ratchet of 2-7. Scatter picks how many.
-- §4.1 wants the burst itself triggered on the beat, so it overrides the
-- rate-derived grid with a whole beat, and lays its ratchet out on a
-- subdivision of that beat rather than on a fraction of its own cycle -- the
-- flam lands on grid lines and finishes before the next beat. the old
-- free spacing comes back as chaos rises, blended in rather than switched.
GAITS.burst = {
  rooted_ok = false, coupling = 1.0, drift = 1.0,
  quant_grid = 1.0,
  read = function(r)
    local hz = 0.3 + char(r) * 2.7
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r) return (GAITS.burst.read(r)) end,
  ratchet = function(r, t0, weight)
    local n = 2 + math.floor((state.global.scatter or 0) * 5 + 0.5)
    if n < 2 then return end
    local chaos = quantise.chaos()
    local grid_gap = quantise.ratchet_gap(n) * quantise.spb()
    local free_gap = (1 / math.max(GAITS.burst.read(r), 0.01)) * 0.45 / n
    local gap = grid_gap + (free_gap - grid_gap) * chaos
    local w = weight
    for i = 1, n - 1 do
      w = w * 0.78
      local jitter = 0
      if chaos > 0 then
        jitter = (math.random() * 2 - 1) * chaos * chaos * gap * 0.5
      end
      rambler.push(t0 + i * gap + jitter, r, w, true)
    end
  end,
  wrap = function(r) return 1.0 end,
}

-- stochastic: a Bernoulli gate at the wrap. E2 is the probability; the rate
-- itself rides Scatter, so wilder settings also mean faster dice.
GAITS.stochastic = {
  rooted_ok = false, coupling = 1.0, drift = 1.0,
  read = function(r)
    local p = char(r)
    return p, string.format("p %.2f", p)
  end,
  rate = function(r) return 1.5 + (state.global.scatter or 0) * 4.5 end,
  wrap = function(r)
    if math.random() < (GAITS.stochastic.read(r)) then
      return 0.6 + math.random() * 0.4
    end
    return nil
  end,
}

-- drifter: fast, free, strongest coupling constant.
GAITS.drifter = {
  rooted_ok = false, coupling = 2.5, drift = 3.0,
  read = function(r)
    local hz = 0.5 + char(r) * 7.5
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r) return (GAITS.drifter.read(r)) end,
  wrap = function(r) return 0.85 end,
}

-- accelerando: rate ramps across a cycle of wraps, then resets.
local ACCEL_CYCLE = 8
GAITS.accelerando = {
  rooted_ok = false, coupling = 1.0, drift = 0.5,
  read = function(r)
    local hz = 0.5 + char(r) * 3.5
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r)
    local t = (r.cycle % ACCEL_CYCLE) / ACCEL_CYCLE
    return (GAITS.accelerando.read(r)) * (0.5 + t * 2.0)
  end,
  -- loudest at the start of each ramp, thinning as it speeds up
  wrap = function(r) return 1.0 - ((r.cycle % ACCEL_CYCLE) / ACCEL_CYCLE) * 0.5 end,
}

rambler.GAITS = GAITS

-- construction ---------------------------------------------------------------

local function reset_gait_state(r)
  r.cycle = 0
  r.drift = 0
  r.abs = nil
end

for id, cell in topology.each() do
  if cell.type == "D" then
    local r = {
      id = id,
      cell = cell,
      gait = state.get_gait(id, cell.gait),
      rooted = state.get_rooted(id, cell.rooted or false),
      -- spread the starting phases: identical starts make every coupling
      -- experiment look like it locked instantly when it never moved at all.
      phase = math.random(),
      cycle = 0,
      flash = -1,
      in_flash = -1,
      last_weight = 0,
      energy = 0,
      d_links = {},
    }
    reset_gait_state(r)
    ramblers[id] = r
    table.insert(order, id)
  end
end

-- the shared pulse bus --------------------------------------------------------
-- edges_at() builds a table per call; at 500 Hz that is real GC pressure on a
-- CM3, so every pulse source's out-list is cached here and rebuilt only when
-- the graph changes. edge tables are stable objects, so a gain tweak is
-- picked up without a rebuild.
--
-- `pulse` on a link means "the far end is itself a pulse cell" (D or R), and
-- that is the flag the one-tick deferral hangs off: pulse-cell to pulse-cell
-- traffic goes through the inbox, so a cycle in the patch cannot recurse. 2 ms
-- per hop is inaudible, and it makes runaway impossible by construction rather
-- than by a depth counter.

local PULSE_CELL = topology.PULSE_TYPES
local out_cache = {}

local function build_out_links(id)
  local links = {}
  for _, edge in ipairs(patch.edges_at(id)) do
    local other = patch.other(edge, id)
    local ocell = topology.get(other)
    -- a one-way cable a->b only emits from a (§3).
    if ocell and ((not edge.oneway) or edge.a == id) then
      table.insert(links, {
        id = other, edge = edge, pulse = PULSE_CELL[ocell.type] or false,
      })
    end
  end
  out_cache[id] = links
  return links
end

function rambler.out_links(id)
  return out_cache[id] or build_out_links(id)
end

local function rebuild_links()
  out_cache = {}
  for _, r in pairs(ramblers) do
    r.d_links = {}
    r.energy = 0
    for _, edge in ipairs(patch.edges_at(r.id)) do
      local other = patch.other(edge, r.id)
      local ocell = topology.get(other)
      if ocell and ocell.type == "D" then
        -- a one-way cable a->b only pulls b (§3).
        if (not edge.oneway) or edge.b == r.id then
          table.insert(r.d_links, {id = other, edge = edge})
          r.energy = math.min(1, r.energy + math.abs(edge.gain))
        end
      end
    end
  end
end

patch.on_change(rebuild_links)
rebuild_links()

-- emission -------------------------------------------------------------------

-- `exact` taps were placed on the grid when they were made (a burst ratchet)
-- and fire as-is; the rest go back through the quantiser when they come due.
function rambler.push(t, r, w, exact)
  if #scheduled >= MAX_SCHEDULED then return end
  table.insert(scheduled, {t = t, r = r, w = w, exact = exact or false})
end

function rambler.schedule(r, delay, w)
  rambler.push(util.time() + delay, r, w, false)
end

-- a pulse arriving at a pulse cell from outside its own family -- one
-- emerging from the heartwood lattice, say. deferred by a tick and delivered
-- through the same inbox as cell-to-cell traffic, so a D->H->D loop is
-- bounded by construction in exactly the way a D->D one is.
function rambler.inject(id, w, src, sign)
  local cell = topology.get(id)
  if not cell or not PULSE_CELL[cell.type] then return end
  if #inbox >= MAX_SCHEDULED then return end
  table.insert(inbox, {
    id = id, w = util.clamp(w or 1, 0, 1), sign = sign or 1, src = src,
  })
end

-- an emission from a cell that is not a pulse cell and therefore has no
-- record here -- a voice's O socket the moment it is struck, or (§2.7b) a G
-- cell answering its own strike. queued rather than walked immediately,
-- because the strike that caused it is itself downstream of a pulse, and a
-- cell cabled back round to its own trigger has to cost a tick per lap like
-- everything else does. `except` is the cable the triggering pulse arrived
-- on, if any -- a G cell needs it so it does not send its answer straight
-- back down its own input (the same rule weave.out and heartwood.inject
-- apply); a voice's O socket has no such cable, so it is simply omitted.
function rambler.post_source(id, w, except)
  if #sources >= MAX_SCHEDULED then return end
  table.insert(sources, {id = id, w = util.clamp(w or 1, 0, 1), except = except})
end

-- the one door every pulse leaves by.
--
-- `only` restricts it to a single cable -- counted over the *eligible* ones --
-- which is how the weave's hocket rule sends successive pulses different ways.
--
-- `except` drops one cable from the fan-out: the one an arriving pulse came in
-- on. cables are undirected, so without it a transform would send its output
-- straight back down its own input, which is not coupling, it is a duplicate.
-- heartwood.lua excludes its `src` for exactly the same reason. a D cell
-- passes no `except` -- a pulse-maker answering its neighbour *is* the
-- coupling, and §2.3 wants it.
function rambler.emit_from(id, weight, only, except)
  if emits_this_tick >= MAX_EMITS_PER_TICK then return 0 end
  emits_this_tick = emits_this_tick + 1

  weight = util.clamp(weight or 1, 0, 1)
  local links = rambler.out_links(id)
  local sent, eligible = 0, 0

  -- `eligible` counts only the cables this pulse may leave by, so `only`
  -- indexes the same list hocket asked out_degree() about.
  --
  -- written flat rather than with a `send` helper closure: this runs on every
  -- pulse of every cell, and a closure per emission is real garbage to collect
  -- on a CM3 for no benefit.
  for _, link in ipairs(links) do
    if link.id ~= except then
      eligible = eligible + 1
      if (not only) or only == eligible then
        if link.pulse then
          if #inbox < MAX_SCHEDULED then
            table.insert(inbox, {
              id = link.id,
              w = weight * math.abs(link.edge.gain),
              -- sign is carried separately: a reactive cell wants the
              -- magnitude, but a phase nudge has to respect §3's "negative
              -- gain ... pulse coupling becomes repulsion" the same way the
              -- Kuramoto term does.
              sign = link.edge.gain < 0 and -1 or 1,
              src = id,
            })
          end
        else
          dispatch.on_pulse(id, link.id, link.edge, weight)
        end
        sent = sent + 1
      end
    end
  end
  return sent, eligible
end

function rambler.out_degree(id, except)
  local links = rambler.out_links(id)
  if not except then return #links end
  local n = 0
  for _, link in ipairs(links) do
    if link.id ~= except then n = n + 1 end
  end
  return n
end

-- a phased gait's cycle length in seconds, which is what picks its grid.
local function period_of(gait, r)
  if not gait.rate then return nil end
  local hz = gait.rate(r)
  if not hz or hz <= 0 then return nil end
  return 1 / hz
end

-- the front door for a *gait*: Swing/Scatter decide whether it speaks now or on
-- the next grid line (§4.1, and quantise.lua for the sweep). the ratchet hook
-- hangs off the quantised time, not the raw one, so a burst's flam is laid
-- out from where the burst is actually heard.
function rambler.emit(r, weight)
  local now = util.time()
  local gait = GAITS[r.gait]
  local t = quantise.snap(now, period_of(gait, r), gait.quant_grid)
  if gait.ratchet then gait.ratchet(r, t, util.clamp(weight or 1, 0, 1)) end
  if t <= now + 1e-9 then
    rambler.emit_now(r, weight)
  else
    rambler.push(t, r, weight, true)
  end
end

function rambler.emit_now(r, weight)
  weight = util.clamp(weight or 1, 0, 1)
  r.flash = util.time()
  r.last_weight = weight
  local sent = rambler.emit_from(r.id, weight)
  if sent and sent > 0 then
    local first = rambler.out_links(r.id)[1]
    local target = first and topology.get(first.id)
    state.set_event(r.cell.name .. " -> " .. (target and target.name or "?"))
  end
end

local function deliver(msg, now)
  local cell = topology.get(msg.id)
  if not cell then return end

  if cell.type == "R" then
    weave.pulse_in(msg.id, msg.w, msg.src, now)
    return
  end

  if cell.type == "TM" then
    tm.pulse_in(msg.id, msg.w, msg.src, now)
    return
  end

  local r = ramblers[msg.id]
  if not r then return end
  local gait = GAITS[r.gait]
  r.in_flash = now
  if not (r.rooted and gait.rooted_ok) then
    -- a phased gait is *nudged* toward its wrap rather than hard-retriggered.
    -- hard retriggering would drown the Kuramoto term and turn every cable
    -- into a clock line, which is precisely what §1.5 says this is not.
    r.phase = r.phase + msg.sign * msg.w * PULSE_NUDGE
    if r.phase >= 1.0 then
      r.phase = 1.0            -- armed; the next tick wraps it
    elseif r.phase < 0 then
      r.phase = 0              -- a repelling nudge delays, it never reverses
    end
  end
end

-- advance --------------------------------------------------------------------

local function fire_wrap(r, gait)
  local w = gait.wrap(r)
  if w then rambler.emit(r, w) end
end

local function advance_rooted(r, gait)
  local cpb = gait.cycles_per_beat(r)
  if cpb <= 0 then return end
  local pos = clock.get_beats() * cpb
  local cyc = math.floor(pos)
  r.phase = pos - cyc
  -- first tick, or the division just changed under us: resync silently.
  if r.abs == nil or math.abs(cyc - r.abs) > 8 then r.abs = cyc end
  local fired = 0
  while r.abs < cyc and fired < 4 do
    r.abs = r.abs + 1
    r.cycle = r.abs
    fire_wrap(r, gait)
    fired = fired + 1
  end
  r.abs = cyc
end

local function advance_wild(r, gait, K, chaos)
  -- §4.1 Scatter is also "gait drift": a slow random walk on the rate, scaled
  -- by chaos (Scatter) rather than Swing -- there is nothing to be gained from
  -- drifting a rate whose output is about to be snapped back onto the grid
  -- anyway.
  if gait.drift > 0 and chaos > 0 then
    r.drift = util.clamp(
      r.drift + (math.random() - 0.5) * chaos * gait.drift * 0.01, -0.4, 0.4)
  else
    r.drift = 0
  end

  local hz = gait.rate(r) * (1 + r.drift)

  -- §2.3: dphi = rate*dt + K * sum_j( g_ij * sin(2pi*(phi_j - phi_i)) )
  local pull = 0
  if gait.coupling > 0 and #r.d_links > 0 then
    local mine = r.snap
    local sum = 0
    for _, link in ipairs(r.d_links) do
      local op = snapshot[link.id]
      if op then sum = sum + link.edge.gain * math.sin(2 * math.pi * (op - mine)) end
    end
    pull = K * gait.coupling * sum
  end

  -- clamped forward-only: a big negative pull must slow an oscillator, never
  -- run it backwards past a wrap it already announced.
  local eff = hz + pull
  if eff < 0 then eff = 0 end
  r.phase = r.phase + eff * TICK

  local fired = 0
  while r.phase >= 1.0 and fired < 4 do
    r.phase = r.phase - 1.0
    r.cycle = r.cycle + 1
    fire_wrap(r, gait)
    fired = fired + 1
  end
  if r.phase >= 1.0 then r.phase = r.phase % 1.0 end
end

function rambler.tick()
  local now = util.time()
  emits_this_tick = 0

  -- §4.1 Still: gaits freeze, resonators ring out. scheduled taps and queued
  -- traffic freeze with them rather than flushing on resume.
  if state.global.still then return end

  -- 0. the heartwood's in-flight pulses (§2.5). first, so a signal emerging
  --    from the lattice this tick reaches the inbox in time to be delivered
  --    in step 3 rather than sitting a whole extra tick.
  heartwood.tick(now)

  -- 0b. the continuous half of the pitch fields (§2.6), and the weather that
  --     is slowly moving everybody's knobs (§2.8). both decimate themselves;
  --     both sit inside the Still check for the same reason the lattice does,
  --     so a frozen patch is frozen in pitch and in weather too.
  grove.tick(now)
  climate.tick(now)

  -- 1. the weave's own scheduled taps (echoes, flams, delays, rolls).
  weave.tick(now)

  -- 2. scheduled gait taps (quantised emissions, burst ratchets).
  --    due and keep are split *before* anything fires, because firing can
  --    push a fresh entry (an un-quantised tap re-snapping itself onto the
  --    grid) and that entry must survive the swap rather than be dropped.
  if #scheduled > 0 then
    local due, keep = {}, {}
    for _, ev in ipairs(scheduled) do
      if ev.t <= now then table.insert(due, ev) else table.insert(keep, ev) end
    end
    scheduled = keep
    for _, ev in ipairs(due) do
      if ev.exact then rambler.emit_now(ev.r, ev.w) else rambler.emit(ev.r, ev.w) end
    end
  end

  -- 3. last tick's pulse-cell traffic, then last tick's voice-out emissions.
  if #inbox > 0 then
    local pending = inbox
    inbox = {}
    for _, msg in ipairs(pending) do deliver(msg, now) end
  end

  if #sources > 0 then
    local pending = sources
    sources = {}
    for _, msg in ipairs(pending) do
      rambler.emit_from(msg.id, msg.w, nil, msg.except)
    end
  end

  -- 4. sample every phase, then advance.
  for _, id in ipairs(order) do
    local r = ramblers[id]
    snapshot[id] = r.phase
    r.snap = r.phase
  end

  local scatter = state.global.scatter or 0
  local K = K_BASE * (0.15 + scatter * 1.85)
  local chaos = quantise.chaos()

  for _, id in ipairs(order) do
    local r = ramblers[id]
    local gait = GAITS[r.gait]
    if r.rooted and gait.rooted_ok then
      advance_rooted(r, gait)
    else
      advance_wild(r, gait, K, chaos)
    end
  end
end

-- read/control surface -------------------------------------------------------

function rambler.get(id)
  return ramblers[id]
end

-- §5.1 "flash 15 on pulse, decay ~120ms; base rises with coupling strength"
function rambler.level(id, base)
  local r = ramblers[id]
  if not r then return base end
  local lvl = base + math.floor(r.energy * 4)
  local age = util.time() - r.flash
  if age >= 0 and age < rambler.FLASH_DECAY then
    local f = 1 - (age / rambler.FLASH_DECAY)
    lvl = lvl + math.floor((15 - lvl) * f * r.last_weight)
  end
  return util.clamp(math.floor(lvl), 0, 15)
end

-- which grid this cell is currently being held to, or nil once Scatter has
-- let go of it entirely (§5.3 reads this out under the gait).
function rambler.grid_name(id)
  local r = ramblers[id]
  if not r then return nil end
  if quantise.chaos() >= 1 then return nil end
  local gait = GAITS[r.gait]
  return quantise.name(gait.quant_grid or quantise.grid_beats(period_of(gait, r)))
end

function rambler.info(id)
  local r = ramblers[id]
  if not r then return nil end
  local gait = GAITS[r.gait]
  local _, text = gait.read(r)
  return {
    gait = r.gait,
    param = text,
    rooted = r.rooted,
    rooted_ok = gait.rooted_ok,
    phased = true,
    phase = r.phase,
    energy = r.energy,
    grid = rambler.grid_name(id),
  }
end

function rambler.set_gait(id, key)
  local r = ramblers[id]
  if not r or not GAITS[key] then return nil end
  r.gait = key
  state.gait[id] = key
  reset_gait_state(r)
  return key
end

-- K1+E2 while holding a D cell (§4.2)
function rambler.cycle_gait(id, delta)
  local r = ramblers[id]
  if not r then return nil end
  local n = #rambler.GAIT_ORDER
  local at = 1
  for i, key in ipairs(rambler.GAIT_ORDER) do
    if key == r.gait then at = i break end
  end
  local nxt = ((at - 1 + delta) % n) + 1
  return rambler.set_gait(id, rambler.GAIT_ORDER[nxt])
end

function rambler.set_rooted(id, flag)
  local r = ramblers[id]
  if not r or not GAITS[r.gait].rooted_ok then return nil end
  r.rooted = flag and true or false
  state.rooted[id] = r.rooted
  r.abs = nil
  return r.rooted
end

-- K1 + tap a D cell (§2.3). no-op on gaits with nothing to root to.
function rambler.toggle_rooted(id)
  local r = ramblers[id]
  if not r or not GAITS[r.gait].rooted_ok then return nil end
  r.rooted = not r.rooted
  state.rooted[id] = r.rooted
  r.abs = nil
  return r.rooted
end

function rambler.start()
  rambler.metro = metro.init(function() rambler.tick() end, TICK, -1)
  rambler.metro:start()
end

function rambler.stop()
  if rambler.metro then
    rambler.metro:stop()
    rambler.metro = nil
  end
end

return rambler
