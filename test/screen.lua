-- lib/screenui.lua: nothing on the 128x64 panel may overlap anything else.
--
-- this exists because the parameter pages were printing on top of themselves
-- in two separate ways at once, and neither was visible to any test we had:
--
--   * vertically -- 8px rows with a 2px bar at y+2 put the bar in the same
--     pixels as the next row's ascenders; and worse, a list longer than the
--     ten slots the page had wrapped modulo the row count, so voice.PARAMS'
--     rows 11 and 12 drew straight over rows 6 and 7.
--   * horizontally -- a label was drawn from the left and its value from the
--     right of the same 60px column with nothing stopping them meeting in the
--     middle, which "Hardness" and "+12.0 st" duly did.
--
-- so: a recording screen stub, a bounding box per draw, and a pairwise
-- overlap check over every view the script can be in.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local M = fresh(1)
local screenui = wl("screenui")
local cellparam = wl("cellparam")
local gridui = wl("gridui")

-- the recording screen ------------------------------------------------------
-- text metrics match the harness's own text_extents stub (5px per character).
-- the font puts 5px above the baseline and 1 below it, so a run drawn at
-- (x, y) covers y-5 .. y+1.

local CHAR_W, ASCENT, DESCENT = 5, 5, 1

local boxes = {}
local cur = {x = 0, y = 0}

local function record(kind, x, y, w, h, text)
  table.insert(boxes, {kind = kind, x0 = x, y0 = y, x1 = x + w, y1 = y + h,
                       text = text})
end

local rec = {}
rec.clear = function() boxes = {} end
rec.update = function() end
rec.level = function() end
rec.stroke = function() end
rec.aa = function() end
rec.font_size = function() end
rec.font_face = function() end
rec.text_extents = function(s) return #tostring(s) * CHAR_W end
rec.move = function(x, y) cur.x, cur.y = x, y end
rec.line = function(x, y)
  -- rules and dividers are 1px and deliberately run edge to edge; they are
  -- structure, not content, so they are recorded but excluded from the
  -- content-vs-content check below.
  record("line", math.min(cur.x, x), math.min(cur.y, y),
         math.abs(x - cur.x), math.max(1, math.abs(y - cur.y)))
  cur.x, cur.y = x, y
end
rec.text = function(s)
  s = tostring(s)
  if s ~= "" then
    record("text", cur.x, cur.y - ASCENT, #s * CHAR_W, ASCENT + DESCENT, s)
  end
end
rec.text_right = function(s)
  s = tostring(s)
  if s ~= "" then
    record("text", cur.x - #s * CHAR_W, cur.y - ASCENT, #s * CHAR_W,
           ASCENT + DESCENT, s)
  end
end
rec.rect = function(x, y, w, h) cur.rect = {x, y, w, h} end
rec.fill = function()
  if cur.rect then
    record("fill", cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4])
    cur.rect = nil
  end
end
screen = setmetatable(rec, {__index = function() return function() end end})

-- checks --------------------------------------------------------------------

local function overlaps(a, b)
  return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

-- everything that carries meaning: text, and the value bars under it. lines
-- are excluded (see rec.line), and so is a `fill` that is exactly a bar's
-- own background track sitting under its own filled portion.
local function content(b)
  return b.kind == "text" or b.kind == "fill"
end

local function collisions(label)
  local bad = {}
  for i = 1, #boxes do
    for j = i + 1, #boxes do
      local a, b = boxes[i], boxes[j]
      if content(a) and content(b) and overlaps(a, b) then
        -- a bar draws its track and then its filled portion in the same
        -- rectangle; that pair is one widget, not a collision.
        local same_bar = (a.kind == "fill" and b.kind == "fill"
                          and a.x0 == b.x0 and a.y0 == b.y0 and a.y1 == b.y1)
        if not same_bar then
          table.insert(bad, string.format("%s[%s] x %s[%s] at (%d,%d)",
                                          a.kind, a.text or "", b.kind,
                                          b.text or "", a.x0, a.y0))
        end
      end
    end
  end
  return bad
end

local function offscreen()
  local bad = {}
  for _, b in ipairs(boxes) do
    if b.kind == "text" and (b.x0 < 0 or b.x1 > 128 or b.y0 < 0 or b.y1 > 64) then
      table.insert(bad, string.format("%s at (%d,%d)-(%d,%d)",
                                      b.text or "", b.x0, b.y0, b.x1, b.y1))
    end
  end
  return bad
end

