-- screenui.lua
-- the global param page, the per-cell settings page, and the edge view.
--
-- the lexicon pages are gone. they were a manual you had to leave the patch
-- to read, and everything worth reading off them -- what a cell's one knob
-- means, what a cable between two types does -- is already printed on the
-- cell and edge views, at the moment you are holding the thing it is about.
--
-- the network view -- the patch drawn as a lit map with dotted cable "wires"
-- -- is gone too, replaced by §5.2's global param page: the same E1-select,
-- E2/E3-nudge shape as the cell page, for the nine macros that reach every
-- voice at once (lib/gparam.lua) rather than one.
--
-- there is now exactly ONE page shape on this screen. voice/GVOICE/TM cells
-- used to get a parameter list and everything else got a bespoke hand-laid
-- readout with its own y coordinates; lib/cellparam.lua gave every type a
-- parameter list, so `draw_cell` draws all of them and `draw_global` draws
-- the macros with the same routine.
--
-- the vertical grid, and why it is what it is. the norns font puts about five
-- pixels above a baseline and one below it, so a row of text at y occupies
-- y-5 .. y+1. the old layout drew 8px rows with a 2px bar at y+2, which is
-- y+2 .. y+3 -- and the next row's ascenders start at y+3. that one-pixel
-- collision is what made the parameter pages look like they were printing on
-- top of themselves, and it got much worse than one pixel when a list ran
-- past ten entries: rows 11 and 12 wrapped back onto rows 6 and 7 outright
-- (voice.PARAMS is twelve rows long). so: 8px rows, a 1px bar at y+2, and a
-- list longer than the page paginates instead of wrapping.

local topology   = wl("topology")
local patch      = wl("patch")
local lexicon    = wl("lexicon")
local state      = wl("state")
local sequencer  = wl("sequencer")
local gparam     = wl("gparam")
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
-- was dropped. used everywhere two pieces of text share one line, which is
-- every line on this screen.
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

local function bar(x, y, w, h, frac, lvl)
  local fw = util.clamp(math.floor(w * (frac or 0)), 0, w)
  screen.level(2)
  screen.rect(x, y, w, h)
  screen.fill()
  if fw > 0 then
    screen.level(lvl or 12)
    screen.rect(x, y, fw, h)
    screen.fill()
  end
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

-- the parameter list ----------------------------------------------------------
-- two columns, five rows, ten to a page; a longer list pages rather than
-- wrapping back over itself, and E1's focus decides which page you are on so
-- the row you are turning is always the row you can see.

-- how long a message keeps the global page's second line before the hint
-- takes it back. long enough to read a sever or a Regrow, short enough that
-- the line is not still reporting it a minute later.
local EVENT_LINGER = 3.0

local PL_ROWS = 5
local PL_COL_X = {2, 66}
local PL_COL_W = 60
local PL_FULL_W = 124
local PL_PER_PAGE = PL_ROWS * 2
local PL_Y0 = 22
local PL_DY = 8

screenui.PARAMS_PER_PAGE = PL_PER_PAGE

-- 1-based page number a given row lives on, and how many pages there are.
function screenui.page_of(i)
  return math.floor((i - 1) / PL_PER_PAGE) + 1
end

