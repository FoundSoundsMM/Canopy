-- weave.lua
-- the §2.7 R cells: what happens to a pulse *between* the cell that made it
-- and the cell it was going to.
--
-- a D cell decides when. an R cell decides what -- divided, doubled, delayed,
-- accented, thinned, swung, swallowed, shadowed. this is the half of a drum
-- machine that is not the drums: patch a straight four to the bar through
-- Sedge and Drove and Bramble and it stops being a metronome and starts being
-- a part, without a single step ever having been programmed.
--
-- every rule has the same shape as a gait: one knob (E2) that means whatever
-- the rule says it means, and K1+E2 swaps the rule. what it does NOT have is a
-- phase -- an R cell is silent until something arrives.
--
-- dependency note: rambler.lua requires this file at load and calls both
-- `pulse_in` and `tick`, so this one must not require rambler at load. it is
-- fetched lazily inside `out`, by which time wl() has it memoised.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local quantise = wl("quantise")

local weave = {}

weave.FLASH_DECAY = 0.12
weave.MAX_PENDING = 128

local cells = {}    -- r_id -> record
local order = {}    -- r_ids, stable iteration order
local pending = {}  -- {t=, id=, w=, only=} taps this cell placed in the future

local function char(r)
  return state.get_character(r.id, r.cell, 0, 1)
end

-- seconds per beat, for the rules that measure themselves musically rather
-- than in milliseconds. a delay of "a sixteenth" has to still be a sixteenth
-- after the tempo moves.
local function spb()
  return quantise.spb()
end

-- emission ------------------------------------------------------------------

-- out through the shared pulse bus, so an R cell's fan-out, its trails and
-- its one-tick deferral to another pulse cell are all identical to a D
-- cell's. `only` restricts it to one cable (hocket); `src` is the cable the
-- pulse arrived on, which is the one cable it must NOT leave by -- cables are
-- undirected, and a transform that sends its output back down its own input
-- is not coupled to its driver, it is doubling it.
function weave.out(r, w, only, src)
  w = util.clamp(w or 1, 0, 1)
  -- below this a repeat is inaudible and only costs scheduler budget; every
  -- decaying rule in here terminates on it.
  if w < 0.03 then return end
  r.flash = util.time()
  r.last_weight = w
  wl("rambler").emit_from(r.id, w, only, src or r.src)
end

-- a tap placed in the future carries the source of the pulse that made it, so
-- an echo tail three hundred milliseconds later still knows which cable not to
-- go back out of.
function weave.later(r, delay, w, only)
  if #pending >= weave.MAX_PENDING then return end
  if (w or 1) < 0.03 then return end
  table.insert(pending, {
    t = util.time() + delay, id = r.id, w = w, only = only, src = r.src,
  })
end

-- rules -----------------------------------------------------------------------
-- each declares:
--   read(r)                   -> value, display text  (E2)
--   pulse_in(r, w, src, now)  what to do with an arrival

local RULES = {}

weave.RULE_ORDER = {
  "divide", "mult", "delay", "echo", "chance", "accent", "sift", "meet",
  "hocket", "swing", "blur", "latch", "fill", "rest", "flam", "ghost",
  "roll", "swell", "mask", "shift",
}

-- divide: every Nth pulse gets through. the oldest trick there is and still
-- the fastest way to get a second, slower part out of one source.
RULES.divide = {
  read = function(r)
    local n = 1 + math.floor(char(r) * 7 + 0.5)
    return n, "every " .. n
  end,
  pulse_in = function(r, w)
    local n = RULES.divide.read(r)
    r.count = r.count + 1
    if r.count % n == 0 then weave.out(r, w) end
  end,
}

-- mult: one in, a ratchet out, laid across half a beat so it always finishes
-- before the next one arrives at any sane tempo.
RULES.mult = {
  read = function(r)
    local n = 2 + math.floor(char(r) * 5 + 0.5)
    return n, "x" .. n
  end,
  pulse_in = function(r, w)
    local n = RULES.mult.read(r)
    local gap = spb() * 0.5 / n
    weave.out(r, w)
    for i = 1, n - 1 do
      w = w * 0.82
      weave.later(r, i * gap, w)
    end
  end,
}

