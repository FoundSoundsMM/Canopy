-- gridui.lua
-- grid render + hold/tap patching state machine. (§3, §4.2, §5.1)

local topology  = wl("topology")
local patch     = wl("patch")
local lexicon   = wl("lexicon")
local state     = wl("state")
local rambler   = wl("rambler")
local weave     = wl("weave")
local heartwood = wl("heartwood")
local grove     = wl("grove")
local climate   = wl("climate")

local gridui = {}

-- K1+E2 cycles the rule a cell runs on -- a D cell's gait, an R cell's
-- transform, an F cell's mode, a C cell's shape (§4.2, §2.6, §2.7, §2.8). one
-- step per three detents, so a normal flick of the encoder moves one rather
-- than five.
local RULE_DETENTS = 3
local rule_acc = {}

-- the cells that have a swappable rule at all, and the function that swaps it.
local CYCLERS = {
  D = function(id, step) return rambler.cycle_gait(id, step) end,
  R = function(id, step) return weave.cycle_rule(id, step) end,
  F = function(id, step) return grove.cycle_mode(id, step) end,
  C = function(id, step) return climate.cycle_shape(id, step) end,
}

-- below this held-duration, releasing a cell counts as a "tap". with a first
-- cell still held that toggles the cable; on its own it is the gesture that
-- opens a voice's sound page or flips a D cell's root. at or above it, the
-- two-down period was a deliberate hold+hold inspection (§3 row 3) and
-- release does not also toggle. the spec doesn't pin an exact figure; this is
-- the implementation's call.
gridui.TAP_THRESHOLD = 0.3

local sever_fired = false

-- grid key handling -------------------------------------------------------

function gridui.on_grid_key(x, y, z, keystate)
  local id = topology.at(x, y)
  if not id then return end -- unregistered coordinate, inert by design

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

    local cell = topology.get(id)

    -- a voice cell is not a socket (§2.2 -- only its four sockets are), so
    -- it is not a cable endpoint. every other cell is.
    if anchor and held_dur < gridui.TAP_THRESHOLD then
      local anchor_cell = topology.get(anchor)
      if anchor_cell.type ~= "voice" and cell.type ~= "voice" then
        local oneway = keystate and keystate.k1
        local result = patch.toggle(anchor, id, oneway, 0.6)
        local verb = (result == "added") and "->" or (result == "removed") and "x" or nil
        if verb then
          state.set_event(anchor_cell.name .. " " .. verb .. " " .. cell.name, 1.5)
        end
      end
    elseif not anchor and held_dur < gridui.TAP_THRESHOLD then
      gridui.on_tap(id, cell, keystate)
    end
  end

  gridui.check_sever_combo(keystate)
end

-- a tap on one cell with nothing else held ---------------------------------

