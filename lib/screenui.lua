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

local function centred(cx, y, str, lvl)
  if str == nil or str == "" then return end
  screen.level(lvl)
  screen.move(cx - text_w(str) / 2, y)
  screen.text(str)
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
-- inverted: a filled bar with the text knocked out of it, which is what makes
-- it read as a title rather than as one more row of the page. it is 11px
-- tall, so a baseline at 8 sits its 5px ascenders at 3 and its 1px descenders
-- at 9 -- clear of both edges.

local HDR_H = 11
local HDR_BASE = 8

-- an inverted box: the bar's own polarity, flipped back. used for the two
-- boxed readouts the Digitakt puts at either end of its title bar (the
-- machine tag on the left, the tempo on the right).
local function chip(x, w, text)
  screen.level(0)
  screen.rect(x, 1, w, HDR_H - 2)
  screen.fill()
  centred(x + w / 2, HDR_BASE, text, 15)
end

local function chip_w(text)
  return text_w(text) + 6
end

-- the transport, in five pixels: a filled triangle when the patch is running
-- and a filled square when it is frozen. Still (K2) and an external MIDI
-- Stop are the same state (§4.3), so this one glyph reports both.
local function draw_transport(x)
  screen.level(0)
  if state.global.still then
    screen.rect(x, 3, 5, 5)
    screen.fill()
  else
    screen.move(x, 3)
    screen.line(x + 5, 5.5)
    screen.line(x, 8)
    screen.close()
    screen.fill()
  end
end

-- how many pages this list has, as dots: filled for the one you are on. the
-- Digitakt's own way of saying "there is more of this", and it costs eight
-- pixels rather than the twenty a "1/2" would.
local function draw_page_dots(x, page, pages)
  local w = 0
  for i = 1, pages do
    screen.level(0)
    if i == page then
      screen.rect(x + w, 4, 3, 3)
      screen.fill()
    else
      screen.rect(x + w + 1, 5, 1, 1)
      screen.fill()
    end
    w = w + 4
  end
  return w
end

-- the tempo, which is on screen on every page whatever the page is about --
-- it is the one number the whole patch is hung off. "ext" when something
-- else is deciding it (§4.3).
local function tempo_text()
  local bpm = gparam.tempo and gparam.tempo() or (state.global.bpm or 120)
  if gparam.external_clock and gparam.external_clock() then
    return string.format("%.0f ext", bpm)
  end
  return string.format("%.0f", bpm)
end

-- how long a message keeps the header's name slot before the page's own name
-- takes it back. long enough to read a sever or a Regrow, short enough that
-- the header is not still reporting it a minute later.
local EVENT_LINGER = 3.0

-- the old list layout kept a whole line for "whatever just happened" -- a
-- cable made, a Regrow, a sever, a knob's new reading. the widget grid has no
-- spare line, and it does not need one: an Elektron box says this sort of
-- thing in its title bar, and so does this. the page's name is the least
-- urgent thing on the screen (you know which page you opened), so the message
-- borrows that slot and gives it back a few seconds later.
local function header_name(name)
  if state.last_event ~= "" and state.event_age() < EVENT_LINGER then
    return state.last_event
  end
  return name
end

-- tag: two or three characters saying what kind of page this is (a cell's
-- panel letter, "MIX", "G"). name: what it is called. value: the full,
-- untrimmed value of whatever the cursor is on, which is the one thing on
-- the screen that must never be abbreviated.
function screenui.draw_header(tag, name, value, page, pages)
  screen.level(15)
  screen.rect(0, 0, 128, HDR_H)
  screen.fill()

  local x = 2
  draw_transport(x)
  x = x + 7

  if tag and tag ~= "" then
    local w = chip_w(tag)
    chip(x, w, tag)
    x = x + w + 3
  end

  if pages and pages > 1 then
    x = x + draw_page_dots(x, page or 1, pages) + 2
  end

  local tempo = tempo_text()
  local tw = chip_w(tempo)
  chip(128 - tw - 1, tw, tempo)

  local region = (128 - tw - 4) - x
  if region > 8 then
    label_value(x, HDR_BASE, region, header_name(name or ""), value or "", 0, 0)
  end
