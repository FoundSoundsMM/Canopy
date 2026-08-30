-- dispatch.lua
-- the §6 type-interaction matrix: what a cable *means*, given the pair of
-- endpoint types. implemented as a dispatch table keyed by "kind:role" (or
-- just "kind" for D/S/H), per the spec's own instruction not to branch.
--
-- this is the *pulse* half of the matrix only. build phase 3 wires the two
-- rules a pulse can express against a voice -- strike (Knock) and choke
-- (Moss) -- and D<->D, which lives in rambler.lua because it is coupling
-- rather than delivery. Sway and Sap take streams, not pulses, so they wait
-- for the exciter/patch-matrix phase; anything touching S or H likewise.
-- on_pulse is a safe no-op for pairs with no handler.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local dispatch = {}

-- a struck-somewhere default; becomes a live/per-voice parameter once
-- voice_pos or a Sway-adjacent control is wired up (later phase).
local STRIKE_POSITION_DEFAULT = 0.15

local HANDLERS = {}

-- D -> Voice.Knock: pulse strikes the resonator, force = edge gain (§2.2),
-- scaled by the pulse's own weight so a Shuck thud and an echo tail's sixth
-- repeat do not land identically.
HANDLERS["node:knock"] = function(source_id, target_id, edge, weight)
  local node = topology.get(target_id)
  local voice = topology.get(node.voice)
  local hardness = state.get_character(target_id, node, 0, 1)
  local force = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  bridge.strike(voice.index - 1, force, hardness, STRIKE_POSITION_DEFAULT)
end

-- D -> Voice.Moss: "a pulse chokes it" (§2.2). a momentary duck on the voice,
-- depth from edge gain x pulse weight, length from the node's own damping
-- character. the envelope itself lives in SC -- Lua only says when and how
-- hard, per §7.2.
HANDLERS["node:moss"] = function(source_id, target_id, edge, weight)
  local node = topology.get(target_id)
  local voice = topology.get(node.voice)
  local curve = state.get_character(target_id, node, 0, 1)
  local depth = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  bridge.voice_choke(voice.index - 1, depth, 0.08 + curve * 0.5)
end

-- fires when `source_id` (a D cell) wraps and has a cable to `target_id`.
function dispatch.on_pulse(source_id, target_id, edge, weight)
  local target = topology.get(target_id)
  if not target then return end

  local key = target.type == "node" and ("node:" .. target.role) or target.type
  local handler = HANDLERS[key]
  if handler then
    handler(source_id, target_id, edge, weight)
  end
end

return dispatch
