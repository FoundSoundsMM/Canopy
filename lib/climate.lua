-- climate.lua
-- the §2.8 C cells: the long game.
--
-- everything else on this panel works on the scale of a bar. the eight cells
-- in the outer corners work on the scale of a piece. cable one to any cell
-- and that cell's own knob is walked around it -- a gait's rate, an exciter's
-- colour, a field's range, a node's conductance, a socket's hardness -- over
-- tens of seconds to tens of minutes.
--
-- the knob itself is never overwritten. a climate cell writes into
-- state.character_mod, which state.get_character adds to the player's value
-- on the way out, so the setting you left is still the setting you left, and
-- pulling the cable puts the cell back exactly where it was.
--
-- this is the difference between a patch that loops and a patch that goes
-- somewhere, and it is deliberately the least visible thing on the panel:
-- if you can hear it happening it is turned up too far.
--
-- a C cell cabled to another C cell modulates *its* period, and that needs no
-- special case at all -- a climate reads its own period through
-- get_character like everything else does.
--
-- nothing here listens for a pulse. see the C handler in dispatch.lua for
-- why: cables are undirected, so anything that made a pulse mean something
-- to a climate would fire on the return leg of the ordinary C->D cable.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")

local climate = {}

-- runs every Nth scheduler tick. 16 x 2 ms = 32 ms: finer than the screen
-- refresh, and about seven orders of magnitude finer than the slowest shape
-- in here needs.
climate.TICK_EVERY = 16

-- E2 (Period), logarithmic, so the fast end -- where this is a slow LFO --
-- gets a fair share of the knob and the slow end still reaches "once in the
-- ten minutes you were listening".
local PERIOD_MIN, PERIOD_MAX = 6.0, 600.0

-- how far a cable at unity gain moves the far cell's knob, in fractions of
-- that knob's own range. bipolar around whatever the player set.
local DEPTH = 0.5

-- below this, a change is not worth an OSC message.
local EPSILON = 0.004

local fields = {}   -- c_id -> record
local order = {}    -- c_ids, stable iteration order
local targets = {}  -- target cell id -> {{f=, gain=}, ...}
local touched = {}  -- target cell id -> true while some climate reaches it
local tick_n = 0

-- shapes -----------------------------------------------------------------------
-- each maps a normalised phase (and the record, for the ones with memory) to
-- a value in -1..+1. `rate` scales the period: shiver is a tremor, not a tide.

local SHAPES = {}

climate.SHAPE_ORDER = {
  "tide", "creep", "season", "gust", "breath", "wane", "flourish", "shiver",
}

-- tide: one long swell. the plain one, and the one to reach for first.
SHAPES.tide = {
  rate = 1,
  value = function(f) return math.sin(2 * math.pi * f.phase) end,
}

-- creep: a bounded drunk walk. never comes back the same way twice, which is
-- exactly what you want under something you are going to listen to for an
-- hour and exactly what you do not want under something rhythmic.
SHAPES.creep = {
  rate = 1,
  value = function(f, dt, period)
    -- step size scaled so one nominal period is roughly one full excursion,
    -- with a weak pull to centre so it does not park on a rail.
    local step = (math.random() * 2 - 1) * (dt / period) * 4
    local v = f.v + step - f.v * (dt / period) * 0.8
    return util.clamp(v, -1, 1)
  end,
}

-- season: straight up, straight down. no curve at all, which reads as
-- deliberate where a sine reads as wobble.
SHAPES.season = {
  rate = 1,
  value = function(f)
    local p = f.phase
    return (p < 0.5) and (-1 + p * 4) or (3 - p * 4)
  end,
}

-- gust: mostly nothing, then everything at once. sits at rest and now and
-- then throws the far knob somewhere and lets it fall back.
SHAPES.gust = {
  rate = 1,
  value = function(f, dt, period)
    if math.random() < dt / (period * 0.25) then
      f.v = (math.random() * 2 - 1)
    end
    return f.v * math.exp(-dt / (period * 0.12)) + 0
  end,
  decays = true,
}

-- breath: a long draw in and a short push out. asymmetric on purpose -- a
-- sine is the same shape backwards and nothing alive is.
SHAPES.breath = {
  rate = 1,
  value = function(f)
    local p = f.phase
    local warped = (p < 0.7) and (p / 0.7 * 0.5) or (0.5 + (p - 0.7) / 0.3 * 0.5)
    return -math.cos(2 * math.pi * warped)
  end,
}

-- wane: falls away over the whole period, then starts again at the top.
SHAPES.wane = {
  rate = 1,
  value = function(f) return 1 - f.phase * 2 end,
}

-- flourish: climbs the whole period and drops in an instant. wane's mirror,
-- and the two of them on one cable each is a very long see-saw.
SHAPES.flourish = {
  rate = 1,
  value = function(f) return -1 + f.phase * 2 end,
}

-- shiver: small and quick. runs twenty times faster than the rest of this
-- row, interpolating between random points -- a tremor rather than a tide.
SHAPES.shiver = {
  rate = 0.05,
  value = function(f)
    -- one new destination per cycle, walked toward smoothly.
    if f.phase < f.last_phase then
      f.from = f.to
      f.to = (math.random() * 2 - 1) * 0.6
    end
    local t = f.phase
    return f.from + (f.to - f.from) * (t * t * (3 - 2 * t))
  end,
}

