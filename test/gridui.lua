-- lib/gridui.lua + lib/topology.lua: the panel layout, and the one gesture
-- vocabulary that now runs on every cell of it.
--
-- covers: (1) the panel matches the sketch it was drawn from -- in particular
-- that all four modal voices sit together on row 2 and that both gust rows,
-- and the LFO row above them, are centred; (2) a tap toggles any cell's
-- settings page, whatever its type; (3) K1+tap fires the cell -- a voice or
-- drum strikes, a gust sounds, an exciter grains, a trigger pulses; (4) the
-- hold/tap cable gesture still
-- works and is not confused by either of those; (5) a gust sounds on the way
-- DOWN, before the release the page toggle rides on; (6) the Output row is
-- exclusive -- a source is in one slot, and cabling it to a second one moves
-- it; (7) an open cell page dims the rest of the panel down to it.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local NONE = {k1 = false, k2 = false, k3 = false}
local K1 = {k1 = true, k2 = false, k3 = false}

-- press and release one cell, fast enough to count as a tap.
local function tap(gridui, x, y, keystate)
  gridui.on_grid_key(x, y, 1, keystate or NONE)
  T = T + 0.05
  gridui.on_grid_key(x, y, 0, keystate or NONE)
end

local function xy(M, id)
  return M.topology.get(id).coords[1][1], M.topology.get(id).coords[1][2]
end

-- 1: the panel ---------------------------------------------------------------

