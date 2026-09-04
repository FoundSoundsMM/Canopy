-- lfo.lua
-- §2.12: the four LFO cells -- a free-running sine source per cell, and the
-- settings page for one.
--
-- an LFO is a sine, always running, with no sound of its own. cable it to a
-- cell and it moves something about that cell; cable it to an Output cell and
-- it is heard directly as a tone, once Speed is up in the audio range.
--
-- WHICH thing it moves is the point of this page. an LFO used to land on one
-- fixed input per destination type: a voice's mod path, an exciter's colour,
-- a gust's cross-mod. that is one destination per cell, chosen by the script
-- and not by the player, and it meant the answer to "what does this LFO do
-- to Oak" was buried in a type table in dispatch.lua. so the page has two
-- more rows now: Target picks one of the cells this LFO is cabled to, and
-- Param picks one row of THAT cell's own settings page. the LFO then moves
-- exactly that knob, by Depth, around wherever the player left it.
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
-- have.

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

-- log-mapped across the whole range: most of a slow modulator's useful travel
-- is in its bottom octave or two, same reasoning as gust's attack/decay.
function lfo.rate_hz(id)
  local v = state.get_vparam(id, "rate", 0.5)
  return lfo.RATE_MIN * ((lfo.RATE_MAX / lfo.RATE_MIN) ^ v)
end

-- destination and parameter -------------------------------------------------

-- the first entry of the Param row: "leave the cable alone". with this
-- selected the LFO modulates no knob and dispatch.lua's ordinary audio-rate
-- spec for the pair stands, which is what an LFO cabled to an Output cell
-- (a plain sine tone) or straight into a gust's cross-mod input wants.
lfo.SIGNAL = "signal"

-- every cell this LFO is currently cabled to, in the panel's own registration
-- order so the Target row does not reshuffle itself when a cable is added in
-- the middle. Output cells are included: "signal" is the only sensible Param
-- for one, and that is already the default.
function lfo.destinations(id)
  local set = {}
  for _, edge in ipairs(patch.edges_at(id)) do
    set[patch.other(edge, id)] = true
  end
  local out = {}
  for cid in topology.each() do
    if set[cid] then table.insert(out, cid) end
  end
  return out
end

-- which one is selected. stored by cell id rather than by position, so
-- cabling something else in does not silently move the target -- and checked
-- against the live cable list on every read, so pulling the cable drops it.
function lfo.target(id)
  local want = state.lfo_target[id]
  local dests = lfo.destinations(id)
  for _, cid in ipairs(dests) do
    if cid == want then return cid end
  end
  return dests[1]
end

function lfo.set_target(id, cell_id)
  if state.lfo_target[id] == cell_id then return end
  state.lfo_target[id] = cell_id
  -- moving the target changes which cables are audio and which are knobs, and
  -- nothing about the graph moved, so dispatch has to be told by hand.
  wl("dispatch").resync_matrix()
end

-- the rows of the target's own settings page, by key, with SIGNAL in front.
-- asked of cellparam rather than of a table here, so a family that grows a
-- new knob grows a new LFO destination on the same day.
function lfo.param_keys(id)
  local keys = {lfo.SIGNAL}
  local target = lfo.target(id)
  if not target then return keys end
  local page = wl("cellparam").page(target)
  if not page then return keys end
  for _, p in ipairs(page.PARAMS) do
    table.insert(keys, p.key or "?")
  end
  return keys
end

function lfo.param_key(id)
  local want = state.lfo_param[id]
  local keys = lfo.param_keys(id)
  for _, k in ipairs(keys) do
    if k == want then return k end
  end
  return lfo.SIGNAL
end

function lfo.set_param_key(id, key)
  if state.lfo_param[id] == key then return end
  state.lfo_param[id] = key
  -- leaving "signal" tears the audio cable down; coming back to it builds it
  -- again. same reason set_target resyncs.
  wl("dispatch").resync_matrix()
end

function lfo.depth(id)
  return state.get_vparam(id, "depth", 0.3)
end

-- true when this LFO is driving a named knob on `cell_id` rather than sending
-- it audio. dispatch.lua asks, and drops its own spec for the pair when it is
-- -- otherwise the cable would be heard twice, once as a knob and once as a
-- signal on a bus the player never asked for.
function lfo.modulates(lfo_id, cell_id)
  local cell = topology.get(lfo_id)
  if not cell or cell.type ~= "LFO" then return false end
  return lfo.target(lfo_id) == cell_id and lfo.param_key(lfo_id) ~= lfo.SIGNAL
end

