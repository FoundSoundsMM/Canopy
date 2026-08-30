-- state.lua
-- shared runtime UI state: held cells, per-cell params, global macros,
-- screen view. kept separate from topology (static map) and patch (the
-- cable graph) so gridui/screenui can both read and mutate it directly.

local state = {}

-- §5.2-5.4 screen views (cycled with K3 when nothing is held)
state.views = {"network", "meters", "lexicon"}
state.view = "network"

function state.cycle_view()
  for i, v in ipairs(state.views) do
    if v == state.view then
      state.view = state.views[(i % #state.views) + 1]
      return
    end
  end
end

-- §4.1 global macros
state.global = {
  canopy = 0.3,   -- E1: reverb amount
  weather = 0.4,  -- E2: groove -- quantise -> swing -> chaos (see quantise.lua)
  bpm = 120,      -- E3: transport tempo, mirrored onto the norns clock param
  level = 0.8,    -- K1+E3: master level
  still = false,  -- K2: freeze all pulse gaits
}

-- grid hold tracking
state.held = {}     -- ordered list of currently-held cell ids
state.held_t = {}   -- id -> util.time() at press

-- per-cell UI params, lazily defaulted
state.focus = {}       -- id -> focused edge index (0 = ALL)
state.character = {}   -- id -> primary character value (E2)
state.character2 = {}  -- id -> secondary character value (K1+E2)
state.decay = {}       -- id -> that sound's decay (E3 when focus == ALL)
state.gait = {}        -- D id -> gait key (K1+E2 swaps it, §4.2)
state.rooted = {}      -- D id -> locked to the norns clock? (K1+tap, §2.3)
state.mode = {}        -- P id -> pitch-field mode key (K1+E2 swaps it, §2.6)
state.snap = {}        -- P id -> quantised to the scale? (K1+tap, §2.6)

function state.get_focus(id)
  if state.focus[id] == nil then state.focus[id] = 0 end
  return state.focus[id]
end

-- 0.5 is "whatever this sound's own default is"; the knob is symmetrical
-- around it in both directions. voice.lua and exciter.lua own the mapping
-- from this number to seconds -- state.lua stays ignorant of audio.
function state.get_decay(id)
  if state.decay[id] == nil then state.decay[id] = 0.5 end
  return state.decay[id]
end

-- which cell's decay a gesture on this one moves, or nil if it moves none.
-- a voice's four nodes are parts of that voice, not sounds of their own, so
-- the gesture on any of them reaches the voice's resonator. D, H and P cells
-- have no sound to decay -- they make pulses, diffuse energy and choose
-- pitches -- and their E3-with-nothing-focused is deliberately inert rather
-- than quietly storing a number nothing reads.
local DECAY_TYPES = {voice = true, node = true, S = true}

function state.decay_target(cell)
  if not cell or not DECAY_TYPES[cell.type] then return nil end
  if cell.type == "node" then return cell.voice end
  return cell.id
end

function state.get_character(id, cell, lo, hi)
  if state.character[id] == nil then
    lo, hi = lo or 0, hi or 1
    state.character[id] = lo + (hi - lo) * 0.5
  end
  return state.character[id]
end

function state.get_character2(id)
  if state.character2[id] == nil then state.character2[id] = 0.5 end
  return state.character2[id]
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

-- same shape for a P cell's mode/snap pair (§2.6), for the same reason.
function state.get_mode(id, default)
  if state.mode[id] == nil then state.mode[id] = default end
  return state.mode[id]
end

function state.get_snap(id, default)
  if state.snap[id] == nil then state.snap[id] = default and true or false end
  return state.snap[id]
end

-- fires when a cell's primary character (E2) changes, so voice.lua etc. can
-- forward the new value to the engine without gridui knowing about audio.
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

-- lexicon view pagination
state.lexicon_page = 1

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

-- confirm-hold gestures (Regrow / Clearing), read by screenui for a progress readout
state.confirm = nil -- {label=, started=, duration=} or nil

-- §5.1 "signal magnitude through it" -- a decaying flash for any cell whose
-- pulse arrival is Lua-known (node strike/choke, a D->S grain firing), the
-- same flash-on-pulse-then-decay-to-15 shape rambler.lua and heartwood.lua
-- each already keep for D and H cells, just without a dedicated per-cell
-- object to hang it on. continuous audio-rate response -- a node under a
-- steady stream, S's own shimmer, a voice's amplitude envelope -- still
-- needs the metering back-channel (§7.4) and isn't lit by this.
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
