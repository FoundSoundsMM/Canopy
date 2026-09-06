-- grove.lua
-- the §2.6 pitch fields -- F cells. the four voices are fixed-pitch modal
-- resonators, and until this file existed nothing ever moved their
-- fundamentals: a patch could be rhythmically alive and still be one chord
-- for as long as you left it running. an F cell is a *field*: a wandering
-- pitch that voices can be cabled into, so the melody comes out of the same
-- patch graph everything else does rather than out of a sequencer.
--
-- three things move a field, and they are deliberately different clocks:
--
--   * a strike. every voice a field tunes re-tunes just before it is struck
--     (grove.on_strike), so one cable is enough to turn an existing rhythm
--     into a melody with nothing else patched.
--   * a pulse. anything cabled into the field steps it on its own clock,
--     independent of whoever is being struck (grove.step, via dispatch).
--   * time. the continuous modes (wander, gravity) and the F<->F pull run on
--     grove.tick, off the same 2 ms scheduler as the ramblers -- decimated,
--     because a pitch field has no business being recomputed at 500 Hz.
--
-- a fourth kind of motion isn't in here at all: the per-voice detune drift
-- is an SC-side LFO (\woodland_voice's driftDepth/driftRate), because a
-- continuous few-cents wander pushed over OSC would be both chatty and
-- steppy. this file only sets its depth. that drift is on by default at a
-- barely-there depth, which is why even an unpatched voice no longer repeats
-- itself exactly.
--
-- dependency note: dispatch.lua requires this file at load, so -- exactly as
-- this one must not require dispatch or rambler at load.
-- both are fetched lazily inside the functions that need them.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local bridge   = wl("bridge")

local grove = {}

-- the continuous half runs every Nth scheduler tick. 8 x 2 ms = 16 ms, which
-- is finer than the screen refresh and far finer than anything a pitch field
-- does audibly, at an eighth of the cost of running it on the raw tick.
grove.TICK_EVERY = 8
grove.FLASH_DECAY = 0.15

-- E2 (Range) spans a quarter-tone-ish shimmer to two octaves, logarithmically
-- so the small end -- where this is a detuner rather than a melody-maker --
-- gets most of the knob.
local SPAN_MIN, SPAN_MAX = 0.25, 24.0

-- the scale a snapped field quantises to. minor pentatonic: with mode banks
-- this inharmonic, anything denser stops reading as a scale and starts
-- reading as an out-of-tune one. K1 + tap sets a field free of it entirely.
grove.SCALE = {0, 3, 5, 7, 10}

-- ...but only once the field is wide enough for a scale to mean anything.
-- below the smallest interval in it, snapping would quantise every degree
-- back onto the root and a narrow field would silently do nothing, which is
-- the opposite of what a narrow field is for: at small Range this is a
-- microtonal detuner, at large Range it is a melody.
local SNAP_MIN_SPAN = 1.5

-- how hard an F<->F cable pulls two fields together, in units of "normalised
-- position per second at unity gain". small: a cable between fields should
-- bend a line, not weld two cells into one.
local COUPLE_K = 0.9

-- semitones of continuous SC-side detune drift a voice gets with nothing
-- cabled to it, and the ceiling once fields are. 35 cents is about where
-- "the wood is breathing" turns into "this is out of tune".
local DRIFT_BASE, DRIFT_MAX = 0.06, 0.35

-- each voice's drift runs at its own irrational-ish rate so no two voices
-- breathe in step. index matches topology's voice index - 1.
local DRIFT_RATES = {0.061, 0.083, 0.047, 0.113, 0.037, 0.071}

-- glide sent with a strike-driven retune: short enough to land on the attack
-- rather than swooping into it, long enough not to zipper.
local STRIKE_GLIDE = 0.012

local fields = {}       -- f_id -> field record
local order = {}        -- f_ids, stable iteration order
local voice_links = {}  -- voice_id -> {{f=, gain=}, ...}
local tracked = {}      -- s_id -> true while some field is driving its Colour
local last_hz = {}      -- voice_id -> the Hz last sent
local last_glide = {}   -- voice_id -> the glide last sent
local last_drift = {}   -- voice_id -> the drift depth last sent
local tick_n = 0

-- rhythm/field wildness used to read Weather directly; gparam.lua now
-- exposes that half of it as Scatter (state.global.scatter), independent of Swing.
local function wild()
  return state.global.scatter or 0
end

-- scale ---------------------------------------------------------------------

-- nearest tone of `scale` to `x` semitones, searching the octave it lands in
-- and the one above (so a note just under an octave snaps up to it, not back
-- down to the seventh).
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

local function snap_semitones(x)
  return snap_to(x, grove.SCALE)
end

-- §4.1 Scale: a final, global quantisation stage every voice's total pitch
-- passes through (grove.hz below), independent of and downstream from a
-- field's own per-cell snap (§2.6, K1+tap) -- that one quantises a field's
-- wandering degree before it is summed with everything else; this one
-- quantises the sum, unconditionally, whenever a scale is selected. index 0
-- is "free": the tuning is whatever it already was.
--
-- pentatonic only, on purpose: every entry here is a five-note anhemitonic
-- set, so nothing this quantises to a scale can land a semitone against
-- itself. E.Pn1 and E.Pn2 are the two distinct 12-TET roundings of a true
-- five-equal-step (slendro-style) division of the octave that aren't already
-- major or minor pentatonic under some rotation.
--
-- the names are abbreviations rather than words, and deliberately so: the
-- Scale row draws with `word` (lib/glyph.lua), whose box is 26px wide -- five
-- characters of norns' font. "Pent Maj" was clipped to "Pent " there, which
-- named the family and hid the only part that differed between the four. so
-- the shared half is the one that gets abbreviated: P.Maj / P.Min / E.Pn1 /
-- E.Pn2 all fit whole, and index 0 stays the word "free".
grove.SCALE_NAMES = {"P.Maj", "P.Min", "E.Pn1", "E.Pn2"}
grove.SCALES = {
  {0, 2, 4, 7, 9},                -- major pentatonic
  {0, 3, 5, 7, 10},               -- minor pentatonic (grove.SCALE's own scale)
  {0, 2, 5, 7, 9},                -- equidistant pentatonic, rounding A
  {0, 2, 5, 8, 10},               -- equidistant pentatonic, rounding B
}

function grove.quantise_semitones(x)
  local i = state.global.scale_i or 0
  if i <= 0 then return x end
  local scale = grove.SCALES[i]
  if not scale then return x end
  return snap_to(x, scale)
end

-- modes ----------------------------------------------------------------------
-- a mode is to an F cell what a gait is to a D cell: the rule that decides
-- where the field goes next. each works in a normalised position (-1..+1)
-- which E2's Range then scales into semitones, so Range means the same thing
-- in every mode and the mode only ever decides the *shape* of the line.
--
--   glide           portamento sent with a move in this mode
--   steps_on_strike does a strike of a voice this field tunes move it?
--   continuous      does it also move on its own, on the tick?
--   step(f)         -> new position, on a strike or an incoming pulse
--   advance(f, dt)  continuous motion (continuous modes only)
--   read(f)         -> value, display text, for the cell screen

local MODES = {}

grove.MODE_ORDER = {
  "call", "drone", "cascade", "octave",
  "flutter", "scatter", "wander", "gravity",
}

-- call: two notes, back and forth, with the occasional third one -- a cuckoo
-- that does not quite repeat itself.
MODES.call = {
  glide = 0.02, steps_on_strike = true,
  step = function(f)
    f.n = f.n + 1
    if f.n % 2 == 1 then return 0 end
    if math.random() < 0.15 + wild() * 0.2 then return -0.62 end
    return -0.35
  end,
}

-- drone: never really leaves the root. what moves is the last few cents of
-- it, so a repeated strike on one note is never twice the same note.
MODES.drone = {
  glide = 0.35, steps_on_strike = true,
  step = function(f)
    return util.clamp(f.pos * 0.5 + (math.random() * 2 - 1) * 0.09 * (0.4 + wild()),
                      -0.12, 0.12)
  end,
}

-- cascade: a descending run, then a leap back to the top. curlew-shaped.
local CASCADE_STEPS = 5
MODES.cascade = {
  glide = 0.03, steps_on_strike = true,
  step = function(f)
    f.n = (f.n + 1) % CASCADE_STEPS
    return 1 - (f.n * (2 / (CASCADE_STEPS - 1)))
  end,
}

-- octave: register jumps, and only register jumps -- this one ignores the
-- scale (snapped or not) and quantises to whole octaves, so it transposes a
-- voice rather than playing a line with it.
MODES.octave = {
  glide = 0.05, steps_on_strike = true, octaves = true,
  step = function(f)
    local r = math.random()
    if r < 0.45 then return 0 elseif r < 0.8 then return -1 else return 1 end
  end,
}

-- flutter: fast small steps either side of a slowly moving centre. a trill
-- that wanders.
MODES.flutter = {
  glide = 0.008, steps_on_strike = true,
  step = function(f)
    f.centre = util.clamp((f.centre or 0)
      + (math.random() * 2 - 1) * 0.05 * (0.4 + wild()), -0.5, 0.5)
    return util.clamp(f.centre + (math.random() < 0.5 and -0.14 or 0.14), -1, 1)
  end,
}

-- scatter: a new degree anywhere in the field, every step. the widest of the
-- discrete modes, and the one that most wants a small Range.
MODES.scatter = {
  glide = 0.02, steps_on_strike = true,
  step = function(f)
    return (math.random() * 2 - 1)
  end,
}

-- wander: no degrees at all. the field picks somewhere to be and walks
-- there at a steady speed, then picks somewhere else -- so a voice under it
-- is always on its way to a note rather than sitting on one. an incoming
-- pulse throws the destination somewhere new mid-walk. Scatter sets both how
-- far it strays and how fast it gets there.
--
-- an earlier version had `target` random-walking by a per-tick increment and
-- `pos` chasing it exponentially; both then converged on wherever they
-- started and effectively stopped, because a walk in steps proportional to
-- dt does not actually go anywhere. constant speed toward a destination it
-- re-rolls on arrival is what makes this audibly a wander.
MODES.wander = {
  glide = 0.25, steps_on_strike = false, continuous = true,
  step = function(f)
    f.target = util.clamp(f.target + (math.random() * 2 - 1) * 0.7, -1, 1)
    return f.pos
  end,
  advance = function(f, dt)
    if math.abs(f.target - f.pos) < 0.03 then
      f.target = util.clamp(
        f.target + (math.random() * 2 - 1) * (0.4 + wild() * 0.8), -1, 1)
    end
    local step = (0.05 + wild() * 0.2) * dt
    local d = f.target - f.pos
    if math.abs(d) <= step then return f.target end
    return f.pos + (d > 0 and step or -step)
  end,
}

-- gravity: knocked off the note by every strike, and pulled back toward
-- whatever other fields it is cabled to -- toward the root when it is cabled
-- to none. on its own that is a pitch envelope: struck sharp, settling. two
-- of them on a cable converge on a consonance and sit there; at negative gain
-- they mirror each other into contrary motion instead.
MODES.gravity = {
  glide = 0.5, steps_on_strike = true, continuous = true,
  step = function(f)
    return util.clamp(f.pos + (math.random() * 2 - 1) * (0.3 + wild() * 0.5), -1, 1)
  end,
  advance = function(f, dt)
    local sum, wsum = 0, 0
    for _, l in ipairs(f.p_links) do
      local other = fields[l.id]
      if other then
        sum = sum + other.pos * l.gain
        wsum = wsum + math.abs(l.gain)
      end
    end
    local target = (wsum > 0) and (sum / wsum) or 0
    return f.pos + (target - f.pos) * math.min(1, dt * 1.6)
  end,
}

grove.MODES = MODES

-- construction ----------------------------------------------------------------

for id, cell in topology.each() do
  if cell.type == "F" then
    local f = {
      id = id,
      cell = cell,
      mode = state.get_mode(id, cell.mode),
      snap = state.get_snap(id, cell.snap),
      -- fields start spread rather than all on the root, for the same reason
      -- rambler spreads its starting phases: identical starts make every
      -- coupling experiment look like it locked when it never moved.
      pos = (math.random() * 2 - 1) * 0.3,
      target = 0,
      centre = 0,
      n = 0,
      flash = -1,
      last_w = 0,
      voices = {},    -- {id=, gain=} voices this field tunes
      exciters = {},  -- {id=, index=, gain=} S cells that track it
      p_links = {},   -- {id=, gain=} other fields pulling on this one
    }
    fields[id] = f
    table.insert(order, id)
  end
end

function grove.span(id)
  local f = fields[id]
  if not f then return SPAN_MIN end
  local v = state.get_character(id, f.cell, 0, 1)
  return SPAN_MIN * ((SPAN_MAX / SPAN_MIN) ^ util.clamp(v, 0, 1))
end

-- is this field actually quantising right now? snap is the player's setting;
-- a field narrower than SNAP_MIN_SPAN ignores it (see the note there).
local function snapping(f)
  return f.snap and grove.span(f.id) >= SNAP_MIN_SPAN
end

-- a field's current offset from the root, in semitones.
function grove.degree(id)
  local f = fields[id]
  if not f then return 0 end
  local raw = f.pos * grove.span(id)
  if MODES[f.mode].octaves then
    return math.floor(raw / 12 + 0.5) * 12
  elseif snapping(f) then
    return snap_semitones(raw)
  end
  return raw
end

-- link caching -----------------------------------------------------------------
-- same reasoning as rambler.lua's: edges_at() allocates,
-- and this is read on the tick, so the lists are rebuilt only on a graph move.

local function rebuild_links()
  voice_links = {}
  tracked = {}

  for _, id in ipairs(order) do
    local f = fields[id]
    f.voices = {}
    f.exciters = {}
    f.p_links = {}
  end

  -- `order`, not pairs(fields): a hash walk would shuffle the per-voice link
  -- lists between runs, and with them the order pitch updates go out in.
  for _, fid in ipairs(order) do
    local f = fields[fid]
    for _, edge in ipairs(patch.edges_at(f.id)) do
      local other_id = patch.other(edge, f.id)
      local other = topology.get(other_id)
      -- a one-way cable a->b only sends from a (§3), the rule rambler and
      -- the weave both use. a field is always the sender here: nothing on
      -- the far end of a P cable ever writes back into the field except
      -- another F cell, which is handled from that cell's own side.
      local can_send = (not edge.oneway) or (edge.a == f.id)
      local can_hear = (not edge.oneway) or (edge.b == f.id)
      if other then
        -- the socket collapse means a field cabled to a voice always tunes
        -- it -- there is no separate P socket left to require, and no other
        -- meaning a pulse-less "neither" family link to a voice could have.
        if other.type == "voice" and can_send then
          table.insert(f.voices, {id = other_id, gain = edge.gain})
          voice_links[other_id] = voice_links[other_id] or {}
          table.insert(voice_links[other_id], {f = f, gain = edge.gain})
        elseif other.type == "E" and can_send then
          table.insert(f.exciters, {id = other_id, index = other.index, gain = edge.gain})
          tracked[other_id] = true
        elseif other.type == "F" and can_hear then
          table.insert(f.p_links, {id = other_id, gain = edge.gain})
        end
      end
    end
  end
end

-- engine forwarding --------------------------------------------------------------

-- a voice's total offset: every field cabled to it, weighted by cable gain
-- (bipolar -- a negative cable inverts the field's contour) and normalised by
-- the total weight, so cabling a second field to a voice averages the two
-- rather than stacking them into a transposition nobody asked for.
-- the sound page's own Depth knob (the old P socket's knob, before the
-- socket collapse -- see voice.lua) is a multiplier on everything the
-- fields do to this voice: at 0 the cables are still there and still drawn,
-- and the voice sits on its root anyway; at 2 a narrow field reads as a wide
-- one. it is the per-voice answer to "that is too much melody".
function grove.depth(voice_id)
  return wl("voice").depth(voice_id)
end

function grove.offset(voice_id)
  local links = voice_links[voice_id]
  if not links or #links == 0 then return 0 end
  local sum, wsum = 0, 0
  for _, l in ipairs(links) do
    sum = sum + grove.degree(l.f.id) * l.gain
    wsum = wsum + math.abs(l.gain)
  end
  return util.clamp((sum / math.max(wsum, 1)) * grove.depth(voice_id), -36, 36)
end

-- root, plus the sound editor's Tune (§5.5), plus whatever the fields are
-- doing, plus whatever the TM cells (§2.3b, lib/tm.lua) cabled to the same P
-- socket are doing -- summed in on top of the fields' own average rather than
-- blended into it, because a shift register and a wandering field are
-- different enough instruments to want kept separate, and scaled by the same
-- P-socket depth knob the fields answer to -- plus the global Pitch macro,
-- plus whatever per-strike detune the caller passes in -- then, if Scale has
-- selected one, quantised as a whole. voice.lua owns Tune; this is the only
-- place all of them are ever summed.
function grove.hz(voice_id, extra_semitones)
  local cell = topology.get(voice_id)
  if not cell or not cell.root then return nil end
  local st = grove.offset(voice_id) + wl("tm").offset(voice_id) * grove.depth(voice_id)
             + wl("voice").tune_semitones(voice_id)
             + (state.global.pitch_offset or 0) + (extra_semitones or 0)
  st = grove.quantise_semitones(st)
  return cell.root * (2 ^ (st / 12))
end

-- push one voice's pitch, if it actually moved. `glide` is the portamento to
-- ask for; nil means "whatever the slowest field driving this voice wants".
local function push_voice(voice_id, glide, extra)
  local cell = topology.get(voice_id)
  if not cell or not cell.root then return end
  local v = cell.index - 1

  if glide == nil then
    glide = 0
    local links = voice_links[voice_id]
    if links then
      for _, l in ipairs(links) do
        glide = math.max(glide, MODES[l.f.mode].glide)
      end
    end
  end
  if last_glide[voice_id] ~= glide then
    last_glide[voice_id] = glide
    bridge.voice_glide(v, glide)
  end

  local hz = grove.hz(voice_id, extra)
  if not hz then return end
  local prev = last_hz[voice_id]
  -- about a third of a cent: under what anyone can hear on a mode bank, and
  -- comfortably under what a continuous mode moves in one 16 ms grove tick,
  -- so this drops redundant sends without ever throttling a real glide into
  -- a staircase.
  if prev and math.abs(hz - prev) < prev * 0.0002 then return end
  last_hz[voice_id] = hz
  bridge.voice_pitch(v, hz)
end

-- how much SC-side detune drift this voice should carry: a floor everyone
-- gets, plus a share of the range of whatever fields are cabled to it, so
-- patching a wide field in also makes the voice itself breathe harder.
local function push_drift(voice_id)
  local cell = topology.get(voice_id)
  if not cell or not cell.root then return end
  local depth = DRIFT_BASE
  for _, l in ipairs(voice_links[voice_id] or {}) do
    depth = depth + math.abs(l.gain) * grove.span(l.f.id) * 0.02
  end
  depth = util.clamp(depth, DRIFT_BASE, DRIFT_MAX)
  if last_drift[voice_id] == depth then return end
  last_drift[voice_id] = depth
  local v = cell.index - 1
  bridge.voice_drift(v, depth, DRIFT_RATES[cell.index] or 0.07, cell.index)
end

-- S cells cabled to a field ride it with their Colour, so a pitched exciter
-- (Mistle's chirps, Beck's moving cutoff) tracks the line the voices are
-- playing instead of sitting still under it. exciter.lua stays the only
-- writer of Colour; this just hands it an offset to add.
--
-- summed over every field driving that cell rather than written per field:
-- two fields on one exciter should average out the way two fields on one
-- voice do, not race each other for the last write.
local function push_exciter(s_id)
  local off = 0
  for _, id in ipairs(order) do
    local f = fields[id]
    for _, e in ipairs(f.exciters) do
      if e.id == s_id then
        local span = grove.span(id)
        local norm = (span > 0) and util.clamp(grove.degree(id) / span, -1, 1) or 0
        off = off + norm * e.gain * 0.5
      end
    end
  end
  wl("exciter").set_colour_offset(s_id, util.clamp(off, -1, 1))
end

local function push_exciters(f)
  for _, e in ipairs(f.exciters) do push_exciter(e.id) end
end

-- everything downstream of one field having moved. `skip_voice` is for the
-- one case where the caller is going to push that voice itself, with better
-- numbers than this has (see grove.on_strike).
local function refresh(f, glide, skip_voice)
  for _, l in ipairs(f.voices) do
    if l.id ~= skip_voice then push_voice(l.id, glide) end
  end
  push_exciters(f)
end

-- motion ------------------------------------------------------------------------

-- while this is set, a field may move without anything being pushed at the
-- engine. on_strike sets it so that stepping three fields cabled to one voice
-- is still exactly one pitch message, sent once they have all landed.
local deferring = false

local function move(f, pos, glide)
  f.pos = util.clamp(pos, -1.5, 1.5)
  if not deferring then refresh(f, glide) end
end

-- one step of a field, from a strike or an incoming pulse.
local function step_field(f, w, now)
  local mode = MODES[f.mode]
  f.flash = now or util.time()
  f.last_w = util.clamp(w or 1, 0, 1)
  move(f, mode.step(f), mode.glide)
end

-- a pulse cabled into an F cell (from a D or R cell, or one emerging from
-- a sample cell). dispatch routes it here; a field never emits a pulse of its
-- own, which is what keeps an F cell out of every feedback path there is.
function grove.step(f_id, w, src_id)
  local f = fields[f_id]
  if not f then return end
  step_field(f, w, util.time())
end

-- called by dispatch immediately before a strike lands. every field tuning
-- this voice takes a step (unless its mode moves on its own clock instead),
-- and the voice is retuned before the mallet does.
--
-- §4.1 Drops: every strike gets a random pitch offset, 0.02 st at Drops=0 --
-- the reason a bare patch never sounded like a machine, now a floor rather
-- than the whole effect -- widening to gparam.DROPS_MAX_ST semitones at 1.
function grove.on_strike(voice_id)
  local links = voice_links[voice_id]
  local glide, stepped = nil, nil
  if links and #links > 0 then
    local now = util.time()
    deferring = true
    for _, l in ipairs(links) do
      if MODES[l.f.mode].steps_on_strike then
        step_field(l.f, 1, now)
        glide = STRIKE_GLIDE
        stepped = stepped or {}
        table.insert(stepped, l.f)
      end
    end
    deferring = false
    -- a field this voice shares with other voices (or with an S cell) still
    -- has to reach them -- just not through the voice being struck, which
    -- gets the send below instead, with the strike's own glide and detune.
    for _, f in ipairs(stepped or {}) do
      refresh(f, MODES[f.mode].glide, voice_id)
    end
  end
  local drops = wl("gparam").DROPS_MAX_ST
  local detune = (math.random() * 2 - 1) * (0.02 + (state.global.drops or 0) * drops)
  push_voice(voice_id, glide, detune)
end

-- voice.lua's Tune knob moved, so this voice's Hz did even though no field
-- did: the same path as everything else, entered from the sound editor.
function grove.push_voice_now(voice_id)
  push_voice(voice_id)
end

-- a pulse arriving at a voice's P socket. every field tuning that voice takes
-- a step and the voice is retuned, without anything being struck -- which is
-- how you get a line that moves between the hits as well as on them.
function grove.step_voice(voice_id, w)
  local links = voice_links[voice_id]
  if not links or #links == 0 then return end
  local now = util.time()
  local stepped = {}
  deferring = true
  for _, l in ipairs(links) do
    if MODES[l.f.mode].steps_on_strike then
      step_field(l.f, w or 1, now)
      table.insert(stepped, l.f)
    end
  end
  deferring = false
  for _, f in ipairs(stepped) do refresh(f, MODES[f.mode].glide) end
  push_voice(voice_id)
end

-- the continuous half: the modes that move on their own, plus the F<->F pull
-- that applies to every mode. called from rambler.tick (so it freezes under
-- Still with everything else) and decimated to TICK_EVERY.
function grove.tick(now)
  tick_n = tick_n + 1
  if tick_n % grove.TICK_EVERY ~= 0 then return end
  local rambler = wl("rambler")
  local dt = rambler.TICK * grove.TICK_EVERY

  for _, id in ipairs(order) do
    local f = fields[id]
    local mode = MODES[f.mode]
    local pos = f.pos

    if mode.advance then pos = mode.advance(f, dt) end

    -- §2.6's pitch coupling: the same shape as D<->D's Kuramoto term, on
    -- position rather than phase. positive gain pulls two fields together,
    -- negative pushes them apart. gravity mode does its own, harder version
    -- of this in advance(), so it is skipped here.
    if #f.p_links > 0 and f.mode ~= "gravity" then
      local pull = 0
      for _, l in ipairs(f.p_links) do
        local other = fields[l.id]
        if other then pull = pull + l.gain * (other.pos - pos) end
      end
      pos = pos + pull * COUPLE_K * dt
    end

    if math.abs(pos - f.pos) > 1e-6 then
      move(f, pos, mode.glide)
    end
  end
end

-- read/control surface -----------------------------------------------------------

-- §5.1: a flash on every step over a base that rises with where the field
-- currently sits, so the grid shows the shape of the line as well as its
-- rhythm -- a rising melody visibly climbs the cell.
function grove.level(id, base)
  local f = fields[id]
  if not f then return base end
  local lvl = base + math.floor(((f.pos + 1.5) / 3) * 5)
  if patch.degree(id) > 0 then lvl = lvl + 2 end
  local age = util.time() - f.flash
  if age >= 0 and age < grove.FLASH_DECAY then
    local k = 1 - (age / grove.FLASH_DECAY)
    lvl = lvl + math.floor((15 - lvl) * k * f.last_w)
  end
  return util.clamp(math.floor(lvl), 0, 15)
end

local function span_text(span)
  if span < 1 then return string.format("%.0f cents", span * 100) end
  return string.format("%.1f st", span)
end

function grove.info(id)
  local f = fields[id]
  if not f then return nil end
  local span = grove.span(id)
  return {
    mode = f.mode,
    param = span_text(span),
    span = span,
    -- the effective value, not the flag: a narrow field reads "free"
    -- because that is what it is doing, whatever the flag says.
    snap = snapping(f),
    continuous = MODES[f.mode].continuous or false,
    degree = grove.degree(id),
    pos = f.pos,
    voices = #f.voices,
    links = #f.p_links,
  }
end

function grove.set_mode(id, key)
  local f = fields[id]
  if not f or not MODES[key] then return nil end
  f.mode = key
  state.mode[id] = key
  f.n = 0
  f.target = f.pos
  f.centre = 0
  refresh(f, MODES[key].glide)
  return key
end

-- K1+E2 while holding an F cell -- the same gesture that swaps a D cell's gait.
function grove.cycle_mode(id, delta)
  local f = fields[id]
  if not f then return nil end
  local n = #grove.MODE_ORDER
  local at = 1
  for i, key in ipairs(grove.MODE_ORDER) do
    if key == f.mode then at = i break end
  end
  return grove.set_mode(id, grove.MODE_ORDER[((at - 1 + delta) % n) + 1])
end

-- K1 + tap an F cell: snapped to the scale, or free to sit between the notes.
function grove.toggle_snap(id)
  local f = fields[id]
  if not f then return nil end
  f.snap = not f.snap
  state.snap[id] = f.snap
  refresh(f, MODES[f.mode].glide)
  return f.snap
end

function grove.get(id)
  return fields[id]
end

-- push every voice's pitch, glide and drift once at startup, the way
-- voice.init does for Grain: a freshly booted engine is at its SynthDef
-- defaults and knows nothing about where the fields were left.
function grove.init()
  rebuild_links()
  for id, cell in topology.each() do
    if cell.type == "voice" then
      push_drift(id)
      push_voice(id)
    end
  end
end

local function on_graph_change()
  local was = tracked
  rebuild_links()
  -- an S cell that has just lost its last field would otherwise keep the
  -- Colour offset it had when the cable was pulled, forever.
  for s_id in pairs(was) do
    if not tracked[s_id] then wl("exciter").set_colour_offset(s_id, 0) end
  end
  for id, cell in topology.each() do
    if cell.type == "voice" then
      push_drift(id)
      push_voice(id)
    end
  end
  for s_id in pairs(tracked) do push_exciter(s_id) end
end

patch.on_change(on_graph_change)
rebuild_links()

-- Range moved: every voice under this field is now a different distance from
-- its root, and the drift depth that rides on Range moved with it.
state.on_character_change(function(id)
  local f = fields[id]
  if not f then return end
  for _, l in ipairs(f.voices) do
    push_drift(l.id)
    push_voice(l.id)
  end
  push_exciters(f)
end)

return grove
