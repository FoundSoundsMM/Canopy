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

-- §5.2c three fixed rings per cell -- what arrived, what left, and what was
-- swallowed -- so the scope can draw the rule as the difference between its
-- two lanes rather than as a number. same discipline as rambler's: written in
-- place, never reallocated, and short enough that a window of a few seconds
-- always fits inside one.
weave.HIST_N = 24

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
  r.oi = (r.oi % weave.HIST_N) + 1
  local e = r.outs[r.oi]
  -- `only` is the cable this one left by, and it is the whole of what hocket
  -- does -- so the ring keeps it. without it the scope would have to guess
  -- which lane a pulse took, and a guess drawn at level 14 is a lie.
  if e then e.t, e.w, e.lane = r.flash, w, only
  else r.outs[r.oi] = {t = r.flash, w = w, lane = only} end
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
-- §4.2b each declares TWO knobs, not one:
--   label  / read(r)                   E2, the rule's own amount
--   label2 / read2(r)                  E3, new -- an offset, a decay, a count
--   d1 / d2                            where both sit when you scroll onto it
--   pulse_in(r, w, src, now)           what to do with an arrival
--
-- every d2 is the constant that used to be hard-coded in the line below it:
-- mult's 0.82, echo's 0.62, flam's 0.4, ghost's 0.32, roll's six taps,
-- swell's 0.3 floor, latch's symmetrical duty. a rule left at its defaults
-- does exactly what it did before it had a second knob.

local RULES = {}

weave.RULE_ORDER = {
  "divide", "mult", "delay", "echo", "chance", "accent", "sift", "meet",
  "hocket", "swing", "blur", "latch", "fill", "rest", "flam", "ghost",
  "roll", "swell", "mask", "shift", "turing",
}

local function char2(r)
  local R = RULES[r.rule]
  return state.base_character_b(r.id, R and R.d2 or 0.5)
end
weave.char2 = char2

