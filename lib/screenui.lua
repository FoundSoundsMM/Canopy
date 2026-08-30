-- screenui.lua
-- network / meters / cell / edge / voice views. (§5.2-5.5)
--
-- the lexicon pages are gone. they were a manual you had to leave the patch
-- to read, and everything worth reading off them -- what a cell's one knob
-- means, what a cable between two types does -- is already printed on the
-- cell and edge views, at the moment you are holding the thing it is about.
-- what replaces them is §5.5: tap a voice cell and the screen becomes that
-- voice's eight-parameter sound page.

local topology  = wl("topology")
local patch     = wl("patch")
local lexicon   = wl("lexicon")
local state     = wl("state")
local rambler   = wl("rambler")
local weave     = wl("weave")
local heartwood = wl("heartwood")
local grove     = wl("grove")
local climate   = wl("climate")
local quantise  = wl("quantise")
local voice     = wl("voice")
local exciter   = wl("exciter")

local screenui = {}

-- §5.2: full 16x8 map at 7px pitch, 112x56, centred on a 128x64 screen.
local PITCH = 7
local OX = (128 - topology.GRID_W * PITCH) / 2
local OY = (64 - topology.GRID_H * PITCH) / 2

local function cell_xy(x, y)
  return OX + (x - 1) * PITCH + PITCH / 2, OY + (y - 1) * PITCH + PITCH / 2
end

-- batching -------------------------------------------------------------------
--
-- everything on the network view is a dot at a brightness, and there are a lot
-- of them: 92 cells, up to a few hundred cable dots, and up to 48 pulse dots.
-- drawn one at a time -- level, shape, fill, level, shape, fill -- that is
-- ~600 screen commands a frame, and about 120 of them are cairo *paint* calls,
-- which is what actually costs. At 15 fps that fills matron's screen queue
-- faster than it drains, and a full queue blocks the Lua thread: the screen
-- stops updating and the front panel stops responding while the grid, on its
-- own callback, carries on -- which is exactly what it looks like from the
-- outside.
--
-- so points are bucketed by brightness and painted once per distinct level:
-- the same picture in ~12 paint calls instead of ~120.
--
-- the bucket tables are reused across frames. rebuilding sixteen of them at
-- 15 fps is pointless garbage on a CM3, and this is the hot path.

local bucket = {}
for i = 0, 15 do bucket[i] = {n = 0} end

local function plot(lvl, x, y)
  lvl = math.floor(lvl)
  if lvl < 1 then return end          -- level 0 paints nothing
  if lvl > 15 then lvl = 15 end
  local b = bucket[lvl]
  local n = b.n
  b[n + 1] = math.floor(x)
  b[n + 2] = math.floor(y)
  b.n = n + 2
end

-- `w`/`h` nil draws single pixels; otherwise a rect of that size centred on
-- the plotted point. empties the buckets as it goes.
local function flush(w, h)
  for lvl = 15, 1, -1 do
    local b = bucket[lvl]
    local n = b.n
    if n > 0 then
      screen.level(lvl)
      if w then
        local ox, oy = w / 2, h / 2
        for i = 1, n, 2 do screen.rect(b[i] - ox, b[i + 1] - oy, w, h) end
      else
        for i = 1, n, 2 do screen.pixel(b[i], b[i + 1]) end
      end
      screen.fill()
      b.n = 0
    end
  end
end

-- network view --------------------------------------------------------------

-- cables are drawn dim and dotted. at full brightness and solid, a patch of
-- twenty cables is a ball of wool: the lines are the least important thing on
-- this screen and they were shouting over the cells, the pulse dots and each
-- other. dotted also gives negative gain somewhere to live that isn't a
-- second line style competing for the same ink -- an inverting cable is drawn
-- with the dots twice as far apart, so you read it as a thinner connection
-- rather than a different kind of drawing.
local CABLE_MAX_LEVEL = 5
local DOT_SPACING = 4.0
local DOT_SPACING_NEG = 7.0
local ONEWAY_LEVEL = 8

-- the total number of cable dots is budgeted rather than left to the patch:
-- 64 cables at one dot every four pixels is over a thousand, and the whole
-- point of drawing them dim is that they are the least important thing here.
-- a big patch gets fewer dots per cable, which also reads better -- a wall of
-- dots is no more legible than a wall of lines was.
local DOT_BUDGET = 320

local function draw_cables()
  local cables = patch.count()
  if cables == 0 then return end
  local per_cable = util.clamp(math.floor(DOT_BUDGET / cables), 3, 14)

  for _, edge in pairs(patch.edges) do
    local ca, cb = topology.get(edge.a), topology.get(edge.b)
    if ca and cb then
      local ax, ay = cell_xy(ca.coords[1][1], ca.coords[1][2])
      local bx, by = cell_xy(cb.coords[1][1], cb.coords[1][2])
      local dx, dy = bx - ax, by - ay
      local dist = math.sqrt(dx * dx + dy * dy)
      local spacing = (edge.gain < 0) and DOT_SPACING_NEG or DOT_SPACING
      -- the dots stay evenly spaced *within* a cable; a long one just spreads
      -- its allowance further apart rather than getting a denser line.
      local n = util.clamp(math.floor(dist / spacing), 2, per_cable)
      local lvl = 1 + math.floor(math.abs(edge.gain) * (CABLE_MAX_LEVEL - 1))
      -- the endpoints themselves are left alone: the cell's own dot is
      -- supposed to be the brightest thing at that coordinate.
      for i = 1, n - 1 do
        local t = i / n
        plot(lvl, ax + dx * t, ay + dy * t)
      end
      if edge.oneway then
        -- one brighter dot three quarters of the way along: enough to read
        -- the direction, not enough to become an arrow made of five pixels.
        plot(ONEWAY_LEVEL, ax + dx * 0.72, ay + dy * 0.72)
      end
    end
  end
  flush()
