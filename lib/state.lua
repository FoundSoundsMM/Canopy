-- state.lua
-- shared runtime UI state: held cells, per-cell params, global macros,
-- screen view. kept separate from topology (static map) and patch (the
-- cable graph) so gridui/screenui can both read and mutate it directly.

local state = {}

-- the open settings page. tapping ANY cell puts its id in here and the screen
-- becomes that cell's parameter page; tapping it again (or K3) clears it and
-- the screen goes back to the global param page. it was `voice_edit` and only
-- voice/GVOICE/TM cells could fill it -- every other type had its settings
-- spread over modifier gestures instead. now every type has a page
-- (lib/cellparam.lua) and every type opens it the same way, so the field is
-- named for what it holds.
state.cell_edit = nil
state.vparam_focus = 1

-- §5.2b which of the two full-screen pages the encoders and the screen are
-- on when no cell page is open: "global" (the seven macros) or "mixer" (the
-- four soundscape loops, lib/mixer.lua). K3 goes to the mixer from anywhere,
-- K2 comes back -- and K3 from an open cell page goes to the mixer *and*
-- drops the cell's focus, so there is never a page hiding behind the mixer.
state.view = "global"
state.mparam_focus = 1

-- §4.1/§5.2 the global param page (nothing held, no voice page open): E1
-- walks gparam.PARAMS, E2/E3 nudge coarse/fine. replaced the network/wires
-- map -- see lib/gparam.lua.
state.gparam_focus = 1

-- §4.1 global macros. `swing` and `scatter` used to be one combined "Weather"
-- knob (low half swing, high half chaos/wildness); gparam.lua now exposes
-- them as independent params, so quantise.lua and every rhythm/field
-- "wildness" read in rambler.lua/grove.lua that used to share the one
-- weather value now reads `scatter` directly. (`scatter` was called `rain`
-- until the Rain.wav ambience -- now one of the mixer's four loops, see
-- lib/mixer.lua -- took that name for something literal.)
state.global = {
  swing = 0.8,       -- quantise.lua's swing() -- preserves the old default feel
  scatter = 0,       -- quantise.lua's chaos(), plus rhythm/field wildness
  bpm = 120,         -- transport tempo, mirrored onto the norns clock param
  scale_i = 0,       -- global pitch quantisation; 0 = free (grove.SCALES)
  drops = 0,         -- per-strike random pitch offset range
  decay_mult = 0.5,  -- global decay multiplier, 0.5 = x1 (voice.lua)
  pitch_offset = 0,  -- global transpose, semitones (grove.lua)
  level = 0.8,       -- K1+E3, and the mixer's fifth fader: master level
  -- §4.3: the ONE flag a freeze lives in, whether it came from K2 or from an
  -- external transport Stop. deliberately not two -- a separate record of
  -- "the transport says stopped" alongside "the gaits are frozen" is two
  -- things that can disagree, and the whole point is that they cannot.
  still = false,     -- K2, or an external transport Stop: freeze all gaits
  -- §4.1b the mixer's faders, keyed by mixer.LOOPS' `key`. the single
  -- `rain_volume` these replaced lived here too (as did `rain_excite`,
  -- which has no successor -- the loops are a dry mix only now).
  -- lib/mixer.lua owns the defaulting, so this starts empty rather than
  -- naming four loops this file has no other business knowing about.
  amb_level = {},    -- loop key -> dry level in the mix. all off by default.
  -- §2.11 the gusts' one shared delay line -- mix / time / feedback. same
  -- arrangement: lib/gust.lua owns the defaults and the ranges, this only
  -- holds the numbers so a PSET picks them up with everything else.
  gust_space = nil,
}

-- grid hold tracking
state.held = {}     -- ordered list of currently-held cell ids
state.held_t = {}   -- id -> util.time() at press

-- per-cell UI params, lazily defaulted. every one of these is a named row on
-- some cell type's settings page now (lib/cellparam.lua) rather than a
-- modifier gesture, but what they hold and who reads them is unchanged.
state.character = {}   -- id -> primary character value, player-set
state.decay = {}       -- id -> that sound's decay
state.gait = {}        -- D id -> gait key (the Gait row)
state.rooted = {}      -- D id -> locked to the norns clock? (the Clock row)
state.rule = {}        -- R id -> weave rule key (the Rule row)
state.mode = {}        -- F id -> pitch-field mode key (the Mode row)
state.snap = {}        -- F id -> quantised to the scale? (the Snap row)
state.vparam = {}      -- voice/GVOICE/TM/GUST id -> {key -> 0..1}

-- 0.5 is "whatever this sound's own default is"; the knob is symmetrical
-- around it in both directions. voice.lua and exciter.lua own the mapping
-- from this number to seconds -- state.lua stays ignorant of audio.
function state.get_decay(id)
  if state.decay[id] == nil then state.decay[id] = 0.5 end
  return state.decay[id]
end

-- which cell's decay a gesture on this one moves, or nil if it moves none.
-- the voice socket collapse means a voice's own point already carries its
-- decay directly -- there is no separate socket to forward through any more.
-- D, R, H, F and C cells have no sound to decay -- they make pulses, bend
-- them, diffuse energy, choose pitches and track the clock -- and their
-- E3-with-nothing-focused is deliberately inert rather than quietly storing
-- a number nothing reads. a GVOICE cell is a sound of its own, same as a
-- voice or an E cell -- and so is a GUST cell, whose Decay row is the fall
-- half of its envelope (§2.11).
local DECAY_TYPES = {voice = true, GVOICE = true, E = true, GUST = true}

