-- lib/gridui.lua + lib/topology.lua: the panel layout, and the one gesture
-- vocabulary that now runs on every cell of it.
--
-- covers: (1) the panel matches the sketch it was drawn from -- in particular
-- that all four modal voices sit together on row 2 and that both sequencer
-- lanes are centred; (2) a tap toggles any cell's settings page, whatever its
-- type; (3) K1+tap fires the cell -- a voice or drum strikes, an exciter
-- grains, a trigger pulses, a sequencer step goes in or out; (4) the hold/tap
-- cable gesture still works and is not confused by either of those; (5) the
-- sequencer lanes are visibly different in their three states; (6) the Output
-- row is exclusive -- a source is in one slot, and cabling it to a second one
-- moves it; (7) an open cell page dims the rest of the panel down to it.
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
    "F..ttCTTTTCtt..H",
    ".F...CTTTTC...H.",
    "E.F..........H.R",
    "EE.F..qqqq..H.RR",
    "EEE..pppppp..RRR",
  }
  -- the letter each type prints on the map above. lower case only to keep the
  -- two-character families (TM, Q4, Q6) to one column each.
  local LETTER = {O = "O", voice = "M", GVOICE = nil, D = "T", TM = "t",
                  C = "C", H = "H", E = "E", R = "R", F = "F"}
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
        elseif cell.type == "SEQ" then
          got = (cell.len == 4) and "q" or "p"
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

  local q4x = {}
  for id, cell in M.topology.each() do
    if cell.type == "SEQ" and cell.len == 4 then
      table.insert(q4x, cell.coords[1][1])
    end
  end
  table.sort(q4x)
  check("the 4-step lane is centred on the panel",
        q4x[1] == 7 and q4x[4] == 10,
        table.concat(q4x, ","))
  -- centred means the same margin either side, which is the thing that was
  -- one column out.
  check("with equal margins", (q4x[1] - 1) == (16 - q4x[4]),
        (q4x[1] - 1) .. " vs " .. (16 - q4x[4]))
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
  local x, y = xy(M, "q4.2")
  gridui.on_grid_key(x, y, 1, NONE)
  T = T + 0.35                     -- unhurried, but not a hold
  gridui.on_grid_key(x, y, 0, NONE)
  check("0.35 s is under the tap threshold", M.state.cell_edit == "q4.2",
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

print("\n-- K1 + tap puts a sequencer step in and takes it out --")
do
  local M = fresh(8)
  local gridui = wl("gridui")
  local sequencer = wl("sequencer")
  local x, y = xy(M, "q6.3")
  check("a step starts armed", sequencer.is_active("q6.3"))
  tap(gridui, x, y, K1)
  check("K1+tap takes it out", not sequencer.is_active("q6.3"))
  tap(gridui, x, y, K1)
  check("and puts it back", sequencer.is_active("q6.3"))
  check("without opening anything", M.state.cell_edit == nil,
        tostring(M.state.cell_edit))
  check("and without touching its neighbour", sequencer.is_active("q6.4"))
end

print("\n-- and the Step row on the page does the same thing --")
do
  local M = fresh(9)
  local gridui = wl("gridui")
  local sequencer = wl("sequencer")
  local x, y = xy(M, "q4.1")
  tap(gridui, x, y)                       -- open the page
  M.state.vparam_focus = 1                -- Step is row one, deliberately
  for _ = 1, 3 do gridui.page_enc("q4.1", 2, -1) end
  check("turning the Step row down takes the step out",
        not sequencer.is_active("q4.1"))
  for _ = 1, 3 do gridui.page_enc("q4.1", 2, 1) end
  check("and turning it up puts it back", sequencer.is_active("q4.1"))
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
  M.patch.add("oak", "h.taproot", 0.6)
  M.patch.add("oak", "e.bracken", 0.6)
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

-- 5: the lanes are legible ---------------------------------------------------

print("\n-- the sequencer lanes read at a glance --")
do
  local M = fresh(11)
  local sequencer = wl("sequencer")
  local gridui = wl("gridui")

  M.state.step_active["q6.1"] = false
  local off = sequencer.level("q6.1", 2)
  M.state.step_active["q6.1"] = true
  local on = sequencer.level("q6.1", 2)
  check("an armed step is clearly brighter than an empty one", on - off >= 4,
        off .. " -> " .. on)

  -- drive the lane one step and check the playhead outruns both
  M.patch.add("d.hob", "q6.6", 1.0)       -- q6.6 is the lane's driver
  sequencer.pulse_in("q6.6", 1.0, "d.hob", T)
  check("the playhead moved", sequencer.playhead("q6") == 1,
        tostring(sequencer.playhead("q6")))
  local head = sequencer.level("q6.1", 2)
  check("and the cell it is on is brighter still", head > on,
        on .. " -> " .. head)
  check("bright enough to see across a room", head >= 12, tostring(head))

  -- every level the lane can produce is a legal grid level
  local legal = true
  for _, id in ipairs({"q4.1", "q4.4", "q6.1", "q6.6"}) do
    for _, active in ipairs({true, false}) do
      M.state.step_active[id] = active
      local lvl = sequencer.level(id, 2)
      if lvl < 0 or lvl > 15 or lvl ~= math.floor(lvl) then legal = false end
    end
  end
  check("and every level it produces is a legal one", legal)
end

report()
