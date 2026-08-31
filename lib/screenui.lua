-- screenui.lua
-- global param / cell / edge / voice views. (§5.2-5.5)
--
-- the lexicon pages are gone. they were a manual you had to leave the patch
-- to read, and everything worth reading off them -- what a cell's one knob
-- means, what a cable between two types does -- is already printed on the
-- cell and edge views, at the moment you are holding the thing it is about.
-- what replaces them is §5.5: tap a voice cell and the screen becomes that
-- voice's eight-parameter sound page.
--
-- the network view -- the patch drawn as a lit map with dotted cable "wires"
-- -- is gone too, replaced by §5.2's global param page: the same E1-select,
-- E2/E3-nudge shape as the sound page, for the nine macros that reach every
-- voice at once (lib/gparam.lua) rather than one.

local topology  = wl("topology")
local patch     = wl("patch")
local lexicon   = wl("lexicon")
local state     = wl("state")
local rambler   = wl("rambler")
local weave     = wl("weave")
local heartwood = wl("heartwood")
local grove     = wl("grove")
local climate   = wl("climate")
local voice     = wl("voice")
local gparam    = wl("gparam")
local exciter   = wl("exciter")

local screenui = {}

-- shared widgets --------------------------------------------------------------

local function bar(x, y, w, h, frac, lvl)
  screen.level(2)
  screen.rect(x, y, w, h)
  screen.stroke()
  local fw = util.clamp(math.floor(w * frac), 0, w)
  if fw > 0 then
    screen.level(lvl or 12)
    screen.rect(x, y, fw, h)
    screen.fill()
  end
end

-- naive word wrap for the small screen font (~26 chars fit at 128px wide)
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

-- nine-parameter list page -----------------------------------------------------
-- shared by §5.2 (global) and §5.5 (voice): two columns, five rows in the
-- first (nine params split 5+4), the focused row lit. `text_fn`/`frac_fn`
-- take a param and return its printable value / 0..1 bar position -- the two
-- callers differ only in whether those close over a voice id.

local PL_ROWS = 5
local PL_COL_X = {2, 66}
local PL_COL_W = 60

local function draw_param_list(params, focus, text_fn, frac_fn, hint)
  for i, p in ipairs(params) do
    local col = (i <= PL_ROWS) and 1 or 2
    local row = ((i - 1) % PL_ROWS)
    local x = PL_COL_X[col]
    -- 8px rows starting at 20: the fifth bar ends at 56, which still leaves
    -- the hint line at 63 its own space on a 64px panel.
    local y = 20 + row * 8
    local on = (i == focus)
    screen.level(on and 15 or 6)
    screen.move(x, y)
    screen.text(p.label)
    screen.move(x + PL_COL_W, y)
    screen.text_right(text_fn(p))
    bar(x, y + 2, PL_COL_W, 2, frac_fn(p), on and 12 or 4)
  end

  screen.level(2)
  screen.move(2, 63)
  screen.text(hint)
end

-- §5.5 voice page ---------------------------------------------------------------
-- reached by tapping a voice cell (which keeps it open and gives it the
-- encoders) or by holding it (which shows the same page for as long as you
-- hold, without taking the encoders off the patch).

function screenui.draw_voice(id, live)
  local cell = topology.get(id)
  screen.level(15)
  screen.move(2, 8)
  screen.text(cell.name)
  screen.level(live and 15 or 4)
  screen.move(126, 8)
  screen.text_right(live and "sound" or "sound \xC2\xB7 hold")

  screen.level(4)
  screen.move(2, 11)
  screen.line(126, 11)
  screen.stroke()

  local focus = util.clamp(state.vparam_focus or 1, 1, voice.PARAM_COUNT)
  draw_param_list(voice.PARAMS, focus,
                  function(p) return p.text(id) end,
                  function(p) return p.get(id) end,
                  live and "E1 pick  E2/E3 coarse/fine" or "tap the cell to edit")
end

