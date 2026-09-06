-- §4.4 the Colour page (lib/colour.lua): the master chain that sits one K3
-- past the mixer.
--
-- what this checks, in order: that every row arrives at a bypass position, so
-- a patch that never opens the page sounds exactly as it did before the page
-- existed; that the eight keys are the eight the engine will accept, which is
-- the one thing about this module that can be wrong without anything
-- crashing; that a nudge clamps and reaches the engine; and that the numbers
-- live on state.global where a PSET will find them.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("== colour ==")

-- the eight argument names \woodland_fx actually declares, and the eight
-- \colourKeys the engine's `colour` command will accept. hardcoded here on
-- purpose: this is the far end of the wire, and a test that read the list out
-- of colour.lua would agree with itself no matter what the engine says.
local ENGINE_KEYS = {"tape", "crush", "alias", "loss",
                     "chorus", "swirl", "shape", "comp"}

print("\n-- eight rows, one screen, and every key is one the engine knows --")
do
  local M = fresh(1)
  check("eight params", M.colour.PARAM_COUNT == 8,
        tostring(M.colour.PARAM_COUNT))

  local want, got = {}, {}
  for _, k in ipairs(ENGINE_KEYS) do want[k] = true end
  local unknown = {}
  for _, p in ipairs(M.colour.PARAMS) do
    got[p.key] = true
    if not want[p.key] then table.insert(unknown, p.key) end
  end
  check("no row carries a key the engine would drop", #unknown == 0,
        table.concat(unknown, ","))
  local missing = {}
  for _, k in ipairs(ENGINE_KEYS) do
    if not got[k] then table.insert(missing, k) end
  end
  check("and every argument the chain has is on the page", #missing == 0,
        table.concat(missing, ","))

  -- glyph.lua's rule: no two parameters on a page may look alike. this page
  -- is the one most at risk of breaking it, since half of it is degradation.
  local seen, dupes = {}, {}
  for _, p in ipairs(M.colour.PARAMS) do
    if seen[p.glyph] then table.insert(dupes, p.glyph) end
    seen[p.glyph] = true
  end
  check("no two rows draw the same shape", #dupes == 0,
        table.concat(dupes, ","))

  local glyph = wl("glyph")
  local absent = {}
  for _, p in ipairs(M.colour.PARAMS) do
    if not glyph.exists(p.glyph) then table.insert(absent, p.glyph) end
  end
  check("and every shape it names actually exists", #absent == 0,
        table.concat(absent, ","))
end

print("\n-- a fresh patch arrives with the whole chain bypassed --")
do
  local M = fresh(3)
  -- everything at zero except Shape, which is bipolar and neutral in the
  -- middle, and Swirl, which is the chorus's rate and inaudible until Chorus
  -- is up. that is the contract: opening this page must not be the only way
  -- to get the instrument back to how it sounded before it existed.
  local bypass = {tape = 0, crush = 0, alias = 0, loss = 0, chorus = 0,
                  shape = 0.5}
  for key, v in pairs(bypass) do
    check(key .. " starts bypassed", M.colour.get(key) == v,
          tostring(M.colour.get(key)))
  end
  check("Swirl starts somewhere audible, for when Chorus is turned up",
        M.colour.get("swirl") > 0 and M.colour.get("swirl") < 1,
        tostring(M.colour.get("swirl")))
  check("and its readout is in Hz, not knob units",
        M.colour.PARAMS[6].text():match("Hz") ~= nil,
        M.colour.PARAMS[6].text())
  check("Shape reads as a signed offset from neutral",
        M.colour.PARAMS[7].text() == "+0.00", M.colour.PARAMS[7].text())
end

