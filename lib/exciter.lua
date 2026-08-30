-- exciter.lua
-- S-cell control layer (§2.4). the audio itself lives in SC; this decides
-- when each of the twenty exciters is running (lazy alloc: "only instantiated
-- when it has at least one cable"), whether it's gated (has an incoming pulse
-- cable, so a cable-driven pulse turns it into a grain instead of letting it
-- free-run), and forwards Colour (E2).

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local bridge   = wl("bridge")

local exciter = {}

local on_state = {}    -- s.id -> true while its exciter synth is running
local gated_state = {} -- s.id -> true while it has an incoming pulse cable
local colour_offset = {} -- s.id -> grove.lua's addition to Colour (§2.6 F<->S)

-- Colour has two writers now -- E2 here, and a cabled pitch field tracking
-- its line -- so it is summed in one place rather than raced from two.
local function colour_of(id, cell)
  return util.clamp(state.get_character(id, cell, 0, 1) + (colour_offset[id] or 0), 0, 1)
end

-- §4.2 E3 with no cable focused, S-cell half. an exciter has no single ring
-- time to name in seconds the way a voice does -- twenty recipes, twenty
-- different envelopes -- so the knob is a ratio instead: 0.5 leaves every time
-- constant the recipe chose for itself, and the sweep is 1.5 octaves either
-- side of that, applied to the grain envelope and to whatever tail it has.
exciter.DECAY_OCTAVES = 1.5

function exciter.decay_scale(id)
  return 2 ^ ((state.get_decay(id) - 0.5) * 2 * exciter.DECAY_OCTAVES)
end

-- deliberately D and R cables only, not "anything that can carry a pulse".
-- the heartwood can deliver one too, and so can a voice's O socket, but an
-- S<->H cable's *usual* meaning is the stream diffusing through the lattice
-- and an O->S cable's is the voice colouring the exciter (§6) -- gating on
-- either would silence an exciter the player cabled in expecting to hear it.
-- a pulse arriving at an ungated S cell still fires exciter_gate; it just
-- doesn't envelope anything, since the cell is free-running.
local GATING_TYPES = {D = true, R = true}

local function has_gate_neighbor(id)
  for _, edge in ipairs(patch.edges_at(id)) do
    local other = topology.get(patch.other(edge, id))
    if other and GATING_TYPES[other.type] then return true end
  end
  return false
end

-- re-derive on/off and gated state for every S cell from the current patch
-- graph. cheap (20 cells, <=64 edges) and only runs when the graph changes.
function exciter.resync()
  for id, cell in topology.each() do
    if cell.type == "S" then
      local live = patch.degree(id) > 0
      if live and not on_state[id] then
        on_state[id] = true
        bridge.exciter_on(cell.index)
        -- a fresh synth starts at its SC-side defaults; push whatever this
        -- cell's character/gating already are so it doesn't briefly sound
        -- wrong if they were set while it was unpatched.
        bridge.exciter_colour(cell.index, colour_of(id, cell))
        bridge.exciter_decay(cell.index, exciter.decay_scale(id))
        gated_state[id] = has_gate_neighbor(id)
        bridge.exciter_gated(cell.index, gated_state[id])
      elseif (not live) and on_state[id] then
        on_state[id] = false
        bridge.exciter_off(cell.index)
      elseif live then
        local gated = has_gate_neighbor(id)
        if gated ~= gated_state[id] then
          gated_state[id] = gated
          bridge.exciter_gated(cell.index, gated)
        end
      end
    end
  end
end

-- §2.6: an F->S cable makes that exciter's Colour ride the pitch field, so
-- a pitched source follows the line the voices are playing. grove.lua owns
-- the offset; this stays the only thing that talks to the engine about it.
function exciter.set_colour_offset(id, off)
  off = util.clamp(off or 0, -1, 1)
  if colour_offset[id] == off then return end
  colour_offset[id] = off
  local cell = topology.get(id)
  if cell and cell.type == "S" and on_state[id] then
    bridge.exciter_colour(cell.index, colour_of(id, cell))
  end
end

state.on_character_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "S" and on_state[id] then
    bridge.exciter_colour(cell.index, colour_of(id, cell))
  end
end)

state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "S" and on_state[id] then
    bridge.exciter_decay(cell.index, exciter.decay_scale(id))
  end
end)

patch.on_change(exciter.resync)

return exciter