climate.SHAPES = SHAPES

-- construction -------------------------------------------------------------------

for id, cell in topology.each() do
  if cell.type == "C" then
    local f = {
      id = id,
      cell = cell,
      shape = state.get_shape(id, cell.shape),
      -- spread the starting phases, for the same reason rambler spreads its
      -- oscillators': eight modulators that all start at zero are one
      -- modulator until they drift apart, which at these periods is never.
      phase = math.random(),
      last_phase = 0,
      v = 0,
      from = 0,
      to = 0,
    }
    fields[id] = f
    table.insert(order, id)
  end
end

function climate.period(id)
  local f = fields[id]
  if not f then return PERIOD_MIN end
  local v = state.get_character(id, f.cell, 0, 1)
  local base = PERIOD_MIN * ((PERIOD_MAX / PERIOD_MIN) ^ util.clamp(v, 0, 1))
  return base * (SHAPES[f.shape].rate or 1)
end

function climate.value(id)
  local f = fields[id]
  return f and f.out or 0
end

-- link caching ---------------------------------------------------------------------

local function rebuild_links()
  local was = targets
  targets = {}
  for _, id in ipairs(order) do
    local f = fields[id]
    for _, edge in ipairs(patch.edges_at(f.id)) do
      local other_id = patch.other(edge, f.id)
      local other = topology.get(other_id)
      -- a one-way cable a->b only sends from a (§3), the rule every other
      -- source on the panel uses. a voice cell has no single knob to move --
      -- it has the eight-parameter page instead -- so it is not a target.
      local can_send = (not edge.oneway) or (edge.a == f.id)
      if other and can_send and other.type ~= "voice" then
        targets[other_id] = targets[other_id] or {}
        table.insert(targets[other_id], {f = f, gain = edge.gain})
      end
    end
  end
  -- anything that has just lost its last climate cable goes back to exactly
  -- the value the player left it at, rather than keeping whatever offset it
  -- happened to be carrying when the cable was pulled.
  for id in pairs(was) do
    if not targets[id] and state.character_mod[id] then
      state.character_mod[id] = nil
      state.notify_character_change(id)
    end
  end
end

patch.on_change(rebuild_links)
rebuild_links()

-- motion -----------------------------------------------------------------------------

function climate.tick(now)
  tick_n = tick_n + 1
  if tick_n % climate.TICK_EVERY ~= 0 then return end
  local dt = wl("rambler").TICK * climate.TICK_EVERY

  for _, id in ipairs(order) do
    local f = fields[id]
    local shape = SHAPES[f.shape]
    local period = math.max(climate.period(id), 0.1)
    f.last_phase = f.phase
    f.phase = (f.phase + dt / period) % 1
    if shape.decays then
      f.v = shape.value(f, dt, period)
      f.out = f.v
    else
      local v = shape.value(f, dt, period)
      f.v = v
      f.out = v
    end
  end

  -- one write per target, summed, rather than one per cable -- two climates
  -- on one cell should average into a single motion, not race each other for
  -- the last word.
  for target_id, links in pairs(targets) do
    local sum = 0
    for _, l in ipairs(links) do
      sum = sum + climate.value(l.f.id) * l.gain
    end
    local mod = util.clamp(sum * DEPTH, -1, 1)
    local prev = state.character_mod[target_id] or 0
    if math.abs(mod - prev) >= EPSILON then
      state.character_mod[target_id] = mod
      state.notify_character_change(target_id)
    end
  end
end

-- read/control surface ------------------------------------------------------------------

-- §5.1: no flash -- nothing here happens at an instant. the cell's brightness
-- *is* its value, so the row of them along the edge reads as eight slow
-- meters, which is exactly what they are.
function climate.level(id, base)
  local f = fields[id]
  if not f then return base end
  local lvl = base + math.floor(((climate.value(id) + 1) / 2) * 8)
  if patch.degree(id) > 0 then lvl = lvl + 3 end
  return util.clamp(math.floor(lvl), 0, 15)
end

local function period_text(secs)
  if secs < 90 then return string.format("%.0f s", secs) end
  return string.format("%.1f min", secs / 60)
end

function climate.info(id)
  local f = fields[id]
  if not f then return nil end
  local period = climate.period(id)
  return {
    shape = f.shape,
    param = period_text(period),
    period = period,
    value = climate.value(id),
    reaches = patch.degree(id),
  }
end

function climate.set_shape(id, key)
  local f = fields[id]
  if not f or not SHAPES[key] then return nil end
  f.shape = key
  state.shape[id] = key
  f.v = 0
  f.from, f.to = 0, 0
  return key
end

-- K1+E2 while holding a C cell -- the same gesture that swaps a D cell's gait.
function climate.cycle_shape(id, delta)
  local f = fields[id]
  if not f then return nil end
  local n = #climate.SHAPE_ORDER
  local at = 1
  for i, key in ipairs(climate.SHAPE_ORDER) do
    if key == f.shape then at = i break end
  end
  return climate.set_shape(id, climate.SHAPE_ORDER[((at - 1 + delta) % n) + 1])
end

function climate.get(id)
  return fields[id]
end

return climate
