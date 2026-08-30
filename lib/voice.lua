-- voice.lua
-- voice state / param mapping. for build phase 2 this is deliberately
-- thin: it just forwards the Grain macro (§4.2, grid E2 on a voice cell)
-- to the engine. deeper per-voice PARAMS (pitch, drive, pos, ...) and
-- node-role param mapping land with later phases.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local voice = {}

function voice.init()
  for id, cell in topology.each() do
    if cell.type == "voice" then
      local g = state.get_character(id, cell, 0, 1)
      bridge.voice_grain(cell.index - 1, g) -- engine voices are 0-indexed
    end
  end
end

state.on_character_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "voice" then
    bridge.voice_grain(cell.index - 1, state.character[id])
  end
end)

return voice
