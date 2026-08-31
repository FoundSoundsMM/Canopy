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
--
-- §5.2b the Digitakt layout added two things this recorder has to understand.
-- first, DELIBERATE backgrounds: the header bar is a filled rectangle with
-- its text knocked out of it, and so is every chip and every focused widget
-- box. second, SHAPES: knob gauges are circles, arcs and pointer lines rather
-- than text and bars. so the overlap rule below is no longer "no two
-- non-line boxes may touch" -- see `collisions`.

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
rec.circle = function(x, y, r) cur.shape = {x - r, y - r, 2 * r, 2 * r} end
rec.arc = function(x, y, r) cur.shape = {x - r, y - r, 2 * r, 2 * r} end
rec.close = function() end
-- a rectangle is a box: filled it is a background, stroked it is a frame,
-- and either way text may legally sit inside it. a circle or an arc is a
-- knob gauge -- it has no inside to put words in, so text drawn through one
-- is a collision whichever way round they are.
local function flush(rect_kind)
  if cur.rect then
    record(rect_kind, cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4])
    cur.rect = nil
  end
  if cur.shape then
    record("shape", cur.shape[1], cur.shape[2], cur.shape[3], cur.shape[4])
    cur.shape = nil
  end
end
rec.fill = function() flush("fill") end
rec.stroke = function() flush("frame") end
screen = setmetatable(rec, {__index = function() return function() end end})

-- checks --------------------------------------------------------------------

local function overlaps(a, b)
  return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

local function contains(outer, inner)
  return outer.x0 <= inner.x0 and outer.x1 >= inner.x1
     and outer.y0 <= inner.y0 and outer.y1 >= inner.y1
end

-- the rule, in three parts:
--
--   text  x text   never. two words in the same pixels is illegible, full
--                  stop, and it is the bug that started this file (a label
--                  and its value meeting in the middle of a 60px column).
--   text  x box    (a filled background or a stroked frame) only when the box
--                  CONTAINS the text -- the inverted header bar, a chip, a
--                  widget's readout box. a box that merely CLIPS a word is
--                  the other bug that started this file (an 8px row's bar
--                  landing in the next row's ascenders), and is still caught.
--   text  x shape  never: a knob gauge has no inside to put words in, so a
--                  word drawn through one is unreadable. this is what pins
--                  the widget grid's geometry -- gauge, label, and the row
--                  underneath.
--   non-text x non-text        always fine. graphics compose: an arc over a
--                  circle over a filled bar is one knob, and a chip sitting
--                  inside the header bar is the point of the header bar.
--
-- lines are excluded entirely (see rec.line) -- rules and dividers are
-- structure, and they deliberately run edge to edge.
local BOXES = {fill = true, frame = true}

local function drawn(b)
  return b.kind == "text" or BOXES[b.kind] or b.kind == "shape"
end

local function legal_pair(a, b)
  if a.kind ~= "text" and b.kind ~= "text" then return true end
  if a.kind == "text" and b.kind == "text" then return false end
  local text, other = a, b
  if b.kind == "text" then text, other = b, a end
  return BOXES[other.kind] and contains(other, text)
end

local function collisions(label)
  local bad = {}
  for i = 1, #boxes do
    for j = i + 1, #boxes do
      local a, b = boxes[i], boxes[j]
      if drawn(a) and drawn(b) and overlaps(a, b) and not legal_pair(a, b) then
        table.insert(bad, string.format("%s[%s] x %s[%s] at (%d,%d)",
                                        a.kind, a.text or "", b.kind,
                                        b.text or "", a.x0, a.y0))
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

-- 1b: the mixer page ---------------------------------------------------------

print("\n-- the mixer page --")
do
  M.state.view = "mixer"
  for i = 1, M.mixer.PARAM_COUNT do
    M.state.mparam_focus = i
    screenui.redraw()
    draws_clean("mixer, fader " .. i)
  end
  -- and with every fader up, since a full knob draws the longest arc and the
  -- widest reading
  for _, p in ipairs(M.mixer.PARAMS) do p.set(1) end
  screenui.redraw()
  draws_clean("mixer, everything up")
  for _, p in ipairs(M.mixer.PARAMS) do p.set(0) end
  M.state.view = "global"
end

-- 1c: the header carries the transport, the tempo and the last event --------
-- all three share the top eleven pixels with the page name and the focused
-- value, and the two that vary in width (a message, an "ext" tempo) are the
-- ones that could push something off the panel.

print("\n-- the header, under pressure --")
do
  M.state.set_event("severed Tatterfoal (7) and then some", 5)
  screenui.redraw()
  draws_clean("header with a long message")

  M.state.global.still = true
  params:set("clock_source", 2)
  params:set("clock_tempo", 300)
  screenui.redraw()
  draws_clean("header, stopped and externally clocked")

  M.state.global.still = false
  params:set("clock_source", 1)
  params:set("clock_tempo", 120)
  M.state.last_event = ""
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
  check("a page holds eight widgets", per == 8, tostring(per))
  check("row 1 is on page 1", screenui.page_of(1) == 1)
  check("row 8 is still on page 1", screenui.page_of(8) == 1)
  check("row 9 starts page 2", screenui.page_of(9) == 2)
  check("voice.PARAMS needs two pages",
        screenui.page_of(M.voice.PARAM_COUNT) == 2,
        tostring(M.voice.PARAM_COUNT))

  -- and everything else lands on one, which is the point of eight rather
  -- than the Digitakt's ten: the only list on the panel long enough to
  -- paginate is a voice's twelve.
  local paginated = {}
  for id, cell in M.topology.each() do
    local page = cellparam.page(id)
    if page and screenui.page_of(page.PARAM_COUNT) > 1 then
      paginated[cell.type] = page.PARAM_COUNT
    end
  end
  local extra = {}
  for t, n in pairs(paginated) do
    if t ~= "voice" then table.insert(extra, t .. "(" .. n .. ")") end
  end
  check("and it is the only one that does", #extra == 0,
        table.concat(extra, ","))
  check("the global page fits on one",
        screenui.page_of(M.gparam.PARAM_COUNT) == 1,
        tostring(M.gparam.PARAM_COUNT))
  check("and so does the mixer",
        screenui.page_of(M.mixer.PARAM_COUNT) == 1,
        tostring(M.mixer.PARAM_COUNT))

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
