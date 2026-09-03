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

local function record(kind, x, y, w, h, text, level)
  table.insert(boxes, {kind = kind, x0 = x, y0 = y, x1 = x + w, y1 = y + h,
                       text = text, level = level})
end

local rec = {}
rec.clear = function() boxes = {} end
rec.update = function() end
-- the last level set before a shape is drawn -- the geometry checks below
-- never read it, but the map page test does, the same way test/gridui.lua
-- reads the physical grid's own led levels.
rec.level = function(l) cur.level = l end
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
-- §5.2c: the widget shapes are cubics now (lib/glyph.lua's Decay, Attack,
-- Body, Bright, Drive, Timbre). without this they were invisible to the
-- recorder and every one of them went unchecked -- a curve that ran into the
-- label under it would have drawn clean here. a cubic is contained by the
-- bounding box of its four points, so that box is what gets recorded, and it
-- is treated as a `line`: strokes are structure, and the same "text may not
-- sit inside a shape" rule that pins the gauges would be wrong for a curve
-- drawn deliberately behind nothing.
rec.curve = function(x1, y1, x2, y2, x3, y3)
  local xs = {cur.x, x1, x2, x3}
  local ys = {cur.y, y1, y2, y3}
  local x0, x9, y0, y9 = xs[1], xs[1], ys[1], ys[1]
  for i = 2, 4 do
    x0 = math.min(x0, xs[i]); x9 = math.max(x9, xs[i])
    y0 = math.min(y0, ys[i]); y9 = math.max(y9, ys[i])
  end
  record("line", x0, y0, x9 - x0, math.max(1, y9 - y0))
  cur.x, cur.y = x3, y3
end
rec.close = function() end
-- a rectangle is a box: filled it is a background, stroked it is a frame,
-- and either way text may legally sit inside it. a circle or an arc is a
-- knob gauge -- it has no inside to put words in, so text drawn through one
-- is a collision whichever way round they are.
local function flush(rect_kind)
  if cur.rect then
    record(rect_kind, cur.rect[1], cur.rect[2], cur.rect[3], cur.rect[4],
           nil, cur.level)
    cur.rect = nil
  end
  if cur.shape then
    record("shape", cur.shape[1], cur.shape[2], cur.shape[3], cur.shape[4],
           nil, cur.level)
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

-- 1d: the map page -------------------------------------------------------
-- every registered cell is drawn every time -- only its brightness changes
-- -- so what these check is the level each one gets, the same way
-- test/gridui.lua reads the physical grid's own led levels rather than
-- counting how many it called. a map cell is a 7x5 fill (MAP_RECT_W x
-- MAP_RECT_H in lib/screenui.lua); the header bar and its chips are also
-- "fill" boxes, but far bigger, and draw before the loop that puts one 7x5
-- fill per cell down in topology's own registration order -- so zipping
-- topology.order against just the 7x5 fills, in order, recovers which level
-- each cell got.

local function fills()
  local out = {}
  for _, b in ipairs(boxes) do
    if b.kind == "fill" and (b.x1 - b.x0) == 7 and (b.y1 - b.y0) == 5 then
      table.insert(out, b)
    end
  end
  return out
end

local function cell_levels(M)
  local out, matched = {}, fills()
  for i, id in ipairs(M.topology.order) do
    out[id] = matched[i] and matched[i].level
  end
  return out
end

local function has_text(s)
  for _, b in ipairs(boxes) do
    if b.kind == "text" and b.text == s then return true end
  end
  return false
end

