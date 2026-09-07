-- tm.lua
-- the §2.3b TM cells: four independent shift-register voltage sources. they
-- sit inside the sealed D core, directly above Hob and Grim and directly
-- below Spriggan and Gabriel.
--
-- what they are now, and what changed. these used to be a Music Thing Turing
-- Machine with its Pulses AND Voltages expanders collapsed onto one cell --
-- so a TM both chose a pitch and answered with a trigger of its own, gated by
-- a Tap bit. the trigger half is gone. this panel already has four families
-- whose entire job is making and shaping pulses (T, C, R and the clock cells
-- that feed them); a fifth one hidden inside the pitch source was a second
-- way to do a job that was already done, and it meant every TM in a patch
-- silently doubled as a sequencer nobody had asked for.
--
-- so a TM cell is the RIGHT-HAND side of a Mutable Marbles and nothing else:
-- a clocked random voltage with a loop. it is fed a pulse and it answers with
-- a number, not with another pulse.
--
-- each incoming pulse is one clock edge:
--   1. the bit about to fall off the end of the register is either kept
--      (looped) -- with its own small chance of flipping anyway (Drift, the
--      "the knob past noon still surprises you" character) -- or thrown away
--      for a fresh coin flip, decided by Deja.
--   2. the register is read out, binary-weighted, as a position in a
--      distribution: Spread is how wide that distribution is, Bias is where
--      its centre sits, and Steps decides what grid the result is snapped to
--      -- continuous at one end, locked to a single note at the other. the
--      answer is a pitch offset the same shape as a grove.lua field's degree
--      (§2.6), pushed to any voice cabled to this cell on top of whatever
--      fields are also cabled there.
--
-- Spread / Bias / Steps are Marbles' own three knobs and mean what they mean
-- there. Length and Deja are the loop, which Marbles calls Deja Vu and the
-- Turing Machine calls the big knob; they are kept as two rows because a loop
-- length you can set exactly is worth more here than one folded into the same
-- control as the probability of looping at all.
--
-- dependency note: rambler.lua requires this file at load (its inbox needs a
-- branch here, exactly the one weave.lua already gets), so this one must not
-- require rambler or grove at load -- both are fetched lazily inside
-- pulse_in, same as grove.lua does with dispatch/rambler.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")

local tm = {}

-- a step count, not a knob fraction -- its own small integer range rather
-- than living on 0..1 like the rest of these.
local LENGTH_MIN, LENGTH_MAX = 2, 16

-- the same span grove.lua's fields use (§2.6): 25 cents of shimmer at the
-- narrow end, two octaves at the wide one, so a TM cabled to a voice reads on
-- the same scale an F cell would. this is Marbles' Spread.
local SPAN_MIN, SPAN_MAX = 0.25, 24.0

-- Bias moves the CENTRE of the distribution rather than skewing the coin, one
-- octave either way. it used to skew the coin flip instead -- which changed
-- the shape of the distribution and only moved its centre as a side effect,
-- and never by an amount anyone could name. Marbles' own bias is a straight
-- offset and so is this: at +12 the same pattern plays an octave up.
local BIAS_ST = 12

-- Steps: the grid the readout is snapped to, coarsest last. this is Marbles'
-- third knob, and the point of it is that one control walks all the way from
-- "a continuous voltage" to "one note" without ever being ambiguous about
-- which of those it is on -- so it is a ladder of named grids rather than a
-- blend, and the row prints the name of the one it is on.
--
--   free   no snap at all -- a glide, a detune, a continuous line
--   semi   whole semitones
--   scale  the global Scale (§4.1), or the minor pentatonic when that is on
--          "free" -- so a TM lands in tune with everything else by default
--   fifth  the root, its fifth and its octave
--   oct    octaves only
--   lock   the root, and nothing else: the register still runs, and nothing
--          it does reaches the pitch
--
-- `nil` in the grid slot means "no snap"; a table is a set of semitone
-- offsets inside the octave, exactly the shape grove.SCALES entries are.
local PENTATONIC = {0, 3, 5, 7, 10}

tm.STEP_MODES = {
  {name = "free",  grid = nil},
  {name = "semi",  grid = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}},
  {name = "scale", grid = "scale"},
  {name = "fifth", grid = {0, 7}},
  {name = "oct",   grid = {0}},
  {name = "lock",  grid = "lock"},
}

-- nearest tone of `scale` to `x` semitones, searching the octave it lands in
-- and the one above -- the same routine grove.lua uses, kept here rather than
-- imported because every module on this panel keeps its own copy of the small
-- pure helpers it needs (char(), spb(), snap_to...).
local function snap_to(x, scale)
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