function gridui.on_tap(id, cell, keystate)
  if cell.type == "voice" then
    -- §5.5: the screen becomes this voice's sound page, and tapping it again
    -- puts the screen back where it was. K1 is ignored here -- there is no
    -- second gesture on a voice cell to be ambiguous against.
    if state.voice_edit == id then
      state.voice_edit = nil
      state.set_event(cell.name .. ": closed", 1.2)
    else
      state.voice_edit = id
      state.vparam_focus = 1
      state.set_event(cell.name .. ": sound", 1.2)
    end
    return
  end

  if not (keystate and keystate.k1) then return end

  -- §2.3: K1 + tap a D cell toggles rooted (locked to the norns clock)
  -- against wild (free-running). unambiguous against the K1+tap one-way
  -- cable gesture, which only exists while another cell is held.
  if cell.type == "D" then
    local rooted = rambler.toggle_rooted(id)
    if rooted == nil then
      state.set_event(cell.name .. ": nothing to root to", 1.5)
    else
      state.set_event(cell.name .. (rooted and " rooted" or " wild"), 1.5)
    end
  elseif cell.type == "F" then
    -- §2.6: the same gesture on an F cell snaps its field to the scale, or
    -- lets it sit between the notes.
    local snap = grove.toggle_snap(id)
    state.set_event(cell.name .. (snap and " snapped" or " free"), 1.5)
  end
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
    local cycler = CYCLERS[cell.type]
    if keystate and keystate.k1 and cycler then
      -- §4.2's "K1 + E2 secondary character parameter", which for every cell
      -- type that has a bank of rules means: pick a different rule.
      rule_acc[id] = (rule_acc[id] or 0) + d
      while math.abs(rule_acc[id]) >= RULE_DETENTS do
        local step = rule_acc[id] > 0 and 1 or -1
        rule_acc[id] = rule_acc[id] - step * RULE_DETENTS
        local key = cycler(id, step)
        if key then state.set_event(cell.name .. ": " .. key, 1.5) end
      end
    elseif keystate and keystate.k1 then
      state.character2[id] = util.clamp(state.get_character2(id) + delta, 0, 1)
    else
      -- a voice cell has no single character -- it has the eight-parameter
      -- sound page instead (§5.5) -- so E2 on one is inert rather than
      -- quietly storing a number nothing reads.
      local ch = lexicon.character(id)
      if ch then
        -- the *base*, not the effective value: E2 moves the player's setting,
        -- and whatever weather is riding on top of it rides on top of the new
        -- one too (§2.8).
        local v = state.base_character(id, ch.lo, ch.hi)
        state.character[id] = util.clamp(v + delta * (ch.hi - ch.lo), ch.lo, ch.hi)
        state.notify_character_change(id)
      end
    end
  elseif n == 3 then
    local delta = d / 100
    local f = state.get_focus(id)
    if f == 0 or #edges == 0 then
      -- §4.2 E3 with nothing focused is this sound's decay. a voice's four
      -- sockets are parts of the voice rather than sounds of their own, so
      -- the gesture on any of them reaches the voice's resonator
      -- (state.lua's decay_target decides that, not this).
      local target = state.decay_target(cell)
      if target then
        state.decay[target] = util.clamp(state.get_decay(target) + delta, 0, 1)
        state.notify_decay_change(target)
      end
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
-- §5.1 idle brightness. every cell type that knows something about itself
-- lights itself: D and R flash on a pulse over a base that rises with how
-- much is cabled through them, H over how much energy is still circulating, F
-- over where its line currently sits, and C simply *is* its value, so the
-- outer corners read as four pairs of very slow meters. voice envelopes and S
-- shimmer still need the metering back-channel (§7.4) and stay static.

function gridui.brightness(id, cell)
  if cell.type == "voice" then
    -- the one open sound page is worth seeing from across the room.
    return state.voice_edit == id and 12 or 5
  elseif cell.type == "node" then
    local base = patch.degree(id) > 0 and 6 or 2
    return state.flash_level(id, base)
  elseif cell.type == "D" then
    return rambler.level(id, 3)
  elseif cell.type == "R" then
    return weave.level(id, 2)
  elseif cell.type == "S" then
    local base = patch.degree(id) > 0 and 5 or 3
    return state.flash_level(id, base)
  elseif cell.type == "H" then
    return heartwood.level(id, 2)
  elseif cell.type == "F" then
    return grove.level(id, 2)
  elseif cell.type == "C" then
    return climate.level(id, 1)
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
    -- unconnected cells are still valid patch targets, so they get a flat
    -- visibility floor rather than a straight x0.4 (idle brightness is
    -- already low enough that x0.4 floors most of them to 0-1 and hides
    -- every cell you could tap next) -- and flat, not scaled up from
    -- whatever they're doing live, because a D cell's pulse-flash or a
    -- socket's own flash is noise while you're reading a patch: all you need
    -- at that point is what's connected, not what's currently firing. voice
    -- cells aren't cable endpoints (only their sockets are), so they still
    -- fade toward black.
    local TARGET_FLOOR = 3
    for id, cell in topology.each() do
      if state.is_held(id) then
        levels[id] = 15
      elseif revealed[id] then
        levels[id] = blink and 13 or 6
      elseif cell.type == "voice" then
        levels[id] = math.floor(levels[id] * 0.4)
      else
        levels[id] = TARGET_FLOOR
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
