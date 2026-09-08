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
local sample     = wl("sample")
local clockcell  = wl("clockcell")
local gust       = wl("gust")
local weave      = wl("weave")
local cellparam  = wl("cellparam")
local mixer      = wl("mixer")
local fill       = wl("fill")

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
    --
    -- §2.3b a Fill cell is the other exception, and a plainer one: it is
    -- engaged the instant it goes down, for as long as it stays down, and
    -- nothing about the release toggles a page -- there is no page (see the
    -- z == 0 branch below).
    local down = topology.get(id)
    if down and down.type == "GUST" then
      gust.press(id)
    elseif down and down.type == "FILL" then
      fill.engage(id)
    end
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

    -- §2.3b letting go of a Fill cell disengages it and nothing else -- no
    -- cable (a Fill cell isn't a patchable endpoint at all), no page (it has
    -- none). checked before the generic tap/cable branches below so neither
    -- of them ever sees a Fill cell's release.
    if cell and cell.type == "FILL" then
      fill.release(id)
      gridui.check_sever_combo(keystate)
      return
    end

    -- every cell is a cable endpoint and every cell has a page, so this
    -- branch is type-free: with something else held the tap draws a cable,
    -- on its own it works the page. except a Fill cell held as the anchor --
    -- it released its own engagement the moment IT was let go, above, and it
    -- still isn't a cable endpoint, so a tap landing on something else while
    -- one is held draws no cable either.
    if anchor and held_dur < gridui.TAP_THRESHOLD
       and topology.get(anchor).type ~= "FILL" then
      local anchor_cell = topology.get(anchor)
      local oneway = keystate and keystate.k1
      local result, _, replaced = patch.toggle(anchor, id, oneway, 0.6)
      -- "moved" is patch.lua's Output-row exclusivity (§2.1): the source was
      -- already on the row, so this tap slid it to a new pan position rather
      -- than adding a second one. worth its own word -- the cable count did
      -- not change and one of the lit cells just went dark.
      local verb = (result == "added") and "->"
                or (result == "moved") and "=>"
                or (result == "removed") and "x" or nil
      if verb then
        local msg = anchor_cell.name .. " " .. verb .. " " .. cell.name
        -- the other half of the same rule: an Out cell carries one source,
        -- so this cable may have pushed one off. it is a cell going dark
        -- somewhere else on the panel, which is exactly the kind of thing
        -- the event line exists to name.
        if replaced then
          msg = msg .. " (" .. topology.get(replaced).name .. " off)"
        end
        state.set_event(msg, 1.5)
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
-- something landing on them: a trigger, a transform, a clock.
-- rambler.emit_from is the one door every pulse on this panel leaves by, so
-- this is the same event the scheduler would have produced on its own.
--
-- an R cell running the weave's turing rule (§2.3b, the old TM cells'
-- mechanic) is not a special case here: firing it clocks its register the
-- same way any other pulse landing on it would, and lets the next note fall
-- out -- it needs no entry of its own because R is already in this table.
local EMITTERS = {D = true, R = true, C = true}

-- K1 + tap: do the thing this cell does. a synthetic full-gain cable stands
-- in for the pulse's source, so a voice, a drum, an exciter, a field and a
-- sample cell each answer through the same dispatch handler a real cable
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
  -- GUST and SMP are deliberately not in this check: they are the two
  -- families that route themselves to the mix (§2.11, §2.5), so "no output
  -- cable" is their normal state rather than the confusing one this warning
  -- exists for.
  -- §2.13 the two new synth families need this warning for the same reason a
  -- voice does: they are heard through an Output cable or not at all.
  if (cell.type == "voice" or cell.type == "GVOICE"
      or cell.type == "FM" or cell.type == "VA")
     and not reaches_output(id) then
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

  -- §4.2b a T or R cell's page is one page, two knobs and a list. E1 walks
  -- the list -- the gait, the rule -- and the whole page follows it: both
  -- knobs are re-labelled, re-seeded and re-read, and the scope underneath
  -- redraws as whatever the new entry is. E2 and E3 are then row one and row
  -- two, not coarse and fine on one row, because there is no cursor to be
  -- coarse or fine ABOUT. every other page keeps the cursor it always had.
  if page.CYCLE then
    if n == 1 then
      local key = page.cycle(id, d)
      if key then state.set_event(page.CYCLE .. " " .. key, 0.6) end
      return true
    end
    local p = page.nudge(id, (n == 2) and 1 or 2, d * gridui.COARSE)
    if p then
      state.set_event(cellparam.label_of(p, id) .. " " .. p.text(id), 0.5)
    end
    return true
  end

  if n == 1 then
    state.vparam_focus =
      util.clamp((state.vparam_focus or 1) + d, 1, page.PARAM_COUNT)
    return true
  end
  local i = util.clamp(state.vparam_focus or 1, 1, page.PARAM_COUNT)
  local p = page.nudge(id, i, d * ((n == 2) and gridui.COARSE or gridui.FINE))
  if p then
    state.set_event(cellparam.label_of(p, id) .. " " .. p.text(id), 0.5)
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
    -- §7.4: the Output row is the one place on the panel where "is anything
    -- happening here" is a question about audio rather than about events, so
    -- it is the one row lit by a meter rather than by a flash. an empty seat
    -- sits at 1 and a cabled one at 4, which is the floor -- the channel is
    -- open whether or not it happens to be sounding this instant -- and the
    -- meter takes it from there up to full. reading the same post-fader
    -- level the mixer page draws, so a channel pulled down goes dim on the
    -- grid too.
    if patch.degree(id) == 0 then return 1 end
    return util.clamp(4 + math.floor(mixer.meter(id) * 11 + 0.5), 4, 15)
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
  elseif cell.type == "FILL" then
    -- §2.3b a plain button: full while held, dim otherwise -- no cable to
    -- brighten toward and no page to sit on, so neither of a GVOICE cell's
    -- two other levels means anything here.
    return fill.is_engaged(id) and 15 or 3
  elseif cell.type == "E" then
    local base = patch.degree(id) > 0 and 5 or 3
    return state.flash_level(id, base)
  elseif cell.type == "SMP" then
    return sample.level_at(id, 2)
  elseif cell.type == "C" then
    return clockcell.level(id, 2)
  elseif cell.type == "GUST" then
    return gust.level_at(id, 2)
  elseif cell.type == "LFO" then
    return wl("lfo").level_at(id, 2)
  elseif cell.type == "FM" or cell.type == "VA" then
    -- §2.13 the same indicator a drum and a gust get: open page brightest,
    -- cabled next, idle dim, with the strike flash on top.
    return wl("synth").level_at(id, 2)
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