local function span_text(span)
  if span < 1 then return string.format("%.0f cents", span * 100) end
  return string.format("%.1f st", span)
end

local machines = {}     -- id -> record
local order = {}        -- ids, stable iteration order
local voice_links = {}  -- voice_id -> {{m=, gain=}, ...}, this cell's P cables

-- real-unit readers -----------------------------------------------------------

function tm.length(id)
  local v = state.get_vparam(id, "length", 0.43)
  return util.clamp(math.floor(LENGTH_MIN + v * (LENGTH_MAX - LENGTH_MIN) + 0.5),
                    LENGTH_MIN, LENGTH_MAX)
end

-- Spread, in semitones: how wide the distribution the register is read out
-- into actually is. log-mapped, same as an F cell's Range, because the useful
-- half of it is at the narrow end where this is a detuner rather than a tune.
function tm.spread(id)
  local v = state.get_vparam(id, "range", 0.5)
  return SPAN_MIN * ((SPAN_MAX / SPAN_MIN) ^ v)
end

-- kept under its old name as well: two dozen lines below and one test file
-- read it, and "span" is what the number is.
tm.span = tm.spread

-- Bias, in semitones: where the centre of that distribution sits.
function tm.bias_semitones(id)
  return (state.get_vparam(id, "bias", 0.5) - 0.5) * 2 * BIAS_ST
end

-- which of tm.STEP_MODES this cell is on, 1..#STEP_MODES. the knob stays a
-- plain continuous 0..1 -- the mode is derived from it rather than stored --
-- so the row round-trips through its own getter and needs none of the
-- unrounded-accumulator machinery a genuinely stepped row does.
function tm.step_mode(id)
  local v = state.get_vparam(id, "steps", 0.4)
  local n = #tm.STEP_MODES
  return util.clamp(math.floor(v * n) + 1, 1, n)
end

function tm.step_name(id)
  return tm.STEP_MODES[tm.step_mode(id)].name
end

-- snap `x` onto whatever grid this cell's Steps row is asking for.
function tm.quantise(id, x)
  local grid = tm.STEP_MODES[tm.step_mode(id)].grid
  if grid == nil then return x end
  if grid == "lock" then return 0 end
  if grid == "scale" then
    -- the global Scale, so a TM tunes with the rest of the panel. with Scale
    -- on "free" grove.quantise_semitones is the identity and there would be
    -- no snap at all -- which is what the row's own "free" position is for --
    -- so this position falls back to the minor pentatonic, which is the scale
    -- a TM has always quantised to.
    if (state.global.scale_i or 0) <= 0 then return snap_to(x, PENTATONIC) end
    return wl("grove").quantise_semitones(x)
  end
  return snap_to(x, grid)
end

-- how many of the register's bits are summed into the readout. no longer a
-- row of its own: Marbles has no such control, and what it did here -- fewer
-- bits is coarser and jumpier -- is the same axis Steps now covers, from the
-- other end and more legibly. fixed at the full eight, which is the smoothest
-- setting and the one the row defaulted to.
local READ_BITS = 8

function tm.bits()
  return READ_BITS
end

-- every voice cabled to this cell needs to hear the new value the moment
-- Spread, Bias or Steps changes the shape of the readout, exactly the way
-- grove.lua's state.on_character_change listener re-pushes a field's voices
-- when its Range knob moves -- otherwise the change would sit silent until
-- the next clock edge.
local function push_voices(id)
  local r = machines[id]
  if not r then return end
  local grove = wl("grove")
  for _, l in ipairs(r.voices) do grove.push_voice_now(l.id) end
end

-- the six, in E1 order ----------------------------------------------------

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