end

-- the meters view's bar height is a function of its level, so it gets its own
-- flush rather than the shared one.
local function flush_meters()
  for lvl = 15, 1, -1 do
    local b = bucket[lvl]
    local n = b.n
    if n > 0 then
      screen.level(lvl)
      local h = 1 + math.floor((lvl / 15) * 4)
      for i = 1, n, 2 do screen.rect(b[i] - 2, b[i + 1] + 2 - h, 4, h) end
      screen.fill()
      b.n = 0
    end
  end
end

local function draw_cells(meters_mode)
  -- voices are squares and everything else is a dot, so they are two passes;
  -- within each pass every cell at the same brightness is painted together.
  for id, cell in topology.each() do
    if cell.type ~= "voice" then
      for _, c in ipairs(cell.coords) do
        local x, y = cell_xy(c[1], c[2])
        if meters_mode then
          -- real meter data arrives with bridge.lua (§7.4); idle brightness
          -- stands in for now
          plot(patch.degree(id) > 0 and 8 or 3, x, y)
        else
          plot(state.is_held(id) and 15 or 4, x, y)
        end
      end
    end
  end
  if meters_mode then flush_meters() else flush() end

  for id, cell in topology.each() do
    if cell.type == "voice" then
      for _, c in ipairs(cell.coords) do
        local x, y = cell_xy(c[1], c[2])
        plot(meters_mode and 4 or (state.is_held(id) and 15 or 8), x, y)
      end
    end
  end
  flush(4, 4)
end

-- §5.2 "pulses render as a dot travelling the line". rambler.trails is a
-- short capped ring of recent emissions; each is drawn at however far along
-- its cable it has got by now. these stay bright: now that the cables
-- themselves are dim, the travelling dots are what the network view is for.
local function draw_trails()
  local now = util.time()
  local any = false
  for _, tr in ipairs(rambler.trails) do
    local age = now - tr.t
    if age >= 0 and age < rambler.TRAIL_LIFE then
      local ca, cb = topology.get(tr.from), topology.get(tr.to)
      if ca and cb then
        local ax, ay = cell_xy(ca.coords[1][1], ca.coords[1][2])
        local bx, by = cell_xy(cb.coords[1][1], cb.coords[1][2])
        local f = age / rambler.TRAIL_LIFE
        plot(15, ax + (bx - ax) * f, ay + (by - ay) * f)
        any = true
      end
    end
  end
  if any then flush(2, 2) end
end

function screenui.draw_network()
  draw_cables()
  draw_cells(false)
  draw_trails()
  screen.level(15)
  screen.move(2, 62)
  screen.text(string.sub(state.last_event or "", 1, 18))
  -- Weather (E2) is the groove knob and E3 is the transport, so the corner
  -- reads out both: the tempo everything quantises against, and a four-letter
  -- tag for where on the sweep Weather has it (lock / swNN / lsNN / rain).
  screen.level(3)
  screen.move(127, 62)
  screen.text_right(string.format("%.0f %s", state.global.bpm or 120,
                                  quantise.tag()))
end

function screenui.draw_meters()
  draw_cells(true)
  screen.level(4)
  screen.move(2, 62)
  screen.text("meters \xE2\x80\x94 back-channel is phase 7")
end

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

-- §5.5 voice page ---------------------------------------------------------------
-- nine parameters, two columns -- five in the first (Tune and Bend are both
-- pitch, so they sit together), four in the second. E1 walks them, E2 moves
-- the one under the cursor coarsely and E3 finely. reached by tapping the
-- voice cell (which keeps it open and gives it the encoders) or by holding
-- it (which shows the same page for as long as you hold, without taking the
-- encoders off the patch).

local VP_ROWS = 5
local VP_COL_X = {2, 66}
local VP_COL_W = 60

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
  for i, p in ipairs(voice.PARAMS) do
    local col = (i <= VP_ROWS) and 1 or 2
    local row = ((i - 1) % VP_ROWS)
    local x = VP_COL_X[col]
    -- 8px rows starting at 20: the fifth bar ends at 56, which still leaves
    -- the hint line at 63 its own space on a 64px panel.
    local y = 20 + row * 8
    local on = (i == focus)
    screen.level(on and 15 or 6)
    screen.move(x, y)
    screen.text(p.label)
    screen.move(x + VP_COL_W, y)
    screen.text_right(p.text(id))
    bar(x, y + 2, VP_COL_W, 2, p.get(id), on and 12 or 4)
  end

  screen.level(2)
  screen.move(2, 63)
  screen.text(live and "E1 pick  E2/E3 coarse/fine" or "tap the cell to edit")
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
  elseif state.view == "network" then
    screenui.draw_network()
  elseif state.view == "meters" then
    screenui.draw_meters()
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