end

-- the widget grid ---------------------------------------------------------------
-- five columns, two rows, ten to a page; a longer list paginates rather than
-- wrapping back over itself, and E1's focus decides which page you are on so
-- the widget you are turning is always one you can see.

local PL_COLS = 4
local PL_ROWS = 2
local PL_PER_PAGE = PL_COLS * PL_ROWS

-- the panel is 128 wide and 64 tall; the header takes the top eleven, which
-- leaves two 25px blocks with a pixel to spare. within a block the widget is
-- centred eleven pixels down and the label's baseline is fourteen below that
-- -- the font's 5px ascenders then start exactly where the widget stops.
local COL_W = 32
local COL_X0 = 0                    -- left edge of column 1
local BLOCK_TOP = {12, 37}          -- top of each widget row
local KNOB_DY = 11                  -- widget centre, from the block's top
local KNOB_R = 9
local LABEL_DY = 25                 -- label baseline, from the block's top

screenui.PARAMS_PER_PAGE = PL_PER_PAGE

-- 1-based page number a given row lives on.
function screenui.page_of(i)
  return math.floor((i - 1) / PL_PER_PAGE) + 1
end

local function col_centre(col)
  return COL_X0 + (col - 1) * COL_W + COL_W / 2
end

-- the gauge: 270 degrees with the gap at the bottom, the way a panel knob's
-- travel is drawn everywhere. cairo's angles run clockwise with y down, so
-- 0.75pi is the bottom-left end of the sweep and 1.5pi of sweep lands the
-- other end at the bottom-right.
local KNOB_A0 = math.pi * 0.75
local KNOB_SWEEP = math.pi * 1.5

-- three strokes, and no more than three: at fifteen frames a second, ten of
-- these plus a header is the whole screen budget (test/soak.lua counts them),
-- and every extra flourish here is paid for ten times over.
--
--   the body     a plain circle, so a knob at zero still reads as a knob
--                rather than as a gap in the row. this is the Digitakt's
--                whole knob glyph.
--   the travel   a bright arc from the start of the sweep to where the value
--                is. the pointer alone is legible up close; from across a
--                room the arc is what you actually see.
--   the pointer  a radial line, drawn last so it sits over the arc.
local function draw_knob(cx, cy, frac, on)
  frac = util.clamp(frac or 0, 0, 1)
  local a = KNOB_A0 + frac * KNOB_SWEEP

  screen.level(on and 5 or 2)
  screen.circle(cx, cy, KNOB_R - 1)
  screen.stroke()

  if frac > 0.005 then
    screen.level(on and 15 or 7)
    screen.arc(cx, cy, KNOB_R, KNOB_A0, a)
    screen.stroke()
  end

  screen.level(on and 15 or 8)
  screen.move(cx + math.cos(a) * (KNOB_R - 6), cy + math.sin(a) * (KNOB_R - 6))
  screen.line(cx + math.cos(a) * KNOB_R, cy + math.sin(a) * KNOB_R)
  screen.stroke()
end

-- a value that is a word rather than a number: a pointer angle says nothing
-- about "euclidean" or "snapped", so those get the Digitakt's other widget --
-- a box with the reading inside it. clipped to the box; the header has it in
-- full.
local BOX_W, BOX_H = 30, 15

local function draw_box(cx, cy, text, on)
  local x, y = cx - BOX_W / 2, cy - BOX_H / 2
  if on then
    screen.level(15)
    screen.rect(x, y, BOX_W, BOX_H)
    screen.fill()
    centred(cx, cy + 3, clip(text, BOX_W - 4), 0)
  else
    screen.level(3)
    screen.rect(x + 0.5, y + 0.5, BOX_W - 1, BOX_H - 1)
    screen.stroke()
    centred(cx, cy + 3, clip(text, BOX_W - 4), 8)
  end
end

