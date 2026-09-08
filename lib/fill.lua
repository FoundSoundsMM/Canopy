-- fill.lua
-- the §2.3b Fill cells: four unpatched, momentary performance buttons where
-- the Turing Machines used to sit (that mechanic moved into the weave as a
-- rule -- lib/weave.lua's "turing" -- and left these four seats for
-- something the panel had no way to do before: reach in and change every
-- trigger currently moving through the patch, without touching a cable).
--
-- hold one and it is engaged; let go and it is not. that is the entire
-- interface -- no settings page, no knob, no cable -- and while it is
-- engaged its own flavour of fill is applied to EVERY primary pulse on the
-- panel, from every D cell's wrap, every R cell's pass-through, every
-- voice's answering strike -- because rambler.emit_from (the one door every
-- one of those already leaves by) asks this file about each one on its way
-- out.
--
-- four flavours, one per cell (topology.lua's FILL_CELLS, `flavor` field):
--   roll    (Ratchet) every pulse also fires a fast, decaying ratchet behind
--            it -- the same shape weave.lua's own `mult` rule draws.
--   ghost   (Haunt)   every pulse also fires one quiet echo shortly after --
--            weave.lua's `ghost` rule, applied to the whole panel at once.
--   double  (Volley)  every pulse immediately fires a second, full-weight
--            copy a few milliseconds behind -- thickens rather than repeats.
--   skip    (Lull)    the opposite of the other three: pulses are thinned
--            out rather than added to, a breakdown for as long as it is held.
-- more than one held at once layers: Ratchet and Haunt together roll AND
-- echo every pulse, because neither one knows the other is engaged.
--
-- the extra pulses a flavour schedules go straight to
-- rambler.emit_from_raw, not rambler.emit_from -- the raw sender, which does
-- not ask this file anything. without that a held Ratchet would roll its own
-- rolls, geometrically, into rambler's MAX_EMITS_PER_TICK ceiling within a
-- handful of generations; going in raw means an echo is exactly one pulse,
-- however many flavours are currently held.

local topology  = wl("topology")
local quantise  = wl("quantise")

local fill = {}

fill.MAX_PENDING = 128

local cells = {}     -- id -> {id=, flavor=}
local engaged = {}   -- id -> true, for however long it is held
local pending = {}   -- {t=, id=, w=, only=, except=} echoes still to fire

for id, cell in topology.each() do
  if cell.type == "FILL" then
    cells[id] = {id = id, flavor = cell.flavor}
  end
end

-- press / release --------------------------------------------------------

function fill.engage(id)
  if cells[id] then engaged[id] = true end
end

function fill.release(id)
  engaged[id] = nil
end

function fill.is_engaged(id)
  return engaged[id] and true or false
end

-- any cell currently held whose flavour is `flavor`, for `suppress` and
-- `echo` below to iterate without caring which physical cell it was.
local function each_engaged(flavor)
  return function(_, id)
    while true do
      id = next(engaged, id)
      if id == nil then return nil end
      local c = cells[id]
      if c and c.flavor == flavor then return id end
    end
  end, engaged, nil
end

-- Lull: the opposite of the other three -- thins the panel out rather than
-- adding to it. independent per engaged Lull (unlikely there is more than
-- one, but each rolls its own dice rather than compounding).
local SKIP_CHANCE = 0.55

function fill.suppress(source_id)
  for _ in each_engaged("skip") do
    if math.random() < SKIP_CHANCE then return true end
  end
  return false
end

-- schedule one extra delivery of `id`'s own pulse, `delay` seconds out, at
-- `w` of its original weight.
local function schedule(id, delay, w, only, except)
  if #pending >= fill.MAX_PENDING then return end
  if w < 0.03 then return end
  table.insert(pending, {
    t = util.time() + delay, id = id, w = w, only = only, except = except,
  })
end

-- Ratchet: the same shape weave.lua's `mult` rule draws -- a burst laid
-- across half a beat so it always finishes before the next pulse arrives at
-- any sane tempo.
local ROLL_TAPS = 3
local ROLL_DECAY = 0.78

local function roll(id, w, only, except)
  local gap = quantise.spb() * 0.5 / (ROLL_TAPS + 1)
  for i = 1, ROLL_TAPS do
    w = w * ROLL_DECAY
    schedule(id, i * gap, w, only, except)
  end
end

-- Haunt: one quiet echo behind every pulse, the same shape weave.lua's
-- `ghost` rule draws.
local GHOST_DELAY = 0.11
local GHOST_LEVEL = 0.4

local function ghost(id, w, only, except)
  schedule(id, GHOST_DELAY, w * GHOST_LEVEL, only, except)
end

-- Volley: one full-weight copy close enough behind the original to thicken
-- the hit rather than read as a repeat -- a flam with no quiet half.
local DOUBLE_DELAY = 0.018

local function double(id, w, only, except)
  schedule(id, DOUBLE_DELAY, w, only, except)
end

local ECHO = {roll = roll, ghost = ghost, double = double}

-- called from rambler.emit_from, once per primary pulse that actually went
-- out (a suppressed one never reaches here). lays every currently engaged
-- add-on flavour on top; `skip` has none to add, so it is simply absent from
-- ECHO and this loop does nothing for it.
function fill.echo(source_id, weight, only, except)
  for flavor, fn in pairs(ECHO) do
    for _ in each_engaged(flavor) do
      fn(source_id, weight, only, except)
    end
  end
end

-- serviced from rambler.tick, the same split-before-firing shape weave.lua's
-- own `pending` queue uses and for the same reason: firing can push a fresh
-- entry and it must survive the swap.
function fill.tick(now)
  if #pending == 0 then return end
  local due, keep = {}, {}
  for _, ev in ipairs(pending) do
    if ev.t <= now then table.insert(due, ev) else table.insert(keep, ev) end
  end
  pending = keep
  for _, ev in ipairs(due) do
    wl("rambler").emit_from_raw(ev.id, ev.w, ev.only, ev.except)
  end
end

-- §4.3 an external transport Start: drop every echo still in flight, the
-- same reason weave.resync and rambler.resync clear their own queues --
-- otherwise a stop leaves timestamps already in the past for the first tick
-- after a Start to fire in one block.
function fill.resync()
  pending = {}
end

function fill.pending_count()
  return #pending
end

return fill
