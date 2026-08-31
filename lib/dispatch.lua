-- dispatch.lua
-- the §6 type-interaction matrix: what a cable *means*, given the pair of
-- endpoint types. two halves, because pulses and streams are delivered on
-- entirely different clocks:
--
-- `on_pulse` -- event-driven, fires when a pulse-carrying cell speaks. it
-- covers everything a pulse can land on: a voice's T socket (strike), its M
-- socket (choke), its P socket (re-roll the pitch), an S cell (fire a grain),
-- an F cell (step the field), an H cell (into the lattice) and a C cell
-- (restart the weather). pulse-cell to pulse-cell traffic never comes here --
-- that is rambler's inbox, because it is coupling rather than delivery.
--
-- `resync_matrix` -- graph-driven, not event-driven: continuous pairs are
-- just live SC synths for as long as the cable exists, so there is no
-- per-pulse Lua work -- only "does this synth exist and does its gain match",
-- checked whenever patch.lua reports a change.
--
-- the re-cut closed the one hole that had been open since phase 4. a voice
-- had inputs and no output, so §6's "audio/CV cross-feed both ways" was a
-- promise rather than a cable. the O socket is that output, and it is
-- androgynous in the way the spec always wanted: continuously it is the
-- voice's audio on a bus, and discretely it is a pulse the instant the voice
-- is struck. the discrete half costs nothing -- Lua is the thing doing the
-- striking, so it already knows -- which is why voice<->voice feedback landed
-- without ever needing the §7.4 metering back-channel.
--
-- both halves fall through silently for pairs with no handler.

local topology  = wl("topology")
local state     = wl("state")
local bridge    = wl("bridge")
local patch     = wl("patch")
local lexicon   = wl("lexicon")
local heartwood = wl("heartwood")
local grove     = wl("grove")
local climate   = wl("climate")

local dispatch = {}

-- a real drum head cannot be re-struck instantly, and neither can this one.
-- it is a sound-design detail and it is also the safety rail on the new
-- feedback paths: a voice cabled out of its O socket and back round into its
-- own T socket is a legal, interesting patch, and this is what stops it from
-- being a 500 Hz machine gun.
local VOICE_REFRACTORY = 0.028

local last_strike = {}  -- voice id -> util.time() of the last one that landed

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

local function node_char(id, cell)
  local ch = lexicon.character(id)
  local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
  return state.get_character(id, cell, lo, hi)
end

local HANDLERS = {}

-- -> T: the pulse strikes the resonator, force = edge gain (§2.2), scaled by
-- the pulse's own weight so a Shuck thud and an echo tail's sixth repeat do
-- not land identically. force/hardness/position each get a small per-hit
-- wobble on top of that -- no two strikes land quite the same, the way no two
-- real mallet hits do. and the voice answers out of its O socket, a tick
-- later, so anything cabled there hears that it was hit.
HANDLERS["node:trig"] = function(source_id, target_id, edge, weight)
  local node = topology.get(target_id)
  local voice_id = node.voice
  local voice = topology.get(voice_id)
  local now = util.time()
  -- `>= 0` as well as `< refractory`: a clock that has gone backwards under us
  -- (a reload, a test harness rewinding its virtual time) must read as "long
  -- ago" rather than latch the voice silent forever.
  local since = now - (last_strike[voice_id] or -1)
  if since >= 0 and since < VOICE_REFRACTORY then return end
  last_strike[voice_id] = now

  local hardness = node_char(target_id, node)
  local force = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  local wForce = wobble(force, 0.04, 0, 1)
  local wHardness = wobble(hardness, 0.05, 0, 1)
  local wPosition = wobble(wl("voice").position(voice_id), 0.07, 0.01, 0.99)
  -- §2.6, and the pitch half of the wobble above: every field cabled to this
  -- voice takes a step and the new pitch is sent *before* the mallet, so the
  -- strike lands on the note the field just chose. a voice with no field
  -- still gets a few cents of per-strike detune out of this.
  grove.on_strike(voice_id)
  bridge.strike(voice.index - 1, wForce, wHardness, wPosition)
  state.flash(target_id, force)

  -- the O socket speaks. queued rather than walked here and now: the strike
  -- is itself downstream of a pulse, so a lap of any feedback loop the player
  -- has patched costs one scheduler tick, exactly like every other lap.
  local out_id = voice_id .. ".out"
  if patch.degree(out_id) > 0 then
    state.flash(out_id, wForce)
    wl("rambler").post_source(out_id, wForce)
  end
