-- a device-faithful soak. the other tests stub `screen` with a catch-all
-- metatable that returns a no-op function for *any* key, which means they
-- cannot see a call to a screen function that does not exist on norns, and
-- they only ever redraw a handful of hand-picked cells.
--
-- this one stubs the real norns surface strictly -- an unknown `screen.*`,
-- `util.*` or `clock.*` is an error, exactly as it would be on the device --
-- and then drives the whole script the way a player would: the scheduler
-- running, grid keys going down and up on live cells and on dark coordinates,
-- the front-panel keys and encoders being turned, and `redraw()` called from
-- every state it can reach, including every cell held one at a time and every
-- pair of cells held together.
--
-- the failure this exists to catch: an error inside redraw() kills the screen
-- metro. the grid keeps working (its own metro, its own callback), so the
-- script looks alive while the front panel appears dead.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

function include(file) return dofile(ROOT .. "/" .. file:gsub("^Woodland/", "") .. ".lua") end

-- strict norns surfaces ------------------------------------------------------

local function strict(name, fns)
  local t = {}
  for _, f in ipairs(fns) do t[f] = function() end end
  return setmetatable(t, {
    __index = function(_, k)
      error(name .. "." .. tostring(k) .. " does not exist on norns", 2)
    end,
  })
end

-- the norns screen API, as of core/screen.lua. anything not in here is a typo
-- that would be `attempt to call a nil value` on the device.
screen = strict("screen", {
  "aa", "arc", "blend_mode", "circle", "clear", "close", "curve", "curve_rel",
  "display_image", "display_image_region", "display_png", "export_screenshot",
  "fill", "font_face", "font_size", "level", "line", "line_cap", "line_join",
  "line_rel", "line_width", "load_png", "mask", "move", "move_rel", "peek",
  "ping", "pixel", "poke", "rect", "restore", "rotate", "save", "stroke",
  "text", "text_center", "text_center_rotate", "text_right", "text_rotate",
  "translate", "update",
})
-- the two that return something; everything else is fire-and-forget
screen.text_extents = function() return 10, 6 end
screen.peek = function() return "" end

local real_util = util
util = strict("util", {})
util.clamp = real_util.clamp
util.time = real_util.time
util.round = real_util.round
util.linlin = real_util.linlin
util.wrap = function(x, a, b) return a + ((x - a) % (b - a)) end

local real_clock = clock
clock = strict("clock", {})
clock.get_tempo = real_clock.get_tempo
clock.get_beats = real_clock.get_beats
clock.run = function(f) f() return 1 end
clock.cancel = function() end
clock.sleep = function() end

local metros, gridobj = {}, nil
metro.init = function(f, t, c)
  local m = {callback = f, running = false}
  table.insert(metros, m)
  m.start = function() m.running = true end
  m.stop = function() m.running = false end
  return m
end

grid.connect = function()
  gridobj = {
    led = function(_, x, y, l)
      assert(x == math.floor(x) and x >= 1 and x <= 16, "grid x " .. tostring(x))
      assert(y == math.floor(y) and y >= 1 and y <= 8, "grid y " .. tostring(y))
      assert(l == math.floor(l) and l >= 0 and l <= 15, "grid level " .. tostring(l))
    end,
    all = function() end,
    refresh = function() end,
  }
  return gridobj
end

_woodland_mods = nil
dofile(ROOT .. "/Woodland.lua")
init()
local M = _woodland_mods

-- helpers ---------------------------------------------------------------------

local failures = {}
local function guard(label, fn)
  local ok, err = pcall(fn)
  if not ok and #failures < 12 then
    table.insert(failures, label .. ": " .. tostring(err))
  end
  return ok
end

local function tick(n)
  for _ = 1, (n or 1) do
    T = T + M.rambler.TICK
    M.rambler.tick()
  end
end

local function ids_of(kind)
  local out = {}
  for id, cell in M.topology.each() do
    if (not kind) or cell.type == kind then table.insert(out, id) end
  end
  return out
end

local all_ids = ids_of(nil)
local function coords(id)
  local c = M.topology.get(id).coords[1]
  return c[1], c[2]
end

-- every state redraw can reach ---------------------------------------------------

print("\n-- redraw survives every view, from every state --")
do
  -- something worth drawing: a patch, running, with pulses in flight
  math.randomseed(4)
  key(1, 1); key(2, 1); key(2, 0); key(1, 0)     -- Regrow
  tick(500 * 4)

  local ok = true
  for _ = 1, 40 do
    tick(33)
    ok = guard("redraw global page", redraw) and ok
  end
  check("the global param page redraws with a live patch", ok, failures[1])

  ok = true
  for _, id in ipairs(all_ids) do
    local x, y = coords(id)
    gridobj.key(x, y, 1)
    tick(20)
    ok = guard("cell view " .. id, redraw) and ok
    gridobj.key(x, y, 0)
  end
  check("the cell view redraws for every one of the " .. #all_ids .. " cells",
        ok, failures[1])

  ok = true
  M.state.voice_edit = nil
  for _, a in ipairs(ids_of("voice")) do
    local ax, ay = coords(a)
    gridobj.key(ax, ay, 1)
    tick(2)
    ok = guard("sound page " .. a, redraw) and ok
    gridobj.key(ax, ay, 0)
  end
  check("the sound page redraws for every voice, held", ok, failures[1])
