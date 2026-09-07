-- §2.11c / lib/send.lua: the shared send effect and its page.
--
-- covers: (1) every sounding family has a Send row and it starts at zero, so
-- a patch that never opens the page sounds exactly as it did before there
-- was one; (2) turning one up builds a patch synth from that cell's own tap
-- into the send bus and turning it back down frees it; (3) the ids it claims
-- cannot collide with a cable's; (4) the four effect knobs clamp, print and
-- reach the engine; and (5) the numbers still live where the gusts' delay
-- line kept them, so a patch saved before the move comes back on its
-- settings.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("== send ==")

local function last(list) return list[#list] end

print("\n-- every sounding family has a Send row, and it starts at zero --")
do
  local M = fresh(1)
  local want = {voice = "oak", GVOICE = "gv.yaffle", GUST = "gu.gale",
                SMP = "smp.rain", FM = "fm.1", VA = "va.1"}
  for kind, id in pairs(want) do
    local page = M.cellparam.page(id)
    local found
    for _, p in ipairs(page.PARAMS) do
      if p.key == "send" then found = p end
    end
    check(kind .. " has a Send row", found ~= nil)
    check("and it starts at zero", found and found.get(id) == 0,
          found and tostring(found.get(id)))
    -- last on the page: it is a routing decision, and it belongs after the
    -- knobs that decide what the sound is.
    check("sitting last on the page",
          page.PARAMS[page.PARAM_COUNT].key == "send",
          page.PARAMS[page.PARAM_COUNT].key)
  end

  -- and an exciter deliberately has none: it is a texture that runs
  -- continuously rather than a note, so a send on one is a permanent wash.
  local e = M.cellparam.page("e.bracken")
  local has = false
  for _, p in ipairs(e.PARAMS) do if p.key == "send" then has = true end end
  check("an exciter has no Send row", not has)
end

print("\n-- a fresh patch sends nothing at all, and costs no synths --")
do
  local M = fresh(2)
  local before = #CALLS.patch_add
  M.send.init()
  check("init pushed the four effect knobs", #CALLS.gust_space > 0)
  check("and built no send synths", #CALLS.patch_add == before,
        tostring(#CALLS.patch_add - before))
  check("nothing is sending", M.send.active_count() == 0,
        tostring(M.send.active_count()))
end

print("\n-- turning one up builds a synth, turning it down frees it --")
do
  local M = fresh(3)
  M.send.init()
  local id = "gv.chaff"
  local cell = M.topology.get(id)

  M.state.set_vparam(id, "send", 0.5)
  M.send.push(id)
  local add = last(CALLS.patch_add)
  check("a patch synth was built", add ~= nil)
  check("from this drum's own tap",
        add.src == M.bridge.bus("gvoice_out", cell.index - 1),
        tostring(add and add.src))
  check("into the send bus", add.dst == M.bridge.bus("send", 0),
        tostring(add and add.dst))
  -- squared on the way, for the same reason a fader is.
  check("at the squared knob position", math.abs(add.gain - 0.25) < 1e-9,
        tostring(add and add.gain))
  check("and it counts as sending", M.send.active_count() == 1,
        tostring(M.send.active_count()))

  -- moving it is a gain change, not a second synth.
  local n = #CALLS.patch_add
  M.state.set_vparam(id, "send", 0.8)
  M.send.push(id)
  check("moving it only changes the gain", #CALLS.patch_add == n
        and #CALLS.patch_gain > 0, tostring(#CALLS.patch_add - n))

  -- and pushing the same value again sends nothing: a patch_add is a synth
  -- allocation and a patch_free is an audible cut.
  local g = #CALLS.patch_gain
  M.send.push(id)
  check("re-pushing an unchanged value is silent", #CALLS.patch_gain == g,
        tostring(#CALLS.patch_gain - g))

  local frees = #CALLS.patch_free
  M.state.set_vparam(id, "send", 0)
  M.send.push(id)
  check("back at zero the synth is freed", #CALLS.patch_free > frees)
  check("and nothing is sending again", M.send.active_count() == 0)
end

print("\n-- a send id can never collide with a cable's --")
do
  local M = fresh(4)
  -- dispatch keys its specs `edge.id * 10 + i`, and patch.MAX_CABLES caps the
  -- edge count -- so the highest a cable can reach is nowhere near the block
  -- send.lua claims.
  local highest_cable = (M.patch.MAX_CABLES + 1) * 10
  check("the send block starts far above any cable id",
        M.send.ID_BASE > highest_cable,
        M.send.ID_BASE .. " vs " .. highest_cable)

  -- and it is one flat block in registration order, so an id never moves when
  -- the graph does.
  M.send.init()
  M.state.set_vparam("oak", "send", 0.5)
  M.send.push("oak")
  local first = last(CALLS.patch_add).id
  M.patch.add("d.hob", "oak", 1.0)
  M.state.set_vparam("oak", "send", 0.7)
  M.send.push("oak")
  check("the same cell keeps the same id across a graph change",
        last(CALLS.patch_gain).id == first,
        tostring(last(CALLS.patch_gain).id) .. " vs " .. first)
end

print("\n-- the page: four knobs, one screen --")
do
  local M = fresh(5)
  check("four rows", M.send.PARAM_COUNT == 4, tostring(M.send.PARAM_COUNT))
  local keys = {}
  for _, p in ipairs(M.send.PARAMS) do table.insert(keys, p.key) end
  check("Space, Delay, Regen, Tone",
        table.concat(keys, ",") == "send_space,send_delay,send_regen,send_tone",
        table.concat(keys, ","))

  -- no two rows draw the same shape (glyph.lua's one rule).
  local seen, dupes = {}, {}
  for _, p in ipairs(M.send.PARAMS) do
    if seen[p.glyph] then table.insert(dupes, p.glyph) end
    seen[p.glyph] = true
  end
  check("and no two draw the same shape", #dupes == 0, table.concat(dupes, ","))

  for i = 1, M.send.PARAM_COUNT do
    local p = M.send.param(i)
    CALLS.gust_space = {}
    M.send.nudge(i, 10000, true)
    check(p.label .. " clamps at the top and pushes",
          p.frac() <= 1 and #CALLS.gust_space > 0, tostring(p.frac()))
    M.send.nudge(i, -10000, true)
    check(p.label .. " clamps at the bottom", p.frac() >= 0, tostring(p.frac()))
    check(p.label .. " prints something", type(p.text()) == "string"
          and #p.text() > 0, p.text())
  end
end

print("\n-- the ranges and the state are the delay line's own, unchanged --")
do
  local M = fresh(6)
  M.send.set_fx("delay", 99)
  check("delay time is capped", M.send.get_fx("delay") == M.send.DELAY_MAX,
        tostring(M.send.get_fx("delay")))
  M.send.set_fx("regen", 1.0)
  check("feedback stops short of unity",
        M.send.get_fx("regen") == M.send.REGEN_MAX,
        tostring(M.send.get_fx("regen")))
  M.send.set_fx("space", -3)
  check("mix cannot go negative", M.send.get_fx("space") == 0)

  -- the key on state.global is unchanged on purpose: renaming it would
  -- silently discard the settings out of every patch saved before the move.
  check("the numbers live where the gusts' delay line kept them",
        M.state.global.gust_space.delay == M.send.DELAY_MAX,
        tostring(M.state.global.gust_space
                 and M.state.global.gust_space.delay))

  -- Tone prints in Hz, because a damping frequency is a number worth reading.
  check("Tone reads as a frequency",
        M.send.PARAMS[4].text():match("Hz") ~= nil, M.send.PARAMS[4].text())
  check("and reaches the engine as the fourth argument",
        (function()
          CALLS.gust_space = {}
          M.send.push_fx()
          local c = last(CALLS.gust_space)
          return c and c.tone == M.send.get_fx("tone")
        end)())
end

print("\n-- an LFO can move a Send knob, like any other row --")
do
  local M = fresh(7)
  local L, V = "lfo.flood", "gv.scree"
  M.patch.add(L, V, 1.0)
  local keys = {}
  for _, k in ipairs(M.lfo.param_keys(L)) do keys[k] = true end
  check("Send is one of the knobs on offer", keys.send == true,
        table.concat(M.lfo.param_keys(L), ","))

  M.lfo.set_param_key(L, "send")
  M.lfo.set_depth(L, 0.4)
  M.state.set_vparam(V, "send", 0.5)
  local before = #CALLS.patch_gain + #CALLS.patch_add
  M.lfo.apply()
  check("and moving it re-routes the send live",
        #CALLS.patch_gain + #CALLS.patch_add > before)
  check("while the stored value never moved",
        math.abs(M.send.amount(V) - 0.5) < 1e-9, tostring(M.send.amount(V)))
end

report()
