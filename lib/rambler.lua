-- rambler.lua
-- D-cell gaits + the phase-coupling scheduler (§2.3, §7.2).
--
-- build phase 3: all ten gaits, D<->D Kuramoto coupling, and the 2ms tick.
-- a "rambler" is one D cell's free-running phase oscillator; the gait is the
-- rule that decides how the phase advances and whether a wrap actually emits.
-- three of the ten gaits (divider, echo, coincidence) have no phase of their
-- own -- they are purely reactive, and only speak when spoken to.
--
-- §7.2 says "one clock.run coroutine at a 2ms tick"; this uses a metro
-- instead, deliberately -- clock.sleep() inside clock.run is tempo-relative
-- (beats, not seconds) in norns, and D-cell rates are genuine Hz, not
-- tempo-scaled, so a wall-clock metro is what "2ms tick" actually needs.
-- rooted gaits (§2.3) get their tempo relation back by reading
-- clock.get_beats() directly rather than by integrating a rate, which locks
-- them to the transport exactly instead of approximately.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local dispatch = wl("dispatch")

local rambler = {}

rambler.TICK = 1 / 500
rambler.FLASH_DECAY = 0.12  -- §5.1 "flash 15 on pulse, decay ~120 ms"
rambler.TRAIL_LIFE = 0.30   -- §5.2 pulse dot travel time along a cable

local TICK = rambler.TICK

-- Kuramoto coupling constant, in Hz of phase pull at unity edge gain (§2.3).
-- scaled by Weather (E2) and by each gait's own coupling multiplier.
local K_BASE = 2.0

-- runaway guards. a patch is a graph with cycles in it by design, so both the
-- fan-out per tick and the scheduled-tap backlog are hard-capped.
local MAX_EMITS_PER_TICK = 64
local MAX_SCHEDULED = 192
local MAX_TRAILS = 48

-- how far an arriving pulse shoves a free-running neighbour's phase (§6's
-- "mutual triggering", the discrete half of a D<->D cable). deliberately
-- small: §2.3 calls the coupling "the whole rhythm engine", so the nudge is
-- a flavour on top of it, not a rival. at 0.15 it swamped the Kuramoto term
-- and two locked cells visibly rang against each other instead of settling.
local PULSE_NUDGE = 0.05

local ramblers = {}    -- d_id -> rambler
local order = {}       -- d_ids, stable iteration order
local snapshot = {}    -- d_id -> phase, sampled once per tick so coupling is
                       -- simultaneous rather than order-dependent
local scheduled = {}   -- {t=, r=, w=} future taps (burst ratchets, echo)
local inbox = {}       -- {id=, w=, src=} D->D traffic, delivered next tick
local emits_this_tick = 0
local tick_n = 0

rambler.trails = {}    -- {from=, to=, t=} recent pulses, for the network view

local function char(r)
  return state.get_character(r.id, r.cell, 0, 1)
end
rambler.char = char

local function bps()
  return (clock.get_tempo() or 120) / 60
end

-- gaits --------------------------------------------------------------------
-- each gait declares:
--   phased          does it free-run on a phase, or only react to input?
--   rooted_ok       can it lock to the norns clock (§2.3)?
--   coupling        multiplier on K for this gait
--   drift           multiplier on Weather-driven rate drift
--   read(r)         -> value, display text   (E2, the one knob per §4.2)
--   rate(r)         -> Hz                    (phased, wild)
--   cycles_per_beat -> multiplier            (phased, rooted)
--   wrap(r)         -> weight, or nil to swallow this cycle
--   pulse_in(r,w,src,now)                    (reactive)

local GAITS = {}

rambler.GAIT_ORDER = {
  "metric", "euclidean", "divider", "slow", "burst",
  "drifter", "coincidence", "echo", "stochastic", "accelerando",
}

-- metric: locks to the norns clock, integer division.
local DIVS = {
  {1/4, "1/4"}, {1/3, "1/3"}, {1/2, "1/2"}, {2/3, "2/3"}, {1, "1"},
  {3/2, "3/2"}, {2, "2"}, {3, "3"}, {4, "4"},
}
GAITS.metric = {
  phased = true, rooted_ok = true, coupling = 0.8, drift = 0.2,
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
  phased = true, rooted_ok = true, coupling = 0.8, drift = 0.2,
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

-- divider: passes every Nth *incoming* pulse. no phase of its own.
GAITS.divider = {
  phased = false, rooted_ok = false, coupling = 0, drift = 0,
  read = function(r)
    local n = 1 + math.floor(char(r) * 7 + 0.5)
    return n, "every " .. n
  end,
  pulse_in = function(r, w, src, now)
    local n = GAITS.divider.read(r)
    r.count = r.count + 1
    if r.count % n == 0 then rambler.emit(r, w) end
  end,
}

-- slow: very low rate, high weight.
GAITS.slow = {
  phased = true, rooted_ok = false, coupling = 1.4, drift = 0.5,
  read = function(r)
    local hz = 0.03 + char(r) * 0.47
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r) return (GAITS.slow.read(r)) end,
  wrap = function(r) return 1.0 end,
}