tm.PARAMS = {
  {
    key = "length", label = "Length", glyph = "steps", default = 0.43,
    get = vp_get("length", 0.43), set = vp_set("length"),
    text = function(id) return tm.length(id) .. " steps" end,
    -- the shape draws LENGTH_MAX slots and lights the ones in play, so it
    -- reports the real step count rather than the knob's fraction of it.
    glyph_data = function(id) return {n = LENGTH_MAX, lit = tm.length(id)} end,
    push = function() end, -- takes effect on the register's next step
  },
  {
    -- Marbles calls it Deja Vu and the Turing Machine calls it the big knob:
    -- how often the bit that would fall off the end is kept (the loop) rather
    -- than thrown away for a fresh coin flip. 0 is a fresh sequence every
    -- step; 1 never lets go of the loop it started with. the stored key stays
    -- `prob`, which is what four other places in this file call it.
    key = "prob", label = "Deja", glyph = "dots", default = 0.65,
    get = vp_get("prob", 0.65), set = vp_set("prob"),
    text = function(id)
      return string.format("%.0f%% loop", state.get_vparam(id, "prob", 0.65) * 100)
    end,
    push = function() end,
  },
  {
    -- separated out from Deja on purpose: a locked loop that never moves is a
    -- bar-length loop forever, and the real module's charm past noon is that
    -- it doesn't quite stay locked. this is that, as its own knob.
    key = "drift", label = "Drift", glyph = "wander", default = 0.15,
    get = vp_get("drift", 0.15), set = vp_set("drift"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "drift", 0.15)) end,
    push = function() end,
  },
  {
    -- Marbles' Spread: how wide the distribution the register is read out
    -- into is. the stored key stays `range`, which is what it was called when
    -- it did exactly this job under the other name.
    key = "range", label = "Spread", glyph = "span", default = 0.5,
    get = vp_get("range", 0.5), set = vp_set("range"),
    text = function(id) return span_text(tm.spread(id)) end,
    push = function(id) push_voices(id) end,
  },
  {
    -- Marbles' Bias: where that distribution's centre sits, an octave either
    -- way. it used to skew the coin flip instead -- see BIAS_ST above.
    key = "bias", label = "Bias", glyph = "bipolar", default = 0.5,
    get = vp_get("bias", 0.5), set = vp_set("bias"),
    text = function(id) return string.format("%+.1f st", tm.bias_semitones(id)) end,
    push = function(id) push_voices(id) end,
  },
  {
    -- Marbles' Steps: the grid the readout lands on, from no grid at all to
    -- one note. `stack` rather than `word` because the six positions are an
    -- ordered ladder from continuous to locked, and a stack of six with one
    -- lit says where on that ladder you are in a way a boxed word cannot --
    -- the word itself is printed on the value line underneath.
    key = "steps", label = "Steps", glyph = "stack", default = 0.4,
    get = vp_get("steps", 0.4), set = vp_set("steps"),
    text = function(id) return tm.step_name(id) end,
    glyph_data = function(id)
      return {n = #tm.STEP_MODES, lit = tm.step_mode(id)}
    end,
    push = function(id) push_voices(id) end,
  },
}

tm.PARAM_COUNT = #tm.PARAMS

