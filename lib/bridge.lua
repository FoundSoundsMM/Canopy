-- bridge.lua
-- thin wrapper around Engine_Canopy's OSC commands (§7.2: "SC owns every
-- sample of audio"; this is just the Lua-side call surface, one function
-- per command in §8's list, so callers never touch `engine.*` directly).
--
-- throttling and the meter-cache readback (§7.4) are phase 7 concerns and
-- aren't implemented yet.

local bridge = {}

-- offsets into Engine_Canopy.sc's single `patchBus` (see the classvar block
-- at the top of that file). dispatch.lua resolves a cabled pair's endpoints
-- to {bus name, per-cell index} and calls bridge.bus() to get the absolute
-- number patch_add/patch_gain/patch_free expect. keep the base/n pairs here
-- identical to the .sc file's excBase/modInBase/etc.
--
-- the grid overhaul's socket collapse means a voice's own audio tap
-- (`voice_out`) is now its only cable endpoint's continuous half, reached
-- from `mod_in` (another voice, unconditionally now) and from `out` (the
-- Output row -- the only way any of this is ever heard, since nothing
-- routes there automatically any more). `gvoice_out` is new for the same
-- reason: the six percussion cells used to reach the speakers through a
-- fixed always-on mix; now they need an addressable tap of their own, same
-- shape as a voice's.
bridge.BUS = {
  exc        = {base = 0,  n = 6},  -- E cell raw outputs
  colour_mod = {base = 6,  n = 6},  -- per-E colour cross-mod sum
  mod_in     = {base = 12, n = 4},  -- per-voice mod-path input sum
  voice_out  = {base = 16, n = 4},  -- per-voice audio tap
  gvoice_out = {base = 20, n = 6},  -- per-GVOICE (percussion) audio tap
  heart_in   = {base = 26, n = 4},  -- per-H lattice injection sum
  heart_out  = {base = 30, n = 4},  -- per-H lattice emergence tap
  out        = {base = 34, n = 16}, -- the Output row's 16 fixed-pan buses
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

-- §5.5 the sound editor's eight knobs. these are the individual resonator
-- parameters the old Grain macro used to morph together behind your back;
-- with a page of its own per voice there is no reason to hide them.
function bridge.voice_decay(voice_index, seconds)
  engine.voice_decay(voice_index, seconds)
end

function bridge.voice_structure(voice_index, v)
  engine.voice_structure(voice_index, v)
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

-- §5.5 Bend: a pitch envelope on top of Tune, fired the same instant as the
-- strike. 0 is a no-op; turned up, the voice starts sharp and glides down
-- to its tuned pitch over a short, fixed time (see Engine_Canopy.sc).
function bridge.voice_bend(voice_index, v)
  engine.voice_bend(voice_index, v)
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

-- the collapsed point's stream half: one balance knob (the sound page's
-- Balance row) deciding what a stream landing on this voice does -- 0
-- injects it into the resonator as excitation, 1 lands it on the body as
-- damping/brightness/structure bend, and everything between is a mix of the
-- two. discrete choke is gone with the socket that used to carry it -- every
-- pulse strikes now (see dispatch.lua).
function bridge.voice_mod(voice_index, balance)
  engine.voice_mod(voice_index, balance)
end

-- the voice's own audio tap onto its `voice_out` bus runs at a fixed level --
-- there is no separate output-level knob any more, since the Output row's
-- own cable gain is what decides how loud a voice is at each pan position it
-- reaches (or whether it's heard at all).

-- FM addendum: voice_fm's ratio/depth are engine-level knobs, not (yet) a
-- patchable cable -- see docs/canopy-spec.md §8. depth=0 is a no-op.
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

-- §2.7b percussion cells: the same shape as the voice_* commands above, six
-- knobs instead of eight -- a G cell has no sockets, so there is no glide,
-- drift, choke, mod balance, tap level or FM to forward, only the strike and
-- the sound page's own five.
function bridge.g_strike(index, force)
  engine.g_strike(index, force)
end

function bridge.g_pitch(index, hz)
  engine.g_pitch(index, hz)
end

function bridge.g_decay(index, seconds)
  engine.g_decay(index, seconds)
end

function bridge.g_tone(index, v)
  engine.g_tone(index, v)
end

function bridge.g_punch(index, v)
  engine.g_punch(index, v)
end

function bridge.g_drive(index, v)
  engine.g_drive(index, v)
end

function bridge.g_amp(index, v)
  engine.g_amp(index, v)
end

-- §2.4 exciter cells: lazy on/off, Colour (E2), the gated flag (has this S
-- cell got an incoming pulse cable?), and the grain trigger itself.
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

function bridge.master_level(v)
  engine.master_level(v)
end

-- the always-on Rain.wav ambience (§4.1). rain_load fires once at init with
-- the sample's absolute path; the engine loads it async and only starts
-- \wl_rain once it's ready. rain_volume/rain_excite are ordinary always-on
-- synth sets (the fx stage and every voice exist from alloc), so they work
-- immediately either way -- the bus they read from is just silent until
-- \wl_rain exists to write to it.
function bridge.rain_load(path)
  engine.rain_load(path)
end

function bridge.rain_volume(v)
  engine.rain_volume(v)
end

function bridge.rain_excite(v)
  engine.rain_excite(v)
end

return bridge