local function draws_clean(label)
  local bad = collisions(label)
  check(label .. ": nothing overlaps", #bad == 0, bad[1] or "")
  local off = offscreen()
  check(label .. ": nothing runs off the panel", #off == 0, off[1] or "")
end

-- 1: the global param page ---------------------------------------------------

print("\n-- the global page --")
for i = 1, M.gparam.PARAM_COUNT do
  M.state.gparam_focus = i
  screenui.redraw()
  draws_clean("global, row " .. i)
end

-- 2: every cell's page, held and open ----------------------------------------
-- the failing case was specifically a long list (voice.PARAMS is twelve) and
-- a long label next to a long value, so walk every row of every cell rather
-- than sampling.

print("\n-- every cell page, every row --")
do
  local worst = nil
  local n = 0
  for id, cell in M.topology.each() do
    local page = cellparam.page(id)
    if page then
      for i = 1, page.PARAM_COUNT do
        M.state.vparam_focus = i
        for _, live in ipairs({false, true}) do
          M.state.held = live and {} or {id}
          M.state.cell_edit = live and id or nil
          screenui.redraw()
          local bad = collisions(id)
          local off = offscreen()
          n = n + 1
          if (#bad > 0 or #off > 0) and not worst then
            worst = id .. " row " .. i .. ": " .. (bad[1] or off[1])
          end
        end
      end
    end
  end
  M.state.held = {}
  M.state.cell_edit = nil
  check("every row of every cell page draws clean", worst == nil,
        tostring(worst))
  check("and that was a real sweep", n > 300, tostring(n))
end

-- 3: with cables on the cell, which is what the second line switches to ------

print("\n-- a heavily cabled cell --")
do
  local M2 = fresh(2)
  for _, other in ipairs({"o.1", "o.16", "e.bracken", "h.taproot", "d.hob",
                          "f.cuckoo", "tm.padfoot"}) do
    M2.patch.add("oak", other, 0.5)
  end
  M2.state.held = {"oak"}
  for i = 1, M2.voice.PARAM_COUNT do
    M2.state.vparam_focus = i
    screenui.redraw()
    draws_clean("cabled Oak, row " .. i)
  end
  M2.state.held = {}
end

-- 4: the edge view, every type pair ------------------------------------------

print("\n-- the edge view --")
do
  local M3 = fresh(3)
  local seen, worst = {}, nil
  local pairs_drawn = 0
  local ids = {}
  for id, cell in M3.topology.each() do
    if not seen[cell.type] then
      seen[cell.type] = true
      table.insert(ids, id)
    end
  end
  for _, a in ipairs(ids) do
    for _, b in ipairs(ids) do
      if a ~= b then
        M3.state.held = {a, b}
        screenui.redraw()
        pairs_drawn = pairs_drawn + 1
        local bad = collisions(a .. "|" .. b)
        if #bad > 0 and not worst then worst = a .. "|" .. b .. ": " .. bad[1] end
      end
    end
  end
  -- and once more with the longest pair of names the panel has, cabled
  M3.state.held = {}
  M3.patch.add("tm.tatterfoal", "d.spriggan", 0.5)
  M3.state.held = {"tm.tatterfoal", "d.spriggan"}
  screenui.redraw()
  local bad = collisions("longest names")
  if #bad > 0 and not worst then worst = "longest names: " .. bad[1] end
  M3.state.held = {}
  check("every type pair draws clean", worst == nil, tostring(worst))
  check("and that was every pair", pairs_drawn > 80, tostring(pairs_drawn))
end

-- 5: the page grid itself ----------------------------------------------------
-- the wrap-around bug was a property of the layout arithmetic, not of any one
-- page, so assert the arithmetic directly too.

print("\n-- the page arithmetic --")
do
  local per = screenui.PARAMS_PER_PAGE
  check("a page holds ten rows", per == 10, tostring(per))
  check("row 1 is on page 1", screenui.page_of(1) == 1)
  check("row 10 is still on page 1", screenui.page_of(10) == 1)
  check("row 11 starts page 2", screenui.page_of(11) == 2)
  check("voice.PARAMS needs two pages",
        screenui.page_of(M.voice.PARAM_COUNT) == 2,
        tostring(M.voice.PARAM_COUNT))

  -- every cell type has a page at all -- "some cells have settings and some
  -- don't" was half of the inconsistency this replaced.
  local missing = {}
  local types = {}
  for id, cell in M.topology.each() do
    if not types[cell.type] then
      types[cell.type] = true
      local page = cellparam.page(id)
      if not page or page.PARAM_COUNT < 1 then
        table.insert(missing, cell.type)
      end
    end
  end
  check("every cell type on the panel has a settings page", #missing == 0,
        table.concat(missing, ","))
end

report()