local function draw_param_list(params, focus, text_fn, frac_fn)
  -- a list that fits in one column gets the whole width rather than half of
  -- it. most cell pages are three or four rows, and their values are words
  -- ("euclidean", "snapped", "4:8") rather than two-decimal numbers -- in a
  -- 60px column those crowd the label right off the line.
  local single = (#params <= PL_ROWS)
  local page = screenui.page_of(focus)
  local first = (page - 1) * PL_PER_PAGE + 1
  for slot = 0, PL_PER_PAGE - 1 do
    local i = first + slot
    local p = params[i]
    if p then
      local col = (slot < PL_ROWS) and 1 or 2
      local x = single and PL_COL_X[1] or PL_COL_X[col]
      local w = single and PL_FULL_W or PL_COL_W
      local y = PL_Y0 + (slot % PL_ROWS) * PL_DY
      local on = (i == focus)
      label_value(x, y, w, p.label, text_fn(p), on and 15 or 6, on and 15 or 6)
      -- 1px, at y+2: the row's own descenders reach y+1 and the next row's
      -- ascenders start at y+3, so this is the only clear line there is.
      bar(x, y + 2, w, 1, frac_fn(p), on and 13 or 4)
    end
  end
  return page, math.max(1, math.ceil(#params / PL_PER_PAGE))
end

-- the header: a name on the left, a status word on the right, a rule under
-- both. shared by every page so they all sit on the same two lines.
local function draw_header(name, right, right_lvl)
  label_value(2, 6, 124, name, right or "", 15, right_lvl or 4)
  screen.level(3)
  screen.move(2, 8)
  screen.line(126, 8)
  screen.stroke()
end

local function draw_note(text, lvl)
  if not text or text == "" then return end
  screen.level(lvl or 8)
  screen.move(2, 15)
  screen.text(fit(text, 124))
end

-- §5.2 global param page (nothing held, no cell page open) --------------------
-- what replaced the network view: E1 walks gparam.PARAMS, E2/E3 nudge the one
-- under the cursor coarse/fine (Canopy.lua's enc()).

function screenui.draw_global()
  local focus = util.clamp(state.gparam_focus or 1, 1, gparam.PARAM_COUNT)
  local page, pages = screenui.page_of(focus),
                      math.ceil(gparam.PARAM_COUNT / PL_PER_PAGE)
  draw_header("Canopy", (pages > 1) and (page .. "/" .. pages) or "", 6)
  -- the line the old network view kept along its bottom edge: whatever just
  -- happened, for a few seconds, and the encoder hint the rest of the time.
  local fresh = state.last_event ~= "" and state.event_age() < EVENT_LINGER
  draw_note(fresh and state.last_event or "E1 pick   E2/E3 coarse/fine",
            fresh and 10 or 5)
  draw_param_list(gparam.PARAMS, focus,
                  function(p) return p.text() end,
                  function(p) return p.frac() end)
end

-- the cell page (one cell held, or one cell tapped open) ----------------------
-- the same page either way. holding is a glance: the encoders are on it for
-- as long as you hold, and the patch gesture is still live underneath.
-- tapping latches it open and the grid goes back to patching.

-- what the top-right of the header says: the panel letter, plus how the page
-- got here.
local function cell_status(cell, live)
  local letter = cell.letter or cell.type
  if cell.type == "voice" then letter = "M" end
  return live and (letter .. " \xC2\xB7 open") or letter
end

function screenui.draw_cell(id, live)
  local cell = topology.get(id)
  if not cell then return end
  local page_mod = cellparam.page(id)

  local count = page_mod and page_mod.PARAM_COUNT or 0
  local focus = util.clamp(state.vparam_focus or 1, 1, math.max(1, count))
  local pages = math.max(1, math.ceil(count / PL_PER_PAGE))
  local right = cell_status(cell, live)
  if pages > 1 then
    right = right .. " " .. screenui.page_of(focus) .. "/" .. pages
  end
  draw_header(cell.name, right, live and 12 or 5)

  -- the second line is the cable readout when the cell is patched (that is
  -- what you are usually holding it to find out) and lexicon's one-line
  -- description of the type when it is not.
  local edges = patch.edges_at(id)
  if #edges > 0 then
    local names = {}
    for _, edge in ipairs(edges) do
      local other = topology.get(patch.other(edge, id))
      table.insert(names, (other and other.name or "?"))
    end
    draw_note(#edges .. (#edges == 1 and " cable: " or " cables: ")
              .. table.concat(names, ", "), 8)
  else
    local desc = lexicon.describe(id)
    draw_note(desc and wrap(desc, 30)[1] or "", 6)
  end

  if page_mod then
    draw_param_list(page_mod.PARAMS, focus,
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

  -- two names on one line: split the width between them and let each give way
  -- on its own side rather than letting a long pair meet in the middle.
  screen.level(15)
  screen.move(2, 8)
  screen.text(fit(a.name, 58))
  screen.move(126, 8)
  screen.text_right(fit(b.name, 58))
  screen.level(4)
  screen.move(62, 8)
  screen.text("\xE2\x80\x94")

  screen.level(3)
  screen.move(2, 11)
  screen.line(126, 11)
  screen.stroke()

  if edge_id then
    local edge = patch.get(edge_id)
    label_value(2, 22, 124, edge.oneway and "gain (one-way)" or "gain",
                string.format("%+.2f", edge.gain), 12, 12)
    bar(2, 24, 124, 1, (edge.gain + 1) / 2, 13)
  else
    screen.level(4)
    screen.move(2, 22)
    screen.text(fit("not cabled \xE2\x80\x94 tap-release one", 124))
  end

  screen.level(8)
  local desc_lines = wrap(interaction_text(a.type, b.type), 30)
  for i, line in ipairs(desc_lines) do
    if i > 3 then break end
    screen.move(2, 32 + i * 9)
    screen.text(fit(line, 124))
  end

  screen.level(2)
  screen.move(2, 63)
  screen.text("E3 sets gain")
end

-- top-level dispatch ----------------------------------------------------------

function screenui.redraw()
  screen.clear()

  if #state.held == 2 then
    screenui.draw_edge(state.held[1], state.held[2])
  elseif #state.held == 1 then
    -- a glance: the same page the tap latches open, for as long as the cell
    -- is down. `live` is false so the header says so.
    screenui.draw_cell(state.held[1], state.cell_edit == state.held[1])
  elseif state.cell_edit then
    screenui.draw_cell(state.cell_edit, true)
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
    screen.rect(10, 24, 108, 16)
    screen.stroke()
    screen.move(14, 34)
    screen.text(state.confirm.label)
    screen.level(6)
    screen.rect(14, 37, math.floor(100 * frac), 2)
    screen.fill()
  end

  screen.update()
end

return screenui