function state.decay_target(cell)
  if not cell or not DECAY_TYPES[cell.type] then return nil end
  return cell.id
end

-- the player's own setting. this is what E2 moves and what the cell view's
-- bar draws.
function state.base_character(id, lo, hi)
  if state.character[id] == nil then
    lo, hi = lo or 0, hi or 1
    state.character[id] = lo + (hi - lo) * 0.5
  end
  return state.character[id]
end

-- what the cell actually runs on. every consumer reads through here.
function state.get_character(id, cell, lo, hi)
  return state.base_character(id, lo, hi)
end

-- gait/rooted default to topology's per-cell value on first read; the caller
-- passes it in so state.lua stays ignorant of the map.
function state.get_gait(id, default)
  if state.gait[id] == nil then state.gait[id] = default end
  return state.gait[id]
end

function state.get_rooted(id, default)
  if state.rooted[id] == nil then state.rooted[id] = default and true or false end
  return state.rooted[id]
end

-- the same shape for an R cell's rule (§2.7), an F cell's mode/snap pair
-- (§2.6) and a C cell's shape (§2.8), for the same reason.
function state.get_rule(id, default)
  if state.rule[id] == nil then state.rule[id] = default end
  return state.rule[id]
end

function state.get_mode(id, default)
  if state.mode[id] == nil then state.mode[id] = default end
  return state.mode[id]
end

function state.get_snap(id, default)
  if state.snap[id] == nil then state.snap[id] = default and true or false end
  return state.snap[id]
end

-- §5.5 the eight per-voice sound parameters, all stored 0..1. voice.lua owns
-- what each of them means in real units.
function state.get_vparam(voice_id, key, default)
  local t = state.vparam[voice_id]
  if not t then t = {}; state.vparam[voice_id] = t end
  if t[key] == nil then t[key] = default or 0.5 end
  return t[key]
end

function state.set_vparam(voice_id, key, v)
  local t = state.vparam[voice_id]
  if not t then t = {}; state.vparam[voice_id] = t end
  t[key] = util.clamp(v, 0, 1)
  return t[key]
end

-- fires when a cell's primary character (E2, or the weather moving under it)
-- changes, so voice.lua etc. can forward the new value to the engine without
-- gridui knowing about audio.
state._character_listeners = {}
function state.on_character_change(fn)
  table.insert(state._character_listeners, fn)
end
function state.notify_character_change(id)
  for _, fn in ipairs(state._character_listeners) do fn(id) end
end

-- the same shape for decay (E3 with no cable focused), so voice.lua and
-- exciter.lua can each forward the cells they own without gridui knowing
-- which of them a given id belongs to.
state._decay_listeners = {}
function state.on_decay_change(fn)
  table.insert(state._decay_listeners, fn)
end
function state.notify_decay_change(id)
  for _, fn in ipairs(state._decay_listeners) do fn(id) end
end

function state.is_held(id)
  for _, hid in ipairs(state.held) do
    if hid == id then return true end
  end
  return false
end

-- §5.2 network view bottom line: text of the most recent event.
-- once the scheduler is running, pulse traffic would otherwise overwrite a
-- patching message within a few milliseconds and you would never read it, so
-- a message can claim the line for `hold` seconds before anything else may
-- replace it. pulses claim it with no hold at all.
state.last_event = ""
state._event_t = 0
state._event_hold = 0

function state.set_event(text, hold)
  local now = util.time()
  if now - state._event_t < state._event_hold then return end
  state.last_event = text
  state._event_t = now
  state._event_hold = hold or 0
end

-- how long ago the current message landed. the global page reads this so a
-- message that has had its moment gives the line back to the hint rather than
-- sitting there for the rest of the session looking like live information.
function state.event_age()
  return util.time() - state._event_t
end

-- confirm-hold gestures (Regrow / Clearing), read by screenui for a progress readout
state.confirm = nil -- {label=, started=, duration=} or nil

-- §5.1 "signal magnitude through it" -- a decaying flash for any cell whose
-- pulse arrival is Lua-known (a socket strike/choke, a D->S grain firing),
-- the same flash-on-pulse-then-decay shape rambler.lua, weave.lua and
-- heartwood.lua each already keep for their own cells, just without a
-- dedicated per-cell object to hang it on. continuous audio-rate response --
-- a socket under a steady stream, S's own shimmer, a voice's amplitude
-- envelope -- still needs the metering back-channel (§7.4) and isn't lit by
-- this.
state.FLASH_DECAY = 0.12
state._flash = {} -- id -> {t=, w=}

function state.flash(id, weight)
  state._flash[id] = {t = util.time(), w = util.clamp(weight or 1, 0, 1)}
end

function state.flash_level(id, base)
  local f = state._flash[id]
  if not f then return base end
  local age = util.time() - f.t
  if age < 0 or age >= state.FLASH_DECAY then return base end
  local k = 1 - (age / state.FLASH_DECAY)
  return base + math.floor((15 - base) * k * f.w)
end

return state
