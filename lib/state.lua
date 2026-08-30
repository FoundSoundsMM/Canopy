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
  weather = 0.4,  -- E2: wildness (coupling K, gait drift, exciter variance)
  level = 0.8,    -- E3: master level
  still = false,  -- K2: freeze all pulse gaits
}

-- grid hold tracking
state.held = {}     -- ordered list of currently-held cell ids
state.held_t = {}   -- id -> util.time() at press

-- per-cell UI params, lazily defaulted
state.focus = {}       -- id -> focused edge index (0 = ALL)
state.character = {}   -- id -> primary character value (E2)
state.character2 = {}  -- id -> secondary character value (K1+E2)
state.trim = {}        -- id -> node/cell trim (E3 when focus == ALL)
state.gait = {}        -- D id -> gait key (K1+E2 swaps it, §4.2)
state.rooted = {}      -- D id -> locked to the norns clock? (K1+tap, §2.3)

function state.get_focus(id)
  if state.focus[id] == nil then state.focus[id] = 0 end
  return state.focus[id]
end

function state.get_trim(id)
  if state.trim[id] == nil then state.trim[id] = 0.0 end
  return state.trim[id]
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

-- fires when a cell's primary character (E2) changes, so voice.lua etc. can
-- forward the new value to the engine without gridui knowing about audio.
state._character_listeners = {}
function state.on_character_change(fn)
  table.insert(state._character_listeners, fn)
end
function state.notify_character_change(id)
  for _, fn in ipairs(state._character_listeners) do fn(id) end
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

return state
