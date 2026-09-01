-- gridui.lua
-- grid render + hold/tap patching state machine. (§3, §4.2, §5.1)
--
-- one gesture vocabulary, the same on every cell of every type:
--
--   tap a cell                 toggle its settings page open / closed
--   hold a cell                glance at the same page, until you let go
--   hold, then E1 / E2 / E3    pick a row, move it coarse / fine
--   press a GUST cell          it sounds, on the way down -- a key that waits
--                              for the release is not a key (§2.11). the
--                              release still toggles its page like any other
--   K1 + tap a cell            do the thing that cell does: strike a voice or
--                              a drum, sound a gust, fire an exciter, pulse a
--                              trigger
--   hold one, tap another      cable them (K1 held: one-way)
--   hold two                   E3 sets that cable's gain
--   K2 + K3 while holding      sever every cable at that cell
--
-- what this replaced: only voice/GVOICE/TM cells had a page and a tap that
-- opened it; K1+tap flipped a
-- boolean on D and F cells and did nothing anywhere else; K1+E2 cycled a bank
-- on D/R/F and stored a number nothing read on everything else; E1 walked a
-- cable list only visible one row at a time. every one of those is now a
-- named row on a page that every cell type has (lib/cellparam.lua).

local topology   = wl("topology")
local patch      = wl("patch")
local state      = wl("state")
local rambler    = wl("rambler")
local heartwood  = wl("heartwood")
local grove      = wl("grove")
local clockcell  = wl("clockcell")
local gust       = wl("gust")
local weave      = wl("weave")
local cellparam  = wl("cellparam")

local gridui = {}

-- E2 is coarse and E3 is fine on the same row, on the held glance and on the
-- open page alike -- Canopy.lua uses these same two numbers.
gridui.COARSE = 1 / 80
gridui.FINE = 1 / 500

-- below this held-duration, releasing a cell counts as a "tap". with a first
-- cell still held that toggles the cable; on its own it opens or closes the
-- cell's settings page. at or above it, the press was a deliberate hold --
-- a glance at the page, or a two-cell inspection (§3 row 3) -- and the
-- release does not also toggle. 0.3 s turned out to be short enough that an
-- unhurried tap missed it and appeared to do nothing at all; this is the
-- implementation's call and 0.45 is a more forgiving one.
gridui.TAP_THRESHOLD = 0.45

local sever_fired = false

-- grid key handling -------------------------------------------------------

function gridui.on_grid_key(x, y, z, keystate)
  local id = topology.at(x, y)
  if not id then return end -- unregistered coordinate, inert by design

  if z == 1 then
    table.insert(state.held, id)
    state.held_t[id] = util.time()
    -- §2.11: a gust is a key, and a key sounds when it goes down. this is
    -- the whole of the "press a button, it plays a note" gesture -- nothing
    -- else about the release changes, so the same press still toggles the
    -- cell's page on the way up, and holding it still glances at that page.
    -- it also means auditioning a gust while patching it is free: you hear
    -- the cell you are holding.
    local down = topology.get(id)
    if down and down.type == "GUST" then gust.press(id) end
  else
    local press_t = state.held_t[id]
    local held_dur = press_t and (util.time() - press_t) or math.huge

    local anchor = nil
    for _, hid in ipairs(state.held) do
      if hid ~= id then
        anchor = hid
        break
      end
    end

    for i, hid in ipairs(state.held) do
      if hid == id then
        table.remove(state.held, i)
        break
      end
    end
    state.held_t[id] = nil

    local cell = topology.get(id)

    -- every cell is a cable endpoint and every cell has a page, so this
    -- branch is type-free: with something else held the tap draws a cable,
    -- on its own it works the page.
    if anchor and held_dur < gridui.TAP_THRESHOLD then
      local anchor_cell = topology.get(anchor)
      local oneway = keystate and keystate.k1
      local result = patch.toggle(anchor, id, oneway, 0.6)
      -- "moved" is patch.lua's Output-row exclusivity (§2.1): the source was
      -- already on the row, so this tap slid it to a new pan position rather
      -- than adding a second one. worth its own word -- the cable count did
      -- not change and one of the lit cells just went dark.
      local verb = (result == "added") and "->"
                or (result == "moved") and "=>"
                or (result == "removed") and "x" or nil
      if verb then
        state.set_event(anchor_cell.name .. " " .. verb .. " " .. cell.name, 1.5)
      end
    elseif not anchor and held_dur < gridui.TAP_THRESHOLD then
      gridui.on_tap(id, cell, keystate)
    end
  end

  gridui.check_sever_combo(keystate)
end

-- a tap on one cell with nothing else held ---------------------------------
-- exactly two outcomes, the same for every type on the panel: K1 held fires
-- the cell, K1 up toggles its page.