end

-- -> M: "a pulse chokes it" (§2.2). a momentary duck on the voice, depth from
-- edge gain x pulse weight, length from the socket's own balance knob. the
-- envelope itself lives in SC -- Lua only says when and how hard, per §7.2.
HANDLERS["node:mod"] = function(source_id, target_id, edge, weight)
  local node = topology.get(target_id)
  local voice = topology.get(node.voice)
  local curve = node_char(target_id, node)
  local depth = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  local wDepth = wobble(depth, 0.04, 0, 1)
  local wTime = wobble(0.08 + curve * 0.5, 0.03, 0.01, 4)
  bridge.voice_choke(voice.index - 1, wDepth, wTime)
  state.flash(target_id, depth)
end

-- -> P: a pulse re-rolls the voice's pitch without striking it. every field
-- cabled to that socket steps, and the voice is retuned -- so a line can move
-- on a clock of its own instead of only on the beats that play it.
HANDLERS["node:pitch"] = function(source_id, target_id, edge, weight)
  local node = topology.get(target_id)
  local w = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  grove.step_voice(node.voice, w)
  state.flash(target_id, w)
end

-- -> O: nothing. the out socket is a source; a pulse arriving at one is a
-- patch that means nothing, not an error.
HANDLERS["node:out"] = function() end

-- -> G: §2.7b. a G cell has no separate T socket -- the cell itself is the
-- trigger -- so this is node:trig's strike, refractory and all, collapsed
-- onto one id. it also answers out of that same id, a tick later and
-- excluding the cable it arrived on, exactly the way a voice's O socket
-- answers out of a different one: that is what lets a G cell still sit in a
-- chain the way the R cell it replaced did.
HANDLERS["G"] = function(source_id, target_id, edge, weight)
  local cell = topology.get(target_id)
  local now = util.time()
  local since = now - (last_strike[target_id] or -1)
  if since >= 0 and since < VOICE_REFRACTORY then return end
  last_strike[target_id] = now

  local force = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  local wForce = wobble(force, 0.04, 0, 1)
  bridge.g_strike(cell.index - 1, wForce)
  state.flash(target_id, wForce)

  if patch.degree(target_id) > 1 then
    wl("rambler").post_source(target_id, wForce, source_id)
  end
end

local DEFAULT_GATE_DUR = 0.15

-- -> S: "an S cell is continuous until a pulse is cabled into it. a pulse
-- cable turns the exciter into an enveloped grain, fired by that pulse"
-- (§2.4). exciter.lua sets the `gated` flag on the cable's existence; this
-- only fires the grain itself.
HANDLERS["S"] = function(source_id, target_id, edge, weight)
  local cell = topology.get(target_id)
  local amp = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  local wAmp = wobble(amp, 0.04, 0, 1)
  local wDur = wobble(DEFAULT_GATE_DUR, 0.02, 0.02, 4)
  bridge.exciter_gate(cell.index, wDur, wAmp)
  state.flash(target_id, amp)
end

