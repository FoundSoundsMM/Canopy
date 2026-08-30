-- screenui.lua
-- network / meters / cell / edge / lexicon views. (§5.2-5.4)

local topology = wl("topology")
local patch    = wl("patch")
local lexicon  = wl("lexicon")
local state    = wl("state")
local rambler  = wl("rambler")

local screenui = {}

-- §5.2: full 16x8 map at 7px pitch, 112x56, centred on a 128x64 screen.
local PITCH = 7
local OX = (128 - topology.GRID_W * PITCH) / 2
local OY = (64 - topology.GRID_H * PITCH) / 2

local function cell_xy(x, y)
  return OX + (x - 1) * PITCH + PITCH / 2, OY + (y - 1) * PITCH + PITCH / 2
end

local LEXICON_ROWS = 6

-- network view --------------------------------------------------------------

local function draw_cables()
  for _, edge in pairs(patch.edges) do
    local ca, cb = topology.get(edge.a), topology.get(edge.b)
    if ca and cb then
      local ax, ay = cell_xy(ca.coords[1][1], ca.coords[1][2])
      local bx, by = cell_xy(cb.coords[1][1], cb.coords[1][2])
      local lvl = math.max(1, math.floor(math.abs(edge.gain) * 15))
      screen.level(lvl)
      screen.line_width(1)
      if edge.gain < 0 then
        -- dashed
        local steps = 10
        for s = 0, steps - 1, 2 do
          local t0, t1 = s / steps, (s + 1) / steps
          screen.move(ax + (bx - ax) * t0, ay + (by - ay) * t0)
          screen.line(ax + (bx - ax) * t1, ay + (by - ay) * t1)
          screen.stroke()
        end
      else
        screen.move(ax, ay)
        screen.line(bx, by)
        screen.stroke()
      end
      if edge.oneway then
        local dx, dy = bx - ax, by - ay
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0 then
          local ux, uy = dx / d, dy / d
          local hx, hy = bx - ux * 3, by - uy * 3
          local px, py = -uy, ux
          screen.move(bx, by)
          screen.line(hx + px * 1.5, hy + py * 1.5)
          screen.move(bx, by)
          screen.line(hx - px * 1.5, hy - py * 1.5)
          screen.stroke()
        end
      end
    end
  end
end

local function draw_cells(meters_mode)
  for id, cell in topology.each() do
    for _, c in ipairs(cell.coords) do
      local x, y = cell_xy(c[1], c[2])
      local lvl
      if meters_mode then
        -- real meter data arrives with bridge.lua (§7.4); idle brightness stands in for now
        local degree = patch.degree(id)
        lvl = cell.type == "voice" and 4 or (degree > 0 and 8 or 3)
      else
        lvl = state.is_held(id) and 15 or (cell.type == "voice" and 6 or 3)
      end
      screen.level(lvl)
      if cell.type == "voice" then
        screen.rect(x - 2, y - 2, 4, 4)
        screen.fill()
      elseif meters_mode then
        local h = 1 + math.floor((lvl / 15) * 4)
        screen.rect(x - 2, y + 2 - h, 4, h)
        screen.fill()
      else
        screen.pixel(x, y)
        screen.fill()
      end
    end
  end
end

-- §5.2 "pulses render as a dot travelling the line". rambler.trails is a
-- short capped ring of recent emissions; each is drawn at however far along
-- its cable it has got by now.
local function draw_trails()
  local now = util.time()
  for _, tr in ipairs(rambler.trails) do
    local age = now - tr.t
    if age >= 0 and age < rambler.TRAIL_LIFE then
      local ca, cb = topology.get(tr.from), topology.get(tr.to)
      if ca and cb then
        local ax, ay = cell_xy(ca.coords[1][1], ca.coords[1][2])
        local bx, by = cell_xy(cb.coords[1][1], cb.coords[1][2])
        local f = age / rambler.TRAIL_LIFE
        screen.level(15)
        screen.rect(ax + (bx - ax) * f - 1, ay + (by - ay) * f - 1, 2, 2)
        screen.fill()
      end
    end
  end
end

function screenui.draw_network()
  draw_cells(false)
  draw_cables()
  draw_trails()
  screen.level(15)
  screen.move(2, 62)
  screen.text(string.sub(state.last_event or "", 1, 24))
  -- Weather (E2) now audibly sets the coupling constant, so it needs a readout
  screen.level(3)
  screen.move(127, 62)
  screen.text_right(string.format("W%.2f", state.global.weather or 0))
end

function screenui.draw_meters()
  draw_cells(true)
  screen.level(4)
  screen.move(2, 62)
  screen.text("meters \xE2\x80\x94 back-channel is phase 7")
end

-- cell view (one cell held) --------------------------------------------------

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