function gridui.on_tap(id, cell, keystate)
  if keystate and keystate.k1 then
    gridui.act(id, cell)
  else
    gridui.toggle_page(id, cell)
  end
end

function gridui.toggle_page(id, cell)
  if state.cell_edit == id then
    state.cell_edit = nil
    state.set_event(cell.name .. ": closed", 1.2)
  else
    state.cell_edit = id
    state.vparam_focus = 1
    state.set_event(cell.name .. ": settings", 1.2)
  end
end

-- can anything this cell makes actually leave the panel? nothing reaches a
-- speaker unless it is cabled, directly or through the patch, to one of the
-- sixteen Output cells -- so a voice you fire and cannot hear is a normal,
-- correct, and very confusing state to be in. K1+tap says so out loud.
local function reaches_output(id)
  local seen, queue = {[id] = true}, {id}
  local head = 1
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    if topology.get(cur) and topology.get(cur).type == "O" then return true end
    for _, edge in ipairs(patch.edges_at(cur)) do
      local other = patch.other(edge, cur)
      if not seen[other] then
        seen[other] = true
        table.insert(queue, other)
      end
    end
  end
  return false
end

-- the cells whose "fire it once" is a pulse out of their own door rather than
-- something landing on them: a trigger, a transform, a register, a clock.
-- rambler.emit_from is the one door every pulse on this panel leaves by, so
-- this is the same event the scheduler would have produced on its own.
local EMITTERS = {D = true, R = true, TM = true, C = true}

-- K1 + tap: do the thing this cell does. a synthetic full-gain cable stands
-- in for the pulse's source, so a voice, a drum, an exciter, a field and a
-- heartwood node each answer through the same dispatch handler a real cable
-- would have used -- no second, subtly different audition path to keep in
-- step with the first.
function gridui.act(id, cell)
  if cell.type == "O" then
    state.set_event(cell.name .. ": " .. patch.degree(id) .. " in", 1.2)
    return
  end

  if EMITTERS[cell.type] then
    rambler.emit_from(id, 1.0)
    state.flash(id, 1)
    state.set_event(cell.name .. ": pulse", 1.2)
    return
  end

  wl("dispatch").on_pulse(id, id, {id = -1, a = id, b = id, gain = 1.0}, 1.0)
  -- a GUST cell is deliberately not in this check: §2.11 routes it to the
  -- mix by itself, so "no output cable" is its normal state rather than the
  -- confusing one this warning exists for.
  if (cell.type == "voice" or cell.type == "GVOICE") and not reaches_output(id) then
    state.set_event(cell.name .. ": no output cable", 2.0)
  else
    state.set_event(cell.name .. ": fired", 1.2)
  end
end

