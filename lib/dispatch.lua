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
-- build phase 5 adds H to both halves: a pulse cabled into a heartwood node
-- enters the lattice and diffuses (`on_pulse`), and a stream cabled to one
-- is injected into / tapped out of the lattice's audio side
-- (`resync_matrix`). the lattice's own walk lives in heartwood.lua.
--
-- node<->node and Sap/Sway/Moss's own *outputs* need a follower/analyser tap
-- this codebase doesn't have yet, so those stay no-ops (see the comment
-- above specs_for).
--
-- P (§2.6) appears only in the first half. a pitch field's whole output is a
-- number of semitones, which Lua turns into voice_pitch/exciter_colour calls
-- from grove.lua directly -- there is no stream to route, so P contributes no
-- specs to the continuous matrix at all.
--
-- both halves fall through silently for pairs with no handler.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local patch    = wl("patch")
local heartwood = wl("heartwood")
local grove    = wl("grove")

local dispatch = {}

-- a struck-somewhere default; becomes a live/per-voice parameter once
-- voice_pos or a Sway-adjacent control is wired up (later phase).
local STRIKE_POSITION_DEFAULT = 0.15

-- organic-rhythm addendum: real hands never land twice identically. every
-- pulse-triggered audio event below gets a small parameter wobble (force,
-- hardness, strike position, choke depth/time, grain amp/dur each move a
-- few percent per hit) on top of the edge-gain/weight shaping that was
-- already there. deliberately NOT touching rambler.lua's phase/coupling
-- timing itself, and not deferring the call either -- that timing is
-- calibrated for Kuramoto stability (PULSE_NUDGE etc.) and for the exact
-- gait-rate counts the test suite checks; this only wobbles *what* a pulse
-- that already landed sounds like, not *when*.
local function wobble(v, amt, lo, hi)
  return util.clamp(v + (math.random() * 2 - 1) * amt, lo, hi)
end

local HANDLERS = {}

-- D -> Voice.Knock: pulse strikes the resonator, force = edge gain (§2.2),
-- scaled by the pulse's own weight so a Shuck thud and an echo tail's sixth
-- repeat do not land identically. force/hardness/position each get a small
-- per-hit wobble on top of that (see the organic-rhythm note above) -- no
-- two strikes land quite the same, the way no two real mallet hits do.
HANDLERS["node:knock"] = function(source_id, target_id, edge, weight)
  local node = topology.get(target_id)
  local voice = topology.get(node.voice)
  local hardness = state.get_character(target_id, node, 0, 1)
  local force = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  local wForce = wobble(force, 0.04, 0, 1)
  local wHardness = wobble(hardness, 0.05, 0, 1)
  local wPosition = wobble(STRIKE_POSITION_DEFAULT, 0.07, 0, 1)
  -- §2.6, and the pitch half of the wobble above: every field cabled to this
  -- voice takes a step and the new pitch is sent *before* the mallet, so the
  -- strike lands on the note the field just chose. a voice with no field
  -- still gets a few cents of per-strike detune out of this.
  grove.on_strike(node.voice)
  bridge.strike(voice.index - 1, wForce, wHardness, wPosition)
  state.flash(target_id, force)
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
  local wDepth = wobble(depth, 0.04, 0, 1)
  local wTime = wobble(0.08 + curve * 0.5, 0.03, 0.01, 4)
  bridge.voice_choke(voice.index - 1, wDepth, wTime)
  state.flash(target_id, depth)
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
  local wAmp = wobble(amp, 0.04, 0, 1)
  local wDur = wobble(DEFAULT_GATE_DUR, 0.02, 0.02, 4)
  bridge.exciter_gate(cell.index, wDur, wAmp)
  state.flash(target_id, amp)
end