print("\n-- init pushes all eight, once each --")
do
  local M = fresh(5)
  M.colour.init()
  check("eight messages went out", #CALLS.colour == 8,
        tostring(#CALLS.colour))
  local seen = {}
  for _, c in ipairs(CALLS.colour) do seen[c.key] = (seen[c.key] or 0) + 1 end
  local once = true
  for _, k in ipairs(ENGINE_KEYS) do if seen[k] ~= 1 then once = false end end
  check("one per key, none doubled and none missed", once)
  -- the engine holds these whether or not anyone has touched them, so the
  -- values it is holding have to be this module's defaults rather than
  -- \woodland_fx's own -- one set of defaults, in one file.
  local by_key = {}
  for _, c in ipairs(CALLS.colour) do by_key[c.key] = c.v end
  local matched = true
  for k, v in pairs(M.colour.DEFAULTS) do
    if math.abs(by_key[k] - v) > 1e-9 then matched = false end
  end
  check("at exactly the defaults this file declares", matched)
end

print("\n-- every row is a 0..1 knob that clamps and pushes --")
do
  local M = fresh(7)
  for i = 1, M.colour.PARAM_COUNT do
    local p = M.colour.param(i)
    CALLS.colour = {}
    M.colour.nudge(i, 10000, true)
    check(p.label .. " clamps at 1", p.get() == 1, tostring(p.get()))
    check(p.label .. " pushed its own key on the way",
          CALLS.colour[#CALLS.colour].key == p.key,
          CALLS.colour[#CALLS.colour].key)
    M.colour.nudge(i, -10000, true)
    check(p.label .. " clamps at 0", p.get() == 0, tostring(p.get()))
    check(p.label .. " draws a value between 0 and 1",
          p.frac() >= 0 and p.frac() <= 1 and type(p.text()) == "string")
  end

  -- coarse and fine are the same two step sizes every other page uses.
  M.colour.set("tape", 0.5)
  M.colour.nudge(1, 1, true)
  local coarse = M.colour.get("tape") - 0.5
  M.colour.set("tape", 0.5)
  M.colour.nudge(1, 1, false)
  local fine = M.colour.get("tape") - 0.5
  check("coarse moves further than fine", coarse > fine and fine > 0,
        string.format("%.5f vs %.5f", coarse, fine))
end

print("\n-- the numbers live where a PSET will find them --")
do
  local M = fresh(9)
  M.colour.set("crush", 0.75)
  check("on state.global, keyed by row",
        M.state.global.colour.crush == 0.75,
        tostring(M.state.global.colour and M.state.global.colour.crush))
  -- and nothing else on the panel writes there
  check("and the page reads back what was written",
        M.colour.get("crush") == 0.75)
end

print("\n-- the page is reached with K3 and left with K2 --")
do
  -- driven through the real Canopy.lua, since the page stack IS Canopy.lua.
  function include(file)
    return dofile(ROOT .. "/" .. file:gsub("^Canopy/", "") .. ".lua")
  end
  _canopy_mods = nil
  dofile(ROOT .. "/Canopy.lua")
  init()
  local M = _canopy_mods

  local function press(n) key(n, 1); key(n, 0) end

  M.state.view = "global"
  M.state.cell_edit = nil
  M.state.held = {}
  press(3); press(3); press(3)
  check("three K3s from the main screen land on Colour",
        M.state.view == "colour", M.state.view)

  -- the encoders follow the screen: E1 walks this page's own cursor and E2
  -- moves the row under it, not the global page's.
  M.state.cparam_focus = 1
  enc(1, 3)
  check("E1 walks the Colour page's own focus", M.state.cparam_focus == 4,
        tostring(M.state.cparam_focus))
  enc(1, 99)
  check("clamped at the last row",
        M.state.cparam_focus == M.colour.PARAM_COUNT,
        tostring(M.state.cparam_focus))

  local bpm_before = M.state.global.bpm
  local comp_before = M.colour.get("comp")
  CALLS.colour = {}
  enc(2, 5)
  check("E2 moves the row under the cursor",
        M.colour.get("comp") > comp_before, tostring(M.colour.get("comp")))
  check("and it reached the engine", #CALLS.colour > 0)
  check("without touching the global page",
        M.state.global.bpm == bpm_before, tostring(M.state.global.bpm))

  press(2)
  check("K2 comes back to the mixer", M.state.view == "mixer", M.state.view)
  press(3)
  press(3)
  check("and K3 past Colour is the map, not a wrap",
        M.state.view == "map", M.state.view)
  press(3)
  check("which is where the walk stops", M.state.view == "map", M.state.view)

  -- K1+E3 is still master level from this page, as from every other.
  local lvl = M.state.global.level
  key(1, 1)
  enc(3, 10)
  key(1, 0)
  check("K1+E3 is still the master from here",
        M.state.global.level > lvl, tostring(M.state.global.level))
end

report()
