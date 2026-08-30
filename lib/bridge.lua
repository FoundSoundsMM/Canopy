-- bridge.lua
-- thin wrapper around Engine_Woodland's OSC commands (§7.2: "SC owns every
-- sample of audio"; this is just the Lua-side call surface, one function
-- per command in §8's list, so callers never touch `engine.*` directly).
--
-- throttling and the meter-cache readback (§7.4) are phase 7 concerns and
-- aren't implemented yet.

local bridge = {}

function bridge.strike(voice_index, force, hardness, position)
  engine.strike(voice_index, force, hardness, position)
end

function bridge.voice_pitch(voice_index, hz)
  engine.voice_pitch(voice_index, hz)
end

function bridge.voice_grain(voice_index, v)
  engine.voice_grain(voice_index, v)
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

function bridge.canopy(size, damp, mix)
  engine.canopy(size, damp, mix)
end

function bridge.master_level(v)
  engine.master_level(v)
end

return bridge
