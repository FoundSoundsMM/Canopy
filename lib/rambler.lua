-- rambler.lua
-- D-cell gaits + the phase-coupling scheduler (§2.3, §7.3).
--
-- build phase 2 only implements the "metric" gait (Knocker's default) --
-- a free-running phase oscillator advanced by a fixed rate, emitting a
-- pulse on wrap. the other nine gaits and Kuramoto phase-coupling between
-- D cells are phase 3. an unimplemented gait just leaves that cell silent
-- (phase never advances) rather than erroring.
--
-- §7.3 says "one clock.run coroutine at a 2ms tick"; this uses a metro
-- instead, deliberately -- clock.sleep() inside clock.run is tempo-relative
-- (beats, not seconds) in norns, and D-cell rates are genuine Hz, not
-- tempo-scaled, so a wall-clock metro is what "2ms tick" actually needs.

local topology = include("Woodland/lib/topology")
local patch = include("Woodland/lib/patch")
local state = include("Woodland/lib/state")
local dispatch = include("Woodland/lib/dispatch")

local rambler = {}

local TICK = 1 / 500 -- 2ms

local phase = {}   -- d_id -> 0..1
local D_IDS = {}

for id, cell in topology.each() do
  if cell.type == "D" then
    phase[id] = 0
    table.insert(D_IDS, id)
  end
end

-- returns the cell's rate in Hz, or nil if its gait isn't implemented yet
-- (leaves it silent rather than erroring).
local function rate_hz(id, cell)
  if cell.gait == "metric" then
    local char = state.get_character(id, cell, 0, 1) -- §4.2: D cell E2 = rate
    return 0.5 + char * 3.5 -- 0.5 .. 4 Hz
  end
  return nil
end

function rambler.fire(id, cell)
  state.last_event = cell.name .. " *"
  for _, edge in ipairs(patch.edges_at(id)) do
    local target = patch.other(edge, id)
    dispatch.on_pulse(id, target, edge)
  end
end

function rambler.tick()
  if state.global.still then return end
  for _, id in ipairs(D_IDS) do
    local cell = topology.get(id)
    local hz = rate_hz(id, cell)
    if hz then
      phase[id] = phase[id] + hz * TICK
      if phase[id] >= 1.0 then
        phase[id] = phase[id] - math.floor(phase[id])
        rambler.fire(id, cell)
      end
    end
  end
end

function rambler.start()
  rambler.metro = metro.init(function() rambler.tick() end, TICK, -1)
  rambler.metro:start()
end

function rambler.stop()
  if rambler.metro then
    rambler.metro:stop()
    rambler.metro = nil
  end
end

return rambler
