-- lfo.lua
-- §2.12: the four LFO cells -- a free-running modulator per cell, and the
-- settings page for one.
--
-- an LFO is a shape, always running, with no sound of its own. cable it to a
-- cell and it moves something about that cell; cable it to an Output cell and
-- it is heard directly as a tone, once Speed is up in the audio range.
--
-- WHICH thing it moves is the point of this page. an LFO used to land on one
-- fixed input per destination type: a voice's mod path, an exciter's colour,
-- a gust's cross-mod. that is one destination per cell, chosen by the script
-- and not by the player, and it meant the answer to "what does this LFO do
-- to Oak" was buried in a type table in dispatch.lua. so the page grew a
-- Target row picking one of the cells this LFO is cabled to and a Param row
-- picking one row of THAT cell's own settings page.
--
-- two things changed after that, and they are what this file is now.
--
-- MULTIPLE DESTINATIONS, not always one. one modulator moving one knob is a
-- patch cable with extra steps; the useful thing a modulator can do is move
-- several things at once, at different depths, so that turning one knob
-- opens a filter AND lengthens a decay AND pulls a pitch. so an LFO carries
-- SLOTS, each with its own Target, Param and Depth, and the page has a Slot
-- row saying which the three rows under it are describing. an empty slot
-- costs nothing and shows "-".
--
-- how many slots is per cell now (§2.12, topology.lua's `slots` field): the
-- four LFOs already on the panel keep the full four they always had, and the
-- four newer ones get one apiece -- a single-destination modulator has
-- nothing for a Slot cursor to page through, so its Slot row simply never
-- moves off "1".
--
-- IN TIME, or not. an LFO has a Sync row now, and with it on the cell stops
-- keeping its own time and reads its phase straight off the transport, at a
-- division or multiple of the beat taken from the same ladder a Clock cell
-- walks. that is a different thing from setting the Hz so that it happens to
-- come out at one cycle per beat: a rate is not a phase, and two modulators
-- at exactly the right rate still land wherever they were started. synced,
-- the cycle begins on the beat and is still beginning on the beat an hour
-- later. a square on the beat is a gate, a ramp over a bar is a sweep that
-- ends where the bar does, and a sample-and-hold at 1/2 is a sequence in
-- time with the drums. synced at 1x is the DEFAULT now (lfo.SYNC_DEFAULT):
-- everything else on this panel is already in time, and a modulator that is
-- not is the exception. free is one detent away for the case that wants it --
-- a modulator whose whole job is to be at odds with the beat.
--
-- EIGHT SHAPES, not one sine. a sine is a good default and a poor bank: a
-- square is a switch, a ramp is a sweep, a sample-and-hold is a stepped
-- sequence you did not have to program, and none of those is a sine at a
-- different speed. the last of the eight is not an oscillator at all --
-- `follow` is an envelope follower on the Output row, so the LFO moves with
-- what the instrument is actually doing rather than against it. one shape per
-- cell, shared by all four of its slots: an LFO is one modulator with four
-- wires out of it, not four modulators sharing a seat.
--
-- how that works, since it is worth knowing before reading `apply` below.
-- every settings page in this script is the same object -- a list of rows
-- with get/set/text/push -- so "modulate row 3 of the gust page" needs no new
-- machinery at all: read the base value, set the modulated one, push it,
-- write the base back. the stored number never moves, so the screen keeps
-- showing where the player left the knob and turning it still works while the
-- LFO is running. it costs one OSC message per LFO per frame, which is what
-- a knob turn costs, and it reaches every parameter on the panel rather than
-- the four that had a bus.
--
-- Param's first entry is "signal", which is the old behaviour: no knob is
-- modulated and the cable stays the audio-rate one dispatch.lua builds. that
-- is what an LFO cabled to an Output cell wants, and it is the default, so
-- an existing patch sounds the way it did.
--
-- the page is the same shape voice.lua/gvoice.lua/gust.lua expose -- PARAMS
-- with get/set/text/push, plus nudge/param/PARAM_COUNT -- so cellparam.lua
-- hands it to screenui and gridui through the one code path they already
-- have. seven rows now: Speed, Sync, Shape, Slot, Target, Param, Depth.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local patch    = wl("patch")

local lfo = {}

-- a genuine low-frequency range: slow enough at the bottom to move a sound
-- over the course of a whole phrase, fast enough at the top to sit in
-- tremolo/audio-rate cross-mod territory -- and, cabled straight to an
-- Output cell, to be heard as a plain sine tone.
lfo.RATE_MIN, lfo.RATE_MAX = 0.02, 20.0

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

-- clock sync -----------------------------------------------------------------
-- §2.12b an LFO has two ways of knowing how fast it is going, and the Sync
-- row picks between them.
--
-- FREE is what it always was: a Speed knob in Hz, running off wall time,
-- answering to nothing. that is the right thing for a modulator whose whole
-- job is to be at odds with the beat -- a slow drift under a rhythm, or a
-- cell fast enough to be heard as a tone.
--
-- CLOCK is the other half, and it is not the same thing as "set the Hz so
-- that it happens to come out at one cycle per beat". a rate is not a phase:
-- two modulators at exactly the right Hz still land wherever they were
-- started, and drift apart over a piece however carefully they were tuned.
-- so a synced LFO does not integrate a rate at all -- it READS its phase off
-- the transport (see lfo.phase), which means the cycle starts on the beat,
-- stays on the beat for as long as the piece runs, and is in the same place
-- as every other synced LFO and every Clock cell at the same ratio. a square
-- wave on the beat is a gate; a ramp over a bar is a sweep that ends where
-- the bar does.
--
-- the ladder is clockcell.lua's own RATIOS, borrowed rather than copied: a
-- Clock cell at 1/4 and an LFO at 1/4 mean the same thing, print the same
-- word and sit at the same detent, so the ratio is learned once for the whole
-- panel. `ratio` is cycles per beat -- 1x is one cycle every beat, 1/4 one
-- cycle every four (a bar, in four), 8x eight cycles a beat.
--
-- stored as its own vparam rather than sharing the Speed knob's: switching to
-- clock and back leaves the free Speed exactly where the player left it,
-- which is the same reason a Clock cell keeps `high` apart from `character`.
--
-- CLOCK is the default, and free is the deliberate choice. this was the other
-- way round when Sync was new, on the reasoning that a free modulator is what
-- an LFO has always been -- but the four cells sit on the panel next to the
-- Clock family and the triggers, everything else on it is already in time,
-- and a modulator that is not is the exception rather than the norm. so the
-- four come up locked to the transport at 1x and a player who wants one at
-- odds with the beat says so.
lfo.SYNC_DEFAULT = 1

function lfo.synced(id)
  return state.get_vparam(id, "sync", lfo.SYNC_DEFAULT) >= 0.5
end

function lfo.set_synced(id, on)
  state.set_vparam(id, "sync", on and 1 or 0)
end

-- the chosen ratio, as a number and as its printed name. the knob is a plain
-- continuous 0..1 and the position is derived from it rather than stored --
-- so, unlike Target and Param, this row round-trips through its own getter
-- and needs none of the unrounded-accumulator machinery below.
function lfo.ratio(id)
  local cc = wl("clockcell")
  local entry = cc.RATIOS[cc.index_for(state.get_vparam(id, "ratio", 0.5))]
  return entry[1], entry[2]
end

-- log-mapped across the whole range: most of a slow modulator's useful travel
-- is in its bottom octave or two, same reasoning as gust's attack/decay.
--
-- a synced cell answers this in the transport's terms instead. deliberately
-- NOT clamped to RATE_MIN/RATE_MAX: this is the true rate, and it is what the
-- Speed row prints and what the engine is told. \wl_lfo does its own clip, so
-- one pulse a minute at 1/128 shows honestly on the page and the audio-rate
-- copy simply runs as slow as it can -- which is the right way round. the
-- knob-modulation path, which is what a synced LFO is nearly always for, has
-- no such floor at all.
function lfo.rate_hz(id)
  if lfo.synced(id) then
    return lfo.ratio(id) * (clock.get_tempo() / 60)
  end
  local v = state.get_vparam(id, "rate", 0.5)
  return lfo.RATE_MIN * ((lfo.RATE_MAX / lfo.RATE_MIN) ^ v)
end

-- the shape bank ------------------------------------------------------------
-- keep this list, in this order, identical to \wl_lfo's own Select.ar array:
-- the index is what goes over the wire, and a mismatch is a modulator quietly
-- running the wrong shape with nothing to show for it on the screen.
--
-- `follow` is the odd one and the reason the bank is worth having at all: it
-- is not an oscillator, it is an envelope follower on the Output row, so an
-- LFO on that shape moves with whatever the instrument is actually playing.
-- pointed at a filter it is a wah that opens on the loud parts; pointed at a
-- decay it is a patch that rings longer the harder it is hit.
lfo.SHAPES = {"sine", "tri", "ramp", "saw", "square", "s+h", "rand", "follow"}

lfo.FOLLOW = "follow"

-- the knob stays a plain continuous 0..1 and the position is derived from it
-- rather than stored, so the row round-trips through its own getter and needs
-- none of the unrounded-accumulator machinery a genuinely stepped row does.
function lfo.shape_index(id)
  local v = state.get_vparam(id, "shape", 0)
  local n = #lfo.SHAPES
  return util.clamp(math.floor(v * n) + 1, 1, n)
end

function lfo.shape(id)
  return lfo.SHAPES[lfo.shape_index(id)]
end

-- slots -----------------------------------------------------------------------
-- up to four destinations per LFO, each with its own Target, Param and
-- Depth. the page shows one at a time, chosen by the Slot row.
--
-- how many a given cell actually has is topology.lua's `slots` field, not a
-- constant any more (§2.12): the four LFOs already on the panel keep the
-- full four, and the four newer ones get one apiece. lfo.SLOTS is what is
-- left of the old constant -- the most any cell can have, used as a fallback
-- for a cell topology doesn't say otherwise about.
lfo.SLOTS = 4

-- how many destinations THIS cell's page offers -- 4 for the original four
-- LFOs, 1 for the newer four, topology.lua's `slots` field either way.
function lfo.slot_count(id)
  local cell = topology.get(id)
  return (cell and cell.slots) or lfo.SLOTS
end

-- the first entry of the Param row: "leave the cable alone". with this
-- selected the LFO modulates no knob and dispatch.lua's ordinary audio-rate
-- spec for the pair stands, which is what an LFO cabled to an Output cell
-- (a plain tone) or straight into a gust's cross-mod input wants.
lfo.SIGNAL = "signal"

-- and the first entry of the Target row: "this slot is not used". slots 2..4
-- start here, so an LFO behaves exactly as a one-destination one until the
-- player fills a second slot in.
lfo.OFF = "off"

local function slots_of(id)
  state.lfo_slots[id] = state.lfo_slots[id] or {}
  return state.lfo_slots[id]
end

local function slot_rec(id, i)
  local t = slots_of(id)
  t[i] = t[i] or {}
  return t[i]
end

-- which slot the page's Target/Param/Depth rows are describing. derived from
-- a plain 0..1 knob, same as Shape.
function lfo.slot(id)
  local v = state.get_vparam(id, "slot", 0)
  local n = lfo.slot_count(id)
  return util.clamp(math.floor(v * n) + 1, 1, n)
end

-- where every cell sits in registration order, built once. the panel is
-- static, so this is a constant -- and it is what lets both the destination
-- list below and `apply`'s hot path agree on which cable is "the first" one
-- without either of them walking all eighty-odd cells to find out.
local ORDINAL = {}
do
  local n = 0
  for cid in topology.each() do
    n = n + 1
    ORDINAL[cid] = n
  end
end

-- every cell this LFO is currently cabled to, in that order, so the Target
-- row does not reshuffle itself when a cable is added in the middle. Output
-- cells are included: "signal" is the only sensible Param for one, and that
-- is already the default.
function lfo.destinations(id)
  local out = {}
  for _, edge in ipairs(patch.edges_at(id)) do
    table.insert(out, patch.other(edge, id))
  end
  table.sort(out, function(a, b) return ORDINAL[a] < ORDINAL[b] end)
  return out
end

-- what the Target row actually offers: "off" and then every cabled cell.
function lfo.target_options(id)
  local out = {lfo.OFF}
  for _, cid in ipairs(lfo.destinations(id)) do table.insert(out, cid) end
  return out
end

-- which cell this slot is aimed at, or nil. stored by cell id rather than by
-- position, so cabling something else in does not silently re-aim a slot that
-- was already pointed somewhere -- and checked against the live cable list on
-- every read, so pulling the cable drops it.
--
-- slot 1 falls back to the first cabled cell and the rest fall back to "off".
-- that is what keeps a freshly cabled LFO behaving the way a one-destination
-- one did: cable it somewhere and it is already aimed there, and the other
-- three slots stay out of the way until someone fills them in.
function lfo.target(id, i)
  i = i or lfo.slot(id)
  local want = slot_rec(id, i).target
  if want == lfo.OFF then return nil end
  local dests = lfo.destinations(id)
  for _, cid in ipairs(dests) do
    if cid == want then return cid end
  end
  if want == nil and i == 1 then return dests[1] end
  return nil
end

-- the same question as a position in `target_options`, which is what the
-- stepped row needs.
function lfo.target_option(id, i)
  return lfo.target(id, i) or lfo.OFF
end

function lfo.set_target(id, cell_id, i)
  i = i or lfo.slot(id)
  local r = slot_rec(id, i)
  if r.target == cell_id then return end
  r.target = cell_id
  -- moving a target changes which cables are audio and which are knobs, and
  -- nothing about the graph moved, so dispatch has to be told by hand.
  wl("dispatch").resync_matrix()
end

-- the rows of this slot's target's own settings page, by key, with SIGNAL in
-- front. asked of cellparam rather than of a table here, so a family that
-- grows a new knob grows a new LFO destination on the same day.
function lfo.param_keys(id, i)
  local keys = {lfo.SIGNAL}
  local target = lfo.target(id, i)
  if not target then return keys end
  local page = wl("cellparam").page(target)
  if not page then return keys end
  for _, p in ipairs(page.PARAMS) do
    table.insert(keys, p.key or "?")
  end
  return keys
end

function lfo.param_key(id, i)
  i = i or lfo.slot(id)
  local want = slot_rec(id, i).param
  for _, k in ipairs(lfo.param_keys(id, i)) do
    if k == want then return k end
  end
  return lfo.SIGNAL
end

function lfo.set_param_key(id, key, i)
  i = i or lfo.slot(id)
  local r = slot_rec(id, i)
  if r.param == key then return end
  r.param = key
  -- leaving "signal" tears the audio cable down; coming back to it builds it
  -- again. same reason set_target resyncs.
  wl("dispatch").resync_matrix()
end

-- how far this slot swings the knob it holds, either side of where the player
-- left it. deliberately not the cable's gain: a cable is shared with whatever
-- else the pair means to each other, and this belongs to the slot -- which is
-- also what lets one LFO move a filter hard and a decay barely at all.
function lfo.depth(id, i)
  i = i or lfo.slot(id)
  local d = slot_rec(id, i).depth
  return (d == nil) and 0.3 or d
end

function lfo.set_depth(id, v, i)
  i = i or lfo.slot(id)
  slot_rec(id, i).depth = util.clamp(v, 0, 1)
  return slot_rec(id, i).depth
end

-- true when this LFO is driving a named knob on `cell_id` in ANY of its four
-- slots, rather than sending it audio. dispatch.lua asks, and drops its own
-- spec for the pair when it is -- otherwise the cable would be heard twice,
-- once as a knob and once as a signal on a bus the player never asked for.
function lfo.modulates(lfo_id, cell_id)
  local cell = topology.get(lfo_id)
  if not cell or cell.type ~= "LFO" then return false end
  for i = 1, lfo.slot_count(lfo_id) do
    if lfo.target(lfo_id, i) == cell_id
       and lfo.param_key(lfo_id, i) ~= lfo.SIGNAL then
      return true
    end
  end
  return false
end

-- the shape, as a number ------------------------------------------------------
-- the Lua-side twin of \wl_lfo's Select.ar, used by `apply` to move knobs and
-- by the grid indicator. it has to AGREE with the engine rather than merely
-- resemble it: an LFO with Param on "signal" is heard through the engine's
-- copy and one aimed at a knob is heard through this one, and the same cell
-- switching between them must not change shape on the way.

-- sample-and-hold and smooth-random both need a value that only changes once
-- per cycle, so each cell keeps the last two it drew. seeded from math.random
-- like everything else on the panel that is deliberately unpredictable.
local sh = {}

local function sh_rec(id)
  local r = sh[id]
  if not r then
    r = {prev = math.random() * 2 - 1, cur = math.random() * 2 - 1}
    sh[id] = r
  end
  return r
end

-- called from lfo.phase when the phase wraps: one fresh value per cycle.
local function sh_step(id)
  local r = sh_rec(id)
  r.prev = r.cur
  r.cur = math.random() * 2 - 1
end

-- how loud the instrument actually is, 0..1 -- the mean over the Output cells
-- that are carrying anything. the mean and not the peak: a follower that
-- tracked whichever channel happened to be loudest would jump every time a
-- different instrument spoke, which reads as noise rather than as level.
function lfo.output_level()
  local mixer = wl("mixer")
  local sum, n = 0, 0
  for _, oid in ipairs(mixer.active_outputs()) do
    sum = sum + mixer.meter(oid)
    n = n + 1
  end
  if n == 0 then return 0 end
  return util.clamp(sum / n, 0, 1)
end

function lfo.value(id)
  local shape = lfo.shape(id)
  if shape == lfo.FOLLOW then
    return lfo.output_level() * 2 - 1
  end
  local ph = lfo.phase(id)
  if shape == "sine" then
    return math.sin(ph * 2 * math.pi)
  elseif shape == "tri" then
    return 1 - 4 * math.abs(ph - 0.5)
  elseif shape == "ramp" then
    return ph * 2 - 1
  elseif shape == "saw" then
    return 1 - ph * 2
  elseif shape == "square" then
    return (ph < 0.5) and 1 or -1
  elseif shape == "s+h" then
    return sh_rec(id).cur
  elseif shape == "rand" then
    -- a raised cosine between the last two held values: continuous, with no
    -- corner at the wrap, which is what makes it read as a wander rather than
    -- as a stepped sequence with the steps smoothed off.
    local r = sh_rec(id)
    local k = (1 - math.cos(ph * math.pi)) / 2
    return r.prev + (r.cur - r.prev) * k
  end
  return math.sin(ph * 2 * math.pi)
end

-- applying it ----------------------------------------------------------------

-- the row object for one slot's (target, param) pair, or nil.
--
-- deliberately NOT written in terms of lfo.target/lfo.param_key, which is
-- what it looks like it should be. those two are written for the page: they
-- rebuild the destination list and the key list on every call, which is
-- exactly right when a human is turning an encoder and wrong sixteen times a
-- frame -- four cells by four slots, forty times a second, each rebuild
-- allocating two tables. so this takes the destination set already built once
-- for the cell, and looks the stored key up in the target's page in a single
-- walk. the semantics are identical, down to slot 1's fallback; the cost is
-- one table lookup instead of two list builds.
local function slot_row(id, i, dests, first)
  -- an untouched slot has no Param chosen either, so there is nothing here to
  -- move whichever cable it would otherwise aim itself at.
  local r = slots_of(id)[i]
  if not r then return nil end
  local target = r.target
  if target == lfo.OFF then return nil end
  if target == nil then
    if i ~= 1 then return nil end
    target = first
  elseif not dests[target] then
    return nil
  end
  if not target then return nil end

  local key = r.param
  if key == nil or key == lfo.SIGNAL then return nil end
  local page = wl("cellparam").page(target)
  if not page then return nil end
  for _, p in ipairs(page.PARAMS) do
    if p.key == key then return p, target end
  end
  return nil
end

-- what each slot last moved, so that changing Target or Param puts the knob it
-- was holding back where the player left it rather than leaving the engine
-- stuck at whatever the shape happened to be at.
local held = {}

local function release(entry)
  if not entry then return end
  local page = wl("cellparam").page(entry.target)
  if not page then return end
  for _, p in ipairs(page.PARAMS) do
    -- the stored value was never moved (see `apply`), so pushing it is all
    -- that putting the knob back takes.
    if p.key == entry.key then p.push(entry.target) return end
  end
end

-- called from Canopy.lua's modulation metro, a few dozen times a second.
--
-- the whole trick is the three lines in the middle: read the base, set the
-- modulated value, push it, write the base straight back. `set` and `push`
-- are separate calls on every page in this script -- `set` writes the stored
-- number, `push` sends whatever is stored to the engine -- so this sends a
-- moving value while the stored one never moves. nothing else reads the
-- parameter in between: Lua here is single-threaded and neither call yields.
--
-- the shape is read ONCE per cell rather than once per slot: four slots of one
-- LFO are four wires out of one modulator, so they have to be reading the same
-- number at the same instant -- and with a sample-and-hold or a follower,
-- asking twice can genuinely give two answers.
-- §2.12b what a synced LFO's rate is depends on the tempo, and the tempo is
-- not ours to be told about -- it moves from the norns PARAMS menu, from a
-- MIDI clock, from a link peer, none of which call anything here. so the
-- engine-side rate is reconciled on the modulation metro instead of pushed
-- from a row: read what it should be, compare, send only on a change.
--
-- four float comparisons forty times a second, and an OSC message only when
-- the number actually moves -- which is a tempo change, a Sync flip or a
-- turn of the Ratio knob, and nothing else. this also makes the row's own
-- push redundant rather than wrong: whichever gets there first, the other
-- sees no change and says nothing.
local pushed_hz = {}

local function reconcile_rate(id)
  local hz = lfo.rate_hz(id)
  if pushed_hz[id] ~= hz then
    pushed_hz[id] = hz
    bridge.lfo_rate(topology.get(id).index, hz)
  end
end

function lfo.apply()
  for _, id in ipairs(lfo.each()) do
    reconcile_rate(id)
    -- the cell's cables, resolved once for all four slots: a set to check a
    -- stored target against, and the first in registration order for slot 1's
    -- fallback. sixteen rebuilds a frame was where the cost of four slots
    -- landed, and this is the whole of the fix.
    local dests, first = {}, nil
    for _, edge in ipairs(patch.edges_at(id)) do
      local other = patch.other(edge, id)
      dests[other] = true
      if first == nil or ORDINAL[other] < ORDINAL[first] then first = other end
    end

    local swing = lfo.value(id)
    for i = 1, lfo.slot_count(id) do
      local p, target = slot_row(id, i, dests, first)
      local k = id .. "\0" .. i
      local prev = held[k]
      if prev and (not p or prev.target ~= target or prev.key ~= p.key) then
        release(prev)
        held[k] = nil
      end
      if p then
        local base = p.get(target)
        p.set(target, util.clamp(base + lfo.depth(id, i) * swing, 0, 1))
        p.push(target)
        p.set(target, base)
        held[k] = {target = target, key = p.key}
      end
    end
  end
end

-- the page ---------------------------------------------------------------------
-- six rows, one screen. Speed and Shape belong to the cell; Slot picks which
-- of the four destinations the three under it describe.

-- a stepped row cannot round-trip through its own getter -- Target reads back
-- as one of a handful of fixed positions, so adding a third of a step and
-- reading it again lands where it started and the row never moves. so the
-- encoder's own position is kept here, unrounded, exactly the way
-- cellparam.lua does it for Gait and Rule. keyed by slot as well as by row,
-- since the same two rows describe four different things.
local acc = {}

local function stepped_row(key, label, list_fn, current_fn, apply_fn, text_fn)
  return {
    key = key, label = label, glyph = "word", stepped = true,
    glyph_data = function(id)
      local list = list_fn(id)
      local cur = current_fn(id)
      for i, v in ipairs(list) do
        if v == cur then return {idx = i - 1, total = #list} end
      end
      return {idx = 0, total = math.max(1, #list)}
    end,
    steps_fn = function(id) return #list_fn(id) end,
    get = function(id)
      local list = list_fn(id)
      local cur = current_fn(id)
      for i, v in ipairs(list) do
        if v == cur then return (i - 1) / math.max(1, #list - 1) end
      end
      return 0
    end,
    set = function(id, frac)
      local list = list_fn(id)
      if #list == 0 then return end
      local i = util.clamp(math.floor(frac * (#list - 1) + 0.5), 0, #list - 1) + 1
      apply_fn(id, list[i])
    end,
    text = text_fn,
    push = function() end,
  }
end

lfo.PARAMS = {
  {
    -- one knob, two things behind it (§2.12b). free, it is a continuous Hz
    -- sweep and stores `rate`; synced, it walks clockcell's ratio ladder and
    -- stores `ratio`. two vparams rather than one, so flipping Sync and
    -- flipping back finds both knobs where they were left.
    --
    -- it stays a plain continuous row in both modes. the ratio is derived
    -- from the stored 0..1 rather than snapped into it, so this getter
    -- round-trips exactly and the accumulator the genuinely stepped rows
    -- below need is not needed here -- and nineteen ratios across eighty
    -- detents is already about four detents apiece.
    key = "rate", label = "Speed", glyph = "fader", default = 0.5,
    label_fn = function(id) return lfo.synced(id) and "Ratio" or "Speed" end,
    get = function(id)
      return state.get_vparam(id, lfo.synced(id) and "ratio" or "rate", 0.5)
    end,
    set = function(id, v)
      return state.set_vparam(id, lfo.synced(id) and "ratio" or "rate", v)
    end,
    text = function(id)
      -- a follower has no rate: it is reading the mix, not running a cycle.
      -- the knob still stores whatever it was left on, so switching back to
      -- an oscillator shape lands where it did before.
      if lfo.shape(id) == lfo.FOLLOW then return "follows" end
      if lfo.synced(id) then
        local _, name = lfo.ratio(id)
        return name
      end
      return string.format("%.2f Hz", lfo.rate_hz(id))
    end,
    push = function(id)
      local cell = topology.get(id)
      bridge.lfo_rate(cell.index, lfo.rate_hz(id))
    end,
  },
  {
    -- what the Speed knob above is measured against. a switch and not a
    -- value, so it draws as a flag and takes two detents to flip -- the same
    -- shape and the same feel as a Clock cell's own Mode row.
    key = "sync", label = "Sync", glyph = "flag", default = lfo.SYNC_DEFAULT,
    stepped = true, steps_fn = function() return 2 end,
    get = function(id) return lfo.synced(id) and 1 or 0 end,
    set = function(id, v) lfo.set_synced(id, v >= 0.5) end,
    text = function(id) return lfo.synced(id) and "clock" or "free" end,
    -- nothing to send: flipping this changes the rate, and the rate has one
    -- owner (reconcile_rate, on the modulation metro) precisely because the
    -- tempo can move without any row being touched at all. it picks the
    -- change up on the next pass, a fortieth of a second later.
    push = function() end,
  },
  {
    -- which of the eight. `stack` rather than `word` because these are an
    -- ordered bank and the stack says where in it you are; the name itself is
    -- printed on the value line underneath.
    key = "shape", label = "Shape", glyph = "stack", default = 0,
    get = vp_get("shape", 0), set = vp_set("shape"),
    text = function(id) return lfo.shape(id) end,
    glyph_data = function(id)
      return {n = #lfo.SHAPES, lit = lfo.shape_index(id)}
    end,
    push = function(id)
      local cell = topology.get(id)
      bridge.lfo_shape(cell.index, lfo.shape_index(id) - 1)
    end,
  },
  {
    -- which of the four destinations the three rows below describe. it moves
    -- nothing on its own -- it is the page's own cursor, made visible.
    key = "slot", label = "Slot", glyph = "steps", default = 0,
    get = vp_get("slot", 0), set = vp_set("slot"),
    text = function(id)
      local i = lfo.slot(id)
      local t = lfo.target(id, i)
      if not t then return i .. " off" end
      return i .. " on"
    end,
    glyph_data = function(id) return {n = lfo.slot_count(id), lit = lfo.slot(id)} end,
    push = function() end,
  },
  stepped_row("target", "Target",
    function(id) return lfo.target_options(id) end,
    function(id) return lfo.target_option(id) end,
    function(id, v) lfo.set_target(id, v) end,
    function(id)
      local t = lfo.target(id)
      if t then return topology.get(t).name end
      if #lfo.destinations(id) == 0 then return "no cable" end
      return "off"
    end),
  stepped_row("param", "Param",
    function(id) return lfo.param_keys(id) end,
    function(id) return lfo.param_key(id) end,
    function(id, v) lfo.set_param_key(id, v) end,
    function(id)
      if not lfo.target(id) then return "-" end
      return lfo.param_key(id)
    end),
  {
    key = "depth", label = "Depth", glyph = "wander", default = 0.3,
    get = function(id) return lfo.depth(id) end,
    set = function(id, v) return lfo.set_depth(id, v) end,
    text = function(id) return string.format("%.2f", lfo.depth(id)) end,
    push = function() end,   -- read live by lfo.apply
  },
}

lfo.PARAM_COUNT = #lfo.PARAMS

function lfo.param(i)
  return lfo.PARAMS[util.clamp(i, 1, #lfo.PARAMS)]
end

-- E2's own step is 1/80 of the knob, so a row with n positions wants this
-- much extra gain to move one position per three detents of encoder travel
-- (cellparam.lua's DETENTS_PER_STEP, kept in step with it by hand -- two
-- short tables beat one shared one neither file owns).
local DETENTS_PER_STEP = 3

function lfo.nudge(id, i, delta)
  local p = lfo.param(i)
  if not p.stepped then
    p.set(id, util.clamp(p.get(id) + delta, 0, 1))
    p.push(id)
    return p
  end

  local n = p.steps_fn(id)
  local scale = (n and n > 1) and (80 / ((n - 1) * DETENTS_PER_STEP)) or 1
  -- the slot is part of the key: Target on slot 2 is a different row from
  -- Target on slot 1, and one shared accumulator would drag them together.
  local k = id .. "\0" .. lfo.slot(id) .. "\0" .. p.key
  local cur = p.get(id)
  local a = acc[k]
  if not a or a.seen ~= cur then
    a = {raw = cur, seen = cur}
    acc[k] = a
  end
  a.raw = util.clamp(a.raw + delta * scale, 0, 1)
  p.set(id, a.raw)
  p.push(id)
  a.seen = p.get(id)
  return p
end

function lfo.push_all(id)
  for _, p in ipairs(lfo.PARAMS) do p.push(id) end
end

-- the four cell ids, built once: the panel is static, and this is read on
-- every pass of the modulation metro.
local EACH = nil

function lfo.each()
  if not EACH then
    EACH = {}
    for id, cell in topology.each() do
      if cell.type == "LFO" then table.insert(EACH, id) end
    end
  end
  return EACH
end

-- §5.1: unlike every other family's indicator, an LFO has no discrete event
-- to flash on -- what it does instead is never stop, so the grid shouldn't
-- either. each cell keeps its own running phase, advanced in real time by
-- its own Speed every time anything asks to see it (gridui polls this at
-- grid_metro's rate, ~30 Hz) -- so the LED breathes through one full cycle
-- exactly as often as the audio does, at whatever rate the player has it set
-- to.
local last_t = {}
local phase = {}

function lfo.phase(id)
  local now = util.time()
  local was = phase[id]
  local ph

  if lfo.synced(id) then
    -- §2.12b the whole of what "synced" means, and the reason it is a
    -- different line rather than a different rate: the phase is READ off the
    -- transport, not integrated from one. an integrated phase at the right Hz
    -- is only ever as accurate as the last frame's dt and lands wherever it
    -- was started; this one is a pure function of the beat, so at 1x the
    -- cycle begins on the beat and is still beginning on the beat an hour
    -- later, and two cells at the same ratio are in step with each other and
    -- with every Clock cell without anything having to be reset.
    ph = (clock.get_beats() * lfo.ratio(id)) % 1.0
    if ph < 0 then ph = ph + 1 end     -- a transport counting below zero
  elseif last_t[id] == nil then
    ph = 0
  else
    -- a clock that has gone backwards (a reload, the test harness rewinding
    -- its virtual time) reads as "no time passed" rather than winding the
    -- phase back through a negative turn.
    local dt = math.max(now - last_t[id], 0)
    ph = ((was or 0) + lfo.rate_hz(id) * dt) % 1.0
  end

  phase[id] = ph
  -- the wrap is where sample-and-hold draws its next value. done here rather
  -- than in lfo.value because this is the one function that knows time has
  -- passed -- value() is asked several times a frame (the grid, the
  -- modulation metro, the screen) and a fresh draw per ask would be noise at
  -- frame rate rather than a held step. it reads the same either way round:
  -- a synced cell's phase falls at its wrap exactly as a free one's does.
  if was ~= nil and ph < was then sh_step(id) end
  -- kept up to date even while synced, so switching back to free does not
  -- see the whole synced stretch as one enormous dt.
  last_t[id] = now
  return ph
end

-- three non-overlapping bands (idle / cabled / open) so "cabled reads
-- brighter than idle" and "open brighter than cabled" hold at every point in
-- the cycle, not just at the peak -- and within each band, the cell's own
-- shape is what moves the LED, trough to peak and back, once per cycle. that
-- means the panel shows which shape is running: a square blinks, a ramp
-- swells and snaps back, a sample-and-hold steps, and a follower pulses with
-- the mix.
local function pulse(lo, hi, swing)
  return util.clamp(math.floor(lo + swing * (hi - lo) + 0.5), 0, 15)
end

function lfo.level_at(id, base)
  base = base or 2
  local swing = (lfo.value(id) + 1) / 2
  if state.cell_edit == id then
    return pulse(11, 15, swing)
  elseif wl("patch").degree(id) > 0 then
    return pulse(base + 5, base + 8, swing)
  else
    return pulse(base, base + 2, swing)
  end
end

function lfo.init()
  for _, id in ipairs(lfo.each()) do
    lfo.push_all(id)
  end
end

return lfo
