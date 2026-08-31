-- tm.lua
-- the §2.3b TM cells: four independent 8-bit shift-register sequencers, akin
-- to the Music Thing Modular Turing Machine with its Pulses/Voltages
-- expanders collapsed onto one cell each. they sit inside the sealed D core,
-- directly above Hob and Grim and directly below Spriggan and Gabriel.
--
-- unlike a D cell, a TM cell has no phase and no free-running gait -- it has
-- no clock of its own at all. the only thing that ever moves its register is
-- a pulse cabled into it. that is the point: it is meant to be clocked, the
-- way the hardware it is named after always is.
--
-- each incoming pulse is one clock edge:
--   1. the bit about to fall off the end of the register is either kept
--      (looped) -- with its own small chance of flipping anyway (Drift, the
--      "the knob past noon still surprises you" character) -- or thrown away
--      for a fresh, Bias-skewed coin flip, decided by Prob.
--   2. some number of the register's bits (Bits) are summed, binary-weighted,
--      into a pitch offset the same shape as a grove.lua field's degree
--      (§2.6) -- scaled by Range and snapped to the same minor pentatonic --
--      and pushed to any voice cabled to this cell's P socket, on top of
--      whatever fields are also cabled there.
--   3. if the register's Tap bit reads high, the cell answers with a pulse of
--      its own, weighted by Level -- the Pulses expander's eight gate outputs
--      collapsed onto the one bit you pick, since one cell has one outgoing
--      cable bank rather than eight.
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
-- narrow end, two octaves at the wide one, so a TM cabled to a P socket reads
-- on the same scale an F cell would.
local SPAN_MIN, SPAN_MAX = 0.25, 24.0

-- the same minor pentatonic grove.lua's fields snap to by default. duplicated
-- rather than exported -- every module here keeps its own copy of the small
-- pure helpers it needs (char(), spb(), snap_to...) rather than reaching into
-- a neighbour for one function.
local SCALE = {0, 3, 5, 7, 10}

local function snap_to(x)
  local oct = math.floor(x / 12)
  local rem = x - oct * 12
  local best, bd = 0, math.huge
  for _, s in ipairs(SCALE) do
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

function tm.bits(id)
  local v = state.get_vparam(id, "bits", 1.0)
  return util.clamp(math.floor(1 + v * 7 + 0.5), 1, 8)
end

function tm.tap(id)
  local v = state.get_vparam(id, "tap", 0)
  return util.clamp(math.floor(1 + v * 7 + 0.5), 1, 8)
end

function tm.span(id)
  local v = state.get_vparam(id, "range", 0.5)
  return SPAN_MIN * ((SPAN_MAX / SPAN_MIN) ^ v)
end

function tm.out_level(id)
  return state.get_vparam(id, "level", 0.8)
end

-- every voice cabled to this cell's P socket needs to hear the new value the
-- moment Range or Bits changes the shape of the DAC, exactly the way
-- grove.lua's state.on_character_change listener re-pushes a field's voices
-- when its Range knob moves -- otherwise the change would sit silent until
-- the next trigger.
local function push_voices(id)
  local r = machines[id]
  if not r then return end
  local grove = wl("grove")
  for _, l in ipairs(r.voices) do grove.push_voice_now(l.id) end
end

-- the eight, in E1 order --------------------------------------------------

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

