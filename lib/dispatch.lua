-- dispatch.lua
-- the §6 type-interaction matrix: what a cable *means*, given the pair of
-- endpoint types. implemented as a dispatch table keyed by "kind:role" (or
-- just "kind" for D/S/H), per the spec's own instruction not to branch.
--
-- build phase 2 only wires the one rule it needs -- a D cell's pulse
-- striking a voice's Knock node. every other cell of the matrix (D<->D
-- coupling, D->S gating, S<->S, anything touching H, Sway/Sap/Moss pulses)
-- is later-phase work; on_pulse is a safe no-op for pairs with no handler.

local topology = include("Woodland/lib/topology")
local state = include("Woodland/lib/state")
local bridge = include("Woodland/lib/bridge")

local dispatch = {}

-- a struck-somewhere default; becomes a live/per-voice parameter once
-- voice_pos or a Sway-adjacent control is wired up (later phase).
local STRIKE_POSITION_DEFAULT = 0.15

local HANDLERS = {}

-- D -> Voice.Knock: pulse strikes the resonator, force = edge gain (§2.2).
HANDLERS["node:knock"] = function(source_id, target_id, edge)
  local node = topology.get(target_id)
  local voice = topology.get(node.voice)
  local hardness = state.get_character(target_id, node, 0, 1)
  local force = util.clamp(math.abs(edge.gain), 0, 1)
  bridge.strike(voice.index - 1, force, hardness, STRIKE_POSITION_DEFAULT)
end

-- fires when `source_id` (a D cell) wraps and has a cable to `target_id`.
function dispatch.on_pulse(source_id, target_id, edge)
  local target = topology.get(target_id)
  if not target then return end

  local key = target.type == "node" and ("node:" .. target.role) or target.type
  local handler = HANDLERS[key]
  if handler then
    handler(source_id, target_id, edge)
  end
end

return dispatch