-- K2+K3 while a cell is held: sever every cable at that cell (§3, §4.2)
function gridui.check_sever_combo(keystate)
  if not keystate then return end
  if keystate.k2 and keystate.k3 and #state.held >= 1 then
    if not sever_fired then
      local id = state.held[#state.held]
      local n = patch.sever_all(id)
      if n > 0 then
        state.set_event("severed " .. topology.get(id).name .. " (" .. n .. ")", 1.5)
      end
      sever_fired = true
    end
  else
    sever_fired = false
  end
end

function gridui.on_norns_key(n, z, keystate)
  gridui.check_sever_combo(keystate)
end

-- encoders while holding a cell (or two) -----------------------------------
-- returns true if it consumed the encoder turn (caller should skip the
-- "nothing held" global encoder behaviour).

-- the one place a settings page is driven, whether it is open (tapped) or
-- borrowed for as long as a cell is held. Canopy.lua calls the same function
-- for the open page, so a row behaves identically either way.
function gridui.page_enc(id, n, d)
  local page = cellparam.page(id)
  if not page then return false end
  if n == 1 then
    state.vparam_focus =
      util.clamp((state.vparam_focus or 1) + d, 1, page.PARAM_COUNT)
    return true
  end
  local i = util.clamp(state.vparam_focus or 1, 1, page.PARAM_COUNT)
  local p = page.nudge(id, i, d * ((n == 2) and gridui.COARSE or gridui.FINE))
  if p then
    state.set_event(p.label .. " " .. p.text(id), 0.5)
  end
  return true
end

function gridui.on_norns_enc(n, d, keystate)
  -- two cells held: the cable between them, which is the only thing that
  -- belongs to the pair rather than to either cell.
  if #state.held == 2 and n == 3 then
    local a, b = state.held[1], state.held[2]
    local edge_id = patch.has(a, b)
    if edge_id then
      local edge = patch.get(edge_id)
      patch.set_gain(edge_id, util.clamp(edge.gain + d / 100, -1, 1))
    end
    return true
  end

  if #state.held == 0 then return false end

  -- one cell held: its page, exactly as if it were open.
  return gridui.page_enc(state.held[#state.held], n, d)
end

-- rendering -----------------------------------------------------------------
-- §5.1 idle brightness. every cell type that knows something about itself
-- lights itself: D and R flash on a pulse over a base that rises with how
-- much is cabled through them, H over how much energy is still circulating, F
-- over where its line currently sits, and C simply *is* its value, so the
-- outer corners read as four pairs of very slow meters. voice envelopes and S
-- shimmer still need the metering back-channel (§7.4) and stay static.

function gridui.brightness(id, cell)
  if cell.type == "voice" then
    -- the one open sound page is worth seeing from across the room. now
    -- also a cable endpoint, so it takes the same degree-of-connection bump
    -- every other endpoint gets once it is patched.
    local base = (state.cell_edit == id) and 12 or (patch.degree(id) > 0 and 6 or 3)
    return state.flash_level(id, base)
  elseif cell.type == "O" then
    return patch.degree(id) > 0 and 5 or 1
  elseif cell.type == "D" then
    return rambler.level(id, 3)
  elseif cell.type == "R" then
    return weave.level(id, 2)
  elseif cell.type == "GVOICE" then
    -- §2.7b: the sound-page indicator a voice cell gets, plus a strike
    -- flash on top -- a GVOICE cell has no separate socket to carry that,
    -- so it carries its own.
    local base = (state.cell_edit == id) and 10 or (patch.degree(id) > 0 and 4 or 2)
    return state.flash_level(id, base)
  elseif cell.type == "TM" then
    -- §2.3b: same idea as a GVOICE cell's indicator.
    local base = (state.cell_edit == id) and 10 or (patch.degree(id) > 0 and 4 or 2)
    return state.flash_level(id, base)
  elseif cell.type == "E" then
    local base = patch.degree(id) > 0 and 5 or 3
    return state.flash_level(id, base)
  elseif cell.type == "H" then
    return heartwood.level(id, 2)
  elseif cell.type == "F" then
    return grove.level(id, 2)
  elseif cell.type == "C" then
    return clockcell.level(id, 2)
  elseif cell.type == "GUST" then
    return gust.level_at(id, 2)
  end
  return 0
end

function gridui.grid_redraw(g)
  local levels = {}
  for id, cell in topology.each() do
    levels[id] = gridui.brightness(id, cell)
  end

  -- §5.1b inspecting one cell: with a settings page open and nothing held,
  -- the panel dims to that cell and what it is cabled to. the page you are
  -- reading is about ONE cell, and ninety cells all doing their own thing
  -- behind it is ninety things competing with the four numbers you came to
  -- look at -- so everything else drops to a floor that says "still there,
  -- not what this is about". the cell itself stays at full, its cables stay
  -- readable, and the moment you let go of the page the panel comes back.
  if #state.held == 0 and state.cell_edit and topology.get(state.cell_edit) then
    local focus = state.cell_edit
    local cabled = {}
    for _, edge in ipairs(patch.edges_at(focus)) do
      cabled[patch.other(edge, focus)] = true
    end
    local INSPECT_FLOOR = 1
    for id, cell in topology.each() do
      if id == focus then
        levels[id] = 15
      elseif cabled[id] then
        -- dimmer than the held-glance reveal and not blinking: this is a
        -- page you can sit on for a minute, so it has to be restful.
        levels[id] = 7
      else
        levels[id] = INSPECT_FLOOR
      end
    end
  end

  if #state.held >= 1 then
    local revealed = {}
    for _, hid in ipairs(state.held) do
      revealed[hid] = true
      for _, edge in ipairs(patch.edges_at(hid)) do
        revealed[patch.other(edge, hid)] = true
      end
    end
    local blink = (math.floor(util.time() * 4) % 2 == 0)
    -- unconnected cells are still valid patch targets, so they get a flat
    -- visibility floor rather than a straight x0.4 (idle brightness is
    -- already low enough that x0.4 floors most of them to 0-1 and hides
    -- every cell you could tap next) -- and flat, not scaled up from
    -- whatever they're doing live, because a D cell's pulse-flash is noise
    -- while you're reading a patch: all you need at that point is what's
    -- connected, not what's currently firing. a voice is a cable endpoint
    -- like everything else now, so it gets the same floor rather than a
    -- special dim-toward-black case.
    local TARGET_FLOOR = 3
    for id, cell in topology.each() do
      if state.is_held(id) then
        levels[id] = 15
      elseif revealed[id] then
        levels[id] = blink and 13 or 6
      else
        levels[id] = TARGET_FLOOR
      end
    end
  end

  g:all(0)
  for id, cell in topology.each() do
    local lvl = levels[id]
    for _, c in ipairs(cell.coords) do
      g:led(c[1], c[2], lvl)
    end
  end
  g:refresh()
end

return gridui
