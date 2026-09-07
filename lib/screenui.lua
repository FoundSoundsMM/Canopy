-- screenui.lua
-- the global param page, the gusts page, the mixer page, the Send page, the
-- Colour page, the map, the per-cell settings page, and the edge view.
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
--   * the header bar -- the transport, what kind of page this is, its name,
--     which page of it, and the tempo. it never moves and it is never empty.
--   * a 4 x 2 grid of widgets, eight to a page. one drawn shape per
--     parameter (lib/glyph.lua); one whose value is a WORD -- a gait, a
--     scale, on/off -- draws as a boxed readout instead, since no shape
--     tells you anything about "euclidean". the focused one is drawn
--     bright, everything else dim.
--   * under each widget, two lines: its value, then its name.
--
-- §5.2d the value line. §5.2c took every number off this panel on the
-- grounds that the shapes already carried them, and lived with the cost it
-- named at the time: nowhere to read an exact setting. the cost turned out
-- to be the wrong way round. a shape is the fastest thing on the screen for
-- "where is this set and is it moving", and no use at all for "set the other
-- three to the same 0.42", "how long is this tail in seconds", "is Pitch on
-- a semitone or between two". so every widget now prints its own reading
-- under it, in the unit the parameter is actually in -- seconds, semitones,
-- hertz, cents, x-multiples, per cent, a count of steps -- and the shape
-- above it is unchanged in job: the glance, not the fact.
--
-- what it costs, exactly: seven pixels a row, which came off the shape
-- (19px to 13px, lib/glyph.lua). four of the twenty-eight shapes had to be
-- re-cut to survive that and are noted where they are drawn.
--
-- the value is shortened to fit its column rather than clipped, by `shorten`
-- below -- a number cut off halfway is worse than no number, which is the
-- one thing a clipped label is not.
--
-- four columns and not the Digitakt's five, for one reason: at five, a column
-- is twenty-five pixels, and twenty-five pixels of this font is four or five
-- characters -- which turns both "Scatter" and "Scale" into "Sca.", two
-- adjacent parameters that now read identically. thirty-two pixels fits the
-- longest label the panel has. it also means eight to a page rather than ten,
-- which lands every page in the script except a voice's twelve on one screen.
--
-- what that buys, beyond looking like the thing it is inspired by: a grid of
-- eight can be taken in at once where eight rows of text cannot, and no page
-- has to choose between showing a name and showing a number -- it shows both,
-- one under the other, under the shape they belong to.
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
local gust       = wl("gust")   -- §2.11b its family page, not its cell page
local colour     = wl("colour") -- §4.4 the master colour chain
local send       = wl("send")   -- §2.11c the shared send effect
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

