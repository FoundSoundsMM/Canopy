-- dispatch.lua
-- the §6 type-interaction matrix: what a cable *means*, given the pair of
-- endpoint types. two halves, because pulses and streams are delivered on
-- entirely different clocks:
--
-- `on_pulse` -- event-driven, fires once when a D cell wraps. build phase 3
-- wired D->Voice.Knock (strike) and D->Voice.Moss (choke); phase 4 adds
-- D->S (turns a free-running exciter into a fired grain, §2.4). D<->D lives
-- in rambler.lua, since it's coupling rather than delivery.
--
-- `resync_matrix` -- graph-driven, not event-driven: continuous pairs (S<->S,
-- S<->Sap/Sway/Moss) are just live SC synths for as long as the cable
-- exists, so there is no per-pulse Lua work -- only "does this synth exist
-- and does its gain match", checked whenever patch.lua reports a change.
--
-- H is still unbuilt, so every H pair is a no-op; node<->node and Sap/Sway/
-- Moss's own *outputs* need a follower/analyser tap this codebase doesn't
-- have yet, so those stay no-ops too (see the comment above specs_for).
--
-- both halves fall through silently for pairs with no handler.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local patch    = wl("patch")

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

local DEFAULT_GATE_DUR = 0.15

-- D -> S: "an S cell is continuous until a pulse is cabled into it. a D->S
-- cable turns the exciter into an enveloped grain, fired by that pulse"
-- (§2.4). exciter.lua sets the `gated` flag on the cable's existence; this
-- only fires the grain itself, same force-from-edge-gain-and-weight shape
-- as the Knock/Moss handlers above.
HANDLERS["S"] = function(source_id, target_id, edge, weight)
  local cell = topology.get(target_id)
  local amp = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  bridge.exciter_gate(cell.index, DEFAULT_GATE_DUR, amp)
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

-- continuous matrix (§6, the non-pulse pairs) ------------------------------
-- resolves a cabled pair to zero or more SC-side patch specs. no node<->node
-- or S<-node feedback: those need a stream *out* of a node (Sway's
-- amplitude envelope, Moss's spectral centroid, Sap's audio tap) and none of
-- those taps exist yet -- every node this phase only has an In. §6 also says
-- S<->S "modulates the other's colour AND level"; only colour is wired here.

local NODE_BUS = {sap = "exc_in", sway = "sway", moss = "moss"}

local function s_to_node_spec(s, node, gain)
  local bus = NODE_BUS[node.role]
  if not bus then return nil end
  local voice = topology.get(node.voice)
  return {
    kind = "aa",
    src = bridge.bus("exc", s.index),
    dst = bridge.bus(bus, voice.index - 1),
    gain = gain,
  }
end

local function specs_for(edge)
  local a, b = topology.get(edge.a), topology.get(edge.b)
  local out = {}

  if a.type == "S" and b.type == "S" then
    table.insert(out, {
      kind = "ak", src = bridge.bus("exc", a.index),
      dst = bridge.bus("colour_mod", b.index), gain = edge.gain,
    })
    table.insert(out, {
      kind = "ak", src = bridge.bus("exc", b.index),
      dst = bridge.bus("colour_mod", a.index), gain = edge.gain,
    })
  elseif a.type == "S" and b.type == "node" then
    local spec = s_to_node_spec(a, b, edge.gain)
    if spec then table.insert(out, spec) end
  elseif b.type == "S" and a.type == "node" then
    local spec = s_to_node_spec(b, a, edge.gain)
    if spec then table.insert(out, spec) end
  end

  return out
end

-- sc_patch_id -> the spec last sent for it, so a resync only sends what
-- actually changed (add/free are audible clicks; gain is cheap to repeat
-- but there is no reason to).
local active = {}

-- called whenever patch.lua's graph changes. a full recompute is fine here
-- (<=64 edges, user-driven, not per-tick) -- unlike on_pulse, nothing about
-- this needs to be fast.
function dispatch.resync_matrix()
  local wanted = {}
  for _, edge in pairs(patch.edges) do
    for i, spec in ipairs(specs_for(edge)) do
      wanted[edge.id * 10 + (i - 1)] = spec
    end
  end

  for id in pairs(active) do
    if not wanted[id] then
      bridge.patch_free(id)
      active[id] = nil
    end
  end

  for id, spec in pairs(wanted) do
    local cur = active[id]
    if not cur then
      bridge.patch_add(id, spec.kind, spec.src, spec.dst, spec.gain)
      active[id] = spec
    elseif cur.gain ~= spec.gain then
      bridge.patch_gain(id, spec.gain)
      active[id] = spec
    end
  end
end

patch.on_change(dispatch.resync_matrix)

return dispatch