-- which of the two a parameter gets. anything whose reading starts with a
-- number (or an "x", for the decay multiplier's "x1.00") is a quantity and
-- draws as a knob; everything else is a word and draws as a box. deciding it
-- from the text rather than from a flag on the parameter means voice.lua,
-- gvoice.lua, tm.lua, gparam.lua, mixer.lua and cellparam.lua all keep the
-- one contract they already share, and a row that changes from a number to a
-- word (Scale's "free" at position zero) changes widget with it.
local function is_quantity(text)
  return text ~= nil and text:match("^%s*[%+%-x]?%d") ~= nil
end

local function draw_widget(slot, label, text, frac, on)
  local col = (slot % PL_COLS) + 1
  local row = math.floor(slot / PL_COLS) + 1
  local top = BLOCK_TOP[row]
  local cx = col_centre(col)

  if is_quantity(text) then
    draw_knob(cx, top + KNOB_DY, frac, on)
  else
    draw_box(cx, top + KNOB_DY, text, on)
  end

  -- clipped, not fitted: a trailing full stop costs a whole character here
  -- and says nothing the widget's position in the grid does not. the four
  -- pixels held back are the gutter -- at the full column width two long
  -- labels in neighbouring columns run into each other.
  centred(cx, top + LABEL_DY, clip(label, COL_W - 4), on and 15 or 5)
end

-- draw one page of a PARAMS list. `text_fn`/`frac_fn` adapt the two calling
-- conventions in the codebase (a cell page's take an id, a global page's take
-- nothing) so this routine never learns which kind of list it has.
local function draw_param_grid(params, focus, text_fn, frac_fn)
  local page = screenui.page_of(focus)
  local first = (page - 1) * PL_PER_PAGE + 1
  for slot = 0, PL_PER_PAGE - 1 do
    local p = params[first + slot]
    if p then
      draw_widget(slot, p.label, text_fn(p), frac_fn(p), (first + slot) == focus)
    end
  end
  return page, math.max(1, math.ceil(#params / PL_PER_PAGE))
end

-- §5.2 global param page (nothing held, no cell page open) --------------------
-- what replaced the network view: E1 walks gparam.PARAMS, E2/E3 nudge the one
-- under the cursor coarse/fine (Canopy.lua's enc()).
--
-- the second line the old list kept for "whatever just happened" is gone with
-- the list; the messages themselves are not -- they surface in the header's
-- name slot for a few seconds (header_name above), on every page rather than
-- only on this one.

function screenui.draw_global()
  local focus = util.clamp(state.gparam_focus or 1, 1, gparam.PARAM_COUNT)
  local p = gparam.param(focus)
  local pages = math.ceil(gparam.PARAM_COUNT / PL_PER_PAGE)
  screenui.draw_header("G", "Canopy", p and p.text() or "",
                       screenui.page_of(focus), pages)
  draw_param_grid(gparam.PARAMS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end)
end

-- §4.1b the mixer page (K3, back with K2) --------------------------------------
-- five faders: the four always-on soundscape loops and the master
-- (lib/mixer.lua). exactly one row of the grid, which is the whole reason the
-- list is five long.

function screenui.draw_mixer()
  local focus = util.clamp(state.mparam_focus or 1, 1, mixer.PARAM_COUNT)
  local p = mixer.param(focus)
  local pages = math.ceil(mixer.PARAM_COUNT / PL_PER_PAGE)
  screenui.draw_header("MIX", "Mixer", p and p.text() or "",
                       screenui.page_of(focus), pages)
  draw_param_grid(mixer.PARAMS, focus,
                  function(q) return q.text() end,
                  function(q) return q.frac() end)
end

-- the cell page (one cell held, or one cell tapped open) ----------------------
-- the same page either way. holding is a glance: the encoders are on it for
-- as long as you hold, and the patch gesture is still live underneath.
-- tapping latches it open and the grid goes back to patching -- and dims
-- everything that is not this cell (gridui.grid_redraw), so the panel is
-- showing the same one thing the screen is.

local function cell_tag(cell)
  local letter = cell.letter or cell.type
  if cell.type == "voice" then letter = "M" end
  return letter
end

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

  local value = ""
  if page_mod and count > 0 then
    local p = page_mod.param(focus)
    if p then value = p.text(id) end
  end

  screenui.draw_header(cell_tag(cell), cell.name, value,
                       screenui.page_of(focus), pages)

  if page_mod then
    draw_param_grid(page_mod.PARAMS, focus,
                    function(p) return p.text(id) end,
                    function(p) return p.get(id) end)
  end
end

-- edge view (two cells held) -------------------------------------------------

-- the socket collapse means a voice is one point that reacts to whatever's
-- at the other end of the cable: a pulse always strikes it; a stream (E/H)
-- always drives its mod path; a field or TM tunes it; another voice does
-- both a pulse-answer and a continuous mod-feed on the same cable, in both
-- directions. an Output cell is a pure destination -- only voice/GVOICE/E/H
-- reach it, and it never talks back.
local INTERACTION_DESC = {
  ["voice|voice"] = "each voice's own audio feeds the other's mod path; either answers a strike",
  ["voice|O"] = "the voice's audio reaches the speakers at this cell's pan position",
  ["D|voice"] = "the pulse strikes the voice, which answers out of its own point",
  ["R|voice"] = "the transformed pulse strikes the voice, which answers in turn",
  ["TM|voice"] = "the pulse clocks the register and strikes the voice; also feeds its pitch",
  ["SEQ|voice"] = "an active step's pulse strikes the voice",
  ["C|voice"] = "the clock's pulse strikes the voice",
  ["E|voice"] = "the stream drives the voice's mod path (Balance decides how)",
  ["H|voice"] = "the lattice returns into the voice's mod path",
  ["F|voice"] = "the field tunes the voice, scaled by its own Depth knob",
  ["D|D"] = "mutual phase coupling (Kuramoto) + mutual triggering",
  ["D|R"] = "the pulse goes through the transform on its way out",
  ["R|R"] = "transforms in series -- the chain is the pattern",
  ["D|E"] = "pulse envelopes the stream into a grain; free-running otherwise",
  ["R|E"] = "the transformed pulse fires the grain",
  ["D|H"] = "pulse enters the lattice and diffuses",
  ["R|H"] = "the transformed pulse enters the lattice",
  ["E|E"] = "cross-modulation: each modulates the other's colour",
  ["E|H"] = "stream diffuses through the lattice",
  ["E|O"] = "the stream reaches the speakers at this cell's pan position",
  ["H|O"] = "the lattice's emergence reaches the speakers at this cell's pan position",
  ["H|H"] = "direct link -- short-circuits two lattice points",
  ["D|F"] = "each pulse steps the field to a new degree",
  ["R|F"] = "the transformed pulse steps the field",
  ["E|F"] = "the exciter's colour rides the field's line",
  ["H|F"] = "a pulse out of the lattice steps the field",
  ["F|F"] = "the two fields pull together (or apart, at negative gain)",
  ["D|C"] = "no meaning: a clock cell is a pure source",
  -- §2.7b: a GVOICE cell has no sockets, so it is struck directly and
  -- answers with its own pulse out, the same shape as an R cell's transform.
  ["D|GVOICE"] = "the pulse strikes it, which answers with a pulse of its own",
  ["R|GVOICE"] = "the transformed pulse strikes it, which answers in turn",
  ["E|GVOICE"] = "the drum's answering pulse fires the grain",
  ["H|GVOICE"] = "a pulse out of the lattice strikes it, which answers into the lattice",
  ["F|GVOICE"] = "the drum's answering pulse steps the field",
  ["GVOICE|GVOICE"] = "one drum's answering pulse strikes the next",
  ["GVOICE|O"] = "the drum's audio reaches the speakers at this cell's pan position",
  -- §2.3b: a TM cell is a pulse cell like D and R, but has no gait of its
  -- own -- every pulse that reaches it is one clock edge for its shift
  -- register, and its own answering pulse is gated by whichever bit its Tap
  -- knob picks. it is also a pitch source in its own right when cabled to a
  -- voice, summed alongside whatever fields are cabled there (§2.6).
  ["D|TM"] = "the pulse clocks the register, which answers with a pulse of its own",
  ["R|TM"] = "the transformed pulse clocks the register, which answers in turn",
  ["E|TM"] = "the register's answering pulse fires the grain",
  ["H|TM"] = "a pulse out of the lattice clocks the register",
  ["F|TM"] = "no meaning: TM takes a trigger, not a field",
  ["TM|GVOICE"] = "the register's answering pulse strikes it, which answers in turn",
  ["TM|TM"] = "each register's answering pulse clocks the other -- a mutual, evolving loop",
  -- Clock cells: pure sources, flash on a multiple/division of the master
  -- clock, feed anything pulse-shaped.
  ["C|C"] = "no meaning: a clock cell has nothing to gate",
  ["C|R"] = "the clock's pulse goes through the transform on its way out",
  ["C|GVOICE"] = "the clock's pulse strikes it, which answers with a pulse of its own",
  ["C|E"] = "the clock's pulse envelopes the stream into a grain",
  ["C|H"] = "the clock's pulse enters the lattice",
  ["C|F"] = "each clock pulse steps the field to a new degree",
  ["C|TM"] = "the clock's pulse clocks the register",
  ["C|SEQ"] = "the clock drives the lane, or fires one step directly",
  -- Q4/Q6 lanes: a pulse on the last cell of a lane advances the shared
  -- playhead; a pulse on any other cell fires that step directly.
  ["D|SEQ"] = "the pulse drives the lane, or fires one step directly",
  ["R|SEQ"] = "the transformed pulse drives the lane, or fires one step",
  ["TM|SEQ"] = "the register's answering pulse drives the lane, or fires one step",
  ["GVOICE|SEQ"] = "the drum's answering pulse drives the lane, or fires one step",
  ["H|SEQ"] = "a pulse out of the lattice drives the lane, or fires one step",
  ["SEQ|SEQ"] = "one lane's firing step can drive or fire a step in the other",
  ["E|SEQ"] = "no meaning: an exciter has no pulse of its own to send",
  ["F|SEQ"] = "no meaning: a field never emits a pulse",
  -- the Output row is exclusive (patch.lua): a source sits at one pan
  -- position, and cabling it to a second Out cell moves it rather than
  -- adding to it. two Out cells together is not a cable at all.
  ["O|O"] = "no meaning: an Output cell is a destination, never a source",
}

local TYPE_ORDER = {
  voice = 1, D = 2, R = 3, E = 4, H = 5, F = 6, C = 7, TM = 8, GVOICE = 9,
  SEQ = 10, O = 11,
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

  screenui.draw_header("<>", "cable",
                       edge and string.format("%+.2f", edge.gain) or "none")

  -- two names on one line: split the width between them and let each give way
  -- on its own side rather than letting a long pair meet in the middle.
  screen.level(15)
  screen.move(2, 20)
  screen.text(fit(a.name, 56))
  screen.move(126, 20)
  screen.text_right(fit(b.name, 56))
  screen.level(4)
  screen.move(62, 20)
  screen.text("\xE2\x80\x94")

  if edge then
    -- one full-width bar rather than a knob: a cable's gain is bipolar and
    -- what you want to see is which side of centre it is on and how far,
    -- which a straight run of pixels shows and a 270-degree gauge does not.
    screen.level(2)
    screen.rect(2, 24, 124, 2)
    screen.fill()
    screen.level(13)
    screen.rect(2, 24, math.floor(124 * ((edge.gain + 1) / 2)), 2)
    screen.fill()
    if edge.oneway then
      screen.level(6)
      screen.move(2, 33)
      screen.text("one-way")
    end
  else
    screen.level(4)
    screen.move(2, 33)
    screen.text(fit("not cabled \xE2\x80\x94 tap-release one", 124))
  end

  screen.level(8)
  local desc_lines = wrap(interaction_text(a.type, b.type), 30)
  for i, line in ipairs(desc_lines) do
    if i > 3 then break end
    screen.move(2, 36 + i * 9)
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
    -- is down.
    screenui.draw_cell(state.held[1])
  elseif state.cell_edit then
    screenui.draw_cell(state.cell_edit)
  elseif state.view == "mixer" then
    screenui.draw_mixer()
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