tm.PARAMS = {
  {
    key = "length", label = "Length", default = 0.43,
    get = vp_get("length", 0.43), set = vp_set("length"),
    text = function(id) return tm.length(id) .. " steps" end,
    push = function() end, -- takes effect on the register's next step
  },
  {
    -- the classic module's one knob, isolated: how often the bit that would
    -- fall off the end is kept (the loop) rather than thrown away for a fresh
    -- coin flip. 0 is fully random every step; 1 never lets go of the loop it
    -- started with.
    key = "prob", label = "Prob", default = 0.65,
    get = vp_get("prob", 0.65), set = vp_set("prob"),
    text = function(id) return string.format("%.0f%% lock", state.get_vparam(id, "prob", 0.65) * 100) end,
    push = function() end,
  },
  {
    -- separated out from Prob on purpose: a locked loop that never moves is a
    -- bar-length loop forever, and the real module's charm past noon is that
    -- it doesn't quite stay locked. this is that, as its own knob.
    key = "drift", label = "Drift", default = 0.15,
    get = vp_get("drift", 0.15), set = vp_set("drift"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "drift", 0.15)) end,
    push = function() end,
  },
  {
    -- skews a fresh coin flip toward 0 or 1, so the pattern's density -- and
    -- the pitch line's average height -- can drift instead of sitting at 50/50.
    key = "bias", label = "Bias", default = 0.5,
    get = vp_get("bias", 0.5), set = vp_set("bias"),
    text = function(id) return string.format("%+.2f", (state.get_vparam(id, "bias", 0.5) - 0.5) * 2) end,
    push = function() end,
  },
  {
    key = "range", label = "Range", default = 0.5,
    get = vp_get("range", 0.5), set = vp_set("range"),
    text = function(id) return span_text(tm.span(id)) end,
    push = function(id) push_voices(id) end,
  },
  {
    -- how many of the register's bits are summed into the pitch DAC: fewer is
    -- coarser and jumpier, more is smoother -- the "Voltages expander" idea
    -- (more bits summed, more continuous a line) folded into one knob rather
    -- than eight fixed weights.
    key = "bits", label = "Bits", default = 1.0,
    get = vp_get("bits", 1.0), set = vp_set("bits"),
    text = function(id) return tm.bits(id) .. " bits" end,
    push = function(id) push_voices(id) end,
  },
  {
    -- which bit gates the outgoing trigger: the "Pulses expander"'s eight
    -- per-bit gate outputs, collapsed onto the one you pick, since a TM cell
    -- has one outgoing cable bank rather than eight.
    key = "tap", label = "Tap", default = 0,
    get = vp_get("tap", 0), set = vp_set("tap"),
    text = function(id) return "bit " .. tm.tap(id) end,
    push = function() end,
  },
  {
    key = "level", label = "Level", default = 0.8,
    get = vp_get("level", 0.8), set = vp_set("level"),
    text = function(id) return string.format("%.2f", tm.out_level(id)) end,
    push = function() end,
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
  local bias = (state.get_vparam(id, "bias", 0.5) - 0.5) * 2

  local old = r.bits[n]
  local new_bit
  if math.random() < prob then
    new_bit = old
    if math.random() < drift then new_bit = 1 - new_bit end
  else
    local p1 = util.clamp(0.5 + bias * 0.5, 0, 1)
    new_bit = (math.random() < p1) and 1 or 0
  end

  for i = n, 2, -1 do r.bits[i] = r.bits[i - 1] end
  r.bits[1] = new_bit
end

-- the register's current pitch offset, in semitones -- a pure read, the same
-- shape as grove.degree(): a normalised position times Range, snapped.
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
  return snap_to((norm * 2 - 1) * tm.span(id))
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

-- P-socket linking -------------------------------------------------------------
-- same shape as grove.lua's rebuild_links: a cable from this cell to a
-- voice's P socket makes it a pitch source for that voice, summed with
-- whatever fields are also cabled there (§2.6's "neither" family -- a number,
-- not a pulse or a stream -- so this bypasses dispatch.lua entirely).

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
      if other and other.type == "node" and other.role == "pitch" and can_send then
        table.insert(r.voices, {id = other.voice, gain = edge.gain})
        voice_links[other.voice] = voice_links[other.voice] or {}
        table.insert(voice_links[other.voice], {m = r.id, gain = edge.gain})
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
-- emitted -- exactly the delivery path weave.pulse_in already gets, since a TM
-- cell is a pulse cell for the same reason an R cell is (topology.PULSE_TYPES).

function tm.pulse_in(id, w, src, now)
  local r = machines[id]
  if not r then return end

  step_register(id, r)
  state.flash(id, w or 1)

  for _, l in ipairs(r.voices) do
    wl("grove").push_voice_now(l.id)
  end

  local n = math.max(#r.bits, 1)
  local tap = util.clamp(tm.tap(id), 1, n)
  if r.bits[tap] == 1 then
    wl("rambler").emit_from(id, tm.out_level(id), nil, src)
  end
end

function tm.get(id)
  return machines[id]
end

return tm
