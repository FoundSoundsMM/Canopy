-- bridge.lua
-- thin wrapper around Engine_Woodland's OSC commands (§7.2: "SC owns every
-- sample of audio"; this is just the Lua-side call surface, one function
-- per command in §8's list, so callers never touch `engine.*` directly).
--
-- throttling and the meter-cache readback (§7.4) are phase 7 concerns and
-- aren't implemented yet.

local bridge = {}

-- offsets into Engine_Woodland.sc's single 54-channel `patchBus` (see the
-- classvar block at the top of that file). dispatch.lua resolves a cabled
-- pair's endpoints to {bus name, per-cell index} and calls bridge.bus() to
-- get the absolute number patch_add/patch_gain/patch_free expect. keep the
-- base/n pairs here identical to the .sc file's excBase/excInBase/etc.
bridge.BUS = {
  exc        = {base = 0,  n = 10}, -- S cell raw outputs
  exc_in     = {base = 10, n = 6},  -- per-voice Sap injection sum
  sway       = {base = 16, n = 6},  -- per-voice Sway stream sum
  moss       = {base = 22, n = 6},  -- per-voice Moss stream sum
  colour_mod = {base = 28, n = 10}, -- per-S colour cross-mod sum
  heart_in   = {base = 38, n = 8},  -- per-H lattice injection sum
  heart_out  = {base = 46, n = 8},  -- per-H lattice emergence tap
}

function bridge.bus(name, index)
  return bridge.BUS[name].base + index
end

function bridge.strike(voice_index, force, hardness, position)
  engine.strike(voice_index, force, hardness, position)
end

function bridge.voice_pitch(voice_index, hz)
  engine.voice_pitch(voice_index, hz)
end

-- §2.6 grove: portamento on voice_pitch. a discrete field wants this near
-- zero so a retune lands on the strike; a continuous one wants it long, so
-- the voice is heard sliding rather than stepping.
function bridge.voice_glide(voice_index, seconds)
  engine.voice_glide(voice_index, seconds)
end

-- §2.6 grove: the always-on detune wander. `depth` is in semitones, `rate`
-- in Hz, `seed` only spreads the phase so no two voices breathe in step.
-- this is the one piece of pitch motion SC generates itself -- a few cents
-- of continuous drift is far too fine-grained to push over OSC.
function bridge.voice_drift(voice_index, depth, rate, seed)
  engine.voice_drift(voice_index, depth, rate, seed)
end

function bridge.voice_grain(voice_index, v)
  engine.voice_grain(voice_index, v)
end

-- §4.2 E3: the voice's resonator ring time, in seconds. voice.lua maps the
-- 0..1 knob to this around each voice's own default (topology's `decay`).
function bridge.voice_decay(voice_index, seconds)
  engine.voice_decay(voice_index, seconds)
end

function bridge.voice_damp(voice_index, v)
  engine.voice_damp(voice_index, v)
end

function bridge.voice_bright(voice_index, v)
  engine.voice_bright(voice_index, v)
end

function bridge.voice_pos(voice_index, v)
  engine.voice_pos(voice_index, v)
end

function bridge.voice_drive(voice_index, v)
  engine.voice_drive(voice_index, v)
end

function bridge.voice_amp(voice_index, v)
  engine.voice_amp(voice_index, v)
end

function bridge.voice_modes(voice_index, n)
  engine.voice_modes(voice_index, n)
end

-- §2.2 Moss: "a pulse chokes it". the duck envelope itself is in SC; this
-- only says when, how deep, and for how long.
function bridge.voice_choke(voice_index, depth, time)
  engine.voice_choke(voice_index, depth, time)
end

-- §2.2 stream-modulation half of Sap/Sway/Moss (as opposed to the
-- pulse-choke path voice_choke covers): each node's own E2 character.
function bridge.voice_sap(voice_index, level)
  engine.voice_sap(voice_index, level)
end

function bridge.voice_sway(voice_index, balance)
  engine.voice_sway(voice_index, balance)
end

function bridge.voice_moss(voice_index, curve)
  engine.voice_moss(voice_index, curve)
end

-- FM addendum: voice_fm's ratio/depth are engine-level knobs, not (yet) a
-- patchable cable -- see docs/woodland-spec.md §8. depth=0 is a no-op.
function bridge.voice_fm(voice_index, ratio, depth)
  engine.voice_fm(voice_index, ratio, depth)
end

-- the tuneable-pink-noise half of the same addendum: bipolar octave tune
-- and bandpass Q for the voice's own strike exciter, on top of hardness.
function bridge.voice_noise_tune(voice_index, v)
  engine.voice_noise_tune(voice_index, v)
end

function bridge.voice_noise_q(voice_index, v)
  engine.voice_noise_q(voice_index, v)
end

-- §2.4 exciter cells: lazy on/off, Colour (E2), the gated flag (has this S
-- cell got an incoming D cable?), and the D->S grain trigger itself.
function bridge.exciter_on(index)
  engine.exciter_on(index)
end

function bridge.exciter_off(index)
  engine.exciter_off(index)
end

function bridge.exciter_colour(index, v)
  engine.exciter_colour(index, v)
end

-- §4.2 E3, S-cell half: a plain multiplier on this exciter's grain envelope
-- and on whatever tail its own recipe has. exciter.lua owns the mapping.
function bridge.exciter_decay(index, scale)
  engine.exciter_decay(index, scale)
end

function bridge.exciter_gated(index, flag)
  engine.exciter_gated(index, flag and 1 or 0)
end

function bridge.exciter_gate(index, dur, amp)
  engine.exciter_gate(index, dur, amp)
end

-- FM addendum, S-cell half (see bridge.voice_fm above).
function bridge.exciter_fm(index, ratio, depth)
  engine.exciter_fm(index, ratio, depth)
end

-- §2.5 heartwood: per-node conductance (E2 while holding), which sets that
-- node's hop delay and loss on the continuous side. the discrete side's
-- copy of the same mapping lives in heartwood.lua.
function bridge.heart_conductance(index, v)
  engine.heart_conductance(index, v)
end

-- §7.3/§8 generic audio-rate patch matrix. `src`/`dst` are absolute
-- patchBus numbers -- callers build them with bridge.bus(). `kind` is "aa"
-- (straight pass) or "ak" (amplitude-follow into the target).
function bridge.patch_add(id, kind, src, dst, gain)
  engine.patch_add(id, kind, src, dst, gain)
end

function bridge.patch_gain(id, gain)
  engine.patch_gain(id, gain)
end

function bridge.patch_free(id)
  engine.patch_free(id)
end

function bridge.canopy(size, damp, mix)
  engine.canopy(size, damp, mix)
end

function bridge.master_level(v)
  engine.master_level(v)
end

return bridge