-- delay: one copy, late by a musical interval rather than by milliseconds --
-- so it stays in time when the tempo moves, which a millisecond delay does
-- not, and which is the whole reason to have both this and Blur.
local DELAYS = {
  {1/4, "1/16"}, {1/3, "1/12"}, {1/2, "1/8"}, {2/3, "1/6"}, {3/4, "3/16"},
  {1, "1/4"}, {4/3, "1/3"}, {3/2, "3/8"}, {2, "1/2"}, {3, "3/4"},
}
RULES.delay = {
  read = function(r)
    local i = util.clamp(math.floor(char(r) * (#DELAYS - 1) + 0.5), 0, #DELAYS - 1) + 1
    return DELAYS[i][1], DELAYS[i][2]
  end,
  pulse_in = function(r, w)
    weave.later(r, (RULES.delay.read(r)) * spb(), w)
  end,
}

-- echo: a decaying tail. in milliseconds, not beats -- this is the one that
-- is supposed to smear across the grid rather than sit on it.
RULES.echo = {
  read = function(r)
    local iv = 0.04 + char(r) * 0.46
    return iv, string.format("%.0f ms", iv * 1000)
  end,
  pulse_in = function(r, w)
    local iv = RULES.echo.read(r)
    for i = 1, 6 do
      w = w * 0.62
      weave.later(r, i * iv, w)
    end
  end,
}

-- chance: a coin at the gate.
RULES.chance = {
  read = function(r)
    local p = char(r)
    return p, string.format("p %.2f", p)
  end,
  pulse_in = function(r, w)
    if math.random() < (RULES.chance.read(r)) then weave.out(r, w) end
  end,
}

-- accent: everything gets through, but not at the weight it arrived with. an
-- eight-step contour cycles under the incoming stream, so a flat line comes
-- out with a shape on it. the knob is how much of the contour is applied, so
-- 0 is a straight wire.
local CONTOUR = {1.0, 0.42, 0.68, 0.5, 0.86, 0.42, 0.62, 0.55}
RULES.accent = {
  read = function(r)
    local d = char(r)
    return d, string.format("depth %.2f", d)
  end,
  pulse_in = function(r, w)
    local d = RULES.accent.read(r)
    r.count = r.count + 1
    local c = CONTOUR[(r.count % #CONTOUR) + 1]
    weave.out(r, w * (1 + (c - 1) * d))
  end,
}

-- sift: a weight gate. put it after Accent or Swell and you get a part that
-- only plays the loud hits of another part -- the cheapest way there is to
-- pull one line out of a busy patch.
RULES.sift = {
  read = function(r)
    local t = char(r)
    return t, string.format(">= %.2f", t)
  end,
  pulse_in = function(r, w)
    if w >= (RULES.sift.read(r)) then weave.out(r, w) end
  end,
}

-- meet: fires when two *different* inputs land inside a window. a genuine
-- AND, and the only rule in here that needs more than one cable in.
RULES.meet = {
  read = function(r)
    local win = 0.01 + char(r) * 0.24
    return win, string.format("%.0f ms", win * 1000)
  end,
  pulse_in = function(r, w, src, now)
    local win = RULES.meet.read(r)
    r.recent[src] = {t = now, w = w}
    for other, e in pairs(r.recent) do
      if other ~= src and (now - e.t) <= win then
        if now - r.last_fire > win then
          weave.out(r, (w + e.w) * 0.5)
          r.last_fire = now
        end
        r.recent = {}
        return
      end
    end
  end,
}

-- hocket: successive pulses go down different cables. one line in, N lines
-- out, none of them playing the same beat -- medieval, and the single most
-- useful thing on this row for making four voices sound like a kit rather
-- than like four voices.
RULES.hocket = {
  read = function(r)
    local stride = 1 + math.floor(char(r) * 3 + 0.5)
    return stride, (stride == 1) and "round" or ("step " .. stride)
  end,
  pulse_in = function(r, w)
    local n = wl("rambler").out_degree(r.id, r.src)
    if n == 0 then return end
    local stride = RULES.hocket.read(r)
    r.count = r.count + 1
    weave.out(r, w, ((r.count * stride) % n) + 1)
  end,
}

-- swing: holds every other arrival back. the panel already has a global
-- swing on the Weather knob; this one is local, so one part can be swung
-- against a straight one instead of all of them moving together.
RULES.swing = {
  read = function(r)
    local amt = char(r)
    return amt, string.format("%.0f%%", amt * 100)
  end,
  pulse_in = function(r, w)
    r.count = r.count + 1
    if r.count % 2 == 1 then
      weave.out(r, w)
    else
      weave.later(r, (RULES.swing.read(r)) * spb() * 0.25, w)
    end
  end,
}

-- blur: a human amount of lateness. always late, never early -- there is no
-- scheduling into the past, and a drummer who is early is a different
-- problem from a drummer who is loose.
RULES.blur = {
  read = function(r)
    local ms = char(r) * 60
    return ms / 1000, string.format("%.0f ms", ms)
  end,
  pulse_in = function(r, w)
    local j = RULES.blur.read(r)
    if j <= 0 then weave.out(r, w) else weave.later(r, math.random() * j, w) end
  end,
}

-- latch: a gate that flips every N arrivals, so a steady stream comes out in
-- blocks of N on and N off. the bar-length variation nobody has to program.
RULES.latch = {
  read = function(r)
    local n = 1 + math.floor(char(r) * 7 + 0.5)
    return n, n .. " on, " .. n .. " off"
  end,
  pulse_in = function(r, w)
    local n = RULES.latch.read(r)
    r.count = r.count + 1
    if (r.count - 1) % (n * 2) == 0 then r.gate = not r.gate end
    if r.gate then weave.out(r, w) end
  end,
}

-- fill: passes everything, and every Nth arrival answers with a flurry
-- instead. this is the turnaround.
RULES.fill = {
  read = function(r)
    local n = 4 + math.floor(char(r) * 28 + 0.5)
    return n, "every " .. n
  end,
  pulse_in = function(r, w)
    local n = RULES.fill.read(r)
    r.count = r.count + 1
    weave.out(r, w)
    if r.count % n == 0 then
      local gap = spb() * 0.25
      for i = 1, 3 do weave.later(r, i * gap, w * (0.9 - i * 0.12)) end
    end
  end,
}

-- rest: now and then it stops for a moment. a hole in a part is as much a
-- part of the part as a hit is, and nothing else on this row makes one.
RULES.rest = {
  read = function(r)
    local p = char(r) * 0.4
    return p, string.format("p %.2f", p)
  end,
  pulse_in = function(r, w)
    if r.skip > 0 then
      r.skip = r.skip - 1
      return
    end
    if math.random() < (RULES.rest.read(r)) then
      r.skip = 1 + math.random(4)
      return
    end
    weave.out(r, w)
  end,
}

-- flam: two hits where there was one, a few milliseconds apart. the grace
-- note has to come first and there is no scheduling into the past, so the
-- quiet one goes out now and the loud one is the one that is late -- which
-- is also how a real flam is played.
RULES.flam = {
  read = function(r)
    local ms = 8 + char(r) * 55
    return ms / 1000, string.format("%.0f ms", ms)
  end,
  pulse_in = function(r, w)
    weave.out(r, w * 0.4)
    weave.later(r, RULES.flam.read(r), w)
  end,
}

-- ghost: the shadow behind the beat. same idea as Flam pointing the other
-- way, and the two of them either side of one cable is a drag.
RULES.ghost = {
  read = function(r)
    local ms = 20 + char(r) * 200
    return ms / 1000, string.format("%.0f ms", ms)
  end,
  pulse_in = function(r, w)
    weave.out(r, w)
    weave.later(r, RULES.ghost.read(r), w * 0.32)
  end,
}

-- roll: one pulse becomes a run that gathers speed. six taps over the knob's
-- worth of time, each gap shorter than the last.
local ROLL_TAPS = 6
RULES.roll = {
  read = function(r)
    local total = 0.08 + char(r) * 0.7
    return total, string.format("%.0f ms", total * 1000)
  end,
  pulse_in = function(r, w)
    local total = RULES.roll.read(r)
    weave.out(r, w)
    local t = 0
    for i = 1, ROLL_TAPS do
      -- geometric: each gap is 0.72 of the one before, normalised so the run
      -- takes `total` however many taps it has.
      t = t + total * 0.28 * (0.72 ^ (i - 1))
      weave.later(r, t, w * (0.9 ^ i))
    end
  end,
}

-- swell: a crescendo across successive hits, then back to the bottom. the
-- long-form dynamic a pattern cannot give you.
RULES.swell = {
  read = function(r)
    local n = 4 + math.floor(char(r) * 20 + 0.5)
    return n, "over " .. n
  end,
  pulse_in = function(r, w)
    local n = RULES.swell.read(r)
    r.count = (r.count + 1) % n
    weave.out(r, w * (0.3 + 0.7 * (r.count / (n - 1))))
  end,
}

-- mask: a euclidean stencil laid over whatever arrives. the same maths as the
-- euclidean gait, except it does not make the pulses -- it decides which of
-- somebody else's get through, which is a different and much more useful
-- thing to be able to do to a busy source.
local MASK_N = 16
RULES.mask = {
  read = function(r)
    local k = util.clamp(math.floor(char(r) * MASK_N + 0.5), 0, MASK_N)
    return k, k .. ":" .. MASK_N
  end,
  pulse_in = function(r, w)
    local k = RULES.mask.read(r)
    local i = r.count
    r.count = r.count + 1
    if ((i % MASK_N) * k) % MASK_N < k then weave.out(r, w) end
  end,
}

-- shift: a skip pattern that rotates one step every time it comes round, so
-- the part is never quite the bar it was last time and never random either.
local SHIFT_N = 8
RULES.shift = {
  read = function(r)
    local k = 1 + math.floor(char(r) * (SHIFT_N - 2) + 0.5)
    return k, k .. " of " .. SHIFT_N
  end,
  pulse_in = function(r, w)
    local k = RULES.shift.read(r)
    local i = r.count % SHIFT_N
    if i == 0 and r.count > 0 then r.rot = (r.rot + 1) % SHIFT_N end
    r.count = r.count + 1
    local j = (i + r.rot) % SHIFT_N
    if (j * k) % SHIFT_N < k then weave.out(r, w) end
  end,
}

weave.RULES = RULES

-- construction -----------------------------------------------------------------

local function reset_rule_state(r)
  r.count = 0
  r.rot = 0
  r.skip = 0
  r.gate = true
  r.recent = {}
  r.last_fire = 0
  r.src = nil
end

for id, cell in topology.each() do
  if cell.type == "R" then
    local r = {
      id = id,
      cell = cell,
      rule = state.get_rule(id, cell.rule),
      flash = -1,
      in_flash = -1,
      last_weight = 0,
    }
    reset_rule_state(r)
    cells[id] = r
    table.insert(order, id)
  end
end

-- delivery ----------------------------------------------------------------------

-- called by rambler's inbox, one tick after the pulse was emitted.
function weave.pulse_in(id, w, src, now)
  local r = cells[id]
  if not r then return end
  r.in_flash = now or util.time()
  r.src = src
  RULES[r.rule].pulse_in(r, util.clamp(w or 1, 0, 1), src, now or util.time())
end

-- the taps this row placed in the future. same split-before-firing shape as
-- rambler's own scheduler, and for the same reason: firing can push a fresh
-- entry (an echo whose tail is still going) and it must survive the swap.
-- §4.3 an external transport Start: drop every tap this file has placed in
-- the future. tick() is not called while Still, so a stop leaves echoes,
-- flams and rolls sitting in `pending` with timestamps already in the past,
-- and the first tick after a Start would fire all of them in one block --
-- see rambler.resync, which calls this.
function weave.resync()
  pending = {}
end

function weave.tick(now)
  if #pending == 0 then return end
  local due, keep = {}, {}
  for _, ev in ipairs(pending) do
    if ev.t <= now then table.insert(due, ev) else table.insert(keep, ev) end
  end
  pending = keep
  for _, ev in ipairs(due) do
    local r = cells[ev.id]
    if r then weave.out(r, ev.w, ev.only, ev.src) end
  end
end

-- read/control surface ------------------------------------------------------------

-- §5.1: an R cell's base rises with how much is cabled through it, and it
-- flashes on the way out rather than the way in -- what you want to see is
-- what it decided, not what it was asked.
function weave.level(id, base)
  local r = cells[id]
  if not r then return base end
  local lvl = base + (patch.degree(id) > 0 and 3 or 0)
  local age = util.time() - r.flash
  if age >= 0 and age < weave.FLASH_DECAY then
    local f = 1 - (age / weave.FLASH_DECAY)
    lvl = lvl + math.floor((15 - lvl) * f * r.last_weight)
  else
    -- a dim second flash on arrival, so a cell that is swallowing everything
    -- still shows that something is reaching it.
    local ia = util.time() - r.in_flash
    if ia >= 0 and ia < weave.FLASH_DECAY then lvl = lvl + 2 end
  end
  return util.clamp(math.floor(lvl), 0, 15)
end

function weave.info(id)
  local r = cells[id]
  if not r then return nil end
  local _, text = RULES[r.rule].read(r)
  return {
    rule = r.rule,
    param = text,
    ins = patch.degree(id),
    outs = wl("rambler").out_degree(id),
    open = r.gate,
  }
end

function weave.set_rule(id, key)
  local r = cells[id]
  if not r or not RULES[key] then return nil end
  r.rule = key
  state.rule[id] = key
  reset_rule_state(r)
  return key
end

-- K1+E2 while holding an R cell -- the same gesture that swaps a D cell's gait.
function weave.cycle_rule(id, delta)
  local r = cells[id]
  if not r then return nil end
  local n = #weave.RULE_ORDER
  local at = 1
  for i, key in ipairs(weave.RULE_ORDER) do
    if key == r.rule then at = i break end
  end
  return weave.set_rule(id, weave.RULE_ORDER[((at - 1 + delta) % n) + 1])
end

function weave.get(id)
  return cells[id]
end

function weave.pending_count()
  return #pending
end

return weave