-- §5.2 global param page (nothing held, no voice page open) -------------------
-- what replaced the network view: E1 walks gparam.PARAMS, E2/E3 nudge the
-- one under the cursor coarse/fine (Woodland.lua's enc()). the title line's
-- right side carries the same transient event feedback the network view used
-- to print along its bottom edge (a sever, a gait swap, Regrow/Clearing).

function screenui.draw_global()
  screen.level(15)
  screen.move(2, 8)
  screen.text("Woodland")
  screen.level(8)
  screen.move(126, 8)
  screen.text_right(string.sub(state.last_event or "", 1, 18))

  screen.level(4)
  screen.move(2, 11)
  screen.line(126, 11)
  screen.stroke()

  local focus = util.clamp(state.gparam_focus or 1, 1, gparam.PARAM_COUNT)
  draw_param_list(gparam.PARAMS, focus,
                  function(p) return p.text() end,
                  function(p) return p.frac() end,
                  "E1 pick  E2/E3 coarse/fine")
end

-- cell view (one cell held) --------------------------------------------------

function screenui.draw_cell(id)
  local cell = topology.get(id)
  if cell.type == "voice" then
    screenui.draw_voice(id, state.voice_edit == id)
    return
  end

  screen.level(15)
  screen.move(2, 8)
  screen.text(cell.name)
  screen.move(126, 8)
  screen.text_right(cell.type)

  screen.level(4)
  screen.move(2, 12)
  screen.line(126, 12)
  screen.stroke()

  -- a plain-English line on what this cell actually is, right under the
  -- title -- everything below it is numbers, and the numbers mean nothing
  -- until you know that. one line only (the screen has no room for lexicon's
  -- full sentence on every type), word-wrapped so it never splits mid-word.
  local desc = lexicon.describe(id)
  if desc then
    screen.level(8)
    screen.move(2, 19)
    screen.text(wrap(desc, 26)[1])
  end

  -- for a D cell the E2 knob means whatever its current gait says it means,
  -- so the gait names the row and supplies its own units (§4.2) -- and the
  -- same is true one type over for R's rule, F's mode and C's shape.
  local info  = (cell.type == "D") and rambler.info(id) or nil
  local winfo = (cell.type == "R") and weave.info(id) or nil
  local hinfo = (cell.type == "H") and heartwood.info(id) or nil
  local finfo = (cell.type == "F") and grove.info(id) or nil
  local cinfo = (cell.type == "C") and climate.info(id) or nil

  local ch = lexicon.character(id)
  local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
  -- the bar draws the player's own setting; the number to its right is what
  -- the cell is actually running on, so a climate cable is visible as the
  -- two of them disagreeing (§2.8).
  local base = state.base_character(id, lo, hi)
  local eff = state.get_character(id, cell, lo, hi)
  screen.level(12)
  screen.move(2, 27)
  screen.text(info and info.gait or winfo and winfo.rule or finfo and finfo.mode
              or cinfo and cinfo.shape or (ch and ch.label or "character"))
  screen.move(126, 27)
  screen.text_right(info and info.param or winfo and winfo.param
                    or finfo and finfo.param or cinfo and cinfo.param
                    or string.format("%.2f", eff))
  bar(2, 30, 124, 3, (base - lo) / (hi - lo))
  if math.abs(eff - base) > 1e-4 then
    -- a single bright pixel where the weather currently has it.
    screen.level(15)
    screen.pixel(2 + math.floor(124 * util.clamp((eff - lo) / (hi - lo), 0, 1)), 29)
    screen.fill()
  end

  if info then
    -- second half of the row is the grid Weather is holding this cell to
    -- (§4.1), or "free" once Weather has let go of it entirely.
    local mode = (info.rooted_ok and info.rooted) and "rooted" or "wild"
    mode = mode .. " \xC2\xB7 " .. (info.grid or "free")
    screen.level(12)
    screen.move(2, 41)
    screen.text(mode)
    screen.move(126, 41)
    screen.text_right(string.format("coupling %.2f", info.energy))
    bar(2, 44, 124, 3, info.phase or 0, 6)
  elseif winfo then
    -- an R cell has nothing of its own to show -- it is silent until spoken
    -- to -- so what the row reads out is its place in the chain: how much
    -- reaches it, how many ways out it has, and whether its gate is open.
    screen.level(12)
    screen.move(2, 41)
    screen.text(string.format("%d in \xC2\xB7 %d out", winfo.ins, winfo.outs))
    screen.move(126, 41)
    screen.text_right(winfo.open and "open" or "shut")
  elseif hinfo then
    -- conductance is one knob standing for two quantities (§2.5), so the row
    -- under it reads out both, and the bar is what is actually still moving
    -- around the lattice rather than anything the player set.
    screen.level(12)
    screen.move(2, 41)
    screen.text(string.format("%.0f ms hop \xC2\xB7 %d links",
                              hinfo.hop * 1000, hinfo.links))
    screen.move(126, 41)
    screen.text_right(string.format("loss %.2f", 1 - hinfo.loss))
    bar(2, 44, 124, 3, hinfo.charge, 6)
  elseif finfo then
    -- where the field is *right now*, in semitones off the root, and the bar
    -- is its position across the whole range rather than anything set: the
    -- point of an F cell is that it is somewhere different every time you look.
    screen.level(12)
    screen.move(2, 41)
    screen.text(string.format("%+.2f st \xC2\xB7 %d voice%s",
                              finfo.degree, finfo.voices,
                              finfo.voices == 1 and "" or "s"))
    screen.move(126, 41)
    screen.text_right(finfo.snap and "snapped" or "free")
    bar(2, 44, 124, 3, util.clamp((finfo.pos + 1) / 2, 0, 1), 6)
  elseif cinfo then
    -- a climate cell's value is the whole of what it is, so it gets the bar,
    -- centred: half-full is "doing nothing right now".
    screen.level(12)
    screen.move(2, 41)
    screen.text(string.format("reaches %d", cinfo.reaches))
    screen.move(126, 41)
    screen.text_right(string.format("%+.2f", cinfo.value))
    bar(2, 44, 124, 3, (cinfo.value + 1) / 2, 6)
  else
    -- §4.2 E3 with no cable focused. a socket hands the gesture to its voice,
    -- so the row names whose decay is actually moving. a voice can be read
    -- out in seconds of ring time; an exciter has twenty different envelopes
    -- and no single one to name, so it reads as a ratio (see exciter.lua).
    local target = state.decay_target(cell)
    local tcell = target and topology.get(target)
    local d = target and state.get_decay(target) or 0
    local label, readout = "decay", string.format("%.2f", d)
    if not tcell then
      label, readout = "", ""
    elseif tcell.type == "voice" then
      readout = string.format("%.2f s", voice.decay_seconds(target))
      if cell.type == "node" then label = "decay \xC2\xB7 " .. tcell.name end
    elseif tcell.type == "S" then
      readout = string.format("x%.2f", exciter.decay_scale(target))
    end
    screen.level(12)
    screen.move(2, 41)
    screen.text(label)
    if tcell then
      screen.move(126, 41)
      screen.text_right(readout)
      bar(2, 44, 124, 3, d)
    end
  end

  screen.level(4)
  screen.move(2, 49)
  screen.line(126, 49)
  screen.stroke()

  local edges = patch.edges_at(id)
  local focus = state.get_focus(id)
  screen.level(12)
  screen.move(2, 55)
  screen.text(#edges .. " cable" .. (#edges == 1 and "" or "s"))

  -- §5.3 draws three cable rows, but the description line above now takes
  -- the vertical room that used to hold a second one, so this is a one-row
  -- window that follows E1's focus instead of a fixed top-of-list slice --
  -- otherwise focusing cable 2+ would attenuvert something you cannot see.
  local CABLE_ROWS = 1
  local first = 1
  if focus > CABLE_ROWS then first = focus - CABLE_ROWS + 1 end
  for row = 0, CABLE_ROWS - 1 do
    local i = first + row
    local edge = edges[i]
    if not edge then break end
    local other = topology.get(patch.other(edge, id))
    local y = 55 + row * 6
    screen.level(i == focus and 15 or 6)
    screen.move(52, y)
    screen.text((i == focus and "> " or "  ") .. (other and other.name or "?"))
    screen.move(126, y)
    screen.text_right(string.format("%+.2f", edge.gain))
  end

  local swap = (cell.type == "D" and "gait") or (cell.type == "R" and "rule")
            or (cell.type == "F" and "mode") or (cell.type == "C" and "shape")
  screen.level(2)
  screen.move(2, 63)
  screen.text(swap and ("K2+K3 sever   K1+E2 " .. swap) or "K2+K3 sever")
end

-- edge view (two cells held) -------------------------------------------------

local INTERACTION_DESC = {
  ["node|node"] = "an out socket rings the other voice; T/P/M are inputs",
  ["D|node"] = "pulse strikes / chokes / re-rolls, by socket",
  ["R|node"] = "the transformed pulse strikes / chokes / re-rolls",
  ["S|node"] = "stream drives the M socket; T and P take pulses only",
  ["H|node"] = "the lattice returns into the M socket",
  ["node|F"] = "no meaning: a field belongs on the P socket, not from it",
  ["node|C"] = "the weather walks that socket's own knob",
  ["D|D"] = "mutual phase coupling (Kuramoto) + mutual triggering",
  ["D|R"] = "the pulse goes through the transform on its way out",
  ["R|R"] = "transforms in series -- the chain is the pattern",
  ["D|S"] = "pulse envelopes S into a grain; free-running otherwise",
  ["R|S"] = "the transformed pulse fires the grain",
  ["D|H"] = "pulse enters the lattice and diffuses",
  ["R|H"] = "the transformed pulse enters the lattice",
  ["S|S"] = "cross-modulation: each modulates the other's colour",
  ["H|S"] = "stream diffuses through the lattice",
  ["H|H"] = "direct link -- short-circuits two lattice points",
  ["D|F"] = "each pulse steps the field to a new degree",
  ["R|F"] = "the transformed pulse steps the field",
  ["S|F"] = "the exciter's colour rides the field's line",
  ["H|F"] = "a pulse out of the lattice steps the field",
  ["F|F"] = "the two fields pull together (or apart, at negative gain)",
  ["D|C"] = "the weather walks this cell's rate",
  ["R|C"] = "the weather walks this transform's own knob",
  ["S|C"] = "the weather walks this exciter's Colour",
  ["H|C"] = "the weather walks this node's conductance",
  ["F|C"] = "the weather walks this field's Range",
  ["C|C"] = "one weather sets how fast the other turns",
}

local function interaction_text(ta, tb)
  local order = {node = 1, D = 2, R = 3, S = 4, H = 5, F = 6, C = 7}
  local a, b = ta, tb
  if (order[a] or 9) > (order[b] or 9) then a, b = b, a end
  return INTERACTION_DESC[a .. "|" .. b] or "no direct interaction defined"
end

function screenui.draw_edge(id_a, id_b)
  local a, b = topology.get(id_a), topology.get(id_b)
  local edge_id = patch.has(id_a, id_b)

  screen.level(15)
  screen.move(2, 10)
  screen.text(a.name)
  screen.move(126, 10)
  screen.text_right(b.name)

  if edge_id then
    local edge = patch.get(edge_id)
    screen.level(12)
    screen.move(2, 24)
    screen.text(string.format("gain %+.2f%s", edge.gain, edge.oneway and "  (one-way)" or ""))
    bar(2, 28, 124, 4, (edge.gain + 1) / 2)
  else
    screen.level(4)
    screen.move(2, 24)
    screen.text("not yet cabled \xE2\x80\x94 tap-release one")
  end

  screen.level(8)
  local desc_lines = wrap(interaction_text(a.type, b.type), 26)
  for i, line in ipairs(desc_lines) do
    if i > 2 then break end
    screen.move(2, 40 + i * 8)
    screen.text(line)
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
    screenui.draw_cell(state.held[1])
  elseif state.voice_edit then
    screenui.draw_voice(state.voice_edit, true)
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
