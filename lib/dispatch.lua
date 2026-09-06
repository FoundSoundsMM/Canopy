-- dispatch.lua
-- the §6 type-interaction matrix: what a cable *means*, given the pair of
-- endpoint types. two halves, because pulses and streams are delivered on
-- entirely different clocks:
--
-- `on_pulse` -- event-driven, fires when a pulse-carrying cell speaks. it
-- covers everything a pulse can land on: a voice (always a strike -- the
-- socket collapse dropped the discrete choke gesture, see below), a GVOICE
-- cell (strike, same as a voice), a GUST cell (play its note, §2.11), a
-- Sample cell (play its recording, §2.5) and an E cell (fire a grain).
-- pulse-cell to pulse-cell traffic (D/R/TM) never comes here -- that is rambler's inbox,
-- because it is coupling rather than delivery. a CLOCK cell never receives
-- one either: it is a pure source, the same shape climate used to be.
-- neither does an O cell -- it is a source's destination, not something with
-- a reaction of its own.
--
-- `resync_matrix` -- graph-driven, not event-driven: continuous pairs are
-- just live SC synths for as long as the cable exists, so there is no
-- per-pulse Lua work -- only "does this synth exist and does its gain match",
-- checked whenever patch.lua reports a change.
--
-- the voice socket collapse: four sockets (T/P/M/O) become one cable
-- endpoint per voice, and what a cable does is decided entirely by what's at
-- the other end -- a pulse always strikes; a stream (an exciter, a gust, an
-- LFO on "signal") always feeds the mod path; a field or TM cabled in tunes
-- it (unchanged, handled in grove.lua/tm.lua, never through here); and cabling to an Output row cell
-- is the only way a voice's own audio is ever heard. discrete choke is gone
-- -- there is no socket left to carry the distinction -- but the voice
-- answers into whatever it's cabled to the instant it's struck, same as
-- always, and that is still how voice<->voice pulse feedback happens.
--
-- both halves fall through silently for pairs with no handler.

local topology  = wl("topology")
local state     = wl("state")
local bridge    = wl("bridge")
local patch     = wl("patch")
local grove     = wl("grove")

local dispatch = {}

-- a real drum head cannot be re-struck instantly, and neither can this one.
-- it is a sound-design detail and it is also the safety rail on every
-- feedback path a cable can make: a voice cabled back round into its own
-- point is a legal, interesting patch, and this is what stops it from being
-- a 500 Hz machine gun.
local VOICE_REFRACTORY = 0.028

local last_strike = {}  -- voice/GVOICE id -> util.time() of the last one that landed

-- organic-rhythm addendum: real hands never land twice identically. every
-- pulse-triggered audio event below gets a small parameter wobble (force,
-- hardness, strike position, grain amp/dur each move a few percent per hit)
-- on top of the edge-gain/weight shaping that was already there.
local function wobble(v, amt, lo, hi)
  return util.clamp(v + (math.random() * 2 - 1) * amt, lo, hi)
end

local HANDLERS = {}

-- -> a voice: every pulse strikes it now, regardless of source. force = edge
-- gain (unchanged), scaled by the pulse's own weight so a Shuck thud and an
-- echo tail's sixth repeat do not land identically. force/hardness/position
-- each get a small per-hit wobble -- no two strikes land quite the same. the
-- voice answers out of its own point a tick later, so anything cabled there
-- (including an Output cell, including itself by way of another cell) hears
-- that it was hit.
local function strike_voice(voice_id, edge, weight)
  local voice = topology.get(voice_id)
  local now = util.time()
  -- `>= 0` as well as `< refractory`: a clock that has gone backwards under
  -- us (a reload, a test harness rewinding its virtual time) must read as
  -- "long ago" rather than latch the voice silent forever.
  local since = now - (last_strike[voice_id] or -1)
  if since >= 0 and since < VOICE_REFRACTORY then return end
  last_strike[voice_id] = now

  local hardness = state.get_vparam(voice_id, "hardness", 0.5)
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
  state.flash(voice_id, force)

  -- the voice answers. queued rather than walked here and now: the strike is
  -- itself downstream of a pulse, so a lap of any feedback loop the player
  -- has patched costs one scheduler tick, exactly like every other lap.
  if patch.degree(voice_id) > 1 then
    wl("rambler").post_source(voice_id, wForce, nil)
  end
