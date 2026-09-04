-- screenui.lua
-- the global param page, the mixer page, the per-cell settings page, and the
-- edge view.
--
-- the lexicon pages are gone. they were a manual you had to leave the patch
-- to read, and everything worth reading off them -- what a cell's one knob
-- means, what a cable between two types does -- is already printed on the
-- cell and edge views, at the moment you are holding the thing it is about.
--
-- the network view -- the patch drawn as a lit map with dotted cable "wires"
-- -- is gone too, replaced by §5.2's global param page: the same E1-select,
-- E2/E3-nudge shape as the cell page, for the macros that reach every voice
-- at once (lib/gparam.lua) rather than one.
--
-- §5.2b the Digitakt layout. every page on this screen used to be a
-- two-column list of `label ....... value` rows with a hairline bar under
-- each. it was compact, and it read like a settings menu -- twelve rows of
-- small type you parse left to right, one at a time, while the thing you are
-- editing is making noise. an Elektron box solves the same problem the
-- opposite way round: a title bar that never moves, and then a fixed grid of
-- WIDGETS, one per parameter, each of which shows its value as a *shape* you
-- read at a glance and its name as a word underneath. you look at the grid,
-- not at the rows.
--
-- so, three parts, and every page on the screen is made of them:
--
--   * the header bar -- inverted, full width, always the same six things in
--     the same six places: the transport, what kind of page this is, which
--     page of it, its name, the value of whatever the cursor is on, and the
--     tempo. it never moves and it is never empty.
--   * a 4 x 2 grid of widgets, eight to a page. a continuous parameter draws
--     as a knob (a gauge arc plus a pointer); one whose value is a WORD --
--     a gait, a scale, on/off -- draws as a boxed readout instead, since a
--     pointer angle tells you nothing about "euclidean". the focused one is
--     drawn bright, everything else dim.
--   * the label under each widget, which is the parameter's name. the
--     *value* is never trimmed: whatever the cursor is on is spelled out in
--     full in the header, so a clipped "eucl" in the grid always has
--     "euclidean" above it.
--
-- four columns and not the Digitakt's five, for one reason: at five, a column
-- is twenty-five pixels, and twenty-five pixels of this font is four or five
-- characters -- which turns both "Scatter" and "Scale" into "Sca.", two
-- adjacent parameters that now read identically. thirty-two pixels fits the
-- longest label the panel has. it also means eight to a page rather than ten,
-- which lands every page in the script except a voice's twelve on one screen.
--
-- what that buys, beyond looking like the thing it is inspired by: a grid of
-- eight can be taken in at once where eight rows of text cannot, and the
-- header's value readout means no page has to choose between showing a name
-- and showing a number.
--
-- text metrics, and why they are measured rather than assumed. the norns font
-- is variable-width, so anything that shares a line with something else --
-- which on a 128px panel is everything -- is fitted with screen.text_extents
-- before it is drawn, and gives way (ending in a full stop) rather than
-- running into its neighbour. the font puts about five pixels above a
-- baseline and one below it, so a run of text at y occupies y-5 .. y+1; every
-- y coordinate in here is placed against that. test/screen.lua checks the
-- whole panel, every page, every row, for overlaps and overruns.

local topology   = wl("topology")
local patch      = wl("patch")
local state      = wl("state")
local gparam     = wl("gparam")
local mixer      = wl("mixer")
local cellparam  = wl("cellparam")
local lexicon    = wl("lexicon")
local glyph      = wl("glyph")

local screenui = {}

-- text metrics ----------------------------------------------------------------
-- screen.text_extents is the only honest measure of the variable-width font.
-- the offline harness has no real screen, so fall back to a per-character
-- estimate there -- everything that depends on this is layout, not behaviour.

local CHAR_W = 5

local function text_w(str)
  if str == nil or str == "" then return 0 end
  local ok, w = pcall(screen.text_extents, str)
  if ok and type(w) == "number" then return w end
  return #str * CHAR_W
end