-- -> P: a pulse steps the pitch field (§6's P column). the field moves on
-- its own clock rather than on whatever is being struck, which is how you
-- get a melody that is not locked to the rhythm playing it. a P cell never
-- emits a pulse of its own, so nothing here can feed back round into itself.
HANDLERS["P"] = function(source_id, target_id, edge, weight)
  local w = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  grove.step(target_id, w, source_id)
end

-- -> H: "pulse enters the lattice and diffuses" (§6). heartwood.lua walks it
-- from there; everything this has to decide is where it goes in and how hard.
HANDLERS["H"] = function(source_id, target_id, edge, weight)
  local w = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  heartwood.inject(target_id, w, source_id)
end

-- fires when `source_id` (a D cell) wraps and has a cable to `target_id`.
-- also the path a pulse *emerging* from the lattice takes, with the H node
-- standing in for the D cell as the source.
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

-- S -> a voice node: the stream lands on whichever of that voice's three
-- summing inputs the node's role owns. Knock has none (it is pulse-only).
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

-- H -> a voice node: "lattice returns to the node" (§6). the other half of
-- that sentence -- "node injects into the lattice" -- needs a tap on the
-- node's out, which does not exist yet, so for now the lattice only speaks.
local function h_to_node_spec(h, node, gain)
  local bus = NODE_BUS[node.role]
  if not bus then return nil end
  local voice = topology.get(node.voice)
  return {
    kind = "aa",
    src = bridge.bus("heart_out", h.index),
    dst = bridge.bus(bus, voice.index - 1),
    gain = gain,
  }
end

-- an H<->H cable is a second path between two points that already sit in one
-- lattice, so its gain rides on top of the ring's own. held well under unity:
-- heart_out -> heart_in closes a loop *outside* \wl_heartwood's own
-- normalisation, and the ring is already tuned to sit just short of
-- self-oscillation at full conductance.
local SHORTCUT_GAIN = 0.7

local function h_to_h_specs(a, b, edge, out)
  local function link(from, to)
    table.insert(out, {
      kind = "aa",
      src = bridge.bus("heart_out", from.index),
      dst = bridge.bus("heart_in", to.index),
      gain = edge.gain * SHORTCUT_GAIN,
    })
  end
  link(a, b)
  -- a one-way shortcut is a genuinely different object from a two-way one:
  -- it makes the lattice directional, which the ring itself never is.
  if not edge.oneway then link(b, a) end
end

-- S <-> H: "stream diffuses through the lattice" (§6). read androgynously,
-- like S<->S above -- the source feeds the lattice, and what the lattice
-- makes of it comes back as colour on the exciter.
local function s_to_h_specs(s, h, edge, out)
  table.insert(out, {
    kind = "aa",
    src = bridge.bus("exc", s.index),
    dst = bridge.bus("heart_in", h.index),
    gain = edge.gain,
  })
  table.insert(out, {
    kind = "ak",
    src = bridge.bus("heart_out", h.index),
    dst = bridge.bus("colour_mod", s.index),
    gain = edge.gain,
  })
end

local function specs_for(edge)
  local a, b = topology.get(edge.a), topology.get(edge.b)
  local out = {}

  -- the matrix is symmetric in the endpoints, so each pair is written once
  -- and `ordered` finds it whichever way round the cable was drawn.
  local function ordered(ta, tb)
    if a.type == ta and b.type == tb then return a, b end
    if b.type == ta and a.type == tb then return b, a end
    return nil
  end

  local x, y

  x, y = ordered("S", "S")
  if x then
    table.insert(out, {
      kind = "ak", src = bridge.bus("exc", x.index),
      dst = bridge.bus("colour_mod", y.index), gain = edge.gain,
    })
    table.insert(out, {
      kind = "ak", src = bridge.bus("exc", y.index),
      dst = bridge.bus("colour_mod", x.index), gain = edge.gain,
    })
    return out
  end

  x, y = ordered("S", "node")
  if x then
    local spec = s_to_node_spec(x, y, edge.gain)
    if spec then table.insert(out, spec) end
    return out
  end

  x, y = ordered("S", "H")
  if x then
    s_to_h_specs(x, y, edge, out)
    return out
  end

  x, y = ordered("H", "node")
  if x then
    local spec = h_to_node_spec(x, y, edge.gain)
    if spec then table.insert(out, spec) end
    return out
  end

  x, y = ordered("H", "H")
  if x then
    -- ordered() may have swapped them; the one-way rule is written in terms
    -- of the edge's own a/b, so re-derive from those rather than from x/y.
    h_to_h_specs(topology.get(edge.a), topology.get(edge.b), edge, out)
    return out
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