-- burst: one wrap fires a ratchet of 2-7. Weather picks how many.
GAITS.burst = {
  phased = true, rooted_ok = false, coupling = 1.0, drift = 1.0,
  read = function(r)
    local hz = 0.3 + char(r) * 2.7
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r) return (GAITS.burst.read(r)) end,
  wrap = function(r)
    local n = 2 + math.floor((state.global.weather or 0.4) * 5 + 0.5)
    local gap = (1 / math.max(GAITS.burst.read(r), 0.01)) * 0.45 / n
    local w = 1.0
    for i = 1, n - 1 do
      w = w * 0.78
      rambler.schedule(r, i * gap, w)
    end
    return 1.0
  end,
}

-- drifter: fast, free, strongest coupling constant.
GAITS.drifter = {
  phased = true, rooted_ok = false, coupling = 2.5, drift = 3.0,
  read = function(r)
    local hz = 0.5 + char(r) * 7.5
    return hz, string.format("%.2f Hz", hz)
  end,
  rate = function(r) return (GAITS.drifter.read(r)) end,
  wrap = function(r) return 0.85 end,
}

-- coincidence: fires when two *different* inputs land inside a window.
GAITS.coincidence = {
  phased = false, rooted_ok = false, coupling = 0, drift = 0,
  read = function(r)
    local win = 0.01 + char(r) * 0.24
    return win, string.format("%.0f ms", win * 1000)
  end,
  pulse_in = function(r, w, src, now)
    local win = GAITS.coincidence.read(r)
    r.recent[src] = {t = now, w = w}
    for other, e in pairs(r.recent) do
      if other ~= src and (now - e.t) <= win then
        if now - r.last_fire > win then
          rambler.emit(r, (w + e.w) * 0.5)
          r.last_fire = now
        end
        r.recent = {}
        return
      end
    end
  end,
}

-- echo: re-emits incoming pulses, tapped, with decay.
GAITS.echo = {
  phased = false, rooted_ok = false, coupling = 0, drift = 0,
  read = function(r)
    local iv = 0.04 + char(r) * 0.46
    return iv, string.format("%.0f ms", iv * 1000)
  end,
  pulse_in = function(r, w, src, now)
    local iv = GAITS.echo.read(r)
    for i = 1, 6 do
      w = w * 0.62
      if w < 0.04 then return end
      rambler.schedule(r, i * iv, w)
    end
  end,
}

-- stochastic: a Bernoulli gate at the wrap. E2 is the probability; the rate
-- itself rides Weather, so wilder settings also mean faster dice.
GAITS.stochastic = {
  phased = true, rooted_ok = false, coupling = 1.0, drift = 1.0,
  read = function(r)
    local p = char(r)
    return p, string.format("p %.2f", p)
  end,
  rate = function(r) return 1.5 + (state.global.weather or 0.4) * 4.5 end,
  wrap = function(r)
    if math.random() < (GAITS.stochastic.read(r)) then
      return 0.6 + math.random() * 0.4
    end
    return nil
  end,
}

-- accelerando: rate ramps across a cycle of wraps, then resets.
local ACCEL_CYCLE = 8
GAITS.accelerando = {
  phased = true, rooted_ok = false, coupling = 1.0, drift = 0.5,
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
  r.count = 0
  r.recent = {}
  r.last_fire = 0
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
      out_links = {},
      d_links = {},
    }
    reset_gait_state(r)
    ramblers[id] = r
    table.insert(order, id)
  end
end

-- link caching ---------------------------------------------------------------
-- edges_at() builds a table per call; at 500 Hz x 10 cells that is real GC
-- pressure on a CM3, so the per-cell link lists are cached and rebuilt only
-- when the graph changes. edge tables are stable objects, so a gain tweak is
-- picked up without a rebuild.