end

-- every pulse strikes a voice, whatever the source type -- strike_voice
-- never reads it. keyed as a single "voice" entry, not one alias per source
-- type: an explicit list is one omission away from a source type silently
-- doing nothing when it lands on a voice, which is exactly what happened to
-- the old heartwood family before this was simplified. every source calls
-- dispatch.on_pulse the same way, and there is no reason a voice should
-- treat one arrival differently from another.
HANDLERS["voice"] = function(source_id, target_id, edge, weight)
  strike_voice(target_id, edge, weight)
end

-- -> a GVOICE cell: §2.7b, unchanged. a GVOICE cell has no separate socket --
-- the cell itself is the trigger -- so this is the same strike, refractory
-- and all, collapsed onto one id, and it answers out of that same id a tick
-- later, excluding the cable it arrived on.
HANDLERS["GVOICE"] = function(source_id, target_id, edge, weight)
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

-- -> a GUST cell: §2.11, the same shape as a GVOICE cell's -- the cell is
-- the trigger, so a pulse landing on it plays its note, and it answers out
-- of that same id a tick later, excluding the cable the pulse arrived on.
-- the refractory is gust.lua's own and much shorter than a drum head's: a
-- gust's attack is seconds long, so retriggering one part-way up its swell
-- is a musical thing to do rather than a machine-gun to be guarded against,
-- and the engine lags the restart so it lifts rather than clicks.
HANDLERS["GUST"] = function(source_id, target_id, edge, weight)
  local force = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  if not wl("gust").play(target_id, wobble(force, 0.04, 0, 1)) then return end

  if patch.degree(target_id) > 1 then
    wl("rambler").post_source(target_id, force, source_id)
  end
end

local DEFAULT_GATE_DUR = 0.15

-- -> E: "a stream cell is continuous until a pulse is cabled into it. a pulse
-- cable turns it into an enveloped grain, fired by that pulse" (§2.4,
-- unchanged, renamed from S). exciter.lua sets the `gated` flag on the
-- cable's existence; this only fires the grain itself.
HANDLERS["E"] = function(source_id, target_id, edge, weight)
  local cell = topology.get(target_id)
  local amp = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  local wAmp = wobble(amp, 0.04, 0, 1)
  local wDur = wobble(DEFAULT_GATE_DUR, 0.02, 0.02, 4)
  bridge.exciter_gate(cell.index, wDur, wAmp)
  state.flash(target_id, amp)
end

-- -> F: a pulse steps the pitch field (§2.6, unchanged). an F cell never
-- emits a pulse, so nothing here can feed back round into itself.
HANDLERS["F"] = function(source_id, target_id, edge, weight)
  local w = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  grove.step(target_id, w, source_id)
end

-- -> a Sample cell: §2.5, play its recording from the top under that cell's
-- own slow attack and fall. it does not answer with a pulse of its own the
-- way a drum or a gust does -- a fifteen-second swell is not an event
-- anything downstream could sensibly be timed against, and a family with no
-- answering pulse cannot become half of a feedback loop either.
HANDLERS["SMP"] = function(source_id, target_id, edge, weight)
  local force = util.clamp(math.abs(edge.gain) * (weight or 1), 0, 1)
  wl("sample").play(target_id, wobble(force, 0.04, 0, 1))
end

-- -> a clock cell: nothing. it is a pure source -- the same "an earlier
-- version restarted the cycle here and it did not survive contact with the
-- panel" reasoning climate used to carry (see docs/canopy-spec.md's history):
-- cables are undirected, so anything that made a pulse mean something to a
-- clock cell would fire on the return leg of the ordinary Clock->T cable.
HANDLERS["C"] = function() end

-- -> an Output cell: nothing. it is a destination for continuous audio, not
-- something with a discrete reaction -- a pulse landing on one is a patch
-- that means nothing, not an error (same shape the old O socket's node:out
-- handler had).
HANDLERS["O"] = function() end

