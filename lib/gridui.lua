-- gridui.lua
-- grid render + hold/tap patching state machine. (§3, §4.2, §5.1)

local topology = wl("topology")
local patch    = wl("patch")
local lexicon  = wl("lexicon")
local state    = wl("state")
local rambler  = wl("rambler")

local gridui = {}

-- K1+E2 cycles a D cell's gait (§4.2). one gait per three detents, so a
-- normal flick of the encoder moves one step rather than five.
local GAIT_DETENTS = 3
local gait_acc = {}

-- below this held-duration, releasing a second cell while a first is still
-- held counts as a "tap" (toggles the cable). at/above it, the two-down
-- period was a deliberate hold+hold inspection (§3 row 3) and release does
-- not also toggle. the spec doesn't pin an exact figure; this is the
-- implementation's call.
gridui.TAP_THRESHOLD = 0.3

local sever_fired = false

-- grid key handling -------------------------------------------------------

function gridui.on_grid_key(x, y, z, keystate)
  local id = topology.at(x, y)
  if not id then return end -- unlit bezel, inert

  if z == 1 then
    table.insert(state.held, id)
    state.held_t[id] = util.time()
  else
    local press_t = state.held_t[id]
    local held_dur = press_t and (util.time() - press_t) or math.huge

    local anchor = nil
    for _, hid in ipairs(state.held) do
      if hid ~= id then
        anchor = hid
        break
      end
    end

    for i, hid in ipairs(state.held) do
      if hid == id then
        table.remove(state.held, i)
        break
      end
    end
    state.held_t[id] = nil

    -- only node/D/S/H cells are cable endpoints (§6 matrix has no "voice"
    -- row — a voice cell itself isn't a socket, only its four nodes are).
    if anchor and held_dur < gridui.TAP_THRESHOLD then
      local anchor_cell = topology.get(anchor)
      local this_cell = topology.get(id)
      if anchor_cell.type ~= "voice" and this_cell.type ~= "voice" then
        local oneway = keystate and keystate.k1
        local result = patch.toggle(anchor, id, oneway, 0.6)
        local verb = (result == "added") and "->" or (result == "removed") and "x" or nil
        if verb then
          state.set_event(anchor_cell.name .. " " .. verb .. " " .. this_cell.name, 1.5)
        end
      end
    elseif not anchor and held_dur < gridui.TAP_THRESHOLD
        and keystate and keystate.k1 then
      -- §2.3: K1 + tap a D cell toggles rooted (locked to the norns clock)
      -- against wild (free-running). unambiguous against the K1+tap one-way
      -- cable gesture, which only exists while another cell is held.
      local cell = topology.get(id)
      if cell.type == "D" then
        local rooted = rambler.toggle_rooted(id)
        if rooted == nil then
          state.set_event(cell.name .. ": nothing to root to", 1.5)
        else
          state.set_event(cell.name .. (rooted and " rooted" or " wild"), 1.5)
        end
      end
    end
  end

  gridui.check_sever_combo(keystate)
end

-- K2+K3 while a cell is held: sever every cable at that cell (§3, §4.2)
function gridui.check_sever_combo(keystate)
  if not keystate then return end
  if keystate.k2 and keystate.k3 and #state.held >= 1 then
    if not sever_fired then
      local id = state.held[#state.held]
      local n = patch.sever_all(id)
      if n > 0 then
        state.set_event("severed " .. topology.get(id).name .. " (" .. n .. ")", 1.5)
      end
      sever_fired = true
    end
  else
    sever_fired = false
  end
end

function gridui.on_norns_key(n, z, keystate)
  gridui.check_sever_combo(keystate)
end

-- encoders while holding a cell (or two) -----------------------------------
-- returns true if it consumed the encoder turn (caller should skip the
-- "nothing held" global encoder behaviour).

function gridui.on_norns_enc(n, d, keystate)
  if #state.held == 2 and n == 3 then
    local a, b = state.held[1], state.held[2]
    local edge_id = patch.has(a, b)
    if edge_id then
      local edge = patch.get(edge_id)
      patch.set_gain(edge_id, util.clamp(edge.gain + d / 100, -1, 1))
    end
    return true
  end

  if #state.held == 0 then return false end

  local id = state.held[#state.held]
  local cell = topology.get(id)
  local edges = patch.edges_at(id)

  if n == 1 then
    local f = state.get_focus(id) + d
    state.focus[id] = util.clamp(f, 0, #edges)
  elseif n == 2 then
    local delta = d / 100
    if keystate and keystate.k1 and cell.type == "D" then
      -- §4.2: "K1 + E2 secondary character parameter (D cells: swap gait)"
      gait_acc[id] = (gait_acc[id] or 0) + d
      while math.abs(gait_acc[id]) >= GAIT_DETENTS do
        local step = gait_acc[id] > 0 and 1 or -1
        gait_acc[id] = gait_acc[id] - step * GAIT_DETENTS
        local key = rambler.cycle_gait(id, step)
        if key then state.set_event(cell.name .. ": " .. key, 1.5) end
      end
    elseif keystate and keystate.k1 then
      state.character2[id] = util.clamp(state.get_character2(id) + delta, 0, 1)
    else
      local ch = lexicon.character(id)
      local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
      local v = state.get_character(id, cell, lo, hi)
      state.character[id] = util.clamp(v + delta * (hi - lo), lo, hi)
      state.notify_character_change(id)
    end
  elseif n == 3 then
    local delta = d / 100
    local f = state.get_focus(id)
    if f == 0 or #edges == 0 then
      state.trim[id] = util.clamp(state.get_trim(id) + delta, -1, 1)
    else
      local edge = edges[f]
      if edge then
        patch.set_gain(edge.id, util.clamp(edge.gain + delta, -1, 1))
      end
    end
  end

  return true
end

-- rendering -----------------------------------------------------------------
-- §5.1 idle brightness. D cells are live from here on -- they flash 15 on a
-- pulse and decay over ~120ms, over a base that rises with how strongly the
-- cell is coupled. voice envelopes, S shimmer and lattice energy still need
-- the metering back-channel (§7.4) and stay static for now.

function gridui.brightness(id, cell)
  if cell.type == "voice" then
    return 4
  elseif cell.type == "node" then
    return patch.degree(id) > 0 and 6 or 2
  elseif cell.type == "D" then
    return rambler.level(id, 3)
  elseif cell.type == "S" then
    return patch.degree(id) > 0 and 5 or 3
  elseif cell.type == "H" then
    return 2
  end
  return 0
end

function gridui.grid_redraw(g)
  local levels = {}
  for id, cell in topology.each() do
    levels[id] = gridui.brightness(id, cell)
  end

  if #state.held >= 1 then
    local revealed = {}
    for _, hid in ipairs(state.held) do
      revealed[hid] = true
      for _, edge in ipairs(patch.edges_at(hid)) do
        revealed[patch.other(edge, hid)] = true
      end
    end
    local blink = (math.floor(util.time() * 4) % 2 == 0)
    for id in pairs(levels) do
      if state.is_held(id) then
        levels[id] = 15
      elseif revealed[id] then
        levels[id] = blink and 13 or 6
      else
        levels[id] = math.floor(levels[id] * 0.4)
      end
    end
  end

  g:all(0)
  for id, cell in topology.each() do
    local lvl = levels[id]
    for _, c in ipairs(cell.coords) do
      g:led(c[1], c[2], lvl)
    end
  end
  g:refresh()
end

return gridui