function screenui.draw_cell(id)
  local cell = topology.get(id)
  screen.level(15)
  screen.move(2, 8)
  screen.text(cell.name)
  screen.move(126, 8)
  screen.text_right(cell.type == "voice" and ("voice " .. cell.index) or cell.type)

  screen.level(4)
  screen.move(2, 12)
  screen.line(126, 12)
  screen.stroke()

  -- for a D cell the E2 knob means whatever its current gait says it means,
  -- so the gait names the row and supplies its own units (§4.2).
  local info = (cell.type == "D") and rambler.info(id) or nil

  local ch = lexicon.character(id)
  local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
  local v = state.get_character(id, cell, lo, hi)
  local frac = (v - lo) / (hi - lo)
  screen.level(12)
  screen.move(2, 22)
  screen.text(info and info.gait or (ch and ch.label or "character"))
  screen.move(126, 22)
  screen.text_right(info and info.param or string.format("%.2f", v))
  bar(2, 25, 124, 3, frac)

  if info then
    local mode
    if not info.phased then
      mode = "reactive"
    elseif info.rooted_ok and info.rooted then
      mode = "rooted \xC2\xB7 clock"
    else
      mode = "wild \xC2\xB7 free"
    end
    screen.level(12)
    screen.move(2, 36)
    screen.text(mode)
    screen.move(126, 36)
    screen.text_right(string.format("coupling %.2f", info.energy))
    if info.phased then bar(2, 39, 124, 3, info.phase or 0, 6) end
  else
    local trim = state.get_trim(id)
    screen.level(12)
    screen.move(2, 36)
    screen.text("trim")
    screen.move(126, 36)
    screen.text_right(string.format("%+.2f", trim))
    bar(2, 39, 124, 3, (trim + 1) / 2)
  end

  screen.level(4)
  screen.move(2, 44)
  screen.line(126, 44)
  screen.stroke()

  local edges = patch.edges_at(id)
  local focus = state.get_focus(id)
  screen.level(12)
  screen.move(2, 50)
  screen.text(#edges .. " cable" .. (#edges == 1 and "" or "s"))

  for i, edge in ipairs(edges) do
    if i > 3 then break end
    local other = topology.get(patch.other(edge, id))
    local y = 50 + i * 7
    screen.level(i == focus and 15 or 6)
    screen.move(6, y)
    screen.text((i == focus and "> " or "  ") .. (other and other.name or "?"))
    screen.move(126, y)
    screen.text_right(string.format("%+.2f", edge.gain))
  end

  screen.level(2)
  screen.move(2, 63)
  screen.text(info and "K2+K3 sever   K1+E2 gait" or "K2+K3 sever")
end

-- edge view (two cells held) -------------------------------------------------

local INTERACTION_DESC = {
  ["node|node"] = "audio/CV cross-feed both ways, per role",
  ["D|node"] = "pulse strikes/chokes the node; node's out resets the D phase",
  ["S|node"] = "stream drives the node; node's follower modulates S colour",
  ["H|node"] = "node injects into the lattice; lattice returns to it",
  ["D|D"] = "mutual phase coupling (Kuramoto) + mutual triggering",
  ["D|S"] = "D pulse envelopes S into a grain; S stream modulates D's rate",
  ["D|H"] = "pulse enters the lattice and diffuses",
  ["S|S"] = "cross-modulation: each modulates the other's colour and level",
  ["H|S"] = "stream diffuses through the lattice",
  ["H|H"] = "direct link — short-circuits two lattice points",
}

local function interaction_text(ta, tb)
  local order = {node = 1, D = 2, S = 3, H = 4}
  local a, b = ta, tb
  if (order[a] or 9) > (order[b] or 9) then a, b = b, a end
  return INTERACTION_DESC[a .. "|" .. b] or "no direct interaction defined"
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
    screen.text("not yet cabled — tap-release one to connect")
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

-- lexicon view ----------------------------------------------------------------

function screenui.draw_lexicon()
  local listing = lexicon.listing()
  local total_pages = math.max(1, math.ceil(#listing / LEXICON_ROWS))
  state.lexicon_page = util.clamp(state.lexicon_page or 1, 1, total_pages)
  local start = (state.lexicon_page - 1) * LEXICON_ROWS + 1

  screen.level(15)
  screen.move(2, 8)
  screen.text(string.format("lexicon  %d/%d", state.lexicon_page, total_pages))

  for i = 0, LEXICON_ROWS - 1 do
    local entry = listing[start + i]
    if entry then
      local y = 18 + i * 8
      screen.level(12)
      screen.move(2, y)
      screen.text(entry.name)
      screen.level(4)
      screen.move(126, y)
      local xy = entry.coords[1]
      screen.text_right(string.format("(%d,%d)", xy[1], xy[2]))
    end
  end
end

-- advances the lexicon page; returns true if it also needs to roll over
-- into the next top-level view (used by K3 in woodland.lua)
function screenui.lexicon_advance()
  local total_pages = math.max(1, math.ceil(#lexicon.listing() / LEXICON_ROWS))
  local page = state.lexicon_page or 1
  if page < total_pages then
    state.lexicon_page = page + 1
    return false
  end
  state.lexicon_page = 1
  return true
end

-- top-level dispatch ----------------------------------------------------------

function screenui.redraw()
  screen.clear()

  if #state.held == 2 then
    screenui.draw_edge(state.held[1], state.held[2])
  elseif #state.held == 1 then
    screenui.draw_cell(state.held[1])
  elseif state.view == "network" then
    screenui.draw_network()
  elseif state.view == "meters" then
    screenui.draw_meters()
  elseif state.view == "lexicon" then
    screenui.draw_lexicon()
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
