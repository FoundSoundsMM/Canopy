-- voice.lua
-- voice state / param mapping. forwards the Grain macro (§4.2, grid E2 on a
-- voice cell) to the engine, and -- as of build phase 4 -- the stream-
-- modulation half of each voice's Sap/Sway/Moss nodes: Sap's injection
-- filter, Sway's bend depth/balance, Moss's damping curve (§4.2's per-node
-- E2). the pulse-choke half of Moss is dispatch.lua's node:moss handler,
-- not this. deeper per-voice PARAMS (pitch, drive, pos, ...) land later.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local lexicon  = wl("lexicon")

local voice = {}

-- role -> the bridge call that forwards that node's E2 character, or nil if
-- this role has no continuous forward (Knock is pulse-only, §2.2).
local NODE_FORWARD = {
  sap  = bridge.voice_sap,
  sway = bridge.voice_sway,
  moss = bridge.voice_moss,
}

function voice.init()
  for id, cell in topology.each() do
    if cell.type == "voice" then
      local g = state.get_character(id, cell, 0, 1)
      bridge.voice_grain(cell.index - 1, g) -- engine voices are 0-indexed
    elseif cell.type == "node" then
      local fwd = NODE_FORWARD[cell.role]
      if fwd then
        local voice_cell = topology.get(cell.voice)
        local ch = lexicon.character(id)
        local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
        fwd(voice_cell.index - 1, state.get_character(id, cell, lo, hi))
      end
    end
  end
end

state.on_character_change(function(id)
  local cell = topology.get(id)
  if not cell then return end
  if cell.type == "voice" then
    bridge.voice_grain(cell.index - 1, state.character[id])
  elseif cell.type == "node" then
    local fwd = NODE_FORWARD[cell.role]
    if fwd then
      local voice_cell = topology.get(cell.voice)
      fwd(voice_cell.index - 1, state.character[id])
    end
  end
end)

return voice
