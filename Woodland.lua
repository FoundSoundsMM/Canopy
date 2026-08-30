-- woodland
--
-- six modal/pinged-filter voices ringed by androgynous nodes, patched by
-- hand into a central cluster of pulse-makers and exciters. every socket
-- is both an input and an output; a cable is an undirected coupling.
--
-- hold a cell, tap another: patch them together.
-- hold a cell, tap a connected one: unpatch them.
-- hold two cells together: read/set that edge's gain on E3.
-- K3: cycle the screen (network -> meters -> lexicon).
-- K2: freeze the pulse gaits (Still).
-- K1+K2 (hold): Regrow — seeded random patch.
-- K1+K3 (hold): Clearing — cut every cable.
--
-- build phase 2: the SC engine's six modal voices + strike, with Knocker
-- (the one D cell whose gait is implemented so far) driving them from Lua.
-- (see docs/woodland-spec.md §9 for the full build order).

engine.name = "Woodland"

local topology = include("Woodland/lib/topology")
local patch = include("Woodland/lib/patch")
local state = include("Woodland/lib/state")
local gridui = include("Woodland/lib/gridui")
local screenui = include("Woodland/lib/screenui")
local bridge = include("Woodland/lib/bridge")
local voice = include("Woodland/lib/voice")
local rambler = include("Woodland/lib/rambler")

-- fixed for now; only the overall wet amount (E1: Canopy) is exposed yet.
local CANOPY_SIZE = 0.6
local CANOPY_DAMP = 0.5

local g = nil
local screen_metro, grid_metro
local keystate = {k1 = false, k2 = false, k3 = false}

local CONFIRM_HOLD = 1.0
local confirm_clock = nil

local function cancel_confirm()
  if confirm_clock then
    clock.cancel(confirm_clock)
    confirm_clock = nil
  end
  state.confirm = nil
end

local function eligible_ids()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type ~= "voice" then table.insert(ids, id) end
  end
  return ids
end

-- K1+K2, held: seeded random patch (§4.1 Regrow)
local function do_regrow()
  patch.clear()
  local ids = eligible_ids()
  local target = math.random(10, 18)
  local made, attempts = 0, 0
  while made < target and attempts < target * 8 do
    attempts = attempts + 1
    local a = ids[math.random(#ids)]
    local b = ids[math.random(#ids)]
    if a ~= b then
      local gain = 0.3 + math.random() * 0.5
      if math.random() < 0.5 then gain = -gain end
      if patch.add(a, b, gain, false) then made = made + 1 end
    end
  end
  state.last_event = "regrew " .. made .. " cables"
end

local function start_confirm(kind, label)
  state.confirm = {kind = kind, label = label, started = util.time(), duration = CONFIRM_HOLD}
  confirm_clock = clock.run(function()
    clock.sleep(CONFIRM_HOLD)
    if state.confirm and state.confirm.kind == kind then
      if kind == "regrow" then
        do_regrow()
      elseif kind == "clear" then
        patch.clear()
        state.last_event = "cleared every cable"
      end
    end
    state.confirm = nil
    confirm_clock = nil
  end)
end

-- press-context flags: was this key pressed alone, with the other two up?
local k2_solo_press, k3_solo_press = false, false

function key(n, z)
  if n == 1 then
    keystate.k1 = (z == 1)
  elseif n == 2 then
    if z == 1 then
      k2_solo_press = not keystate.k1 and not keystate.k3
    end
    keystate.k2 = (z == 1)
    if z == 0 and #state.held == 0 and k2_solo_press then
      state.global.still = not state.global.still
      state.last_event = state.global.still and "Still" or "resumed"
    end
  elseif n == 3 then
    if z == 1 then
      k3_solo_press = not keystate.k1 and not keystate.k2
    end
    keystate.k3 = (z == 1)
    if z == 0 and #state.held == 0 and k3_solo_press then
      if state.view == "lexicon" then
        if screenui.lexicon_advance() then state.cycle_view() end
      else
        state.cycle_view()
      end
    end
  end

  gridui.on_norns_key(n, z, keystate)

  if #state.held == 0 then
    if keystate.k1 and keystate.k2 and not state.confirm then
      start_confirm("regrow", "K1+K2 hold — Regrow")
    elseif keystate.k1 and keystate.k3 and not state.confirm then
      start_confirm("clear", "K1+K3 hold — Clearing")
    elseif state.confirm and not (keystate.k1 and (keystate.k2 or keystate.k3)) then
      cancel_confirm()
    end
  elseif state.confirm then
    cancel_confirm()
  end
end

function enc(n, d)
  if gridui.on_norns_enc(n, d, keystate) then return end
  if n == 1 then
    state.global.canopy = util.clamp(state.global.canopy + d / 500, 0, 1)
    bridge.canopy(CANOPY_SIZE, CANOPY_DAMP, state.global.canopy)
  elseif n == 2 then
    state.global.weather = util.clamp(state.global.weather + d / 500, 0, 1)
  elseif n == 3 then
    state.global.level = util.clamp(state.global.level + d / 500, 0, 1)
    bridge.master_level(state.global.level)
  end
end

function redraw()
  screenui.redraw()
end

function init()
  g = grid.connect()
  g.key = function(x, y, z)
    gridui.on_grid_key(x, y, z, keystate)
  end

  screen_metro = metro.init(function() redraw() end, 1 / 15, -1)
  screen_metro:start()

  grid_metro = metro.init(function()
    if g then gridui.grid_redraw(g) end
  end, 1 / 30, -1)
  grid_metro:start()

  voice.init()
  bridge.canopy(CANOPY_SIZE, CANOPY_DAMP, state.global.canopy)
  bridge.master_level(state.global.level)
  rambler.start()
end

function cleanup()
  if screen_metro then screen_metro:stop() end
  if grid_metro then grid_metro:stop() end
  rambler.stop()
  cancel_confirm()
end