-- turing: the register a TM cell used to be (§2.3b's history), folded into
-- the weave as a rule rather than a family of its own. a TM cell had eight
-- rows -- Length, Deja, Drift, Spread, Bias, Steps -- and a rule gets two, so
-- this keeps the pair that actually decides what you hear (the loop and how
-- far it wanders) and fixes the rest at the settings that made a fresh TM
-- cell sit in tune by default: Bias centred, Steps locked to the global
-- Scale (the minor pentatonic when Scale itself is "free"), Drift a small
-- constant, Length the classic eight bits.
--
-- unlike every other rule here, this one does two jobs at once. every rule
-- above is silent until you cable it in and decides what a pulse becomes on
-- the way through; this rule ALWAYS passes the pulse -- unchanged, like the
-- plain wire a cable used to be before any rule touched it -- and, on top of
-- that, is a pitch source for whatever pitched cell (a voice, an FM or a VA
-- cell) is cabled to this same R cell, exactly the way a TM cell used to be
-- (grove.lua's PITCHED table, weave.offset below). one cable pair, a
-- trigger into this cell and this cell into a voice, both strikes the voice
-- AND tunes it -- where a TM cell needed three (a trigger to the register, a
-- trigger to the voice, and the register to the voice), because the trigger
-- this rule already forwards on its way through covers the second of those
-- for free.
--
-- Loop and Spread take effect on the register's NEXT step, the same way a TM
-- cell's own Deja and Spread rows worked -- a rule's two knobs have no `push`
-- of their own to re-read the register early (§4.2b's shape is one knob
-- meaning one thing, not one knob plus a callback), so a nudge sits and
-- waits for the next pulse exactly the way turning Deja on a live TM cell
-- always did.
local TURING_LENGTH = 8
local TURING_DRIFT = 0.15
local TURING_SPAN_MIN, TURING_SPAN_MAX = 0.25, 24.0
local TURING_PENTATONIC = {0, 3, 5, 7, 10}

local function turing_span_text(span)
  if span < 1 then return string.format("%.0f cents", span * 100) end
  return string.format("%.1f st", span)
end

-- nearest tone of `scale` to `x` semitones -- the same small pure routine
-- grove.lua keeps its own copy of; every module here owns the copies it
-- needs rather than importing one shared helper.
local function turing_snap(x, scale)
  local oct = math.floor(x / 12)
  local rem = x - oct * 12
  local best, bd = 0, math.huge
  for _, s in ipairs(scale) do
    local d = math.abs(rem - s)
    if d < bd then bd, best = d, s end
  end
  if math.abs(rem - 12) < bd then return (oct + 1) * 12 end
  return oct * 12 + best
end

-- Steps, fixed at "scale": the global Scale has the last word, or the minor
-- pentatonic when Scale itself is "free" -- a TM cell's own default grid,
-- and the one that needs no knob of its own to ask for.
local function turing_quantise(x)
  if (state.global.scale_i or 0) <= 0 then return turing_snap(x, TURING_PENTATONIC) end
  return wl("grove").quantise_semitones(x)
end

-- keeps `r.tm_bits` at exactly TURING_LENGTH entries -- lazy, so a cell that
-- has never run this rule pays nothing for the bits it does not have yet.
local function turing_ensure_length(r)
  local n = TURING_LENGTH
  if #r.tm_bits == n then return end
  if #r.tm_bits < n then
    for i = #r.tm_bits + 1, n do r.tm_bits[i] = (i % 2 == 0) and 1 or 0 end
  else
    for _ = n + 1, #r.tm_bits do table.remove(r.tm_bits) end
  end
end

-- one clock edge: the bit about to fall off the end is kept (looped) -- with
-- its own small chance of flipping anyway, Drift -- or thrown away for a
-- fresh coin flip, at a rate Loop decides.
local function turing_step(r, prob)
  turing_ensure_length(r)
  local n = TURING_LENGTH
  local old = r.tm_bits[n]
  local new_bit
  if math.random() < prob then
    new_bit = old
    if math.random() < TURING_DRIFT then new_bit = 1 - new_bit end
  else
    new_bit = (math.random() < 0.5) and 1 or 0
  end
  for i = n, 2, -1 do r.tm_bits[i] = r.tm_bits[i - 1] end
  r.tm_bits[1] = new_bit
end

local function turing_loop(r) return char(r) end

-- Spread, in semitones: how wide the distribution the register is read out
-- into is. log-mapped, same as a TM cell's own Range row, because the useful
-- half of it is at the narrow end, where this is a detuner rather than a
-- tune.
local function turing_spread(r)
  return TURING_SPAN_MIN * ((TURING_SPAN_MAX / TURING_SPAN_MIN) ^ char2(r))
end

-- the register's current pitch offset in semitones -- a pure read, same
-- shape grove.lua's field degree and the old TM cells' own tm.degree always
-- were: the register read out binary-weighted into -1..+1, scaled by
-- Spread, snapped onto whatever Steps is asking for (fixed here at "scale").
local function turing_degree(r)
  turing_ensure_length(r)
  local n = TURING_LENGTH
  local sum, wsum = 0, 0
  for i = 1, n do
    local wgt = 2 ^ (i - 1)
    if r.tm_bits[i] == 1 then sum = sum + wgt end
    wsum = wsum + wgt
  end
  local norm = (wsum > 0) and (sum / wsum) or 0
  return turing_quantise(norm * 2 * turing_spread(r))
end

RULES.turing = {
  label = "Loop", d1 = 0.65, label2 = "Spread", d2 = 0.5,
  read = function(r)
    local p = turing_loop(r)
    return p, string.format("%.0f%% loop", p * 100)
  end,
  read2 = function(r)
    local s = turing_spread(r)
    return s, turing_span_text(s)
  end,
  pulse_in = function(r, w)
    turing_step(r, turing_loop(r))
    -- every voice cabled to this cell needs to hear the new value the
    -- instant the register steps, exactly the way grove.lua's own
    -- state.on_character_change listener re-pushes a field's voices when its
    -- Range knob moves -- otherwise the note would sit silent until the
    -- voice's own next strike asked for it.
    for _, l in ipairs(r.voices) do wl("grove").push_voice_now(l.id) end
    -- and always: the pulse that stepped the register keeps going, the same
    -- as it would through a cell running no rule at all.
    weave.out(r, w)
  end,
}

-- a pulse this rule decided not to pass. the scope draws the hole (§5.2c) --
-- "a hole in a part is as much a part of the part as a hit is" is a claim the
-- panel could not previously show, because a swallowed pulse left no trace
-- anywhere. costs one ring slot and no allocation after the first lap.
local function drop(r, t, w)
  r.di = (r.di % weave.HIST_N) + 1
  local e = r.drops[r.di]
  if e then e.t, e.w = t, w else r.drops[r.di] = {t = t, w = w} end
end

-- divide: every Nth pulse gets through. the oldest trick there is and still
-- the fastest way to get a second, slower part out of one source. Offset is
-- WHICH of the N -- two dividers on one source, offset against each other,
-- is an interlock rather than a doubling.
RULES.divide = {
  label = "Every", d1 = 0.29, label2 = "Offset", d2 = 0,
  read = function(r)
    local n = 1 + math.floor(char(r) * 7 + 0.5)
    return n, "every " .. n
  end,
  read2 = function(r)
    local n = RULES.divide.read(r)
    local o = util.clamp(math.floor(char2(r) * (n - 1) + 0.5), 0, math.max(0, n - 1))
    return o, tostring(o)
  end,
  pulse_in = function(r, w, src, now)
    local n = RULES.divide.read(r)
    local o = RULES.divide.read2(r)
    r.count = r.count + 1
    if r.count % n == o % n then weave.out(r, w) else drop(r, now, w) end
  end,
}

-- mult: one in, a ratchet out, laid across half a beat so it always finishes
-- before the next one arrives at any sane tempo. Decay is how hard the
-- ratchet falls away -- flat is a machine gun, steep is a drag.
RULES.mult = {
  label = "Count", d1 = 0.4, label2 = "Decay", d2 = 0.7,
  read = function(r)
    local n = 2 + math.floor(char(r) * 5 + 0.5)
    return n, "x" .. n
  end,
  read2 = function(r)
    local d = 0.4 + char2(r) * 0.6
    return d, string.format("%.2f", d)
  end,
  pulse_in = function(r, w)
    local n = RULES.mult.read(r)
    local dec = RULES.mult.read2(r)
    local gap = spb() * 0.5 / n
    weave.out(r, w)
    for i = 1, n - 1 do
      w = w * dec
      weave.later(r, i * gap, w)
    end
  end,
}

-- delay: one copy, late by a musical interval rather than by milliseconds --
-- so it stays in time when the tempo moves, which a millisecond delay does
-- not, and which is the whole reason to have both this and Blur. Level is how
-- loud the copy is, so it can be an answer rather than a repeat.
local DELAYS = {
  {1/4, "1/16"}, {1/3, "1/12"}, {1/2, "1/8"}, {2/3, "1/6"}, {3/4, "3/16"},
  {1, "1/4"}, {4/3, "1/3"}, {3/2, "3/8"}, {2, "1/2"}, {3, "3/4"},
}
RULES.delay = {
  label = "Time", d1 = 5/9, label2 = "Level", d2 = 1,
  read = function(r)
    local i = util.clamp(math.floor(char(r) * (#DELAYS - 1) + 0.5), 0, #DELAYS - 1) + 1
    return DELAYS[i][1], DELAYS[i][2]
  end,
  read2 = function(r)
    local l = 0.2 + char2(r) * 0.8
    return l, string.format("%.2f", l)
  end,
  pulse_in = function(r, w)
    weave.later(r, (RULES.delay.read(r)) * spb(), w * (RULES.delay.read2(r)))
  end,
}

-- echo: a decaying tail. in milliseconds, not beats -- this is the one that
-- is supposed to smear across the grid rather than sit on it. Decay is how
-- many of the six taps you actually hear before it falls under the floor.
RULES.echo = {
  label = "Time", d1 = 0.26, label2 = "Decay", d2 = 0.53,
  read = function(r)
    local iv = 0.04 + char(r) * 0.46
    return iv, string.format("%.0f ms", iv * 1000)
  end,
  read2 = function(r)
    local d = 0.3 + char2(r) * 0.6
    return d, string.format("%.2f", d)
  end,
  pulse_in = function(r, w)
    local iv = RULES.echo.read(r)
    local dec = RULES.echo.read2(r)
    for i = 1, 6 do
      w = w * dec
      weave.later(r, i * iv, w)
    end
  end,
}

-- chance: a coin at the gate. Hold makes the coin sticky -- one that comes up
-- heads carries the next few arrivals with it, so the part comes out in
-- clusters rather than as an even sprinkle, which is what a person playing
-- "sometimes" actually sounds like.
RULES.chance = {
  label = "Chance", d1 = 0.55, label2 = "Hold", d2 = 0,
  read = function(r)
    local p = char(r)
    return p, string.format("p %.2f", p)
  end,
  read2 = function(r)
    local n = 1 + math.floor(char2(r) * 3 + 0.5)
    return n, (n == 1) and "off" or (n .. " in a row")
  end,
  pulse_in = function(r, w, src, now)
    if r.hold and r.hold > 0 then
      r.hold = r.hold - 1
      weave.out(r, w)
      return
    end
    if math.random() < (RULES.chance.read(r)) then
      r.hold = (RULES.chance.read2(r)) - 1
      weave.out(r, w)
    else
      drop(r, now, w)
    end
  end,
}

-- accent: everything gets through, but not at the weight it arrived with. a
-- contour cycles under the incoming stream, so a flat line comes out with a
-- shape on it. E2 is how much of the contour is applied, so 0 is a straight
-- wire; Length is how long the contour is, which is the difference between an
-- accent in four and an accent in seven.
local CONTOUR = {1.0, 0.42, 0.68, 0.5, 0.86, 0.42, 0.62, 0.55}
RULES.accent = {
  label = "Depth", d1 = 0.8, label2 = "Length", d2 = 1,
  read = function(r)
    local d = char(r)
    return d, string.format("depth %.2f", d)
  end,
  read2 = function(r)
    local n = 2 + math.floor(char2(r) * 6 + 0.5)
    return n, "over " .. n
  end,
  pulse_in = function(r, w)
    local d = RULES.accent.read(r)
    local n = RULES.accent.read2(r)
    r.count = r.count + 1
    local c = CONTOUR[(r.count % n) + 1]
    weave.out(r, w * (1 + (c - 1) * d))
  end,
}

-- sift: a weight gate. put it after Accent or Swell and you get a part that
-- only plays the loud hits of another part -- the cheapest way there is to
-- pull one line out of a busy patch. Boost puts what survived back up to
-- full, so the line you pulled out arrives level rather than quiet.
RULES.sift = {
  label = "Above", d1 = 0.55, label2 = "Boost", d2 = 0,
  read = function(r)
    local t = char(r)
    return t, string.format(">= %.2f", t)
  end,
  read2 = function(r)
    local b = char2(r)
    return b, string.format("%.0f%%", b * 100)
  end,
  pulse_in = function(r, w, src, now)
    if w >= (RULES.sift.read(r)) then
      local b = RULES.sift.read2(r)
      weave.out(r, w + (1 - w) * b)
    else
      drop(r, now, w)
    end
  end,
}

-- meet: fires when two *different* inputs land inside a window. a genuine
-- AND, and the only rule in here that needs more than one cable in. Hold is
-- how long it stays shut afterwards, which used to be the window itself --
-- one number doing two jobs, so widening the window to catch a loose player
-- also silently slowed the whole rule down.
RULES.meet = {
  label = "Window", d1 = 1/3, label2 = "Hold", d2 = 0.18,
  read = function(r)
    local win = 0.01 + char(r) * 0.24
    return win, string.format("%.0f ms", win * 1000)
  end,
  read2 = function(r)
    local hold = char2(r) * 0.5
    return hold, string.format("%.0f ms", hold * 1000)
  end,
  pulse_in = function(r, w, src, now)
    local win = RULES.meet.read(r)
    local hold = RULES.meet.read2(r)
    r.recent[src] = {t = now, w = w}
    for other, e in pairs(r.recent) do
      if other ~= src and (now - e.t) <= win then
        if now - r.last_fire > hold then
          weave.out(r, (w + e.w) * 0.5)
          r.last_fire = now
        end
        r.recent = {}
        return
      end
    end
    drop(r, now, w)
  end,
}

-- hocket: successive pulses go down different cables. one line in, N lines
-- out, none of them playing the same beat -- medieval, and the single most
-- useful thing on this row for making four voices sound like a kit rather
-- than like four voices. Lanes caps how many of the cables it uses, so three
-- voices can hocket while the fourth stays on the whole part.
RULES.hocket = {
  label = "Step", d1 = 0, label2 = "Lanes", d2 = 1,
  read = function(r)
    local stride = 1 + math.floor(char(r) * 3 + 0.5)
    return stride, (stride == 1) and "round" or ("step " .. stride)
  end,
  -- capped at six because six is what the scope can draw as six rows, and a
  -- hocket you cannot see the shape of is a hocket you cannot set.
  read2 = function(r)
    local want = 2 + math.floor(char2(r) * 4 + 0.5)
    local have = wl("rambler").out_degree(r.id, r.src)
    local n = (have > 0) and math.min(want, have) or want
    return n, (have > 0 and want >= have) and ("all " .. have) or tostring(n)
  end,
  pulse_in = function(r, w)
    local n = RULES.hocket.read2(r)
    if n == 0 then return end
    local stride = RULES.hocket.read(r)
    r.count = r.count + 1
    weave.out(r, w, ((r.count * stride) % n) + 1)
  end,
}

-- swing: holds every other arrival back. the panel already has a global
-- swing on the Weather knob; this one is local, so one part can be swung
-- against a straight one instead of all of them moving together. Every is
-- which arrivals get held -- every second is a shuffle, every third or fourth
-- is a limp, and neither of those was reachable before.
RULES.swing = {
  label = "Amount", d1 = 0.6, label2 = "Every", d2 = 0,
  read = function(r)
    local amt = char(r)
    return amt, string.format("%.0f%%", amt * 100)
  end,
  read2 = function(r)
    local n = 2 + math.floor(char2(r) * 2 + 0.5)
    return n, "every " .. n
  end,
  pulse_in = function(r, w)
    local n = RULES.swing.read2(r)
    r.count = r.count + 1
    if r.count % n ~= 0 then
      weave.out(r, w)
    else
      weave.later(r, (RULES.swing.read(r)) * spb() * 0.25, w)
    end
  end,
}

-- blur: a human amount of lateness. always late, never early -- there is no
-- scheduling into the past, and a drummer who is early is a different
-- problem from a drummer who is loose. Wobble is the other half of playing
-- loose: a hand that is late is usually also uneven.
RULES.blur = {
  label = "Late", d1 = 0.75, label2 = "Wobble", d2 = 0,
  read = function(r)
    local ms = char(r) * 60
    return ms / 1000, string.format("%.0f ms", ms)
  end,
  read2 = function(r)
    local wob = char2(r) * 0.6
    return wob, string.format("%.0f%%", wob * 100)
  end,
  pulse_in = function(r, w)
    local j = RULES.blur.read(r)
    local wob = RULES.blur.read2(r)
    if wob > 0 then w = util.clamp(w * (1 - wob * math.random()), 0, 1) end
    if j <= 0 then weave.out(r, w) else weave.later(r, math.random() * j, w) end
  end,
}

-- latch: a gate that flips every N arrivals, so a steady stream comes out in
-- blocks of N on and N off. the bar-length variation nobody has to program.
-- Duty is how much of that is the on half: at the centre it is the even
-- N-on-N-off it always was, and either side of centre it is a long phrase
-- with a short hole or a short phrase with a long one.
RULES.latch = {
  label = "Length", d1 = 0.29, label2 = "Duty", d2 = 0.5,
  read = function(r)
    local n = 1 + math.floor(char(r) * 7 + 0.5)
    return n, tostring(n)
  end,
  read2 = function(r)
    local d = 0.2 + char2(r) * 0.6
    return d, string.format("%.0f%%", d * 100)
  end,
  pulse_in = function(r, w, src, now)
    local n = RULES.latch.read(r)
    local duty = RULES.latch.read2(r)
    local on = math.max(1, math.floor(n * 2 * duty + 0.5))
    local span = n * 2
    local i = r.count % span
    r.count = r.count + 1
    if i < on then weave.out(r, w) else drop(r, now, w) end
  end,
}

-- fill: passes everything, and every Nth arrival answers with a flurry
-- instead. this is the turnaround. Hits is how big the turnaround is.
RULES.fill = {
  label = "Every", d1 = 1/7, label2 = "Hits", d2 = 0.4,
  read = function(r)
    local n = 4 + math.floor(char(r) * 28 + 0.5)
    return n, "every " .. n
  end,
  read2 = function(r)
    local n = 1 + math.floor(char2(r) * 5 + 0.5)
    return n, "x" .. n
  end,
  pulse_in = function(r, w)
    local n = RULES.fill.read(r)
    local hits = RULES.fill.read2(r)
    r.count = r.count + 1
    weave.out(r, w)
    if r.count % n == 0 then
      local gap = spb() * 0.25
      for i = 1, hits do weave.later(r, i * gap, w * (0.9 - i * 0.12)) end
    end
  end,
}

-- rest: now and then it stops for a moment. a hole in a part is as much a
-- part of the part as a hit is, and nothing else on this row makes one. Run
-- is how long the hole is allowed to get.
RULES.rest = {
  label = "Chance", d1 = 0.625, label2 = "Run", d2 = 3/7,
  read = function(r)
    local p = char(r) * 0.4
    return p, string.format("p %.2f", p)
  end,
  read2 = function(r)
    local n = 1 + math.floor(char2(r) * 7 + 0.5)
    return n, "1-" .. n
  end,
  pulse_in = function(r, w, src, now)
    if r.skip > 0 then
      r.skip = r.skip - 1
      drop(r, now, w)
      return
    end
    if math.random() < (RULES.rest.read(r)) then
      r.skip = math.random((RULES.rest.read2(r)))
      drop(r, now, w)
      return
    end
    weave.out(r, w)
  end,
}

-- flam: two hits where there was one, a few milliseconds apart. the grace
-- note has to come first and there is no scheduling into the past, so the
-- quiet one goes out now and the loud one is the one that is late -- which
-- is also how a real flam is played. Grace is how quiet the quiet one is;
-- take it up and the flam becomes a double rather than an ornament.
RULES.flam = {
  label = "Gap", d1 = 0.545, label2 = "Grace", d2 = 0.375,
  read = function(r)
    local ms = 8 + char(r) * 55
    return ms / 1000, string.format("%.0f ms", ms)
  end,
  read2 = function(r)
    local g = 0.1 + char2(r) * 0.8
    return g, string.format("%.2f", g)
  end,
  pulse_in = function(r, w)
    weave.out(r, w * (RULES.flam.read2(r)))
    weave.later(r, RULES.flam.read(r), w)
  end,
}

-- ghost: the shadow behind the beat. same idea as Flam pointing the other
-- way, and the two of them either side of one cable is a drag. Level is how
-- far behind the beat the shadow sits in the mix.
RULES.ghost = {
  label = "Gap", d1 = 0.5, label2 = "Level", d2 = 0.44,
  read = function(r)
    local ms = 20 + char(r) * 200
    return ms / 1000, string.format("%.0f ms", ms)
  end,
  read2 = function(r)
    local l = 0.1 + char2(r) * 0.5
    return l, string.format("%.2f", l)
  end,
  pulse_in = function(r, w)
    weave.out(r, w)
    weave.later(r, RULES.ghost.read(r), w * (RULES.ghost.read2(r)))
  end,
}

-- roll: one pulse becomes a run that gathers speed. Taps is how many, which
-- with Time is the difference between a drag, a four-stroke and a buzz.
RULES.roll = {
  label = "Time", d1 = 0.486, label2 = "Taps", d2 = 0.5,
  read = function(r)
    local total = 0.08 + char(r) * 0.7
    return total, string.format("%.0f ms", total * 1000)
  end,
  read2 = function(r)
    local n = 2 + math.floor(char2(r) * 8 + 0.5)
    return n, "x" .. n
  end,
  pulse_in = function(r, w)
    local total = RULES.roll.read(r)
    local taps = RULES.roll.read2(r)
    weave.out(r, w)
    local t = 0
    for i = 1, taps do
      -- geometric: each gap is 0.72 of the one before, normalised so the run
      -- takes `total` however many taps it has.
      t = t + total * 0.28 * (0.72 ^ (i - 1))
      weave.later(r, t, w * (0.9 ^ i))
    end
  end,
}

-- swell: a crescendo across successive hits, then back to the bottom. the
-- long-form dynamic a pattern cannot give you. Floor is where it comes back
-- to -- at zero the part disappears between swells, high up it only breathes.
RULES.swell = {
  label = "Over", d1 = 0.2, label2 = "Floor", d2 = 0.375,
  read = function(r)
    local n = 4 + math.floor(char(r) * 20 + 0.5)
    return n, "over " .. n
  end,
  read2 = function(r)
    local f = char2(r) * 0.8
    return f, string.format("%.2f", f)
  end,
  pulse_in = function(r, w)
    local n = RULES.swell.read(r)
    local f = RULES.swell.read2(r)
    r.count = (r.count + 1) % n
    weave.out(r, w * (f + (1 - f) * (r.count / (n - 1))))
  end,
}

-- mask: a euclidean stencil laid over whatever arrives. the same maths as the
-- euclidean gait, except it does not make the pulses -- it decides which of
-- somebody else's get through, which is a different and much more useful
-- thing to be able to do to a busy source. Rotate slides the stencil, exactly
-- as it does on the gait.
local MASK_N = 16
RULES.mask = {
  label = "Steps", d1 = 0.4375, label2 = "Rotate", d2 = 0,
  read = function(r)
    local k = util.clamp(math.floor(char(r) * MASK_N + 0.5), 0, MASK_N)
    return k, k .. ":" .. MASK_N
  end,
  read2 = function(r)
    local rot = util.clamp(math.floor(char2(r) * (MASK_N - 1) + 0.5), 0, MASK_N - 1)
    return rot, (rot == 0) and "none" or ("+" .. rot)
  end,
  pulse_in = function(r, w, src, now)
    local k = RULES.mask.read(r)
    local rot = RULES.mask.read2(r)
    local i = r.count + rot
    r.count = r.count + 1
    if ((i % MASK_N) * k) % MASK_N < k then weave.out(r, w) else drop(r, now, w) end
  end,
}

-- shift: a skip pattern that rotates one step every time it comes round, so
-- the part is never quite the bar it was last time and never random either.
-- Turn is how far it rotates each lap: one step takes eight bars to come
-- back, three takes eight the other way round, and four turns it inside out
-- every other bar.
local SHIFT_N = 8
RULES.shift = {
  label = "Steps", d1 = 1/3, label2 = "Turn", d2 = 0,
  read = function(r)
    local k = 1 + math.floor(char(r) * (SHIFT_N - 2) + 0.5)
    return k, k .. " of " .. SHIFT_N
  end,
  read2 = function(r)
    local t = 1 + math.floor(char2(r) * 3 + 0.5)
    return t, "+" .. t
  end,
  pulse_in = function(r, w, src, now)
    local k = RULES.shift.read(r)
    local turn = RULES.shift.read2(r)
    local i = r.count % SHIFT_N
    if i == 0 and r.count > 0 then r.rot = (r.rot + turn) % SHIFT_N end
    r.count = r.count + 1
    local j = (i + r.rot) % SHIFT_N
    if (j * k) % SHIFT_N < k then weave.out(r, w) else drop(r, now, w) end
  end,
}

weave.RULES = RULES

-- construction -----------------------------------------------------------------

local function reset_rule_state(r)
  -- the three lanes belong to the rule that drew them, so scrolling E1 starts
  -- them again rather than leaving the previous rule's part on screen.
  for _, ring in ipairs({r.ins, r.outs, r.drops}) do
    if ring then for i = 1, #ring do ring[i] = nil end end
  end
  r.ii, r.oi, r.di = 0, 0, 0
  r.count = 0
  r.rot = 0
  r.skip = 0
  r.hold = 0
  r.gate = true
  r.recent = {}
  r.last_fire = 0
  r.src = nil
  -- the turing rule's own register: fresh every time E1 lands on it (or
  -- leaves it), the same "a rule left at its defaults does exactly what it
  -- did before" reasoning the rest of this reset already runs on. `.voices`
  -- is NOT reset here -- it is not rule state, it is which pitched cells this
  -- R cell is cabled to, and it is rebuilt on a patch change (see
  -- rebuild_voice_links below), not on a rule change.
  r.tm_bits = {}
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
      ins = {}, ii = 0,
      outs = {}, oi = 0,
      drops = {}, di = 0,
      voices = {},
    }
    reset_rule_state(r)
    cells[id] = r
    table.insert(order, id)
  end
end

-- pitch linking (the turing rule only) ---------------------------------------
-- same shape the old TM cells' own rebuild_links used before this mechanic
-- moved in here: a cable from an R cell to a pitched cell makes the R cell a
-- pitch source for it, summed with whatever fields are also cabled there. built
-- for every R cell regardless of which rule it currently runs -- cheap, only
-- recomputed on a patch change -- and weave.offset below is what filters to
-- the ones actually running turing at read time, so switching a cell onto or
-- off of turing needs no rebuild of its own.
local voice_links = {}  -- voice_id -> {{m=r_id, gain=}, ...}

local function rebuild_voice_links()
  voice_links = {}
  for _, id in ipairs(order) do cells[id].voices = {} end

  for _, id in ipairs(order) do
    local r = cells[id]
    for _, edge in ipairs(patch.edges_at(r.id)) do
      local other_id = patch.other(edge, r.id)
      local other = topology.get(other_id)
      -- a one-way cable a->b only sends from a (§3), the same rule grove.lua
      -- and rambler.lua apply.
      local can_send = (not edge.oneway) or (edge.a == r.id)
      -- "a voice" here means any pitched cell -- the four modal voices and
      -- the two synth families alike (grove.is_pitched).
      if other and can_send and wl("grove").is_pitched(other) then
        table.insert(r.voices, {id = other_id, gain = edge.gain})
        voice_links[other_id] = voice_links[other_id] or {}
        table.insert(voice_links[other_id], {m = r.id, gain = edge.gain})
      end
    end
  end
end

patch.on_change(rebuild_voice_links)
rebuild_voice_links()

-- a voice's total turing offset: every R cell currently running the turing
-- rule and cabled to it, weighted by cable gain and normalised -- the same
-- shape the old TM cells' own tm.offset always was. an R cell cabled in but
-- running any other rule contributes nothing, which is what lets the link
-- table above stay built for everyone rather than needing a rebuild every
-- time a rule changes.
function weave.offset(voice_id)
  local links = voice_links[voice_id]
  if not links or #links == 0 then return 0 end
  local sum, wsum = 0, 0
  for _, l in ipairs(links) do
    local r = cells[l.m]
    if r and r.rule == "turing" then
      sum = sum + turing_degree(r) * l.gain
      wsum = wsum + math.abs(l.gain)
    end
  end
  return (wsum > 0) and (sum / wsum) or 0
end

-- delivery ----------------------------------------------------------------------

-- called by rambler's inbox, one tick after the pulse was emitted.
function weave.pulse_in(id, w, src, now)
  local r = cells[id]
  if not r then return end
  now = now or util.time()
  r.in_flash = now
  r.src = src
  r.ii = (r.ii % weave.HIST_N) + 1
  local e = r.ins[r.ii]
  if e then e.t, e.w = now, w else r.ins[r.ii] = {t = now, w = w} end
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
  local R = RULES[r.rule]
  local _, text = R.read(r)
  local v2, text2 = R.read2(r)
  return {
    rule = r.rule,
    param = text,
    label = R.label,
    label2 = R.label2,
    param2 = text2,
    value2 = v2,
    ins = patch.degree(id),
    outs = wl("rambler").out_degree(id),
    open = r.gate,
  }
end

-- the two knobs, read back for the page and the scope.
function weave.knobs(id)
  local r = cells[id]
  if not r then return nil end
  local R = RULES[r.rule]
  local v1, t1 = R.read(r)
  local v2, t2 = R.read2(r)
  return v1, t1, v2, t2, R.label, R.label2
end

-- what went in, what came out and what did not, for the scope. the rings
-- themselves plus their write heads; nothing is copied.
function weave.history(id)
  local r = cells[id]
  if not r then return nil end
  return r.ins, r.ii, r.outs, r.oi, r.drops, r.di
end

-- §4.2b E1 on an R cell's page. both knobs are re-seeded to the incoming
-- rule's own defaults, same as a gait -- Ghost's Level is not Mask's Rotate,
-- and carrying the number across would land the new rule somewhere nobody
-- chose. every default below is the constant the rule used to hard-code, so
-- scrolling onto a rule gives you the rule as it always behaved.
function weave.set_rule(id, key)
  local r = cells[id]
  if not r or not RULES[key] then return nil end
  local R = RULES[key]
  r.rule = key
  state.rule[id] = key
  state.character[id] = R.d1 or 0.5
  state.character_b[id] = R.d2 or 0.5
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