print("\n-- the panel matches the sketch --")
do
  local M = fresh(1)
  local SKETCH = {
    "OOOOOOOOOOOOOOOO",
    ".M.M.FFFNNN.M.M.",
    "................",
    "F..ttCTTTTCtt..S",
    ".F...CTTTTC...S.",
    "E.F...LLLL...S.R",
    "EE.F.GGGGGG.S.RR",
    "EEE..GGGGGG..RRR",
  }
  -- the letter each type prints on the map above. lower case only to keep the
  -- two-character family (TM) to one column each.
  local LETTER = {O = "O", voice = "M", GVOICE = nil, D = "T", TM = "t",
                  C = "C", SMP = "S", E = "E", R = "R", F = "F", GUST = "G",
                  LFO = "L"}
  local rows_ok = true
  local first_bad = nil
  for y = 1, 8 do
    for x = 1, 16 do
      local id = M.topology.at(x, y)
      local cell = id and M.topology.get(id)
      local got = "."
      if cell then
        if cell.type == "GVOICE" then
          got = cell.letter          -- F for the pings, N for the noises
        else
          got = LETTER[cell.type] or "?"
        end
      end
      local want = SKETCH[y]:sub(x, x)
      if got ~= want then
        rows_ok = false
        first_bad = first_bad or string.format("(%d,%d) want %s got %s", x, y, want, got)
      end
    end
  end
  check("every one of the 128 keys is what the sketch says", rows_ok,
        tostring(first_bad))

  -- the two complaints the sketch was drawn to settle, asserted directly.
  local vrows = {}
  for id, cell in M.topology.each() do
    if cell.type == "voice" then
      table.insert(vrows, cell.coords[1][2])
    end
  end
  check("there are four modal voices", #vrows == 4, tostring(#vrows))
  local all_row2 = true
  for _, y in ipairs(vrows) do if y ~= 2 then all_row2 = false end end
  check("and all four are on row 2, where you can see them at once", all_row2)

  -- §2.11 the gust rows sit exactly on top of each other, both six wide and
  -- centred -- which is what makes the pan spread read as a stereo image
  -- rather than as an accident of layout.
  local top, bottom = {}, {}
  for id, cell in M.topology.each() do
    if cell.type == "GUST" then
      table.insert(cell.coords[1][2] == 7 and top or bottom, cell.coords[1][1])
    end
  end
  table.sort(top)
  table.sort(bottom)
  check("the top gust row is six wide, centred",
        #top == 6 and top[1] == 6 and top[6] == 11, table.concat(top, ","))
  check("the bottom row is six wide, centred",
        #bottom == 6 and bottom[1] == 6 and bottom[6] == 11,
        table.concat(bottom, ","))
  check("with equal margins either side", (bottom[1] - 1) == (16 - bottom[6]),
        (bottom[1] - 1) .. " vs " .. (16 - bottom[6]))

  -- §2.12 the four LFOs sit on the row right above the gusts, centred inside
  -- their six-column span.
  local lrow = {}
  for id, cell in M.topology.each() do
    if cell.type == "LFO" then table.insert(lrow, cell.coords[1][1]) end
  end
  table.sort(lrow)
  check("the LFO row is four wide, above the gusts",
        #lrow == 4 and lrow[1] == 7 and lrow[4] == 10, table.concat(lrow, ","))
  local ly
  for id, cell in M.topology.each() do
    if cell.type == "LFO" then ly = cell.coords[1][2] end
  end
  check("and sits one row above the top gust row", ly == 6, tostring(ly))
end

-- 2: a tap toggles the page, on every type -----------------------------------

print("\n-- a tap opens any cell's settings page --")
do
  local M = fresh(2)
  local gridui = wl("gridui")
  local seen, missed = {}, {}
  local n = 0
  for id, cell in M.topology.each() do
    if not seen[cell.type] then
      seen[cell.type] = true
      n = n + 1
      local x, y = xy(M, id)
      tap(gridui, x, y)
      if M.state.cell_edit ~= id then
        table.insert(missed, cell.type .. " (open)")
      end
      tap(gridui, x, y)
      if M.state.cell_edit ~= nil then
        table.insert(missed, cell.type .. " (close)")
      end
    end
  end
  check("every type opens and closes on a tap", #missed == 0,
        table.concat(missed, ","))
  check("and that was every type on the panel", n >= 10, tostring(n))
end

print("\n-- a slow tap still counts as a tap --")
do
  local M = fresh(3)
  local gridui = wl("gridui")
  local x, y = xy(M, "r.tangle")
  gridui.on_grid_key(x, y, 1, NONE)
  T = T + 0.35                     -- unhurried, but not a hold
  gridui.on_grid_key(x, y, 0, NONE)
  check("0.35 s is under the tap threshold", M.state.cell_edit == "r.tangle",
        tostring(M.state.cell_edit))
end

-- 3: K1 + tap fires the cell -------------------------------------------------

print("\n-- K1 + tap fires the cell --")
do
  local M = fresh(4)
  local gridui = wl("gridui")

  -- a voice strikes, and says so when nothing can hear it
  local x, y = xy(M, "oak")
  tap(gridui, x, y, K1)
  check("K1+tap strikes a voice", #CALLS.strike == 1, "#" .. #CALLS.strike)
  check("and warns that nothing is cabled to an output",
        M.state.last_event:find("no output") ~= nil, M.state.last_event)
  check("and did NOT open the page", M.state.cell_edit == nil,
        tostring(M.state.cell_edit))

  -- cabled to an Output cell, the warning goes away. (the event line holds a
  -- message for its full duration before anything may replace it, so step
  -- past the 2 s the warning claimed.)
  M.patch.add("oak", "o.8", 0.8)
  T = T + 3
  tap(gridui, x, y, K1)
  check("cabled through to an Output, it just fires",
        M.state.last_event:find("no output") == nil, M.state.last_event)

  -- and through a chain, not only directly
  local M2 = fresh(5)
  M2.patch.add("oak", "e.bracken", 0.6)
  M2.patch.add("e.bracken", "o.3", 0.6)
  local x2, y2 = xy(M2, "oak")
  tap(wl("gridui"), x2, y2, K1)
  check("an indirect path to an Output counts too",
        M2.state.last_event:find("no output") == nil, M2.state.last_event)
end

do
  local M = fresh(6)
  local gridui = wl("gridui")
  local x, y = xy(M, "gv.knap")
  tap(gridui, x, y, K1)
  check("K1+tap strikes a percussion cell", #CALLS.g_strike == 1,
        "#" .. #CALLS.g_strike)

  x, y = xy(M, "e.bracken")
  tap(gridui, x, y, K1)
  check("K1+tap fires an exciter grain", #CALLS.exciter_gate == 1,
        "#" .. #CALLS.exciter_gate)
end

do
  -- a trigger/transform/register/clock has no sound of its own; firing one
  -- means one pulse out of its own door, which anything cabled to it hears.
  local M = fresh(7)
  local gridui = wl("gridui")
  M.patch.add("d.hob", "oak", 0.9)
  local x, y = xy(M, "d.hob")
  tap(gridui, x, y, K1)
  check("K1+tap pulses a trigger cell, and the pulse lands",
        #CALLS.strike == 1, "#" .. #CALLS.strike)
end

print("\n-- §2.11 a gust sounds on the way DOWN --")
do
  -- this is the one gesture on the panel that does not wait for the release,
  -- and it has to be: a key that sounds when you let go is not a key. the
  -- release still toggles the page like every other cell, so nothing in the
  -- vocabulary is lost -- both things happen on the one press.
  local M = fresh(8)
  local gridui = wl("gridui")
  local x, y = xy(M, "gu.whorl")

  gridui.on_grid_key(x, y, 1, NONE)
  check("the note is already out before the release", #CALLS.gust_note == 1,
        "#" .. #CALLS.gust_note)
  check("and nothing has opened yet", M.state.cell_edit == nil)

  T = T + 0.05
  gridui.on_grid_key(x, y, 0, NONE)
  check("the release still opens its page", M.state.cell_edit == "gu.whorl",
        tostring(M.state.cell_edit))
  check("and did not sound it a second time", #CALLS.gust_note == 1,
        "#" .. #CALLS.gust_note)

  -- and it is that cell's own note, not a fixed one.
  local hz = CALLS.gust_note[1].hz
  check("at the cell's own pitch",
        math.abs(hz - M.topology.get("gu.whorl").root) < 0.01, tostring(hz))
end

print("\n-- K1 + tap sounds a gust too, through the same path a cable uses --")
do
  local M = fresh(9)
  local gridui = wl("gridui")
  local x, y = xy(M, "gu.flurry")
  -- the press itself sounds it, then dispatch sounds it again through the
  -- synthetic cable -- except the refractory is in the way, which is exactly
  -- what it is there for. step past it so the K1 half is what is measured.
  gridui.on_grid_key(x, y, 1, K1)
  local after_press = #CALLS.gust_note
  T = T + 0.05
  gridui.on_grid_key(x, y, 0, K1)
  check("K1+tap sounds it a second time", #CALLS.gust_note > after_press,
        "#" .. #CALLS.gust_note)
  check("and did not open the page", M.state.cell_edit == nil,
        tostring(M.state.cell_edit))
  -- a gust routes itself to the mix, so "no output cable" is its normal
  -- state and must NOT be reported as a problem the way a voice's is.
  check("and never warns about a missing Output cable",
        M.state.last_event:find("no output") == nil, M.state.last_event)
end

-- 4: the cable gesture is unharmed -------------------------------------------

print("\n-- hold one, tap another: still a cable --")
do
  local M = fresh(10)
  local gridui = wl("gridui")
  local hx, hy = xy(M, "d.hob")
  local tx, ty = xy(M, "oak")

  gridui.on_grid_key(hx, hy, 1, NONE)     -- hold Hob
  T = T + 0.6
  tap(gridui, tx, ty)                     -- tap Oak
  check("cabled", M.patch.has("d.hob", "oak") ~= nil)
  check("and tapping the target did not open its page",
        M.state.cell_edit == nil, tostring(M.state.cell_edit))

  tap(gridui, tx, ty)                     -- tap it again
  check("tapping it again unpatches", M.patch.has("d.hob", "oak") == nil)

  T = T + 0.6
  gridui.on_grid_key(hx, hy, 0, NONE)     -- release the anchor
  check("releasing a held anchor opens nothing", M.state.cell_edit == nil,
        tostring(M.state.cell_edit))

  -- K1 while patching is still the one-way cable, not "fire the cell"
  gridui.on_grid_key(hx, hy, 1, K1)
  T = T + 0.6
  tap(gridui, tx, ty, K1)
  local edge_id = M.patch.has("d.hob", "oak")
  check("K1 with an anchor held makes a one-way cable",
        edge_id and M.patch.get(edge_id).oneway == true)
  T = T + 0.6
  gridui.on_grid_key(hx, hy, 0, K1)
end

-- 6: the Output row is exclusive ---------------------------------------------

print("\n-- one source, one Output slot --")
do
  local M = fresh(12)
  local gridui = wl("gridui")

  local function cable(from, to)
    local ax, ay = xy(M, from)
    local bx, by = xy(M, to)
    gridui.on_grid_key(ax, ay, 1, NONE)
    T = T + 0.6
    tap(gridui, bx, by)
    T = T + 0.6
    gridui.on_grid_key(ax, ay, 0, NONE)
  end

  cable("oak", "o.3")
  check("a voice reaches the row", M.patch.has("oak", "o.3") ~= nil)
  M.patch.set_gain(M.patch.has("oak", "o.3"), 0.42)

  cable("oak", "o.12")
  check("cabling a second slot moves it there",
        M.patch.has("oak", "o.12") ~= nil)
  check("and vacates the first", M.patch.has("oak", "o.3") == nil)
  check("leaving exactly one Output cable", M.patch.degree("oak") == 1,
        tostring(M.patch.degree("oak")))
  check("at the gain it already had -- a move, not a fresh cable",
        math.abs(M.patch.get(M.patch.has("oak", "o.12")).gain - 0.42) < 1e-9,
        tostring(M.patch.get(M.patch.has("oak", "o.12")).gain))

  -- tapping the slot it is already in is still an unpatch, not a no-op
  cable("oak", "o.12")
  check("tapping its own slot still pulls the cable",
        M.patch.has("oak", "o.12") == nil)

  -- everything else is unaffected: a source may still fan out anywhere else
  M.patch.add("oak", "o.5", 0.6)
  M.patch.add("oak", "e.bracken", 0.6)
  M.patch.add("oak", "e.gorse", 0.6)
  check("a source can still reach as many non-Output cells as it likes",
        M.patch.degree("oak") == 3, tostring(M.patch.degree("oak")))
  M.patch.add("oak", "o.9", 0.6)
  check("and adding another Output cell still leaves just the one",
        M.patch.has("oak", "o.5") == nil and M.patch.has("oak", "o.9") ~= nil)
  check("with the rest of its patch untouched", M.patch.degree("oak") == 3,
        tostring(M.patch.degree("oak")))

  -- two Out cells together have no source to move, so nothing is displaced
  M.patch.add("o.1", "o.2", 0.6)
  check("an Out-to-Out cable displaces nothing",
        M.patch.has("o.1", "o.2") ~= nil and M.patch.has("oak", "o.9") ~= nil)
end

-- 7: an open page dims the panel to its own cell -----------------------------

print("\n-- inspecting a cell dims everything else --")
do
  local M = fresh(13)
  local gridui = wl("gridui")

  M.patch.add("oak", "o.4", 0.8)
  M.patch.add("d.hob", "oak", 0.8)

  local levels = {}
  local g = {led = function(_, x, y, l)
               local id = M.topology.at(x, y)
               if id then levels[id] = l end
             end,
             all = function() end, refresh = function() end}

  gridui.grid_redraw(g)
  local idle_far = levels["r.drove"]

  local ox, oy = xy(M, "oak")
  tap(gridui, ox, oy)
  check("the tap opened the page", M.state.cell_edit == "oak")

  gridui.grid_redraw(g)
  check("the inspected cell is at full", levels["oak"] == 15,
        tostring(levels["oak"]))
  check("what it is cabled to stays readable",
        levels["o.4"] > 3 and levels["d.hob"] > 3,
        levels["o.4"] .. "/" .. levels["d.hob"])
  check("everything else is dimmed right down", levels["r.drove"] <= 1,
        tostring(levels["r.drove"]))
  check("which is dimmer than it was with no page open",
        levels["r.drove"] < idle_far or idle_far <= 1,
        idle_far .. " -> " .. levels["r.drove"])

  -- a live D cell's pulse flash must not punch back through the dimming
  M.state.flash("d.shuck", 1)
  gridui.grid_redraw(g)
  check("and a pulse elsewhere does not light back up through it",
        levels["d.shuck"] <= 1, tostring(levels["d.shuck"]))

  tap(gridui, ox, oy)
  gridui.grid_redraw(g)
  check("closing the page brings the panel back",
        M.state.cell_edit == nil and levels["r.drove"] == idle_far,
        tostring(levels["r.drove"]))

  -- holding still wins: the hold reveal is the more urgent of the two
  M.state.cell_edit = "oak"
  M.state.held = {"d.hob"}
  gridui.grid_redraw(g)
  check("a hold overrides the inspect dimming", levels["d.hob"] == 15,
        tostring(levels["d.hob"]))
  M.state.held = {}
end

-- 5: the gust rows are legible ------------------------------------------------

print("\n-- the gust rows read at a glance --")
do
  local M = fresh(11)
  local gust = wl("gust")
  local gridui = wl("gridui")

  local idle = gust.level_at("gu.squall", 2)
  M.patch.add("d.hob", "gu.squall", 1.0)
  local cabled = gust.level_at("gu.squall", 2)
  check("a cabled gust is brighter than an idle one", cabled > idle,
        idle .. " -> " .. cabled)

  M.state.cell_edit = "gu.squall"
  local open = gust.level_at("gu.squall", 2)
  check("and an open page is brighter still", open > cabled,
        cabled .. " -> " .. open)
  M.state.cell_edit = nil

  -- pressing one flashes it, over whatever it was already doing.
  gust.press("gu.squall")
  local flashed = gust.level_at("gu.squall", 2)
  check("a press lights it up", flashed > cabled, cabled .. " -> " .. flashed)
  check("bright enough to see across a room", flashed >= 12, tostring(flashed))

  -- every level the family can produce is a legal grid level, flash and all
  local legal = true
  for _, id in ipairs(gust.each()) do
    for _, t in ipairs({0, 0.05, 0.2}) do
      T = T + t
      local lvl = gust.level_at(id, 2)
      if lvl < 0 or lvl > 15 or lvl ~= math.floor(lvl) then legal = false end
    end
  end
  check("and every level it produces is a legal one", legal)

  -- and the whole panel still renders with the new family on it
  local levels = {}
  local g = {all = function() end, refresh = function() end,
             led = function(_, x, y, l) levels[x .. "," .. y] = l end}
  gridui.grid_redraw(g)
  local all_legal = true
  for _, l in pairs(levels) do
    if l < 0 or l > 15 or l ~= math.floor(l) then all_legal = false end
  end
  check("the panel renders legal levels everywhere", all_legal)
end

report()