-- -> an LFO cell: nothing. §2.12's sine sources are pure, free-running
-- continuous sources, the same shape a clock cell is on the pulse side --
-- there is nothing here for a pulse arriving down a cable to do.
HANDLERS["LFO"] = function() end

-- §2.9b the gates. a Clock cell set to High (lib/clockcell.lua) does not
-- pulse; it holds every cell it is cabled to open for as long as it is set
-- that way. this is the level version of HANDLERS above -- one entry per
-- family that can sound, saying what "held open" means to it -- and, like
-- HANDLERS, a type missing from the table is a type for which the answer is
-- "nothing", which is not an error.
--
-- the four that are here are the four with an envelope to hold. an exciter
-- is deliberately absent: it free-runs unless a trigger cell gates it
-- (exciter.lua's GATING_TYPES, which a clock cell has never been in), so it
-- is already doing exactly what a held cell does. so are the fields, the
-- registers and the transforms, which have no sound of their own at all.
local GATES = {}

GATES["voice"] = function(cell, on)
  bridge.voice_hold(cell.index - 1, on)
end

GATES["GVOICE"] = function(cell, on)
  bridge.g_hold(cell.index, on)
end

GATES["GUST"] = function(cell, on)
  bridge.gust_hold(cell.index, on)
end

GATES["SMP"] = function(cell, on)
  bridge.smp_hold(cell.index, on)
end

-- hold `target_id` open, or let it go. clockcell.resync_gates is the only
-- caller, and it only calls on a change -- a gate is a level, so re-sending
-- the one it is already at is noise on the wire.
function dispatch.set_gate(target_id, on)
  local cell = topology.get(target_id)
  if not cell then return false end
  local f = GATES[cell.type]
  if not f then return false end
  f(cell, on and true or false)
  return true
end

-- fires when `source_id` speaks and has a cable to `target_id`. also the path
-- a pulse *emerging* from the lattice takes, with the H node standing in for
-- the source cell.
function dispatch.on_pulse(source_id, target_id, edge, weight)
  local target = topology.get(target_id)
  if not target then return end

  local handler = HANDLERS[target.type]
  if handler then
    handler(source_id, target_id, edge, weight)
  end
end

-- continuous matrix (§6, the non-pulse pairs) ------------------------------
-- resolves a cabled pair to zero or more SC-side patch specs.

-- E -> a voice: the stream lands on that voice's single point unconditionally
-- now -- there is no socket left to gate it on.
local function e_to_voice_spec(e, voice, gain)
  return {
    kind = "aa",
    src = bridge.bus("exc", e.index),
    dst = bridge.bus("mod_in", voice.index - 1),
    gain = gain,
  }
end

-- a voice <-> an E cell carries two different meanings at once, one per
-- direction -- not the same transformation mirrored both ways the way
-- voice<->voice or H<->H are, so each half gets its own one-way gate. a
-- one-way cable a->b only sends from a (§3): if the voice is `a`, only its
-- own colouring of the exciter applies; if the exciter is `a`, only its
-- feed into the voice's mod path does.
local function voice_to_e_specs(voice, e, edge, out)
  if (not edge.oneway) or edge.a == voice.id then
    table.insert(out, {
      kind = "ak", src = bridge.bus("voice_out", voice.index - 1),
      dst = bridge.bus("colour_mod", e.index), gain = edge.gain,
    })
  end
  if (not edge.oneway) or edge.a == e.id then
    table.insert(out, e_to_voice_spec(e, voice, edge.gain))
  end
end

-- a voice <-> a voice: fully symmetric now that each side is one point.
-- each voice's own audio feeds the other's mod path -- a one-way cable only
-- sends from the a-side (§3).
local function voice_to_voice_specs(a, b, edge, out)
  local function link(from, to)
    table.insert(out, {
      kind = "aa",
      src = bridge.bus("voice_out", from.index - 1),
      dst = bridge.bus("mod_in", to.index - 1),
      gain = edge.gain,
    })
  end
  link(a, b)
  if not edge.oneway then link(b, a) end
end

-- anything continuous into a gust's cross-mod input (§2.11). the receiving
-- cell's own Cross knob decides how deeply it is heard, so this is a plain
-- pass at the cable's gain and nothing more -- the panel's usual division of
-- labour, where the cable says how much and the cell says what of.
local function to_gust_mod_spec(src_bus, gu, gain)
  return {
    kind = "aa", src = src_bus,
    dst = bridge.bus("gust_mod", gu.index - 1), gain = gain,
  }
end

-- a gust <-> a gust: the Deerhorn gesture, and the reason a gust has a Cross
-- knob at all. each one's audio lands on the other's mod input, where it
-- bends pitch and opens the fold at once -- so the pair is genuinely
-- cross-modulating rather than merely summed. symmetric, like voice<->voice;
-- a one-way cable only sends from the a-side (§3), which is how you get one
-- gust colouring another without being coloured back.
local function gust_to_gust_specs(a, b, edge, out)
  local function link(from, to)
    table.insert(out, to_gust_mod_spec(bridge.bus("gust_out", from.index - 1), to, edge.gain))
  end
  link(a, b)
  if not edge.oneway then link(b, a) end
end

-- a gust <-> a voice: two different meanings, one per direction, gated
-- independently the way voice<->E already is. the gust colours the voice's
-- mod path; the voice colours the gust's core.
local function gust_to_voice_specs(gu, v, edge, out)
  if (not edge.oneway) or edge.a == gu.id then
    table.insert(out, {
      kind = "aa", src = bridge.bus("gust_out", gu.index - 1),
      dst = bridge.bus("mod_in", v.index - 1), gain = edge.gain,
    })
  end
  if (not edge.oneway) or edge.a == v.id then
    table.insert(out, to_gust_mod_spec(bridge.bus("voice_out", v.index - 1), gu, edge.gain))
  end
end

-- a gust <-> an E cell: the exciter's texture into the gust's core, and the
-- gust's own tone riding the exciter's colour. same two-halves-one-cable
-- shape voice<->E has, and for the same reason.
local function gust_to_e_specs(gu, e, edge, out)
  if (not edge.oneway) or edge.a == e.id then
    table.insert(out, to_gust_mod_spec(bridge.bus("exc", e.index), gu, edge.gain))
  end
  if (not edge.oneway) or edge.a == gu.id then
    table.insert(out, {
      kind = "ak", src = bridge.bus("gust_out", gu.index - 1),
      dst = bridge.bus("colour_mod", e.index), gain = edge.gain,
    })
  end
end

-- §2.12 an LFO -> a voice, with Param on "signal": unconditional and
-- one-directional, the same shape e_to_voice_spec has -- an LFO has no mod
-- input of its own for the voice's audio to land back on.
local function lfo_to_voice_spec(l, voice, gain)
  return {
    kind = "aa",
    src = bridge.bus("lfo_out", l.index),
    dst = bridge.bus("mod_in", voice.index - 1),
    gain = gain,
  }
end

-- an LFO -> an E cell: lands on the same colour-mod bus every other source
-- feeding an exciter's colour uses, so a sine there behaves exactly like a
-- gust's or a voice's own audio does -- one shared, well-understood knob.
local function lfo_to_e_spec(l, e, gain)
  return {
    kind = "ak",
    src = bridge.bus("lfo_out", l.index),
    dst = bridge.bus("colour_mod", e.index),
    gain = gain,
  }
end

-- an LFO -> a gust: lands on the cross-mod input, exactly like a second gust
-- would (to_gust_mod_spec, defined above) -- the receiving cell's own Cross
-- knob decides how deeply it is heard.
local function lfo_to_gust_spec(l, gu, gain)
  return to_gust_mod_spec(bridge.bus("lfo_out", l.index), gu, gain)
end

-- a source cell's own audio into an Output row cell -- the only way anything
-- is ever heard. position along the row sets pan (topology's `pan` field);
-- the gain is this cable's own, so patching one source into several O cells
-- spreads it across the stereo field, each copy at its own level.
local function to_output_spec(src_bus, o, gain)
  return {kind = "aa", src = src_bus, dst = bridge.bus("out", o.index), gain = gain}
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

  local x, y

  x, y = ordered("voice", "voice")
  if x then
    voice_to_voice_specs(x, y, edge, out)
    return out
  end

  x, y = ordered("voice", "O")
  if x then
    table.insert(out, to_output_spec(bridge.bus("voice_out", x.index - 1), y, edge.gain))
    return out
  end

  x, y = ordered("GVOICE", "O")
  if x then
    table.insert(out, to_output_spec(bridge.bus("gvoice_out", x.index - 1), y, edge.gain))
    return out
  end

  -- §2.5 a sample cell. this used to be the second family that mixed itself
  -- (the engine panned it by its own seat), and it is an ordinary cabled
  -- source now: the Out cell is the only route to a speaker and the only
  -- thing that decides where in the image it lands.
  x, y = ordered("SMP", "O")
  if x then
    table.insert(out, to_output_spec(bridge.bus("smp_out", x.index), y, edge.gain))
    return out
  end

  -- a gust is the one source left reaching the speakers without a cable
  -- (§2.11: the engine pans it by its own column and mixes it in). an
  -- Output cable is therefore an *addition* rather than the only route --
  -- a second, deliberately-placed copy at whatever gain and pan position
  -- the player wants, alongside the automatic one.
  x, y = ordered("GUST", "O")
  if x then
    table.insert(out, to_output_spec(bridge.bus("gust_out", x.index - 1), y, edge.gain))
    return out
  end

  x, y = ordered("GUST", "GUST")
  if x then
    -- ordered() may have swapped them and the one-way rule is written in
    -- terms of the edge's own a/b, so re-derive from those (same as H<->H).
    gust_to_gust_specs(topology.get(edge.a), topology.get(edge.b), edge, out)
    return out
  end

  x, y = ordered("GUST", "voice")
  if x then
    gust_to_voice_specs(x, y, edge, out)
    return out
  end

  x, y = ordered("GUST", "E")
  if x then
    gust_to_e_specs(x, y, edge, out)
    return out
  end

  x, y = ordered("E", "O")
  if x then
    table.insert(out, to_output_spec(bridge.bus("exc", x.index), y, edge.gain))
    return out
  end

  x, y = ordered("voice", "E")
  if x then
    voice_to_e_specs(x, y, edge, out)
    return out
  end

  x, y = ordered("E", "E")
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

  -- §2.12 the LFOs. an LFO pointed at a named knob on the cell at the other
  -- end (lfo.lua's Target/Param rows) is not an audio cable at all -- Lua
  -- moves that knob directly, a few dozen times a second -- so there is
  -- nothing here to build, and building it anyway would make the same cable
  -- heard twice. asked once, before any of the pairs below.
  if a.type == "LFO" and wl("lfo").modulates(a.id, b.id) then return out end
  if b.type == "LFO" and wl("lfo").modulates(b.id, a.id) then return out end

  -- otherwise they are pure, one-directional continuous sources -- one spec
  -- each, the same shape an exciter already has into a voice.
  x, y = ordered("LFO", "O")
  if x then
    table.insert(out, to_output_spec(bridge.bus("lfo_out", x.index), y, edge.gain))
    return out
  end

  x, y = ordered("LFO", "voice")
  if x then
    table.insert(out, lfo_to_voice_spec(x, y, edge.gain))
    return out
  end

  x, y = ordered("LFO", "E")
  if x then
    table.insert(out, lfo_to_e_spec(x, y, edge.gain))
    return out
  end

  x, y = ordered("LFO", "GUST")
  if x then
    table.insert(out, lfo_to_gust_spec(x, y, edge.gain))
    return out
  end

  return out
end

-- sc_patch_id -> the spec last sent for it, so a resync only sends what
-- actually changed (add/free are audible clicks; gain is cheap to repeat
-- but there is no reason to).
local active = {}

-- called whenever patch.lua's graph changes. a full recompute is fine here
-- (small cable count, user-driven, not per-tick) -- unlike on_pulse, nothing
-- about this needs to be fast.
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
