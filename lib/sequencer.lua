-- sequencer.lua
-- the Q4/Q6 step-sequencer lanes (topology.lua §2.10, type "SEQ"). modeled
-- directly on tm.lua: no phase of its own, no free clock -- the only thing
-- that ever moves it is a pulse cabled in.
--
-- each lane is `len` physical cells (4 or 6), each independently a cable
-- endpoint and independently tap-toggleable (state.step_active). the *last*
-- cell of a lane is the "driver": a pulse there advances the lane's shared
-- playhead by one and, if the step it lands on is active, fires a pulse from
-- that step's own cell id. a pulse on any *other* cell in the lane fires
-- that one step directly and immediately, independent of the playhead --
-- patching a trigger straight into an individual step overrides it, the way
-- the sketch that started this called for.
--
-- dependency note: rambler.lua requires this file at load (its inbox needs a
-- branch here, exactly the one tm.lua and weave.lua already get), so this
-- one must not require rambler at load -- fetched lazily inside pulse_in,
-- same as tm.lua does.

local topology = wl("topology")
local state    = wl("state")

local sequencer = {}

local lanes = {}  -- group -> {len=, cells={id,...}, playhead=}
local cells = {}  -- id -> topology cell, for quick lookup

for id, cell in topology.each() do
  if cell.type == "SEQ" then
    cells[id] = cell
    local lane = lanes[cell.group]
    if not lane then
      lane = {len = cell.len, cells = {}, playhead = 0}
      lanes[cell.group] = lane
    end
    lane.cells[cell.step] = id
  end
end

-- a step's on/off state -- a UI toggle, not a cable. defaults to active so a
-- freshly patched sequencer plays every step until the player starts pulling
-- some out.
function sequencer.is_active(id)
  if state.step_active[id] == nil then state.step_active[id] = true end
  return state.step_active[id]
end

-- the tap gesture (gridui.on_tap, a plain unmodified tap on a SEQ cell).
function sequencer.toggle_step(id)
  local active = not sequencer.is_active(id)
  state.step_active[id] = active
  return active
end

-- which step a lane's playhead currently sits on, or 0 before it has ever
-- been driven -- gridui reads this to light the traveling step.
function sequencer.playhead(group)
  local lane = lanes[group]
  return lane and lane.playhead or 0
end

-- delivery ------------------------------------------------------------------
-- called from rambler's inbox, one tick after the pulse that triggered it.

function sequencer.pulse_in(id, w, src, now)
  local cell = cells[id]
  if not cell then return end
  state.flash(id, w or 1)

  local rambler = wl("rambler")
  if cell.driver then
    local lane = lanes[cell.group]
    lane.playhead = (lane.playhead % lane.len) + 1
    local target_id = lane.cells[lane.playhead]
    if sequencer.is_active(target_id) then
      rambler.emit_from(target_id, w or 1)
    end
  else
    if sequencer.is_active(id) then
      rambler.emit_from(id, w or 1, nil, src)
    end
  end
end

-- read/control surface -------------------------------------------------------

function sequencer.level(id, base)
  local cell = cells[id]
  if not cell then return base end
  local lvl = base
  if sequencer.is_active(id) then lvl = lvl + 2 end
  if sequencer.playhead(cell.group) == cell.step then lvl = lvl + 4 end
  return state.flash_level(id, lvl)
end

function sequencer.info(id)
  local cell = cells[id]
  if not cell then return nil end
  return {
    group = cell.group,
    step = cell.step,
    len = cell.len,
    driver = cell.driver,
    active = sequencer.is_active(id),
    playhead = sequencer.playhead(cell.group),
  }
end

return sequencer