local function rebuild_links()
  for _, r in pairs(ramblers) do
    r.out_links = {}
    r.d_links = {}
    r.energy = 0
    for _, edge in ipairs(patch.edges_at(r.id)) do
      local other = patch.other(edge, r.id)
      local ocell = topology.get(other)
      if ocell then
        local is_d = (ocell.type == "D")
        -- a one-way cable a->b only emits from a and only pulls b (§3).
        local can_send = (not edge.oneway) or (edge.a == r.id)
        local can_hear = (not edge.oneway) or (edge.b == r.id)
        if can_send then
          table.insert(r.out_links, {id = other, edge = edge, d = is_d})
        end
        if is_d and can_hear then
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

function rambler.schedule(r, delay, w)
  if #scheduled >= MAX_SCHEDULED then return end
  table.insert(scheduled, {t = util.time() + delay, r = r, w = w})
end

function rambler.emit(r, weight)
  if emits_this_tick >= MAX_EMITS_PER_TICK then return end
  emits_this_tick = emits_this_tick + 1

  weight = util.clamp(weight or 1, 0, 1)
  local now = util.time()
  r.flash = now
  r.last_weight = weight

  for _, link in ipairs(r.out_links) do
    if link.d then
      -- §6 D<->D: "mutual phase coupling + mutual triggering". the trigger is
      -- deferred by one tick so a cycle in the patch cannot recurse -- 2 ms
      -- per hop is inaudible, and it makes runaway impossible by construction
      -- rather than by a depth counter.
      if #inbox < MAX_SCHEDULED then
        table.insert(inbox, {
          id = link.id,
          w = weight * math.abs(link.edge.gain),
          -- sign is carried separately: reactive gaits want the magnitude,
          -- but a phase nudge has to respect §3's "negative gain ... pulse
          -- coupling becomes repulsion" the same way the Kuramoto term does.
          sign = link.edge.gain < 0 and -1 or 1,
          src = r.id,
        })
      end
    else
      dispatch.on_pulse(r.id, link.id, link.edge, weight)
    end
    if #rambler.trails < MAX_TRAILS then
      table.insert(rambler.trails, {from = r.id, to = link.id, t = now})
    end
  end

  if #r.out_links > 0 then
    local first = topology.get(r.out_links[1].id)
    state.set_event(r.cell.name .. " -> " .. (first and first.name or "?"))
  end
end

local function deliver(msg, now)
  local r = ramblers[msg.id]
  if not r then return end
  local gait = GAITS[r.gait]
  r.in_flash = now
  if gait.pulse_in then
    gait.pulse_in(r, msg.w, msg.src, now)
  elseif gait.phased and not (r.rooted and gait.rooted_ok) then
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

local function advance_wild(r, gait, K, weather)
  -- §4.1 Weather is also "gait drift": a slow random walk on the rate.
  if gait.drift > 0 and weather > 0 then
    r.drift = util.clamp(
      r.drift + (math.random() - 0.5) * weather * gait.drift * 0.01, -0.4, 0.4)
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

local function prune_trails(now)
  local i = 1
  while i <= #rambler.trails do
    if now - rambler.trails[i].t >= rambler.TRAIL_LIFE then
      table.remove(rambler.trails, i)
    else
      i = i + 1
    end
  end
end

function rambler.tick()
  local now = util.time()
  emits_this_tick = 0

  tick_n = tick_n + 1
  if tick_n % 8 == 0 then prune_trails(now) end

  -- §4.1 Still: gaits freeze, resonators ring out. scheduled taps and queued
  -- D->D traffic freeze with them rather than flushing on resume.
  if state.global.still then return end

  -- 1. scheduled taps (burst ratchets, echo repeats)
  if #scheduled > 0 then
    local keep = {}
    for _, ev in ipairs(scheduled) do
      if ev.t <= now then rambler.emit(ev.r, ev.w) else table.insert(keep, ev) end
    end
    scheduled = keep
  end

  -- 2. last tick's D<->D traffic
  if #inbox > 0 then
    local pending = inbox
    inbox = {}
    for _, msg in ipairs(pending) do deliver(msg, now) end
  end

  -- 3. sample every phase, then advance. reactive gaits contribute no phase,
  --    so they drop out of their neighbours' coupling sums entirely.
  for _, id in ipairs(order) do
    local r = ramblers[id]
    local p = GAITS[r.gait].phased and r.phase or nil
    snapshot[id] = p
    r.snap = p
  end

  local weather = state.global.weather or 0.4
  local K = K_BASE * (0.15 + weather * 1.85)

  for _, id in ipairs(order) do
    local r = ramblers[id]
    local gait = GAITS[r.gait]
    if gait.phased then
      if r.rooted and gait.rooted_ok then
        advance_rooted(r, gait)
      else
        advance_wild(r, gait, K, weather)
      end
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
    phased = gait.phased,
    phase = r.phase,
    energy = r.energy,
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