-- applying it ----------------------------------------------------------------

-- the row object for the currently selected (target, param) pair, or nil.
local function selected_row(id)
  local target = lfo.target(id)
  if not target then return nil end
  local key = lfo.param_key(id)
  if key == lfo.SIGNAL then return nil end
  local page = wl("cellparam").page(target)
  if not page then return nil end
  for _, p in ipairs(page.PARAMS) do
    if p.key == key then return p, target end
  end
  return nil
end

-- what each LFO last moved, so that changing Target or Param puts the knob it
-- was holding back where the player left it rather than leaving the engine
-- stuck at whatever the sine happened to be at.
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
function lfo.apply()
  for _, id in ipairs(lfo.each()) do
    local p, target = selected_row(id)
    local prev = held[id]
    if prev and (not p or prev.target ~= target or prev.key ~= p.key) then
      release(prev)
      held[id] = nil
    end
    if p then
      local base = p.get(target)
      local swing = math.sin(lfo.phase(id) * 2 * math.pi)
      p.set(target, util.clamp(base + lfo.depth(id) * swing, 0, 1))
      p.push(target)
      p.set(target, base)
      held[id] = {target = target, key = p.key}
    end
  end
end

-- the page ---------------------------------------------------------------------
-- four rows, half a screen, which leaves the block underneath for the sine
-- scope (screenui.SCOPES.LFO).

-- a stepped row cannot round-trip through its own getter -- Target reads back
-- as one of a handful of fixed positions, so adding a third of a step and
-- reading it again lands where it started and the row never moves. so the
-- encoder's own position is kept here, unrounded, exactly the way
-- cellparam.lua does it for Gait and Rule.
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
    key = "rate", label = "Speed", glyph = "fader", default = 0.5,
    get = vp_get("rate", 0.5), set = vp_set("rate"),
    text = function(id) return string.format("%.2f Hz", lfo.rate_hz(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.lfo_rate(cell.index, lfo.rate_hz(id))
    end,
  },
  {
    -- how far the sine swings the chosen knob, either side of where the
    -- player left it. it is deliberately not the cable's gain: a cable is
    -- shared with whatever else the pair means to each other, and this
    -- belongs to the LFO.
    key = "depth", label = "Depth", glyph = "wander", default = 0.3,
    get = vp_get("depth", 0.3), set = vp_set("depth"),
    text = function(id) return string.format("%.2f", lfo.depth(id)) end,
    push = function() end,   -- read live by lfo.apply
  },
  stepped_row("target", "Target", lfo.destinations, lfo.target, lfo.set_target,
    function(id)
      local t = lfo.target(id)
      if not t then return "no cable" end
      return topology.get(t).name
    end),
  stepped_row("param", "Param", lfo.param_keys, lfo.param_key, lfo.set_param_key,
    function(id)
      if not lfo.target(id) then return "-" end
      return lfo.param_key(id)
    end),
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
  local k = id .. "\0" .. p.key
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

function lfo.each()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "LFO" then table.insert(ids, id) end
  end
  return ids
end

-- §5.1: unlike every other family's indicator, an LFO has no discrete event
-- to flash on -- what it does instead is never stop, so the grid shouldn't
-- either. each cell keeps its own running phase, advanced in real time by
-- its own Speed every time anything asks to see it (gridui polls this at
-- grid_metro's rate, ~30 Hz) -- so the LED breathes through one full sine
-- cycle exactly as often as the audio does, at whatever rate the player has
-- it set to.
local last_t = {}
local phase = {}

function lfo.phase(id)
  local now = util.time()
  local t0 = last_t[id]
  if t0 == nil then
    phase[id] = 0
  else
    -- a clock that has gone backwards (a reload, the test harness rewinding
    -- its virtual time) reads as "no time passed" rather than winding the
    -- phase back through a negative turn.
    local dt = math.max(now - t0, 0)
    phase[id] = (phase[id] + lfo.rate_hz(id) * dt) % 1.0
  end
  last_t[id] = now
  return phase[id]
end

-- three non-overlapping bands (idle / cabled / open) so "cabled reads
-- brighter than idle" and "open brighter than cabled" hold at every point in
-- the cycle, not just at the peak -- and within each band, the sine itself is
-- what moves the LED, trough to peak and back, once per cycle.
local function pulse(lo, hi, swing)
  return util.clamp(math.floor(lo + swing * (hi - lo) + 0.5), 0, 15)
end

function lfo.level_at(id, base)
  base = base or 2
  local swing = (math.sin(lfo.phase(id) * 2 * math.pi) + 1) / 2
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
