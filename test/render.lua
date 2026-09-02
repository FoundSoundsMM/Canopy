-- offline rasteriser: draws the REAL lib/screenui.lua into a 128x64 buffer and
-- writes it out as a PGM per view.
--
-- test/screen.lua proves nothing overlaps and nothing runs off the panel,
-- which is a geometry check -- it cannot tell you whether a Decay looks like
-- a decay. this can. it is a review tool, not an assertion: it takes no
-- position on what it renders, it just puts the shipped drawing code in front
-- of your eyes without a norns on the desk.
--
--   ROOT=$(pwd) SP=$(pwd)/test lua test/render.lua [outdir]
--
-- the raster is deliberately naive next to cairo -- no anti-aliasing, a
-- flattened cubic, integer coordinates. that makes it a HARSHER read than the
-- hardware, not a kinder one, which is the right way round for a review tool.

local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
local OUT = arg and arg[1] or "/tmp/canopy-render"
arg = {ROOT}
dofile(SP .. "/harness.lua")

local FONT = dofile(SP .. "/font3x5.lua")

local W, H = 128, 64
local buf = {}

local function clearbuf()
  for i = 0, W * H - 1 do buf[i] = 0 end
end

local lvl = 15
local cx, cy = 0, 0
local path = {}          -- accumulated rects, cairo-style
local sub = nil          -- the current line/curve subpath

local function px(x, y, l)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if x < 0 or y < 0 or x >= W or y >= H then return end
  buf[y * W + x] = l or lvl
end

local function hline(x0, x1, y)
  if x1 < x0 then x0, x1 = x1, x0 end
  for x = x0, x1 do px(x, y) end
end

local function seg(x0, y0, x1, y1)
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
  for i = 0, n do
    local t = i / n
    px(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
  end
end

local rec = {}
rec.clear = clearbuf
rec.update = function() end
rec.aa = function() end
rec.font_size = function() end
rec.font_face = function() end
rec.level = function(l) lvl = math.max(0, math.min(15, math.floor(l or 0))) end
rec.text_extents = function(s)
  s = tostring(s or "")
  local w = 0
  for i = 1, #s do
    local g = FONT[s:sub(i, i)] or FONT["?"]
    w = w + #(g[1]) + 1
  end
  return math.max(0, w - 1)
end
rec.move = function(x, y) cx, cy = x, y; sub = {{x, y}} end
rec.line = function(x, y)
  if not sub then sub = {{cx, cy}} end
  sub[#sub + 1] = {x, y}
  cx, cy = x, y
end
-- flatten the cubic the same way cairo would, then treat it as a polyline
rec.curve = function(x1, y1, x2, y2, x3, y3)
  if not sub then sub = {{cx, cy}} end
  local x0, y0 = cx, cy
  for i = 1, 24 do
    local t = i / 24
    local u = 1 - t
    sub[#sub + 1] = {
      u*u*u*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t*t*t*x3,
      u*u*u*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t*y3,
    }
  end
  cx, cy = x3, y3
end
rec.close = function()
  if sub and #sub > 1 then sub[#sub + 1] = {sub[1][1], sub[1][2]} end
end
rec.rect = function(x, y, w, h) path[#path + 1] = {x, y, w, h} end
rec.circle = function() end
rec.arc = function() end

local function paint_rects(filled)
  for _, r in ipairs(path) do
    local x0 = math.floor(r[1] + 0.5)
    local y0 = math.floor(r[2] + 0.5)
    local x1 = math.floor(r[1] + r[3] - 0.5)
    local y1 = math.floor(r[2] + r[4] - 0.5)
    if filled then
      for y = y0, y1 do hline(x0, x1, y) end
    else
      hline(x0, x1, y0); hline(x0, x1, y1)
      for y = y0, y1 do px(x0, y); px(x1, y) end
    end
  end
  path = {}
end

local function paint_sub()
  if sub and #sub > 1 then
    for i = 2, #sub do
      seg(sub[i-1][1], sub[i-1][2], sub[i][1], sub[i][2])
    end
  end
  sub = nil
end

rec.fill = function() paint_rects(true); paint_sub() end
rec.stroke = function() paint_rects(false); paint_sub() end

local function draw_text(s, right)
  s = tostring(s or "")
  -- the 3x5 table is ASCII; norns' real font has the em dash the edge view
  -- draws between two cell names, so substitute rather than render "???"
  s = s:gsub("\226\128\148", "-")
  if s == "" then return end
  local x = cx
  if right then x = cx - rec.text_extents(s) end
  for i = 1, #s do
    local ch = s:sub(i, i)
    local g = FONT[ch] or FONT["?"]
    for r = 1, 5 do
      local row = g[r] or ""
      for c = 1, #row do
        if row:sub(c, c) == "#" then px(x + c - 1, cy - 5 + r - 1) end
      end
    end
    x = x + #(g[1]) + 1
  end
end

rec.text = function(s) draw_text(s, false) end
rec.text_right = function(s) draw_text(s, true) end
rec.text_center = function(s)
  cx = cx - rec.text_extents(s) / 2
  draw_text(s, false)
end

screen = setmetatable(rec, {__index = function() return function() end end})

-- ---------------------------------------------------------------------------

local M = fresh(1)
local screenui = wl("screenui")
local cellparam = wl("cellparam")

local function write_pgm(name)
  local f = assert(io.open(OUT .. "/" .. name .. ".pgm", "wb"))
  f:write("P2\n" .. W .. " " .. H .. "\n15\n")
  for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do row[#row + 1] = buf[y * W + x] or 0 end
    f:write(table.concat(row, " "), "\n")
  end
  f:close()
end

local function shot(name)
  clearbuf()
  path = {}; sub = nil
  screenui.redraw()
  write_pgm(name)
  print("  " .. name)
end

os.execute("mkdir -p '" .. OUT .. "'")
print("rendering into " .. OUT)

local function cell_of(t)
  for id, c in M.topology.each() do if c.type == t then return id end end
end

-- the global page, and the mixer
M.state.gparam_focus = 3
shot("01-global")
M.state.view = "mixer"; M.state.mparam_focus = 5
shot("02-mixer")
M.state.view = "global"

-- a voice, both pages
M.state.cell_edit = cell_of("voice")
M.state.vparam_focus = 3
shot("03-voice-p1")
M.state.vparam_focus = 11
shot("04-voice-p2")

-- the shift register
M.state.cell_edit = cell_of("TM"); M.state.vparam_focus = 7
shot("05-turing")

-- the two scopes
M.state.cell_edit = cell_of("D"); M.state.vparam_focus = 2
T = 2.4
shot("06-pulse-scope")
M.state.cell_edit = cell_of("LFO"); M.state.vparam_focus = 1
T = 3.1
shot("07-lfo-scope")

-- a page that still gets its sentence
M.state.cell_edit = cell_of("H"); M.state.vparam_focus = 1
shot("08-heartwood")
M.state.cell_edit = cell_of("F"); M.state.vparam_focus = 2
shot("09-field")
M.state.cell_edit = cell_of("GUST"); M.state.vparam_focus = 4
shot("10-gust")

-- the map, and a cable
M.state.cell_edit = nil
M.patch.add(cell_of("voice"), cell_of("O"), 0.5)
M.patch.add(cell_of("D"), cell_of("voice"), 0.5)
M.state.view = "map"
shot("11-map")
M.state.view = "global"
M.state.held = {cell_of("D"), cell_of("voice")}
shot("12-edge")
M.state.held = {}

print("done")