print("\n-- the map page --")
-- uses the top-level M (fresh(1)) rather than a fresh() of its own: screenui
-- resolved its topology/patch/state/etc. locals once, the first time it was
-- loaded (module-load-time wl() calls, lib/screenui.lua's own top-of-file
-- section) -- against whatever fresh() had most recently populated, which by
-- the time `local screenui = wl("screenui")` runs a few lines up is M's. a
-- later fresh() (M2/M3 elsewhere in this file) hands back genuinely new
-- module tables that screenui's already-loaded closure never sees again, so
-- mutating one of those and expecting it to show up on screen is a no-op --
-- fine for the sections below that only check generic layout, not fine for
-- assertions about specific cable/focus content like these.
do
  M.state.view = "map"

  screenui.redraw()
  draws_clean("map, idle")
  check("map, idle: one box per registered cell",
        #fills() == #M.topology.order, tostring(#fills()))

  local idle = cell_levels(M)
  check("map, idle: an uncabled cell is dim but present",
        idle["oak"] and idle["oak"] > 0 and idle["oak"] < 8,
        tostring(idle["oak"]))

  for _, other in ipairs({"o.1", "d.hob", "gu.sough"}) do
    M.patch.add("oak", other, 0.5)
  end
  screenui.redraw()
  draws_clean("map, a live patch")
  local live = cell_levels(M)
  check("map, a live patch: a cabled cell lights up",
        live["oak"] and live["oak"] > idle["oak"],
        tostring(live["oak"]) .. " vs idle " .. tostring(idle["oak"]))
  check("map, a live patch: an uncabled cell is unchanged",
        live["f.bittern"] == idle["f.bittern"],
        tostring(live["f.bittern"]) .. " vs idle " .. tostring(idle["f.bittern"]))

  -- holding a cell from the map still goes straight to that cell's own
  -- settings page -- same as from any other screen -- rather than staying on
  -- the map. the header carries the cell's own tag, not "MAP", and there are
  -- no 7x5 map fills at all: this is voice.PARAMS' widget grid.
  M.state.held = {"oak"}
  screenui.redraw()
  draws_clean("map, holding a cell")
  check("map, held: goes to the cell's own page, not the map",
        not has_text("MAP") and #fills() == 0,
        tostring(has_text("MAP")) .. "/" .. tostring(#fills()))
  M.state.held = {}

  -- letting go comes back to the map -- state.view was never touched.
  screenui.redraw()
  check("map, after letting go: back on the map",
        has_text("MAP"), tostring(has_text("MAP")))

  -- tapping a cell open (state.cell_edit) does the same thing.
  M.state.cell_edit = "oak"
  screenui.redraw()
  draws_clean("map, oak's page open")
  check("map, cell_edit: goes to the cell's own page, not the map",
        not has_text("MAP") and #fills() == 0,
        tostring(has_text("MAP")) .. "/" .. tostring(#fills()))
  M.state.cell_edit = nil
  screenui.redraw()
  check("map, after closing: back on the map",
        has_text("MAP"), tostring(has_text("MAP")))

  -- two cells held is still the edge view (cable gain), on this page same
  -- as any other.
  M.state.held = {"oak", "o.1"}
  screenui.redraw()
  check("map, two held: falls back to the edge view",
        has_text("cable") and not has_text("MAP"), "")
  M.state.held = {}

  -- leave M exactly as the sections below expect to find it: no stray
  -- cables from this section's patch, back on the main screen.
  M.patch.clear()
  M.state.view = "global"
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

-- 6: the glyph vocabulary ----------------------------------------------------
-- §5.2c. the widget grid stopped being eight identical gauges and became one
-- drawn shape per parameter (lib/glyph.lua), which introduces two ways to be
-- wrong that no geometry check above can see: a row can name a shape that
-- does not exist (it silently falls back to `fader`, so the panel looks fine
-- and the parameter is mislabelled forever), and two rows on the SAME page
-- can end up with the same shape, which puts you straight back to reading the
-- words -- the exact failure the whole re-cut was meant to remove.

print("\n-- the glyph set --")
do
  local glyph = wl("glyph")

  -- every list of rows the panel can put on screen, and what it is called
  local lists = {{"gparam", M.gparam.PARAMS}, {"mixer", M.mixer.PARAMS}}
  local seen_type = {}
  for id, cell in M.topology.each() do
    if not seen_type[cell.type] then
      seen_type[cell.type] = true
      local page = cellparam.page(id)
      if page then table.insert(lists, {cell.type, page.PARAMS}) end
    end
  end

  local unknown, unnamed = {}, {}
  local rows = 0
  for _, entry in ipairs(lists) do
    for _, p in ipairs(entry[2]) do
      rows = rows + 1
      if p.glyph == nil then
        table.insert(unnamed, entry[1] .. "." .. tostring(p.label))
      elseif not glyph.exists(p.glyph) then
        table.insert(unknown, entry[1] .. "." .. tostring(p.label)
                              .. " -> " .. tostring(p.glyph))
      end
    end
  end
  check("every row names a shape", #unnamed == 0, table.concat(unnamed, ","))
  check("and every shape it names exists", #unknown == 0,
        table.concat(unknown, ","))
  check("and that was every row on the panel", rows > 60, tostring(rows))

  -- one shape may not appear twice on one screenful. the two exceptions are
  -- deliberate and named here rather than left to be rediscovered:
  --   mixer   five faders in a row IS what a mixer looks like; the repetition
  --           is the reading (lib/mixer.lua says so at level_row).
  --   D       Gait is a bank of nine and Grid is a read-only quantise name.
  --           both are words, and a word has no other shape to be.
  local ALLOWED = {mixer = true, D = true}
  local dupes = {}
  for _, entry in ipairs(lists) do
    local name, params = entry[1], entry[2]
    if not ALLOWED[name] then
      for page = 1, math.ceil(#params / screenui.PARAMS_PER_PAGE) do
        local first = (page - 1) * screenui.PARAMS_PER_PAGE + 1
        local used = {}
        for i = first, math.min(#params, first + screenui.PARAMS_PER_PAGE - 1) do
          local g = params[i].glyph
          if used[g] then
            table.insert(dupes, name .. " page " .. page .. ": " .. tostring(g)
                                .. " on both " .. tostring(used[g]) .. " and "
                                .. tostring(params[i].label))
          end
          used[g] = params[i].label
        end
      end
    end
  end
  check("no page shows the same shape twice", #dupes == 0, dupes[1] or "")
end

-- 7: the block arithmetic ----------------------------------------------------
-- the header shrank from 11 to 8 and the widget grew from 11 to 19, and the
-- value line went. those three numbers have to still add up to 64 -- the old
-- layout's failure mode was a row that overran the panel by two pixels and
-- only showed up on hardware.

print("\n-- the block arithmetic --")
do
  local glyph = wl("glyph")
  local top = screenui.BLOCK_TOP
  check("the header is 8px", screenui.HEADER_H == 8, tostring(screenui.HEADER_H))
  check("row 1 starts below it", top[1] >= screenui.HEADER_H,
        tostring(top[1]))
  check("row 2 starts below row 1's label",
        top[2] >= top[1] + glyph.H + 6, tostring(top[2]))
  -- the label baseline is 26 from the block top; the font's descender lands
  -- one pixel under it, so the bottom row's last lit pixel is at top[2] + 27.
  check("and the bottom label's descender is still on the panel",
        top[2] + 27 <= 64, tostring(top[2] + 27))
  check("the shape is 26 x 19", glyph.W == 26 and glyph.H == 19,
        glyph.W .. "x" .. glyph.H)
end

-- 8: the scopes --------------------------------------------------------------
-- a page of four rows or fewer hands its second block to a live display
-- instead of to three lines of lexicon prose. what this pins is that the two
-- that exist actually draw INTO that block rather than over the row above it,
-- and that a type without one still gets its sentence.

print("\n-- the scopes --")
do
  local function drew_below(y)
    for _, b in ipairs(boxes) do
      if b.kind ~= "line" and b.y0 >= y then return true end
    end
    return false
  end

  local function first_scope_cell(t)
    for id, cell in M.topology.each() do
      if cell.type == t then return id end
    end
  end

  for _, t in ipairs({"LFO", "D"}) do
    local id = first_scope_cell(t)
    check(t .. ": has a scope", screenui.SCOPES[t] ~= nil, t)
    if id then
      M.state.cell_edit = id
      M.state.vparam_focus = 1
      screenui.redraw()
      draws_clean(t .. " with its scope")
      check(t .. ": the scope drew in the lower block", drew_below(37), id)
      M.state.cell_edit = nil
    end
  end

  -- a type with no scope keeps the lexicon sentence, which is the fallback
  -- that lets the rest land one family at a time.
  local e = first_scope_cell("E")
  if e then
    M.state.cell_edit = e
    M.state.vparam_focus = 1
    screenui.redraw()
    draws_clean("E with its description")
    check("a type with no scope still gets its sentence",
          screenui.SCOPES.E == nil and drew_below(40), e)
    M.state.cell_edit = nil
  end
end

-- 9: the lexicon's own reachability -----------------------------------------
-- interaction_text canonicalises a pair by sorting it on TYPE_ORDER before it
-- looks the string up, so a key written in the other order is dead text: the
-- edge view falls through to "no direct interaction defined" and nobody
-- notices, because the fallback is a plausible sentence. eleven keys were
-- written that way, including every "something strikes a voice" cable. the
-- rule is simply that each key has to be what the lookup produces for its own
-- two types -- which is a fixed point check, and needs no fixture at all.

print("\n-- the lexicon's own reachability --")
do
  -- both are file-locals in lib/screenui.lua, deliberately: the panel is the
  -- only consumer. reach them through draw_edge's upvalues rather than
  -- widening the module for a test.
  local function upvalue(f, want)
    local i = 1
    while true do
      local name, value = debug.getupvalue(f, i)
      if name == nil then return nil end
      if name == want then return value end
      i = i + 1
    end
  end

  local interaction_text = upvalue(screenui.draw_edge, "interaction_text")
  local descs = interaction_text and upvalue(interaction_text, "INTERACTION_DESC")
  check("the lexicon and its lookup are reachable",
        type(interaction_text) == "function" and type(descs) == "table", "")

  if descs then
    local dead = {}
    for key, text in pairs(descs) do
      local a, b = key:match("^([^|]+)|([^|]+)$")
      if not a then
        table.insert(dead, key .. ": not an a|b pair")
      elseif interaction_text(a, b) ~= text then
        table.insert(dead, key .. ": reads as \"" .. interaction_text(a, b) .. "\"")
      end
    end
    table.sort(dead)
    check("every key is what the lookup produces for its own pair",
          #dead == 0, #dead .. " dead: " .. (dead[1] or ""))
    -- and the pair is order-free at the call site, which is what the sort is
    -- there for in the first place.
    check("a pair reads the same held either way round",
          interaction_text("D", "voice") == interaction_text("voice", "D")
          and interaction_text("D", "voice") ~= "no direct interaction defined",
          interaction_text("D", "voice"))
  end
end

report()