-- -> F: a pulse steps the pitch field (§6's F column). the field moves on its
-- own clock rather than on whatever is being struck, which is how you get a
-- melody that is not locked to the rhythm playing it. an F cell never emits a
-- pulse, so nothing here can feed back round into itself.
HANDLERS["F"] = function(source_id, target_id, edge, weight)
  local w = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  grove.step(target_id, w, source_id)
end

-- -> H: "pulse enters the lattice and diffuses" (§6). heartwood.lua walks it
-- from there; everything this has to decide is where it goes in and how hard.
HANDLERS["H"] = function(source_id, target_id, edge, weight)
  local w = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  heartwood.inject(target_id, w, source_id)
end

-- -> C: nothing, and deliberately.
--
-- an earlier version restarted the climate's cycle here, so that a slow gait
-- cabled to one would begin its long shape on a downbeat. it does not
-- survive contact with the panel: cables are undirected, so the *ordinary*
-- way to use a climate cell -- cable it to a pulse-maker so the weather walks
-- that cell's rate -- also points that pulse-maker's output back at the
-- climate, and a gait running at a few Hz then resets a six-second shape
-- thirty times a second. the feature was worth one bar of novelty; the trap
-- was worth an unusable cell.
--
-- so a climate has no pulse input at all, and a C<->D cable means exactly one
-- thing in both directions: the weather moves that cell's knob.
HANDLERS["C"] = function() end

-- fires when `source_id` speaks and has a cable to `target_id`. also the path
-- a pulse *emerging* from the lattice takes, with the H node standing in for
-- the source cell.
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
-- resolves a cabled pair to zero or more SC-side patch specs.

-- S -> a voice's M socket: the stream lands on that voice's single modulation
-- input, and the socket's own balance knob decides what it does when it gets
-- there (inject into the resonator, or bend the body). the other three
-- sockets take no stream: T and P are pulse-only, and O is an output.
local function s_to_mod_spec(s, node, gain)
  if node.role ~= "mod" then return nil end
  local voice = topology.get(node.voice)
  return {
    kind = "aa",
    src = bridge.bus("exc", s.index),
    dst = bridge.bus("mod_in", voice.index - 1),
    gain = gain,
  }
end

-- H -> a voice's M socket: "lattice returns to it" (§6).
local function h_to_mod_spec(h, node, gain)
  if node.role ~= "mod" then return nil end
  local voice = topology.get(node.voice)
  return {
    kind = "aa",
    src = bridge.bus("heart_out", h.index),
    dst = bridge.bus("mod_in", voice.index - 1),
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
-- like S<->S -- the source feeds the lattice, and what the lattice makes of
-- it comes back as colour on the exciter.
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

-- the O socket's three continuous destinations. these are the cables that
-- were not possible before the re-cut: one voice ringing another, a voice
-- colouring an exciter, a voice pouring itself into the wood.
local function out_specs(node, other, edge, out)
  local v = topology.get(node.voice).index - 1
  local src = bridge.bus("voice_out", v)
  if other.type == "node" then
    if other.role == "mod" then
      table.insert(out, {
        kind = "aa", src = src,
        dst = bridge.bus("mod_in", topology.get(other.voice).index - 1),
        gain = edge.gain,
      })
    end
  elseif other.type == "S" then
    table.insert(out, {
      kind = "ak", src = src,
      dst = bridge.bus("colour_mod", other.index), gain = edge.gain,
    })
  elseif other.type == "H" then
    table.insert(out, {
      kind = "aa", src = src,
      dst = bridge.bus("heart_in", other.index), gain = edge.gain,
    })
  end
end

local function specs_for(edge)
  local a, b = topology.get(edge.a), topology.get(edge.b)
  local out = {}
  if not a or not b then return out end

  -- the matrix is symmetric in the endpoints, so each pair is written once
  -- and `ordered` finds it whichever way round the cable was drawn.
  local function ordered(ta, tb)
    if a.type == ta and b.type == tb then return a, b end
    if b.type == ta and a.type == tb then return b, a end
    return nil
  end

  -- an O socket is a source whichever end of the cable it is on, and it is
  -- the only socket that is, so it is resolved before the type matrix.
  local function out_socket(x, y)
    if x.type == "node" and x.role == "out" then
      -- a one-way cable a->b only sends from a (§3). two O sockets cabled to
      -- each other is a patch with no meaning; nothing here gives it one.
      if (not edge.oneway) or edge.a == x.id then
        out_specs(x, y, edge, out)
      end
      return true
    end
    return false
  end
  local handled = out_socket(a, b)
  handled = out_socket(b, a) or handled
  if handled then return out end

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
    local spec = s_to_mod_spec(x, y, edge.gain)
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
    local spec = h_to_mod_spec(x, y, edge.gain)
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