-- trim `str` until it fits `limit` pixels, ending in a full stop if anything
-- was dropped. used everywhere two pieces of text share one line.
local function fit(str, limit)
  str = str or ""
  if limit <= 0 then return "" end
  if text_w(str) <= limit then return str end
  while #str > 1 do
    str = str:sub(1, #str - 1)
    if text_w(str .. ".") <= limit then return str .. "." end
  end
  return ""
end

-- the same, without the full stop: inside a widget box there are only four or
-- five characters to spend and one of them cannot be punctuation. the full
-- value is in the header, so nothing is lost by trimming silently here.
local function clip(str, limit)
  str = str or ""
  if limit <= 0 then return "" end
  while #str > 0 and text_w(str) > limit do
    str = str:sub(1, #str - 1)
  end
  return str
end

-- a label on the left and a value on the right of one line, guaranteed not to
-- touch: the value is whole (it is the number you came to read) and the label
-- gives way.
local GAP = 4

local function label_value(x, y, w, label, value, label_lvl, value_lvl)
  local vw = text_w(value)
  screen.level(value_lvl)
  screen.move(x + w, y)
  screen.text_right(value)
  screen.level(label_lvl)
  screen.move(x, y)
  screen.text(fit(label, w - vw - GAP))
end

-- `lvl` is optional: a caller that has already set the level (every glyph
-- does, since brightness is how focus is drawn) passes nothing rather than
-- spending a second screen.level on the same value.
local function centred(cx, y, str, lvl)
  if str == nil or str == "" then return end
  if lvl then screen.level(lvl) end
  screen.move(cx - text_w(str) / 2, y)
  screen.text(str)
end

-- lib/glyph.lua's `word` is the only shape that draws text, and the text
-- metrics live here (screen.text_extents, with the offline fallback). rather
-- than keep two copies of the measuring code, hand it this one.
glyph.centred = function(cx, y, str, limit)
  centred(cx, y, clip(str, limit))
end

-- naive word wrap for the small screen font
local function wrap(str, max_chars)
  local lines, line = {}, ""
  for word in str:gmatch("%S+") do
    local candidate = (line == "") and word or (line .. " " .. word)
    if #candidate > max_chars then
      table.insert(lines, line)
      line = word
    else
      line = candidate
    end
  end
  if line ~= "" then table.insert(lines, line) end
  return lines
end

-- the header bar --------------------------------------------------------------
-- §5.2c. this used to be an 11px inverted slab: a filled rectangle spanning
-- the whole panel with the text knocked out of it, two boxed chips inside it
-- (the cell tag on the left, the tempo on the right), and the focused
-- parameter's full value in the middle. that is a sixth of a 64px screen lit
-- solid, permanently, to say "Oak" -- and on a display with no colour, the
-- brightest thing on the panel is the thing the eye goes to first. it was
-- going to the title.
--
-- so: 8px, no fill, no chips, and a 1px rule underneath. the same five things
-- are still on it (transport, tag, name, page dots, tempo) as plain text at
-- three different levels, which is enough hierarchy on a 16-level display and
-- costs nothing. the value readout is gone entirely -- every widget now draws
-- its own value, so the header no longer has to choose between showing a name
-- and showing a number.
--
-- a baseline at 6 puts the font's 5px ascenders at 1 and its 1px descenders
-- at 7; the rule sits at 7.5 and the first widget row starts at 9.

local HDR_H = 8
local HDR_BASE = 6

-- the transport, in five pixels: a filled square when the patch is frozen and
-- a triangle when it is running. Still (K2) and an external MIDI Stop are the
-- same state (§4.3), so this one glyph reports both.
local function draw_transport(x)
  screen.level(12)
  if state.global.still then
    screen.rect(x, 2, 4, 4)
    screen.fill()
  else
    screen.move(x, 1)
    screen.line(x + 4, 3.5)
    screen.line(x, 6)
    screen.close()
    screen.fill()
  end
end

-- how many pages this list has, as dots: filled for the one you are on. the
-- unlit ones accumulate into a single path and paint once (see the frame
-- budget note in lib/glyph.lua) rather than costing a fill each.
local function draw_page_dots(x, page, pages)
  local w = pages * 4 - 1
  screen.level(4)
  local any = false
  for i = 1, pages do
    if i ~= page then
      screen.rect(x + (i - 1) * 4 + 1, 3, 1, 1)
      any = true
    end
  end
  if any then screen.fill() end
  screen.level(13)
  screen.rect(x + (page - 1) * 4, 2, 3, 3)
  screen.fill()
  return w
end

-- the tempo, which is on screen on every page whatever the page is about --
-- it is the one number the whole patch is hung off, and the one number that
-- survived §5.2c's cull, because it is not a parameter any widget draws.
-- "ext" when something else is deciding it (§4.3).
local function tempo_text()
  local bpm = gparam.tempo and gparam.tempo() or (state.global.bpm or 120)
  if gparam.external_clock and gparam.external_clock() then
    return string.format("%.0f ext", bpm)
  end
  return string.format("%.0f", bpm)
end

-- tag: what kind of page this is, dim, in front of the name. it is the one
-- thing the name alone cannot tell you: "Bittern" does not say whether it is
-- a pitch field or a drum.
--
-- it used to be the cell's one-letter panel code -- "M Oak", "T Hob",
-- "R Tangle". that letter is silk-screened nowhere; on a monome there is no
-- legend to look it up in, so reading the header at all meant having the
-- alphabet memorised. it is a word now (topology.family), and the header
-- reads "Voice: Oak", "Trigger: Hob", "Process: Tangle". the whole-page tags
-- ("Mixer", "Map", "Canopy") are the same idea and were already words.
function screenui.draw_header(tag, name, page, pages)
  draw_transport(1)

  -- laid out from the right, because the two things on that side (tempo, page
  -- dots) have known widths and the name is what gives way.
  local right = 127
  local tempo = tempo_text()
  screen.level(9)
  screen.move(right, HDR_BASE)
  screen.text_right(tempo)
  right = right - text_w(tempo) - 5

  if pages and pages > 1 then
    right = right - draw_page_dots(right - (pages * 4 - 1), page or 1, pages) - 4
  end

  local x = 7
  if tag and tag ~= "" then
    screen.level(6)
    screen.move(x, HDR_BASE)
    screen.text(tag)
    x = x + text_w(tag) + 3
  end

  screen.level(15)
  screen.move(x, HDR_BASE)
  screen.text(fit(name or "", right - x))

  screen.level(3)
  screen.move(0, HDR_H - 0.5)
  screen.line(128, HDR_H - 0.5)
  screen.stroke()
end

-- the widget grid ---------------------------------------------------------------
-- four columns, two rows, eight to a page; a longer list paginates rather
-- than wrapping back over itself, and E1's focus decides which page you are
-- on so the widget you are turning is always one you can see.
--
-- §5.2c re-cut the block. it was: an 11px gauge, the label under it, and the
-- value under that -- 25px, under an 11px header. it is now a 19px SHAPE and
-- the label, under an 8px header. the seven pixels the value line gave back
-- and the three the header gave back are both spent on the same thing, which
-- is height for the drawing: eight identical circles told you a quantity but
-- never which quantity, so you read the eight words underneath every time and
-- the grid was a list wearing a costume. lib/glyph.lua explains what replaced
-- them and what that costs.

local PL_COLS = 4
local PL_ROWS = 2
local PL_PER_PAGE = PL_COLS * PL_ROWS

-- the panel is 128 wide and 64 tall; the header takes the top eight, which
-- leaves two 27px blocks with two pixels to spare. within a block the shape
-- occupies the first nineteen rows and the label's baseline is at 26 -- so
-- the font's 5px ascenders start two pixels below where the shape stops, and
-- the bottom row's descenders land on 63.
local COL_W = 32
local COL_X0 = 0                    -- left edge of column 1
local BLOCK_TOP = {9, 37}           -- top of each widget row
local BLOCK_H = 27
local GLYPH_W, GLYPH_H = glyph.W, glyph.H
local GLYPH_DX = math.floor((COL_W - GLYPH_W) / 2)
local LABEL_DY = 26                 -- label baseline, from the block's top

screenui.PARAMS_PER_PAGE = PL_PER_PAGE
screenui.BLOCK_TOP = BLOCK_TOP
screenui.BLOCK_H = BLOCK_H
screenui.HEADER_H = HDR_H

-- 1-based page number a given row lives on.
function screenui.page_of(i)
  return math.floor((i - 1) / PL_PER_PAGE) + 1
end

-- one widget: the shape, then the name. nothing else -- see lib/glyph.lua.
--
-- the label is clipped rather than fitted: a trailing full stop costs a whole
-- character here and says nothing the widget's position in the grid does not.
-- the four pixels held back are the gutter -- at the full column width two
-- long labels in neighbouring columns run into each other.
local function draw_widget(slot, p, text, frac, on, data)
  local col = slot % PL_COLS
  local row = math.floor(slot / PL_COLS) + 1
  local top = BLOCK_TOP[row]
  local x = COL_X0 + col * COL_W + GLYPH_DX

  glyph.draw(p.glyph, x, top, GLYPH_W, GLYPH_H, frac, on, text, data)

  screen.level(on and 15 or 6)
  centred(x + GLYPH_W / 2, top + LABEL_DY, clip(p.label, COL_W - 4))
end

-- draw one page of a PARAMS list. `text_fn`/`frac_fn`/`data_fn` adapt the two
-- calling conventions in the codebase (a cell page's take an id, a global
-- page's take nothing) so this routine never learns which kind of list it has.
-- `data_fn` is the extras a few shapes need -- a bank position, a shift
-- register -- and is nil for every row that does not declare glyph_data.
local function draw_param_grid(params, focus, text_fn, frac_fn, data_fn)
  local page = screenui.page_of(focus)
  local first = (page - 1) * PL_PER_PAGE + 1
  for slot = 0, PL_PER_PAGE - 1 do
    local p = params[first + slot]
    if p then
      draw_widget(slot, p, text_fn(p), frac_fn(p), (first + slot) == focus,
                  data_fn and data_fn(p) or nil)
    end
  end
  return page, math.max(1, math.ceil(#params / PL_PER_PAGE))
end

-- how many of the eight slots a page actually uses, which is what decides
-- whether the second block is free for a scope (see draw_cell_scope).
local function slots_used(count, focus)
  local first = (screenui.page_of(focus) - 1) * PL_PER_PAGE + 1
  return math.max(0, math.min(PL_PER_PAGE, count - first + 1))
end

-- §5.2 global param page (nothing held, no cell page open) --------------------
-- what replaced the network view: E1 walks gparam.PARAMS, E2/E3 nudge the one
-- under the cursor coarse/fine (Canopy.lua's enc()).
--
-- the header's name slot is always the page's own name now -- an earlier cut
-- borrowed it for a few seconds to report "whatever just happened", but a
-- readout of every patch/knob event turned out to be noise nobody read.
-- state.set_event/state.last_event are unchanged and other code still uses
-- them; only the screen stopped showing them.

function screenui.draw_global()
  local focus = util.clamp(state.gparam_focus or 1, 1, gparam.PARAM_COUNT)
  local p = gparam.param(focus)
  local pages = math.ceil(gparam.PARAM_COUNT / PL_PER_PAGE)
  screenui.draw_header("", "Canopy", screenui.page_of(focus), pages)
  draw_param_grid(gparam.PARAMS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end,
                  function(q) return q.glyph_data and q.glyph_data() or nil end)
end

-- §4.1b the mixer page (K3, back with K2) --------------------------------------
-- the master, then one fader per Output cell the patch is actually using
-- (lib/mixer.lua). the list grows and shrinks with the cables, so the header
-- says how many channels are open: with nothing patched this page is one
-- fader and a lot of space, and that is the honest picture.

function screenui.draw_mixer()
  local focus = util.clamp(state.mparam_focus or 1, 1, mixer.PARAM_COUNT)
  local pages = math.max(1, math.ceil(mixer.PARAM_COUNT / PL_PER_PAGE))
  screenui.draw_header("Mixer", (mixer.PARAM_COUNT - 1) .. " out",
                       screenui.page_of(focus), pages)
  draw_param_grid(mixer.PARAMS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end,
                  function(q) return q.glyph_data and q.glyph_data() or nil end)
end

-- the cell page (one cell held, or one cell tapped open) ----------------------
-- the same page either way. holding is a glance: the encoders are on it for
-- as long as you hold, and the patch gesture is still live underneath.
-- tapping latches it open and the grid goes back to patching -- and dims
-- everything that is not this cell (gridui.grid_redraw), so the panel is
-- showing the same one thing the screen is.

-- "Voice:" in the tag slot and "Oak" in the name slot. a cell already named
-- for its family -- "Gust 7", "Clock 2" -- gets no tag: "Gust: Gust 7" says
-- one thing twice, and the pixels are better spent on the name.
local function cell_tag(cell)
  local fam = topology.family(cell)
  if fam == "" or cell.name:sub(1, #fam) == fam then return "" end
  return fam .. ":"
end

-- "what does this cell do", under the grid rather than instead of it: it
-- only fits when the page on screen right now leaves its whole second row
-- empty (four rows or fewer -- D, R, F, E, H, C, O, and a voice's second
-- page all qualify; TM's eight and a voice's first page do not, and a
-- GVOICE/GUST page's six leaves it only half empty, so those stay quiet
-- rather than crowd two free columns). toggle_page (gridui.lua) resets
-- vparam_focus to 1 on every tap, so this is exactly the state a freshly
-- opened cell lands on -- it reads once, up front, and gives way the moment
-- E1 walks onto a page with less room.
local DESC_Y0 = 44
local DESC_LINE_H = 9
local DESC_MAX_LINES = 3
local DESC_WRAP_CHARS = 30

local function draw_cell_desc(id)
  local text = lexicon.describe(id)
  if not text or text == "" then return end
  screen.level(6)
  local lines = wrap(text, DESC_WRAP_CHARS)
  for i, line in ipairs(lines) do
    if i > DESC_MAX_LINES then break end
    screen.move(2, DESC_Y0 + (i - 1) * DESC_LINE_H)
    screen.text(fit(line, 124))
  end
end

-- §5.2c the scopes -----------------------------------------------------------
-- what the free block is actually for. a page of four rows or fewer leaves
-- the whole second block empty, and until now that filled with three wrapped
-- lines from the lexicon -- a sentence you read once on the first day and
-- then never again, sitting in the best display real estate on the panel
-- while the thing you are listening to went undrawn.
--
-- so: one live display per cell type, keyed below. every one of these is
-- drawn from state that already exists in Lua and is already being read at
-- frame rate for the grid LEDs -- lfo.phase(id) and rambler.info(id).phase
-- both cost nothing here that gridui was not already paying. a type with no
-- entry falls back to the prose, so this lands one family at a time.
--
-- the block is 128 x 27 at y = 37. the frame is four corner pixels and
-- nothing else: a full box would be 4 more commands and would fence off the
-- one part of the screen that wants to feel open.

local SCOPE_Y = 37
local SCOPE_H = 27

local function scope_corners()
  screen.level(3)
  screen.rect(0, SCOPE_Y, 1, 1)
  screen.rect(127, SCOPE_Y, 1, 1)
  screen.rect(0, SCOPE_Y + SCOPE_H - 1, 1, 1)
  screen.rect(127, SCOPE_Y + SCOPE_H - 1, 1, 1)
  screen.fill()
end

local SCOPES = {}

-- an LFO is a sine and the screen never once showed a sine. the wave scrolls
-- and the right-hand edge is now; the current value is carried out to the
-- margin as a 3px dot, which is the only part of it that matters when you are
-- listening rather than looking.
--
-- sampled, not curved: the phase moves every frame, and a cubic's control
-- points would have to be re-derived per frame anyway. 26 samples across 92
-- pixels is one command each -- affordable here precisely because an LFO page
-- has one widget on it and the whole frame is nowhere near the budget.
SCOPES.LFO = function(id)
  local phase = wl("lfo").phase(id)
  local my = SCOPE_Y + SCOPE_H / 2
  local amp = SCOPE_H / 2 - 4
  local L, R = 4, 118
  local N = 26

  screen.level(2)
  screen.move(L, my)
  screen.line(R, my)
  screen.stroke()

  local function at(t)
    return my - math.sin((t * 2 + phase) * 2 * math.pi) * amp
  end

  screen.level(13)
  screen.move(L, at(0))
  for i = 1, N do
    local t = i / N
    screen.line(L + t * (R - L), at(t))
  end
  screen.stroke()

  -- the writing head, and the value it is writing
  local ey = at(1)
  screen.level(5)
  screen.move(R + 3, SCOPE_Y + 2)
  screen.line(R + 3, SCOPE_Y + SCOPE_H - 3)
  screen.stroke()
  screen.level(15)
  screen.rect(R + 2, ey - 1, 3, 3)
  screen.fill()
  screen.move(R + 6, ey)
  screen.line(126, ey)
  screen.stroke()
end

-- a D cell's phase, which is the gait. a metric gait sweeps evenly and a
-- swung or euclidean one does not, so the bar itself tells you which you are
-- on without reading the word -- and the reset is the pulse.
SCOPES.D = function(id)
  local info = wl("rambler").info(id)
  if not info then return end
  local phase = util.clamp(info.phase or 0, 0, 1)
  local base = SCOPE_Y + SCOPE_H - 6
  local L, R = 4, 123

  -- the cycle, with its quarters ticked
  screen.level(3)
  for i = 0, 4 do
    local px = L + (R - L) * i / 4
    screen.rect(px, base - 2, 1, 3)
  end
  screen.rect(L, base, R - L, 1)
  screen.fill()

  -- how far through it we are
  screen.level(11)
  screen.rect(L, base - 6, (R - L) * phase, 5)
  screen.fill()

  -- and the head, which is where the next pulse comes from
  screen.level(15)
  screen.rect(L + (R - L) * phase - 1, base - 9, 2, 11)
  screen.fill()

  if info.grid then
    screen.level(5)
    screen.move(L, SCOPE_Y + 8)
    screen.text(fit(info.grid, 120))
  end
end

-- the block under a cell page: a scope if this type has one and the page
-- leaves the room, the lexicon's sentence otherwise.
local function draw_cell_scope(id, cell)
  local f = SCOPES[cell.type]
  if f then
    scope_corners()
    f(id)
  else
    draw_cell_desc(id)
  end
end

screenui.SCOPES = SCOPES

-- there is no `live` argument any more. the old header said "M · open" for a
-- latched page and just "M" for a held glance; the tag chip has room for the
-- letter and nothing else, and the panel now says which it is far more
-- plainly than a word could -- an open page dims the whole grid (§5.1b), a
-- held one lights up the cell you are holding.
function screenui.draw_cell(id)
  local cell = topology.get(id)
  if not cell then return end
  local page_mod = cellparam.page(id)

  local count = page_mod and page_mod.PARAM_COUNT or 0
  local focus = util.clamp(state.vparam_focus or 1, 1, math.max(1, count))
  local pages = math.max(1, math.ceil(count / PL_PER_PAGE))

  screenui.draw_header(cell_tag(cell), cell.name,
                       screenui.page_of(focus), pages)

  if page_mod then
    draw_param_grid(page_mod.PARAMS, focus,
                    function(p) return p.text(id) end,
                    function(p) return p.get(id) end,
                    function(p) return p.glyph_data and p.glyph_data(id) or nil end)

    if slots_used(count, focus) <= PL_COLS then
      draw_cell_scope(id, cell)
    end
  end
end

-- §4.1d the map page (K3, twice) -----------------------------------------
-- a reference, not a control surface: the same 16x8 layout topology.lua lays
-- the panel out on (§2's own map, in the comment at the top of that file),
-- redrawn small under the header. no wires -- a cable's other end is already
-- one hold away on the real grid -- just which cells are patched at all: lit
-- if something reaches them, dim (not blank) if not, so an unused cell still
-- reads as a cell rather than as a gap. an unregistered coordinate (the "."
-- in topology's map) is skipped outright -- it was never a cell to begin
-- with, and drawing it at any level would say otherwise.
--
-- holding a cell or tapping one open still does exactly what it does on
-- every other screen -- takes over the screen with that cell's own settings
-- page (screenui.draw_cell) -- so this page never has to draw anything a
-- hold/tap gesture might land on; it only ever shows all of them at once.

local MAP_COLS = topology.GRID_W
local MAP_TOP = 11
local MAP_CELL_W = 128 / MAP_COLS
local MAP_CELL_H = 6
local MAP_RECT_W = MAP_CELL_W - 1
local MAP_RECT_H = MAP_CELL_H - 1

local MAP_ON, MAP_OFF = 13, 2 -- cabled / not

function screenui.draw_map()
  local active = 0
  for id in topology.each() do
    if patch.degree(id) > 0 then active = active + 1 end
  end

  screenui.draw_header("Map", active .. "/" .. #topology.order .. " patched")

  for id, cell in topology.each() do
    screen.level(patch.degree(id) > 0 and MAP_ON or MAP_OFF)
    for _, c in ipairs(cell.coords) do
      screen.rect((c[1] - 1) * MAP_CELL_W, MAP_TOP + (c[2] - 1) * MAP_CELL_H,
                  MAP_RECT_W, MAP_RECT_H)
      screen.fill()
    end
  end
end

-- edge view (two cells held) -------------------------------------------------

-- what a cable between two kinds of cell actually does, in one sentence. the
-- edge view (two cells held) prints this under the two names, wrapped to
-- three lines, so it is written the way the cell descriptions in
-- lexicon.lua are: plain words, the effect first, no dashes standing in for
-- a clause.
--
-- the shape of the matrix: a voice is one point that reacts to whatever is at
-- the other end. a pulse always strikes it. a continuous stream (an exciter,
-- a gust, an LFO) always drives its mod path. a pitch field or a register
-- tunes it. another voice does both at once, in both directions. an Output
-- cell is a pure destination and never talks back.
local INTERACTION_DESC = {
  ["voice|voice"] = "each voice's sound modulates the other, and either one answers a strike",
  ["voice|O"] = "the voice is heard, panned to where this output sits",
  ["voice|D"] = "the pulse strikes the voice, which then answers with a pulse",
  ["voice|R"] = "the changed pulse strikes the voice, which answers in turn",
  ["voice|TM"] = "the pulse clocks the pattern and strikes the voice, and also tunes it",
  ["voice|C"] = "the clock pulse strikes the voice",
  ["voice|E"] = "the exciter drives the voice's mod path. Balance sets what it does",
  ["voice|F"] = "the field tunes the voice, as far as its own Range knob allows",
  ["D|D"] = "the two pull each other into time, and each also triggers the other",
  ["D|R"] = "the pulse goes through this rule on its way out",
  ["R|R"] = "two rules in series. the chain is the pattern",
  ["D|E"] = "each pulse cuts the exciter into a short grain. it runs free otherwise",
  ["R|E"] = "the changed pulse fires one grain of the exciter",
  ["E|E"] = "each exciter modulates the other's colour",
  ["E|O"] = "the exciter is heard, panned to where this output sits",
  ["D|F"] = "each pulse steps the field to a new note",
  ["R|F"] = "the changed pulse steps the field",
  ["E|F"] = "the exciter's colour follows the field's line",
  ["F|F"] = "the two fields pull together, or apart at negative gain",
  ["D|C"] = "nothing. a clock cell only ever sends",
  -- §2.7b a percussion cell has no separate trigger socket: it is struck
  -- directly and answers with a pulse of its own a tick later.
  ["D|GVOICE"] = "the pulse strikes the drum, which answers with a pulse of its own",
  ["R|GVOICE"] = "the changed pulse strikes the drum, which answers in turn",
  ["E|GVOICE"] = "the drum's answering pulse fires one grain of the exciter",
  ["F|GVOICE"] = "the drum's answering pulse steps the field",
  ["GVOICE|GVOICE"] = "one drum's answering pulse strikes the next",
  ["GVOICE|O"] = "the drum is heard, panned to where this output sits",
  -- §2.3b a register is a pulse cell like a trigger or a rule, but has no
  -- rhythm of its own: every pulse in is one step, and its own pulse out is
  -- gated by whichever bit its Tap knob is reading.
  ["D|TM"] = "the pulse steps the pattern, which answers with a pulse of its own",
  ["R|TM"] = "the changed pulse steps the pattern, which answers in turn",
  ["E|TM"] = "the pattern's answering pulse fires one grain of the exciter",
  ["F|TM"] = "nothing. a register takes a trigger, not a note",
  ["TM|GVOICE"] = "the pattern's answering pulse strikes the drum, which answers in turn",
  ["TM|TM"] = "each pattern steps the other. a loop that keeps changing",
  -- clock cells: pure sources, in time with the transport at their own ratio.
  ["C|C"] = "nothing. a clock cell only ever sends",
  ["R|C"] = "the clock pulse goes through this rule on its way out",
  ["C|GVOICE"] = "the clock pulse strikes the drum, which answers with a pulse",
  ["E|C"] = "the clock pulse cuts the exciter into a short grain",
  ["F|C"] = "each clock pulse steps the field to a new note",
  ["C|TM"] = "the clock pulse steps the pattern",
  ["C|GUST"] = "the clock pulse plays the gust's note",
  -- §2.11 the gusts. a pulse plays the note and the gust answers with a pulse
  -- the way a drum does. a continuous cable lands on its cross modulation
  -- input instead, where the gust's own Cross knob scales it into pitch and
  -- fold. that is why two gusts cabled together read as modulation.
  ["D|GUST"] = "the pulse plays the gust's note, which answers with a pulse of its own",
  ["R|GUST"] = "the changed pulse plays the note, which answers in turn",
  ["TM|GUST"] = "the pattern's answering pulse plays the gust's note",
  ["GVOICE|GUST"] = "the drum's answering pulse plays the gust's note",
  ["GUST|GUST"] = "the two gusts FM each other. turn up Cross on both to hear it",
  ["voice|GUST"] = "the gust drives the voice's mod path, and the voice bends the gust",
  ["E|GUST"] = "the exciter bends the gust, and the gust rides the exciter's colour",
  ["F|GUST"] = "nothing. a gust takes its pitch from the Scale, not from a field",
  ["GUST|O"] = "a second copy of the gust here, on top of the one it mixes itself",
  -- §2.5 the sample cells. a pulse plays the recording from the top; nothing
  -- comes back out, because a swell seconds long is not an event anything
  -- downstream could be timed against. they are heard without an output cable.
  ["D|SMP"] = "the pulse plays the sample from the top",
  ["R|SMP"] = "the changed pulse plays the sample from the top",
  ["C|SMP"] = "the clock pulse plays the sample from the top",
  ["TM|SMP"] = "the pattern's answering pulse plays the sample",
  ["GVOICE|SMP"] = "the drum's answering pulse plays the sample",
  ["voice|SMP"] = "the voice's own strike plays the sample",
  ["E|SMP"] = "nothing continuous. only a pulse plays a sample",
  ["F|SMP"] = "nothing. a sample cell takes a trigger, not a note",
  ["GUST|SMP"] = "nothing. neither one sends the other a pulse",
  ["LFO|SMP"] = "nothing. a sample cell has no knob a stream can move",
  ["SMP|SMP"] = "nothing. a sample cell never sends a pulse",
  ["SMP|O"] = "nothing. a sample cell mixes itself, and needs no output cable",
  -- the Output row is exclusive (patch.lua): a source sits at one pan
  -- position, and cabling it to a second Out cell moves it rather than
  -- adding to it. two Out cells together is not a cable at all -- and a
  -- pulse cell reaching one is not either: an output carries audio, and a
  -- trigger, a rule, a clock, a register and a field all make pulses and
  -- notes rather than sound.
  ["O|O"] = "nothing. an output is a destination, never a source",
  ["D|O"] = "nothing. an output carries sound, and a trigger makes pulses",
  ["R|O"] = "nothing. an output carries sound, and a rule makes pulses",
  ["C|O"] = "nothing. an output carries sound, and a clock makes pulses",
  ["TM|O"] = "nothing. an output carries sound, and a register makes pulses",
  ["F|O"] = "nothing. an output carries sound, and a field makes notes",
  -- a drum answers its own strike with a pulse a tick later, so it can drive
  -- a voice the way a trigger does.
  ["voice|GVOICE"] = "the drum's answering pulse strikes the voice, which answers in turn",
  -- §2.12 the LFOs. cable one to a cell, then open the LFO's page and pick
  -- which of that cell's knobs it moves.
  ["LFO|voice"] = "open the LFO's page to pick which of the voice's knobs it moves",
  ["LFO|E"] = "open the LFO's page to pick which of the exciter's knobs it moves",
  ["LFO|GUST"] = "open the LFO's page to pick which of the gust's knobs it moves",
  ["LFO|GVOICE"] = "open the LFO's page to pick which of the drum's knobs it moves",
  ["LFO|TM"] = "open the LFO's page to pick which of the register's knobs it moves",
  ["LFO|D"] = "open the LFO's page to pick which of the trigger's knobs it moves",
  ["LFO|R"] = "open the LFO's page to pick which of the rule's knobs it moves",
  ["LFO|F"] = "open the LFO's page to pick which of the field's knobs it moves",
  ["LFO|C"] = "open the LFO's page to pick which of the clock's knobs it moves",
  ["LFO|LFO"] = "nothing. an LFO has no knob another one can move",
  ["LFO|O"] = "heard directly. turn Speed up into the audio range for a plain tone",
}

local TYPE_ORDER = {
  LFO = 0, voice = 1, D = 2, R = 3, E = 4, F = 6, C = 7, TM = 8,
  GVOICE = 9, GUST = 10, SMP = 11, O = 12,
}

local function interaction_text(ta, tb)
  local a, b = ta, tb
  if (TYPE_ORDER[a] or 99) > (TYPE_ORDER[b] or 99) then a, b = b, a end
  return INTERACTION_DESC[a .. "|" .. b] or "no direct interaction defined"
end

function screenui.draw_edge(id_a, id_b)
  local a, b = topology.get(id_a), topology.get(id_b)
  local edge_id = patch.has(id_a, id_b)
  local edge = edge_id and patch.get(edge_id) or nil

  -- the gain used to be printed in the header. it is not any more, for the
  -- same reason no widget prints its value (lib/glyph.lua): the bar below
  -- says which side of centre the cable is on and how far, which is the
  -- question you actually have while turning E3.
  screenui.draw_header("", "cable")

  -- two names on one line: split the width between them and let each give way
  -- on its own side rather than letting a long pair meet in the middle.
  screen.level(15)
  screen.move(2, 17)
  screen.text(fit(topology.label(a), 56))
  screen.move(126, 17)
  screen.text_right(fit(topology.label(b), 56))
  screen.level(4)
  screen.move(62, 17)
  screen.text("\xE2\x80\x94")

  if edge then
    -- one full-width bar rather than a knob: a cable's gain is bipolar and
    -- what you want to see is which side of centre it is on and how far,
    -- which a straight run of pixels shows and a 270-degree gauge does not.
    -- the centre is ticked now that no number backs it up.
    screen.level(2)
    screen.rect(2, 21, 124, 3)
    screen.fill()
    screen.level(6)
    screen.rect(64, 19, 1, 7)
    screen.fill()
    screen.level(13)
    local mid, span = 64, math.floor(62 * edge.gain)
    if span >= 0 then screen.rect(mid, 21, math.max(1, span), 3)
    else screen.rect(mid + span, 21, -span, 3) end
    screen.fill()
    if edge.oneway then
      screen.level(6)
      screen.move(2, 32)
      screen.text("one-way")
    end
  else
    screen.level(4)
    screen.move(2, 32)
    screen.text(fit("not cabled. tap one to connect", 124))
  end

  screen.level(8)
  local desc_lines = wrap(interaction_text(a.type, b.type), 30)
  for i, line in ipairs(desc_lines) do
    if i > 3 then break end
    screen.move(2, 33 + i * 9)
    screen.text(fit(line, 124))
  end
end

-- top-level dispatch ----------------------------------------------------------

function screenui.redraw()
  screen.clear()

  if #state.held == 2 then
    screenui.draw_edge(state.held[1], state.held[2])
  elseif #state.held == 1 then
    -- a glance: the same page the tap latches open, for as long as the cell
    -- is down. true from the map page too -- holding/tapping a cell always
    -- goes to that cell's own settings page, never stays on the map.
    screenui.draw_cell(state.held[1])
  elseif state.cell_edit then
    screenui.draw_cell(state.cell_edit)
  elseif state.view == "mixer" then
    screenui.draw_mixer()
  elseif state.view == "map" then
    screenui.draw_map()
  else
    screenui.draw_global()
  end

  if state.confirm then
    local elapsed = util.time() - state.confirm.started
    local frac = util.clamp(elapsed / state.confirm.duration, 0, 1)
    screen.level(0)
    screen.rect(10, 24, 108, 16)
    screen.fill()
    screen.level(15)
    screen.rect(10.5, 24.5, 107, 15)
    screen.stroke()
    screen.move(14, 34)
    screen.text(fit(state.confirm.label, 100))
    screen.level(6)
    screen.rect(14, 36, math.floor(100 * frac), 2)
    screen.fill()
  end

  screen.update()
end

return screenui
