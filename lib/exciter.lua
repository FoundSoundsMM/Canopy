-- exciter.lua
-- S-cell control layer (§2.4). the audio itself lives in SC; this decides
-- when each of the ten exciters is running (lazy alloc: "only instantiated
-- when it has at least one cable"), whether it's gated (has an incoming D
-- cable, so a cable-driven pulse turns it into a grain instead of letting
-- it free-run), and forwards Colour (E2).

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local bridge   = wl("bridge")

local exciter = {}

local on_state = {}    -- s.id -> true while its exciter synth is running
local gated_state = {} -- s.id -> true while it has an incoming D cable
local colour_offset = {} -- s.id -> grove.lua's addition to Colour (§2.6 P<->S)

-- Colour has two writers now -- E2 here, and a cabled pitch field tracking
-- its line -- so it is summed in one place rather than raced from two.
local function colour_of(id, cell)
  return util.clamp(state.get_character(id, cell, 0, 1) + (colour_offset[id] or 0), 0, 1)
end

-- deliberately D cables only, not "anything that can carry a pulse": the
-- heartwood can deliver one too, but an S<->H cable's *usual* meaning is the
-- stream diffusing through the lattice (§6), and gating on it would silence
-- an exciter the player cabled in expecting to hear it. a pulse emerging from
-- the lattice into an ungated S cell still fires exciter_gate -- it just
-- doesn't envelope anything, since the cell is free-running.
local function has_d_neighbor(id)
  for _, edge in ipairs(patch.edges_at(id)) do
    local other = topology.get(patch.other(edge, id))
    if other and other.type == "D" then return true end
  end
  return false
end

-- re-derive on/off and gated state for every S cell from the current patch
-- graph. cheap (10 cells, <=64 edges) and only runs when the graph changes.
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
        gated_state[id] = has_d_neighbor(id)
        bridge.exciter_gated(cell.index, gated_state[id])
      elseif (not live) and on_state[id] then
        on_state[id] = false
        bridge.exciter_off(cell.index)
      elseif live then
        local gated = has_d_neighbor(id)
        if gated ~= gated_state[id] then
          gated_state[id] = gated
          bridge.exciter_gated(cell.index, gated)
        end
      end
    end
  end
end

-- §2.6: a P->S cable makes that exciter's Colour ride the pitch field, so
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

patch.on_change(exciter.resync)

return exciter