end

print("\n-- redraw survives every pair of cells held --")
do
  -- one representative of every type against one of every other type, both
  -- ways round, so every branch of the edge view's interaction table is drawn.
  local reps = {}
  for _, kind in ipairs({"voice", "node", "D", "R", "S", "H", "F", "C"}) do
    local list = ids_of(kind)
    table.insert(reps, list[1])
    if kind == "node" then
      -- one of each role, since the four are the whole point
      for _, r in ipairs({"trig", "pitch", "mod", "out"}) do
        table.insert(reps, "oak." .. r)
      end
    end
  end

  local ok, pairs_drawn = true, 0
  for _, a in ipairs(reps) do
    for _, b in ipairs(reps) do
      if a ~= b then
        local ax, ay = coords(a)
        local bx, by = coords(b)
        gridobj.key(ax, ay, 1)
        gridobj.key(bx, by, 1)
        ok = guard("edge view " .. a .. "/" .. b, redraw) and ok
        pairs_drawn = pairs_drawn + 1
        gridobj.key(bx, by, 0)
        gridobj.key(ax, ay, 0)
      end
    end
  end
  check("the edge view redraws for all " .. pairs_drawn .. " type pairs",
        ok, failures[1])
end

print("\n-- the whole script survives a random session --")
do
  math.randomseed(97)
  local ok = true
  local live = {}
  for i, id in ipairs(all_ids) do live[i] = id end

  for step = 1, 4000 do
    local roll = math.random()
    if roll < 0.30 then
      -- a grid press or release, on a live cell or a dark coordinate
      local x, y = math.random(16), math.random(8)
      if math.random() < 0.6 then
        local id = live[math.random(#live)]
        x, y = coords(id)
      end
      ok = guard("grid key", function() gridobj.key(x, y, math.random(0, 1)) end) and ok
    elseif roll < 0.45 then
      ok = guard("key", function() key(math.random(3), math.random(0, 1)) end) and ok
    elseif roll < 0.65 then
      ok = guard("enc", function() enc(math.random(3), math.random(-4, 4)) end) and ok
    elseif roll < 0.75 then
      ok = guard("grid_redraw", function() M.gridui.grid_redraw(gridobj) end) and ok
    else
      ok = guard("redraw", redraw) and ok
    end
    tick(math.random(1, 12))
  end
  check("4000 random gestures with the scheduler running", ok, failures[1])
end

-- release anything the random session left down, then confirm the grid render
-- is still producing legal levels for every cell
do
  M.state.held = {}
  local ok = guard("grid_redraw", function() M.gridui.grid_redraw(gridobj) end)
  check("the grid still renders legal levels", ok, failures[1])
end

-- the screen budget -------------------------------------------------------------
--
-- this is the one that bit, back when the idle screen was the network view: it
-- was issuing ~600 screen commands a frame, ~240 of them cairo paint calls
-- (`level`/`fill`), which at 15 fps fills matron's screen queue faster than it
-- drains. a full queue blocks the Lua thread, so the screen stops updating and
-- the front panel stops responding while the grid -- its own callback, its own
-- metro -- carries on. the global param page that replaced it is nine label/
-- value/bar rows, the same shape as the sound page below, so the budget here
-- is really just guarding against a future regression. numbers, not vibes.

print("\n-- the screen budget, per frame --")
do
  local counted = {}
  local total = 0
  local real = screen
  local counting = setmetatable({}, {__index = function(_, k)
    local f = real[k]              -- still errors on a name norns lacks
    return function(...)
      counted[k] = (counted[k] or 0) + 1
      total = total + 1
      return f(...)
    end
  end})

  local function frame()
    counted, total = {}, 0
    screen = counting
    redraw()
    screen = real
    local paint = (counted.fill or 0) + (counted.stroke or 0) + (counted.level or 0)
    return total, paint
  end

  M.state.held = {}
  M.state.voice_edit = nil
  M.patch.clear()

  -- the worst case the patch cap allows: 64 cables, every cell lit, pulses in
  -- flight. the global page doesn't draw the patch at all any more, but the
  -- cell/edge views still do, so this is still worth setting up.
  local ids = {}
  for id, cell in M.topology.each() do
    if cell.type ~= "voice" then table.insert(ids, id) end
  end
  math.randomseed(11)
  while M.patch.count() < M.patch.MAX_CABLES do
    local a, b = ids[math.random(#ids)], ids[math.random(#ids)]
    if a ~= b then M.patch.add(a, b, 0.9, math.random() < 0.3) end
  end
  tick(500 * 3)

  local calls, paint = frame()
  check("the global param page: under 200 commands", calls < 200, calls .. " calls")

  M.state.voice_edit = "oak"
  calls, paint = frame()
  check("the sound page: under 200 commands", calls < 200, calls .. " calls")
  M.state.voice_edit = nil

  M.state.held = {"d.knocker"}
  calls, paint = frame()
  check("the cell view: under 150 commands", calls < 150, calls .. " calls")
  M.state.held = {}
end

if #failures > 0 then
  print("\nfirst failures:")
  for i, f in ipairs(failures) do
    if i > 6 then break end
    print("  " .. f)
  end
end

report()