function tm.param(i)
  return tm.PARAMS[util.clamp(i, 1, #tm.PARAMS)]
end

function tm.nudge(id, i, delta)
  local p = tm.param(i)
  p.set(id, util.clamp(p.get(id) + delta, 0, 1))
  p.push(id)
  return p
end

-- the register --------------------------------------------------------------

-- keeps `r.bits` at exactly Length entries, growing from the tail with a
-- fixed alternating fill or shrinking from it, so a Length change never has
-- to throw the whole pattern away. deliberately not `math.random()` here --
-- this runs at module load (all four cells' starting registers) as well as
-- from a live Length nudge, and every other module on the panel that seeds
-- something at load with real randomness (rambler's starting phases, §2.3)
-- does it precisely because an identical start would hide a real degeneracy;
-- a shift register has no such case to guard against, and burning random()
-- calls at load order shifts the seeded stream every other module's offline
-- tests rely on (see test/grove.lua's own note by "a continuous field...").
local function ensure_length(r, n)
  if #r.bits == n then return end
  if #r.bits < n then
    for i = #r.bits + 1, n do
      r.bits[i] = (i % 2 == 0) and 1 or 0
    end
  else
    for _ = n + 1, #r.bits do table.remove(r.bits) end
  end
end

local function step_register(id, r)
  local n = tm.length(id)
  ensure_length(r, n)

  local prob = state.get_vparam(id, "prob", 0.65)
  local drift = state.get_vparam(id, "drift", 0.15)

  -- an unbiased coin. Bias moves the readout's centre now rather than
  -- skewing the register itself (see BIAS_ST), so the bit stream is a plain
  -- fair walk and every knob that shapes the melody does so at the output,
  -- where the number it moves things by can be printed on the screen.
  local old = r.bits[n]
  local new_bit
  if math.random() < prob then
    new_bit = old
    if math.random() < drift then new_bit = 1 - new_bit end
  else
    new_bit = (math.random() < 0.5) and 1 or 0
  end

  for i = n, 2, -1 do r.bits[i] = r.bits[i - 1] end
  r.bits[1] = new_bit
end

-- the register's current pitch offset, in semitones -- a pure read, the same
-- shape as grove.degree(). the register is read out binary-weighted into a
-- position in -1..+1, that position is scaled by Spread and shifted by Bias,
-- and the result is snapped onto whatever grid Steps is asking for. those
-- three lines are Marbles' whole right-hand side.
function tm.degree(id)
  local r = machines[id]
  if not r then return 0 end
  local n = math.max(#r.bits, 1)
  local bits = util.clamp(tm.bits(id), 1, n)
  local sum, wsum = 0, 0
  for i = 1, bits do
    local w = 2 ^ (i - 1)
    if r.bits[i] == 1 then sum = sum + w end
    wsum = wsum + w
  end
  local norm = (wsum > 0) and (sum / wsum) or 0
  return tm.quantise(id, (norm * 2 - 1) * tm.spread(id) + tm.bias_semitones(id))
end

-- construction ----------------------------------------------------------------

local function reset_register(id, r)
  r.bits = {}
  ensure_length(r, tm.length(id))
end

for id, cell in topology.each() do
  if cell.type == "TM" then
    local r = {id = id, cell = cell, voices = {}}
    reset_register(id, r)
    machines[id] = r
    table.insert(order, id)
  end
end

-- pitch linking -------------------------------------------------------------
-- same shape as grove.lua's rebuild_links: a cable from this cell to a
-- pitched cell makes it a pitch source for it, summed with whatever fields are
-- also cabled there (§2.6's "neither" family -- a number, not a pulse or a
-- stream -- so this bypasses dispatch.lua entirely). the socket collapse
-- means that's just any cable to the voice's own point now -- there is no
-- separate P socket left to require.

local function rebuild_links()
  voice_links = {}
  for _, id in ipairs(order) do machines[id].voices = {} end

  for _, id in ipairs(order) do
    local r = machines[id]
    for _, edge in ipairs(patch.edges_at(r.id)) do
      local other_id = patch.other(edge, r.id)
      local other = topology.get(other_id)
      -- a one-way cable a->b only sends from a (§3), the same rule grove.lua
      -- and rambler.lua apply.
      local can_send = (not edge.oneway) or (edge.a == r.id)
      -- §2.13 "a voice" here means any pitched cell -- the four modal voices
      -- and the four new synths alike. grove.is_pitched is the one place that
      -- list lives.
      if other and can_send and wl("grove").is_pitched(other) then
        table.insert(r.voices, {id = other_id, gain = edge.gain})
        voice_links[other_id] = voice_links[other_id] or {}
        table.insert(voice_links[other_id], {m = r.id, gain = edge.gain})
      end
    end
  end
end

patch.on_change(rebuild_links)
rebuild_links()

-- a voice's total TM offset: every TM cell cabled to its P socket, weighted
-- by cable gain and normalised, the same shape as grove.offset. grove.hz
-- (§2.6) adds this in on top, scaled by the same P-socket depth knob that
-- scales what the fields do there -- summed alongside them rather than
-- blended into their own average, because a shift register and a wandering
-- field are different enough instruments to want kept separate.
function tm.offset(voice_id)
  local links = voice_links[voice_id]
  if not links or #links == 0 then return 0 end
  local sum, wsum = 0, 0
  for _, l in ipairs(links) do
    sum = sum + tm.degree(l.m) * l.gain
    wsum = wsum + math.abs(l.gain)
  end
  return (wsum > 0) and (sum / wsum) or 0
end

-- delivery ----------------------------------------------------------------------
-- called from rambler's inbox, one tick after the pulse that triggered it was
-- emitted -- exactly the delivery path weave.pulse_in already gets. a TM cell
-- is still a member of topology.PULSE_TYPES, and has to be: that membership is
-- what routes an arriving pulse through the inbox rather than straight into
-- dispatch, which is what keeps a cycle in the patch from recursing.
--
-- what it no longer does is answer. the clock edge steps the register and
-- re-pushes every voice this cell is tuning, and that is the whole of it --
-- there is no rambler.emit_from here any more, and no Tap bit deciding when
-- to fire one. see the note at the top of this file for why.
function tm.pulse_in(id, w, src, now)
  local r = machines[id]
  if not r then return end

  step_register(id, r)
  state.flash(id, w or 1)

  for _, l in ipairs(r.voices) do
    wl("grove").push_voice_now(l.id)
  end
end

function tm.get(id)
  return machines[id]
end

return tm