-- §5.2d the value under a widget. a row's `text()` is written for a line
-- with a hundred pixels in it -- "1.20 s", "+12.0 st", "65% lock" -- and a
-- column has twenty-eight. rather than have every parameter in the script
-- keep a second, shorter string in step with the first, the one string is
-- shortened here, in the order that costs the least meaning:
--
--   1. the space in front of a short unit.       "1.20 s"   -> "1.20s"
--   2. decimal places, least significant first.  "+12.0st"  -> "+12st"
--   3. whole words off the end.                  "65% lock" -> "65%"
--
-- what is never dropped is the sign and the leading digits, which is what
-- stops "+12.0 st" from arriving on the panel as "12". a plain `clip` is the
-- last resort and only reachable for a value that is one long word, where
-- there is nothing to drop and the letters are the reading.
--
-- it measures rather than counts characters, so on hardware -- where the
-- font is narrower than the offline harness's 5px-per-character estimate --
-- more of the string survives than the tests assume, never less.
local function shorten(str, limit)
  str = str or ""
  if text_w(str) <= limit then return str end

  local s = str:gsub("([%d%%]) (%a%a?)$", "%1%2")
  if text_w(s) <= limit then return s end

  while true do
    local head, dec, tail = s:match("^(.-%d)%.(%d+)(.*)$")
    if not dec then break end
    s = head .. ((#dec > 1) and ("." .. dec:sub(1, #dec - 1)) or "") .. tail
    if text_w(s) <= limit then return s end
  end

  while true do
    local t = s:gsub("%s*%S+$", "")
    if t == s or t == "" then break end
    s = t
    if text_w(s) <= limit then return s end
  end

  return clip(s, limit)
end

screenui.shorten = shorten

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
-- leaves two 27px blocks with two pixels to spare. within a block, and this
-- is the whole of §5.2d's arithmetic:
--
--   rows 0..12   the shape (glyph.H)
--   row  13      blank
--   rows 14..20  the value,  baseline at 19
--   rows 21..27  the label,  baseline at 26
--
-- text at baseline y occupies y-5 .. y+1 in this font, so the two lines are
-- seven apart rather than six: a value ending in a descender and a label
-- starting with an ascender are then adjacent rather than sharing a row.
-- the bottom row's descenders land on 63, as before.
local COL_W = 32
local COL_X0 = 0                    -- left edge of column 1
local BLOCK_TOP = {9, 37}           -- top of each widget row
local BLOCK_H = 27
local GLYPH_W, GLYPH_H = glyph.W, glyph.H
local GLYPH_DX = math.floor((COL_W - GLYPH_W) / 2)
local VALUE_DY = 19                 -- value baseline, from the block's top
local LABEL_DY = 26                 -- label baseline, from the block's top
local TEXT_W = COL_W - 4            -- both lines: 2px of gutter either side

screenui.PARAMS_PER_PAGE = PL_PER_PAGE
screenui.BLOCK_TOP = BLOCK_TOP
screenui.BLOCK_H = BLOCK_H
screenui.HEADER_H = HDR_H
screenui.VALUE_DY = VALUE_DY
screenui.LABEL_DY = LABEL_DY
screenui.TEXT_W = TEXT_W

-- 1-based page number a given row lives on.
function screenui.page_of(i)
  return math.floor((i - 1) / PL_PER_PAGE) + 1
end

-- what a widget is made of: the shape, then its reading, then its name.
--
-- the label is clipped rather than fitted: a trailing full stop costs a whole
-- character here and says nothing the widget's position in the grid does not.
-- the value is shortened instead (see `shorten`) -- a name that gives way at
-- the end is still the name, and a number that does is a different number.
-- the four pixels held back are the gutter -- at the full column width two
-- long labels in neighbouring columns run into each other.
--
-- the value sits a level above the label when the widget is not focused (9
-- against 6): with eight of them on screen the numbers are what you are
-- scanning, and the names are what you already know.
--
-- `word` draws no value line at all. its box IS the value spelled out, and
-- printing "dorian" a second time six pixels under the first is not a second
-- fact -- it is the one place on the panel where the shape and the reading
-- are the same object (glyph.reads_own_value).
-- the reading, ready to draw, or nil for a row that is already its own
-- (a `word` box). hoisted out of draw_param_grid rather than closed over it:
-- redraw runs at frame rate and this would be a fresh closure every frame.
local function value_of(w)
  if glyph.reads_own_value(w.p.glyph) then return nil end
  return shorten(w.text, TEXT_W)
end

local function widget_x(slot)
  return COL_X0 + (slot % PL_COLS) * COL_W + GLYPH_DX
end

local function widget_top(slot)
  return BLOCK_TOP[math.floor(slot / PL_COLS) + 1]
end

-- draw one page of a PARAMS list. `text_fn`/`frac_fn`/`data_fn` adapt the two
-- calling conventions in the codebase (a cell page's take an id, a global
-- page's take nothing) so this routine never learns which kind of list it has.
-- `data_fn` is the extras a few shapes need -- a bank position, a shift
-- register -- and is nil for every row that does not declare glyph_data.
--
-- §5.2d it draws in passes -- every shape, then every dim value, then every
-- dim label, then the focused widget's two lines -- rather than finishing one
-- widget before starting the next. that is not tidiness, it is the frame
-- budget (test/soak.lua): screen.level is a socket message like any other, and
-- a level per line per widget is sixteen of them where a level per BAND is
-- three. the value line cost eight commands a page instead of twenty-four for
-- exactly this reason, which is what kept the Colour page under its 200.
local function draw_param_grid(params, focus, text_fn, frac_fn, data_fn)
  local page = screenui.page_of(focus)
  local first = (page - 1) * PL_PER_PAGE + 1

  local shown = {}
  for slot = 0, PL_PER_PAGE - 1 do
    local p = params[first + slot]
    if p then
      local on = (first + slot) == focus
      local text = text_fn(p)
      local x, top = widget_x(slot), widget_top(slot)
      glyph.draw(p.glyph, x, top, GLYPH_W, GLYPH_H, frac_fn(p), on, text,
                 data_fn and data_fn(p) or nil)
      shown[#shown + 1] = {p = p, text = text, on = on, label = p.label,
                           cx = x + GLYPH_W / 2, top = top}
    end
  end

  screen.level(9)
  for _, w in ipairs(shown) do
    if not w.on then centred(w.cx, w.top + VALUE_DY, value_of(w)) end
  end

  screen.level(6)
  for _, w in ipairs(shown) do
    if not w.on then centred(w.cx, w.top + LABEL_DY, clip(w.label, TEXT_W)) end
  end

  screen.level(15)
  for _, w in ipairs(shown) do
    if w.on then
      centred(w.cx, w.top + VALUE_DY, value_of(w))
      centred(w.cx, w.top + LABEL_DY, clip(w.label, TEXT_W))
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

-- §2.11b the gusts page (K3 from the main screen) ------------------------------
-- the five family offsets and the three rows for the delay line all twelve
-- share (lib/gust.lua's MACROS). exactly eight, so the whole family is one
-- look with no page dots and no seam -- which is what a page about twelve
-- cells acting as one ought to be.
--
-- unlike the mixer this page can never be empty -- the twelve cells are
-- always there whether or not anything is cabled to them -- so there is no
-- "nothing here" branch to draw.

function screenui.draw_gusts()
  local focus = util.clamp(state.guparam_focus or 1, 1, gust.MACRO_COUNT)
  local pages = math.max(1, math.ceil(gust.MACRO_COUNT / PL_PER_PAGE))
  screenui.draw_header("Gusts", "all twelve", screenui.page_of(focus), pages)
  draw_param_grid(gust.MACROS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end,
                  function(q) return q.glyph_data and q.glyph_data() or nil end)
end

-- §4.4 the Colour page (K3 from the mixer) -------------------------------------
-- eight processors across the master output (lib/colour.lua), which is
-- exactly one screen -- no page dots, no seam, the whole chain visible at
-- once. that is worth more here than on any other page in the script: what
-- you are doing on this one is balancing eight things against each other,
-- and a chain you have to scroll to see the end of is one you set by memory.

function screenui.draw_colour()
  local focus = util.clamp(state.cparam_focus or 1, 1, colour.PARAM_COUNT)
  local pages = math.max(1, math.ceil(colour.PARAM_COUNT / PL_PER_PAGE))
  screenui.draw_header("Colour", "master", screenui.page_of(focus), pages)
  draw_param_grid(colour.PARAMS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end,
                  function(q) return q.glyph_data and q.glyph_data() or nil end)
end

-- §2.11c the Send page (K3 from the mixer) -------------------------------------
-- the four knobs of the one delay effect every source on the panel can reach
-- (lib/send.lua). it used to be three rows on the gusts page, back when that
-- line was the gusts' own room; every family has a Send knob into it now, so
-- it sits with the master pages, between the faders that balance the dry
-- signal and the chain that colours the sum.
--
-- what is deliberately NOT on this page is how much of anything is going
-- there. that belongs to the cell -- it is a per-instrument decision, it
-- lives on that instrument's page next to its Level, and a second list of
-- twenty-six send amounts here would be a mixer nobody asked for. so the
-- header counts them instead: "3 sending" is the one thing this page cannot
-- show you any other way.

function screenui.draw_send()
  local focus = util.clamp(state.sparam_focus or 1, 1, send.PARAM_COUNT)
  local pages = math.max(1, math.ceil(send.PARAM_COUNT / PL_PER_PAGE))
  screenui.draw_header("Send", send.active_count() .. " sending",
                       screenui.page_of(focus), pages)
  draw_param_grid(send.PARAMS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end,
                  function(q) return q.glyph_data and q.glyph_data() or nil end)
end

-- §4.1b the mixer page (K3, back with K2) --------------------------------------
-- one channel per Output cell the patch is actually using, each named after
-- the instrument cabled to it and each carrying a live meter (lib/mixer.lua).
-- there is no master row: that is one number over the whole instrument rather
-- than a channel, and K1+E3 moves it from this screen as from every other.
--
-- the list grows and shrinks with the cables, so the header says how many
-- channels are open. with nothing patched this page is empty, and that is the
-- honest picture of a patch that makes no sound -- so it says so in words
-- rather than showing a grid of nothing.

function screenui.draw_mixer()
  local count = mixer.PARAM_COUNT
  local focus = util.clamp(state.mparam_focus or 1, 1, math.max(1, count))
  local pages = math.max(1, math.ceil(count / PL_PER_PAGE))
  screenui.draw_header("Mixer", count .. " ch", screenui.page_of(focus), pages)
  if count == 0 then
    screen.level(4)
    centred(64, BLOCK_TOP[1] + 20, "no outputs cabled")
    return
  end
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

-- an LFO is a shape and the screen never once showed one. the wave scrolls
-- and the right-hand edge is now; the current value is carried out to the
-- margin as a 3px dot, which is the only part of it that matters when you are
-- listening rather than looking.
--
-- it draws whichever of the eight shapes the cell is on, so the page says
-- what a square or a ramp or a sample-and-hold actually looks like rather
-- than drawing a sine over the top of one. `follow` has no waveform at all --
-- it is reading the mix -- so it draws as a flat line at wherever the level
-- currently is, which is the honest picture of it.
--
-- sampled, not curved: the phase moves every frame, and a cubic's control
-- points would have to be re-derived per frame anyway. 26 samples across 92
-- pixels is one command each -- affordable here precisely because an LFO page
-- has one widget on it and the whole frame is nowhere near the budget.
SCOPES.LFO = function(id)
  local lfo = wl("lfo")
  local phase = lfo.phase(id)
  local shape = lfo.shape(id)
  local my = SCOPE_Y + SCOPE_H / 2
  local amp = SCOPE_H / 2 - 4
  local L, R = 4, 118
  local N = 26

  screen.level(2)
  screen.move(L, my)
  screen.line(R, my)
  screen.stroke()

  -- the same eight shapes lfo.value computes, as a pure function of a phase
  -- so two cycles can be drawn across the block. the two random ones are the
  -- exception and draw their held value flat: the scope shows one cell's
  -- past, and lfo.value only knows its present.
  local function wave(ph)
    ph = ph % 1
    if shape == "tri" then return 1 - 4 * math.abs(ph - 0.5) end
    if shape == "ramp" then return ph * 2 - 1 end
    if shape == "saw" then return 1 - ph * 2 end
    if shape == "square" then return (ph < 0.5) and 1 or -1 end
    if shape == "s+h" or shape == "rand" or shape == lfo.FOLLOW then
      return lfo.value(id)
    end
    return math.sin(ph * 2 * math.pi)
  end

  local function at(t)
    return my - wave(t * 2 + phase) * amp
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

-- §5.2c the trigger scopes ---------------------------------------------------
-- what replaced the phase bar. that bar drew one number -- how far through its
-- cycle a D cell was -- full width, at level 15, and drew it identically for
-- all nine gaits: a euclidean cell and a swarm cell were the same picture. it
-- was also the fourth widget on the page saying the same thing twice.
--
-- these draw the gait instead, and every one of them is the same two halves:
--
--   x 2..48    the mechanism. the thing that decides -- a ring of eight
--              steps, a sixteen-step strip, a comb, a dice against a bar, a
--              ramp, a line with this cell's phase on it and its neighbours'
--              either side.
--   x 54..126  what came out of it, newest at the right edge, bar height for
--              weight. the same direction the LFO scope scrolls, and the same
--              lane the R scopes use for their two rows, so it is learned
--              once for the whole panel.
--
-- the faint ticks under the lane are the transport's beats: a rooted gait
-- sits on them and a wild one does not, which is a thing the panel could not
-- previously say at all.
--
-- cost: a lane is one screen.level, a run of rects and one fill. the whole
-- block runs about the same as the bar it replaced plus twenty rects, which
-- is what test/soak.lua's 150-command cell budget was holding room for.

local MX0, MX1 = 2, 48                 -- the mechanism pane
local TX0, TX1 = 54, 126               -- the history lane
local LANE_BASE = SCOPE_Y + 22
local LANE_H = 16

-- how many seconds of history each gait shows. a slow gait needs a long
-- window to have anything in it; a drifter at eight hertz needs a short one
-- or the lane is a solid block.
local T_WIN = {
  metric = 5, euclidean = 4, figure = 4, slow = 24, burst = 4,
  stochastic = 5, drifter = 2.5, accelerando = 5, swarm = 4,
}

local function ring_lane(hist, now, win, x0, x1, base, hmax, lvl)
  if not hist then return end
  local pps = (x1 - x0) / win
  screen.level(lvl)
  local n = 0
  for i = 1, #hist do
    local e = hist[i]
    if e then
      local age = now - e.t
      if age >= 0 and age <= win then
        local h = 2 + e.w * (hmax - 2)
        screen.rect(x1 - age * pps, base - h, 1, h)
        n = n + 1
      end
    end
  end
  if n > 0 then screen.fill() end
end

-- the transport, under the lane. one tick a beat, two pixels tall: enough to
-- read a gait as locked or free and not enough to compete with the pulses.
local function beat_ticks(now, win, x0, x1, y)
  local sb = wl("quantise").spb()
  if not sb or sb <= 0 then return end
  local pps = (x1 - x0) / win
  -- a tick every beat is the point of the row; a tick every two pixels is a
  -- grey line that says nothing. thin them to bars, then to fours, rather
  -- than drawing a smear -- a long window is a slow gait, and a slow gait is
  -- read against bars anyway.
  local every = 1
  while sb * every * pps < 5 and every < 16 do every = every * 4 end
  local step = sb * every
  screen.level(4)
  local t = math.floor(now / step) * step
  local n = 0
  while n < 20 do
    local x = x1 - (now - t) * pps
    if x < x0 then break end
    screen.rect(x, y, 1, 2)
    t = t - step
    n = n + 1
  end
  if n > 0 then screen.fill() end
end

-- the nine mechanisms. each draws inside MX0..MX1 and SCOPE_Y+2..SCOPE_Y+24,
-- and each is handed the cell's own record so it can read the phase and the
-- cycle count the gait is actually running on.
local MECH = {}

function MECH.metric(r, v1, v2)
  screen.level(3)
  for i = 0, 4 do screen.rect(MX0 + (MX1 - MX0) * i / 4, SCOPE_Y + 9, 1, 8) end
  screen.fill()
  -- Phase, as the offset of the whole ladder from the beat
  if v2 ~= 0 then
    screen.level(6)
    screen.rect(MX0 + (MX1 - MX0) * ((v2 + 1) % 1), SCOPE_Y + 6, 1, 3)
    screen.fill()
  end
  screen.level(12)
  screen.rect(MX0 + (MX1 - MX0) * r.phase, SCOPE_Y + 7, 1, 12)
  screen.fill()
end

function MECH.euclidean(r, k, rot)
  local cx, cy, rad = 24, SCOPE_Y + 13, 10
  local on_x, on_y, n_on = {}, {}, 0
  screen.level(4)
  for i = 0, 7 do
    local a = -math.pi / 2 + i * math.pi / 4
    local x, y = cx + math.cos(a) * rad, cy + math.sin(a) * rad
    if (((i + rot) % 8) * k) % 8 < k then
      n_on = n_on + 1; on_x[n_on], on_y[n_on] = x, y
    else
      screen.rect(x, y, 1, 1)
    end
  end
  screen.fill()
  if n_on > 0 then
    screen.level(12)
    for i = 1, n_on do screen.rect(on_x[i] - 1, on_y[i] - 1, 3, 3) end
    screen.fill()
  end
  -- the hand, from the middle out to wherever in the ring we are
  local a = -math.pi / 2 + ((r.cycle % 8) + r.phase) * math.pi / 4
  screen.level(13)
  screen.move(cx, cy)
  screen.line(cx + math.cos(a) * (rad - 2), cy + math.sin(a) * (rad - 2))
  screen.stroke()
end

function MECH.figure(r, _, rot, id)
  local pat = wl("rambler").pattern(id)
  if not pat then return end
  local pos = r.cycle % 16
  screen.level(3)
  for i = 0, 15 do
    local step = ((i + rot) % 16) + 1
    if pat:sub(step, step) ~= "1" then
      screen.rect(MX0 + 2 + (i % 8) * 5.5, SCOPE_Y + 7 + math.floor(i / 8) * 7, 1, 1)
    end
  end
  screen.fill()
  screen.level(9)
  for i = 0, 15 do
    local step = ((i + rot) % 16) + 1
    if pat:sub(step, step) == "1" then
      screen.rect(MX0 + 1 + (i % 8) * 5.5, SCOPE_Y + 6 + math.floor(i / 8) * 7,
                  3, (i % 4 == 0) and 4 or 3)
    end
  end
  screen.fill()
  screen.level(14)
  screen.rect(MX0 + 1 + (pos % 8) * 5.5, SCOPE_Y + 11 + math.floor(pos / 8) * 7, 3, 1)
  screen.fill()
end

function MECH.slow(r, _, w)
  screen.level(3)
  screen.rect(6, SCOPE_Y + 4, 36, 1)
  screen.rect(6, SCOPE_Y + 20, 36, 1)
  screen.rect(6, SCOPE_Y + 4, 1, 17)
  screen.rect(41, SCOPE_Y + 4, 1, 17)
  screen.fill()
  -- the box fills over the whole cycle, then everything happens at once
  local fh = math.floor(r.phase * 14 + 0.5)
  if fh > 0 then
    screen.level(9)
    screen.rect(8, SCOPE_Y + 19 - fh, 32, fh)
    screen.fill()
  end
  -- and how hard the hit will be when it comes
  screen.level(13)
  screen.rect(8, SCOPE_Y + 19 - math.floor(w * 14 + 0.5), 32, 1)
  screen.fill()
end

function MECH.burst(r, _, n)
  screen.level(7)
  for i = 1, n do
    local hh = math.max(4, 16 - (i - 1) * 2)
    screen.rect(4 + (i - 1) * 6, SCOPE_Y + 19 - hh, 2, hh)
  end
  screen.fill()
  screen.level(3)
  screen.rect(MX0 + 2, SCOPE_Y + 20, 44, 1)
  screen.fill()
  screen.level(12)
  screen.rect(MX0 + 2 + 44 * r.phase, SCOPE_Y + 21, 1, 3)
  screen.fill()
end

function MECH.stochastic(r, p)
  local x0, y0, y1 = 16, SCOPE_Y + 4, SCOPE_Y + 21
  screen.level(3)
  screen.rect(x0, y0, 1, y1 - y0)
  screen.rect(x0 + 18, y0, 1, y1 - y0)
  screen.fill()
  -- the bar the dice is thrown against
  screen.level(8)
  screen.rect(x0, y1 - p * (y1 - y0), 19, 1)
  screen.fill()
  -- and where the last one that got through actually landed
  if r.last_weight > 0 then
    screen.level(14)
    screen.rect(x0 + 2, y1 - r.last_weight * (y1 - y0), 15, 2)
    screen.fill()
  end
end

function MECH.drifter(r, _, couple, id)
  local y = SCOPE_Y + 14
  screen.level(3)
  screen.rect(MX0 + 2, y + 4, 44, 1)
  screen.fill()
  local nb = wl("rambler").neighbour_phases(id, 3)
  if #nb > 0 then
    screen.level(6)
    for i = 1, #nb do screen.rect(MX0 + 2 + 44 * nb[i], y, 2, 2) end
    screen.fill()
  end
  screen.level(14)
  screen.rect(MX0 + 1 + 44 * r.phase, y - 2, 3, 5)
  screen.fill()
  -- how hard they pull, as the width of the bracket under it
  local w = math.floor(couple * 9 + 0.5)
  if w > 0 then
    screen.level(7)
    screen.rect(MX0 + 2 + 44 * r.phase - w, y + 6, w * 2 + 1, 1)
    screen.fill()
  end
end

function MECH.accelerando(r, _, top)
  local at = r.cycle % 8
  screen.level(4)
  for i = 0, 7 do
    if i ~= at then
      local hh = 3 + i * (1 + top * 0.4)
      screen.rect(MX0 + 3 + i * 5, SCOPE_Y + 19 - hh, 3, hh)
    end
  end
  screen.fill()
  screen.level(13)
  local hh = 3 + at * (1 + top * 0.4)
  screen.rect(MX0 + 3 + at * 5, SCOPE_Y + 19 - hh, 3, hh)
  screen.fill()
  screen.level(3)
  screen.rect(MX0 + 3, SCOPE_Y + 19, 42, 1)
  screen.fill()
end

function MECH.swarm(r, _, spread)
  -- a picture of the setting: four hits, the gaps between them scaled by
  -- Spread, over the run the cluster will actually occupy.
  local x, gaps = MX0 + 3, {1.0, 0.55, 1.35, 0.8}
  screen.level(9)
  for i = 1, 4 do
    screen.rect(x, SCOPE_Y + 16 - (5 - i) * 2, 2, (5 - i) * 2 + 3)
    x = x + 3 + gaps[i] * spread * 3.2
    if x > MX1 - 2 then break end
  end
  screen.fill()
  screen.level(3)
  screen.rect(MX0 + 2, SCOPE_Y + 20, 44, 1)
  screen.fill()
  screen.level(12)
  screen.rect(MX0 + 2 + 44 * r.phase, SCOPE_Y + 21, 1, 3)
  screen.fill()
end

SCOPES.D = function(id)
  local rambler = wl("rambler")
  local r = rambler.get(id)
  if not r then return end
  local v1, _, v2 = rambler.knobs(id)
  local now = util.time()
  local win = T_WIN[r.gait] or 6

  local m = MECH[r.gait]
  if m then m(r, v1, v2, id) end

  -- the divider, so the two halves read as two halves
  screen.level(2)
  for y = SCOPE_Y + 4, SCOPE_Y + 22, 4 do screen.rect(51, y, 1, 2) end
  screen.fill()

  screen.level(3)
  screen.rect(TX0, LANE_BASE, TX1 - TX0, 1)
  screen.fill()
  beat_ticks(now, win, TX0, TX1, LANE_BASE + 2)
  local hist = rambler.history(id)
  ring_lane(hist, now, win, TX0, TX1, LANE_BASE, LANE_H, 13)
end

-- §5.2c the weave scopes -----------------------------------------------------
-- an R cell had no scope at all: its page fell through to the lexicon's
-- sentence, which is the one page on the panel where a sentence is least
-- use -- "sends each pulse out of a different cable, in turn" is a thing you
-- have to imagine, and this is a thing you can watch.
--
-- one layout for all twenty, and it is the rule's own definition: what
-- arrived on the top row, what left on the bottom, and the difference between
-- them IS the rule. a pulse the rule swallowed leaves a short stub on the
-- bottom row rather than nothing at all, because a hole in a part is a part
-- of the part and the panel has never been able to show one.
--
-- two rules break the layout, and they are exactly the two that are not
-- one-in-one-out: `meet` needs two input rows and `hocket` needs four output
-- rows. the break is the information.

-- the block is 27 rows. seven of them are what arrived, five are the rule's
-- own working, ten are what left, and the two spare are the gaps that keep
-- the three from touching -- a stencil drawn through the tops of the output
-- bars is two drawings on top of each other, not one drawing.
local RX0, RX1 = 2, 126
local IN_BASE = SCOPE_Y + 7            -- rows 0..7   what arrived
local IN_H = 7
local BAND_Y = SCOPE_Y + 9             -- rows 9..13  the rule
local OUT_BASE = SCOPE_Y + 25          -- rows 15..25 what left
local OUT_H = 10

-- seconds of history per rule. the millisecond rules -- flam at eight to
-- sixty-three, ghost, roll, blur -- are simply invisible on a lane scaled to
-- bars, so each rule carries the window that shows what it does.
local R_WIN = {
  divide = 5, mult = 1.8, delay = 4, echo = 2.2, chance = 4,
  accent = 6, sift = 5, meet = 4, hocket = 4, swing = 4,
  blur = 2.6, latch = 7, fill = 8, rest = 6, flam = 1.1,
  ghost = 1.8, roll = 2.4, swell = 6, mask = 8, shift = 8,
}

-- the bands: the rule's own working, drawn between the two rows. only the
-- rules where there is something to see -- a counter, a gate, a stencil, a
-- threshold. the rest are legible from the two rows alone.
local BAND = {}

function BAND.divide(v1, v2, r)
  local at = r.count % v1
  screen.level(3)
  for i = 0, v1 - 1 do
    if i ~= at then screen.rect(50 + i * 4, BAND_Y + 2, 3, 2) end
  end
  screen.fill()
  screen.level(11)
  screen.rect(50 + at * 4, BAND_Y + 1, 3, 4)
  screen.fill()
end

function BAND.chance(v1)
  screen.level(3)
  screen.rect(50, BAND_Y + 3, 28, 1)
  screen.fill()
  screen.level(10)
  screen.rect(50, BAND_Y + 2, math.floor(28 * v1 + 0.5), 3)
  screen.fill()
end

function BAND.latch(v1, duty, r)
  local on = math.max(1, math.floor(v1 * 2 * duty + 0.5))
  local span = v1 * 2
  local w = math.floor(48 / span)
  if w < 1 then w = 1 end
  local i = r.count % span
  screen.level(4)
  screen.rect(40, BAND_Y + 4, on * w, 1)
  screen.rect(40 + on * w, BAND_Y + 1, (span - on) * w, 1)
  screen.fill()
  screen.level(12)
  screen.rect(40 + i * w, BAND_Y + 1, 1, 4)
  screen.fill()
end

local function stencil(n, k, rot, at, span)
  local w = math.max(1, math.floor(span / n))
  local x0 = 64 - math.floor(n * w / 2)
  screen.level(3)
  for i = 0, n - 1 do
    if not ((((i + rot) % n) * k) % n < k) then
      screen.rect(x0 + i * w, BAND_Y + 2, 1, 1)
    end
  end
  screen.fill()
  screen.level(9)
  for i = 0, n - 1 do
    if (((i + rot) % n) * k) % n < k then
      screen.rect(x0 + i * w, BAND_Y + 1, w, 3)
    end
  end
  screen.fill()
  screen.level(14)
  screen.rect(x0 + (at % n) * w, BAND_Y + 5, w, 1)
  screen.fill()
end

function BAND.mask(k, rot, r) stencil(16, k, rot, r.count, 64) end
function BAND.shift(k, _, r)  stencil(8, k, r.rot, r.count, 48) end

function BAND.sift(thr)
  -- the bar, drawn across the row it is judging
  screen.level(6)
  for x = RX0, RX1, 4 do screen.rect(x, IN_BASE - thr * IN_H, 1, 1) end
  screen.fill()
end

-- accent and swell get no band. their contour IS the height of the output
-- bars, and drawing it a second time as a dotted line through them is the
-- same fact twice -- which is exactly what the phase bar was doing.

function BAND.blur(late, _, _, win)
  -- the window a pulse can land anywhere inside, over the row it lands on
  local pps = (RX1 - RX0) / win
  local w = math.max(2, math.floor(late * pps + 0.5))
  screen.level(3)
  for x = RX0, RX1 - w, 26 do screen.rect(x, OUT_BASE - 1, w, 1) end
  screen.fill()
end

-- the two that are not one in, one out --------------------------------------

local function draw_hocket(id, now, win, lanes)
  local weave = wl("weave")
  local ins, _, outs = weave.history(id)
  local pps = (RX1 - RX0) / win
  -- one row per cable, up to six -- Lanes is capped at six for exactly this
  -- reason, so the rows are the cables rather than the cables folded onto the
  -- rows that happened to fit.
  local ys = {SCOPE_Y + 15, SCOPE_Y + 17, SCOPE_Y + 19,
              SCOPE_Y + 21, SCOPE_Y + 23, SCOPE_Y + 25}
  local n = math.min(6, math.max(2, lanes))
  screen.level(3)
  for i = 1, n do screen.rect(RX0 + 4, ys[i], RX1 - RX0 - 4, 1) end
  screen.fill()
  screen.level(9)
  for i = 1, #ins do
    local e = ins[i]
    if e and now - e.t >= 0 and now - e.t <= win then
      screen.rect(RX1 - (now - e.t) * pps, SCOPE_Y + 3, 1, 8)
    end
  end
  screen.fill()
  -- each pulse drops onto the cable it actually left by (weave.out records
  -- it), so the four rows are the four cables and the staircase down them is
  -- the hocket. a stride of two skips a row each time and shows as one.
  screen.level(13)
  local k = 0
  for i = 1, #outs do
    local e = outs[i]
    if e and now - e.t >= 0 and now - e.t <= win then
      local x = RX1 - (now - e.t) * pps
      local y = ys[(((e.lane or 1) - 1) % n) + 1]
      screen.rect(x, y - 2, 1, 2)
      k = k + 1
    end
  end
  if k > 0 then screen.fill() end
end

local function draw_meet(id, now, win)
  local weave = wl("weave")
  local ins, _, outs, _, drops = weave.history(id)
  local pps = (RX1 - RX0) / win
  screen.level(3)
  screen.rect(RX0, SCOPE_Y + 7, RX1 - RX0, 1)
  screen.rect(RX0, SCOPE_Y + 14, RX1 - RX0, 1)
  screen.rect(RX0, OUT_BASE, RX1 - RX0, 1)
  screen.fill()
  -- arrivals alternate rows: two cables in is the whole point of this rule,
  -- and which row a pulse lands on is which cable it came down.
  screen.level(9)
  local j = 0
  for i = 1, #ins do
    local e = ins[i]
    if e and now - e.t >= 0 and now - e.t <= win then
      j = j + 1
      local x = RX1 - (now - e.t) * pps
      if j % 2 == 1 then screen.rect(x, SCOPE_Y + 2, 1, 5)
      else screen.rect(x, SCOPE_Y + 10, 1, 4) end
    end
  end
  screen.fill()
  screen.level(4)
  local d = 0
  for i = 1, #drops do
    local e = drops[i]
    if e and now - e.t >= 0 and now - e.t <= win then
      screen.rect(RX1 - (now - e.t) * pps, OUT_BASE - 2, 1, 2)
      d = d + 1
    end
  end
  if d > 0 then screen.fill() end
  screen.level(14)
  local o = 0
  for i = 1, #outs do
    local e = outs[i]
    if e and now - e.t >= 0 and now - e.t <= win then
      local hh = 2 + e.w * (OUT_H - 2)
      screen.rect(RX1 - (now - e.t) * pps, OUT_BASE - hh, 1, hh)
      o = o + 1
    end
  end
  if o > 0 then screen.fill() end
end

SCOPES.R = function(id)
  local weave = wl("weave")
  local r = weave.get(id)
  if not r then return end
  local v1, _, v2 = weave.knobs(id)
  local now = util.time()
  local win = R_WIN[r.rule] or 4

  if r.rule == "hocket" then return draw_hocket(id, now, win, v2) end
  if r.rule == "meet" then return draw_meet(id, now, win) end

  local ins, _, outs, _, drops = weave.history(id)
  local pps = (RX1 - RX0) / win

  -- what arrived
  screen.level(3)
  screen.rect(RX0, IN_BASE, RX1 - RX0, 1)
  screen.rect(RX0, OUT_BASE, RX1 - RX0, 1)
  screen.fill()

  local b = BAND[r.rule]
  if b then b(v1, v2, r, win) end

  screen.level(9)
  local n = 0
  for i = 1, #ins do
    local e = ins[i]
    if e then
      local age = now - e.t
      if age >= 0 and age <= win then
        local hh = 1 + e.w * (IN_H - 1)
        screen.rect(RX1 - age * pps, IN_BASE - hh, 1, hh)
        n = n + 1
      end
    end
  end
  if n > 0 then screen.fill() end

  -- and the holes, which are as much the part as the hits are
  screen.level(4)
  n = 0
  for i = 1, #drops do
    local e = drops[i]
    if e then
      local age = now - e.t
      if age >= 0 and age <= win then
        screen.rect(RX1 - age * pps, OUT_BASE - 2, 1, 2)
        n = n + 1
      end
    end
  end
  if n > 0 then screen.fill() end

  -- what left
  ring_lane(outs, now, win, RX0, RX1, OUT_BASE, OUT_H, 14)
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
-- §4.2b the header of a page whose E1 is a list rather than a cursor. it
-- carries the one thing E1 moves -- which gait, which rule -- because the two
-- widgets under it are only that entry's two knobs, and without it the page
-- would show "Steps" and "Rotate" without ever saying euclidean.
--
-- the tag ("Trigger:", "Process:") gives way to make room for it, and it is
-- the right thing to give: `Hob euclidean` says both what the cell is and
-- what it is set to, where `Trigger: Hob` said the first twice.
local CYC_BAR_W = 26

local function draw_cycle_header(name, entry, at, total)
  draw_transport(1)

  local right = 127
  local tempo = tempo_text()
  screen.level(9)
  screen.move(right, HDR_BASE)
  screen.text_right(tempo)
  right = right - text_w(tempo) - 5

  -- where in the list this entry is: a track with a block on it. nine gaits
  -- would fit as dots and twenty rules would not, and one shape for both is
  -- worth more than dots for one of them.
  local bx = right - CYC_BAR_W
  screen.level(3)
  screen.rect(bx, 4, CYC_BAR_W, 1)
  screen.fill()
  screen.level(11)
  screen.rect(bx + math.floor((at - 1) / math.max(1, total - 1) * (CYC_BAR_W - 3) + 0.5),
              2, 3, 4)
  screen.fill()
  right = bx - 4

  -- the cell's name first, dim: you already know which cell you are on --
  -- it is lit on the grid and you are holding it. the entry is what E1 moves
  -- and what both knobs under it belong to, so it is the bright one.
  local x = 7
  screen.level(7)
  screen.move(x, HDR_BASE)
  screen.text(name)
  x = x + text_w(name) + 4

  screen.level(15)
  screen.move(x, HDR_BASE)
  screen.text(fit(entry or "", right - x))

  screen.level(3)
  screen.move(0, HDR_H - 0.5)
  screen.line(128, HDR_H - 0.5)
  screen.stroke()
end

-- two knobs, side by side, both live. there is no cursor on this page -- E2
-- is the left one and E3 is the right one, always -- so neither is drawn as
-- "the focused one": they are both focused, which is the whole point of
-- having exactly two.
local CYC_X = {19, 83}

local function draw_two_knobs(id, page_mod)
  local top = BLOCK_TOP[1]
  for i = 1, 2 do
    local p = page_mod.PARAMS[i]
    if p then
      glyph.draw(p.glyph, CYC_X[i], top, GLYPH_W, GLYPH_H, p.get(id), true,
                 p.text(id), p.glyph_data and p.glyph_data(id) or nil)
    end
  end
  screen.level(13)
  for i = 1, 2 do
    local p = page_mod.PARAMS[i]
    if p and not glyph.reads_own_value(p.glyph) then
      centred(CYC_X[i] + GLYPH_W / 2, top + VALUE_DY, shorten(p.text(id), TEXT_W + 8))
    end
  end
  screen.level(6)
  for i = 1, 2 do
    local p = page_mod.PARAMS[i]
    if p then
      centred(CYC_X[i] + GLYPH_W / 2, top + LABEL_DY,
              clip(cellparam.label_of(p, id), TEXT_W + 8))
    end
  end
end

function screenui.draw_cell(id)
  local cell = topology.get(id)
  if not cell then return end
  local page_mod = cellparam.page(id)

  -- §4.2b the one-page cells: T and R. one page, two knobs, and a list on E1.
  if page_mod and page_mod.CYCLE then
    local at, total, key = page_mod.cycle_pos(id)
    draw_cycle_header(cell.name, key, at, total)
    draw_two_knobs(id, page_mod)
    scope_corners()
    local f = SCOPES[cell.type]
    if f then f(id) else draw_cell_desc(id) end
    return
  end

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
  ["voice|TM"] = "the pattern tunes the voice, and the voice's strike steps it",
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
  -- §2.3b a register takes a pulse in and answers with a NOTE, not with
  -- another pulse. every pulse in is one step of its pattern; what comes back
  -- out is a number, and the only cell that can hear one is a voice.
  ["D|TM"] = "the pulse steps the pattern to its next note",
  ["R|TM"] = "the changed pulse steps the pattern to its next note",
  ["E|TM"] = "nothing. a register sends notes, and an exciter takes a trigger",
  ["F|TM"] = "nothing. a register takes a trigger, not a note",
  ["TM|GVOICE"] = "nothing. a drum takes a trigger, and a register sends notes",
  ["TM|TM"] = "nothing. neither one clocks the other",
  -- clock cells: pure sources, in time with the transport at their own ratio.
  ["C|C"] = "nothing. a clock cell only ever sends",
  ["R|C"] = "the clock pulse goes through this rule on its way out",
  ["C|GVOICE"] = "the clock pulse strikes the drum, which answers with a pulse",
  ["E|C"] = "the clock pulse cuts the exciter into a short grain",
  ["F|C"] = "each clock pulse steps the field to a new note",
  ["C|TM"] = "the clock pulse steps the pattern to its next note",
  ["C|GUST"] = "the clock pulse plays the gust's note",
  -- §2.11 the gusts. a pulse plays the note and the gust answers with a pulse
  -- the way a drum does. a continuous cable lands on its cross modulation
  -- input instead, where the gust's own Cross knob scales it into pitch and
  -- fold. that is why two gusts cabled together read as modulation.
  ["D|GUST"] = "the pulse plays the gust's note, which answers with a pulse of its own",
  ["R|GUST"] = "the changed pulse plays the note, which answers in turn",
  ["TM|GUST"] = "nothing. a gust takes its pitch from the Scale, not a register",
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
  ["TM|SMP"] = "nothing. a sample takes a trigger, and a register sends notes",
  ["GVOICE|SMP"] = "the drum's answering pulse plays the sample",
  ["voice|SMP"] = "the voice's own strike plays the sample",
  ["E|SMP"] = "nothing continuous. only a pulse plays a sample",
  ["F|SMP"] = "nothing. a sample cell takes a trigger, not a note",
  ["GUST|SMP"] = "nothing. neither one sends the other a pulse",
  ["LFO|SMP"] = "the LFO moves one knob on the sample. pick which on its Param row",
  ["SMP|SMP"] = "nothing. a sample cell never sends a pulse",
  ["SMP|O"] = "the sample is heard, panned to where this output sits",
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
  ["TM|O"] = "nothing. an output carries sound, and a register makes notes",
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

-- §2.13 the FM and VA cells are the same cable endpoint as each other in
-- every direction: same tap out, same mod input, same strike, same pitch
-- route. so the lines are written once, as a synth-shaped counterpart to
-- whatever is at the other end, and installed under both keys -- rather than
-- as twenty-six entries in the table above, half of which would be the other
-- half retyped and one of which would eventually drift.
local SYNTH_DESC = {
  D = "the pulse plays a note on the synth, which answers with a pulse of its own",
  R = "the changed pulse plays a note, which answers in turn",
  C = "the clock pulse plays a note on the synth",
  TM = "the register tunes the synth. cable a trigger in to play it",
  F = "the field tunes the synth, as far as its own Range knob allows",
  E = "the exciter bends the synth, and the synth rides the exciter's colour",
  GVOICE = "the drum's answering pulse plays a note, and its sound bends the synth",
  GUST = "the two cross modulate. turn up Cross on both to hear it",
  voice = "the synth drives the voice's mod path, and the voice bends the synth",
  SMP = "the sample bends the synth. nothing plays a note either way",
  LFO = "open the LFO's page to pick which of the synth's knobs it moves",
  O = "the synth is heard, panned to where this output sits",
}

local TYPE_ORDER = {
  LFO = 0, voice = 1, D = 2, R = 3, E = 4, F = 6, C = 7, TM = 8,
  GVOICE = 9, GUST = 10, FM = 10.3, VA = 10.6, SMP = 11, O = 12,
}

for _, synth_type in ipairs({"FM", "VA"}) do
  for other, text in pairs(SYNTH_DESC) do
    local a, b = other, synth_type
    if (TYPE_ORDER[a] or 99) > (TYPE_ORDER[b] or 99) then a, b = b, a end
    INTERACTION_DESC[a .. "|" .. b] = text
  end
end

-- the two of them cabled to each other, and each to its own kind. one line
-- rather than three, because it is one answer: they modulate each other.
INTERACTION_DESC["FM|FM"] = "the two FM voices cross modulate. Cross on both decides how deeply"
INTERACTION_DESC["VA|VA"] = "the two VA voices cross modulate. Cross on both decides how deeply"
INTERACTION_DESC["FM|VA"] = "the two cross modulate. Cross on each decides how deeply"

-- §2.9b a High clock reaching one of them holds the note open, the same way
-- it does for a voice or a gust.
local SYNTH_HIGH = "the synth holds its note open for as long as this is high"

-- §2.9b a Clock cell set to High is a different cable from the same seat: it
-- sends no pulse at all and holds the far end open instead, so every "the
-- clock pulse ..." line above is the wrong sentence for it. keyed on the
-- OTHER end's type alone, since the near end is a High clock by definition.
-- a type missing here falls through to the ordinary table, which is right:
-- a High cell cabled to a field or a register does exactly what it says
-- there, which is nothing.
local HIGH_DESC = {
  FM = SYNTH_HIGH,
  VA = SYNTH_HIGH,
  voice = "the voice is held open and rings continuously, never struck",
  GVOICE = "the drum is held open and rings continuously, never struck",
  GUST = "the gust swells in and stays there for as long as this is high",
  SMP = "the sample plays continuously instead of swelling and going",
  E = "the exciter runs free, which is what it does uncabled anyway",
  C = "nothing. a clock cell is a source, held or not",
  O = "nothing. an output carries sound, and this carries a gate",
}

local function interaction_text(ta, tb)
  local a, b = ta, tb
  if (TYPE_ORDER[a] or 99) > (TYPE_ORDER[b] or 99) then a, b = b, a end
  return INTERACTION_DESC[a .. "|" .. b] or "no direct interaction defined"
end

-- the same question asked of two actual cells rather than two types, which is
-- what the edge view has and what a mode-dependent answer needs.
local function interaction_text_for(a, b)
  local clockcell = wl("clockcell")
  local other
  if a.type == "C" and clockcell.is_high(a.id) then other = b
  elseif b.type == "C" and clockcell.is_high(b.id) then other = a end
  if other and HIGH_DESC[other.type] then return HIGH_DESC[other.type] end
  return interaction_text(a.type, b.type)
end

function screenui.draw_edge(id_a, id_b)
  local a, b = topology.get(id_a), topology.get(id_b)
  local edge_id = patch.has(id_a, id_b)
  local edge = edge_id and patch.get(edge_id) or nil

  -- the bar below says which side of centre the cable is on and how far,
  -- which is the question you have while turning E3; §5.2d puts the number
  -- back beside it, which is the one you have when you are trying to give
  -- two cables the same gain. it sits on the line under the bar rather than
  -- in the header, so it is next to the thing it describes.
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
    screen.level(13)
    screen.move(126, 32)
    screen.text_right(string.format("%+.2f", edge.gain))
  else
    screen.level(4)
    screen.move(2, 32)
    screen.text(fit("not cabled. tap one to connect", 124))
  end

  screen.level(8)
  local desc_lines = wrap(interaction_text_for(a, b), 30)
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
  elseif state.view == "gusts" then
    screenui.draw_gusts()
  elseif state.view == "mixer" then
    screenui.draw_mixer()
  elseif state.view == "send" then
    screenui.draw_send()
  elseif state.view == "colour" then
    screenui.draw_colour()
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
