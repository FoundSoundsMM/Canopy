-- §4.1b the mixer page (lib/mixer.lua) and §4.3 the external transport
-- (Canopy.lua's clock.transport handlers).
--
-- covers: (1) the four soundscape loops are declared once and load once, at
-- the engine indices the .sc file expects; (2) each fader is an independent
-- 0..1 knob that reaches the engine, the master is the fifth, and the gusts'
-- shared delay line (§2.11) fills the page out to exactly one screen; (3) K3 and
-- K2 move between the main screen, an open cell page and the mixer in the
-- shape Canopy.lua's header describes -- including K3 dropping a cell's
-- focus on the way; (4) an external Start/Stop freezes and unfreezes the
-- patch, and drops -- rather than floods out -- the taps a Stop froze in the
-- scheduler and in the weave.
--
-- this one drives the real Canopy.lua rather than the modules directly,
-- because half of what it is testing IS Canopy.lua -- key(), enc(), and the
-- three transport callbacks.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

function include(file)
  return dofile(ROOT .. "/" .. file:gsub("^Canopy/", "") .. ".lua")
end

_canopy_mods = nil
dofile(ROOT .. "/Canopy.lua")
init()
local M = _canopy_mods
local mixer, state, patch = M.mixer, M.state, M.patch

local function last(list)
  return list[#list]
end

local function last_for(list, index)
  local out
  for _, c in ipairs(list) do if c.index == index then out = c end end
  return out
end

-- a solo key press: down and up with nothing else held.
local function press(n)
  key(n, 1)
  key(n, 0)
end

-- 1: the loops ---------------------------------------------------------------

print("\n-- four loops, loaded once each --")
do
  check("four of them", mixer.LOOP_COUNT == 4, tostring(mixer.LOOP_COUNT))
  check("Rain keeps index 0", mixer.LOOPS[1].key == "rain"
        and mixer.LOOPS[1].index == 0)

  local names = {}
  for _, l in ipairs(mixer.LOOPS) do names[l.key] = l end
  for _, k in ipairs({"rain", "cicada", "thunder", "sea"}) do
    check(k .. " is one of them", names[k] ~= nil)
  end

  check("init loaded exactly four samples", #CALLS.amb_load == 4,
        tostring(#CALLS.amb_load))
  local seen, paths_ok = {}, true
  for _, c in ipairs(CALLS.amb_load) do
    seen[c.index] = true
    if not c.path:match("/audio/[A-Za-z]+%.wav$") then paths_ok = false end
  end
  check("at indices 0..3", seen[0] and seen[1] and seen[2] and seen[3])
  check("each an absolute path under audio/", paths_ok,
        CALLS.amb_load[1] and CALLS.amb_load[1].path)
end

-- 2: the faders --------------------------------------------------------------

print("\n-- eight rows: four loops, the master, and the gusts' delay line --")
do
  -- eight is exactly one screen (screenui.PARAMS_PER_PAGE), which is why the
  -- gusts' shared delay line (§2.11) lives here rather than pushing the
  -- seven-row global page onto a second page.
  check("eight rows", mixer.PARAM_COUNT == 8, tostring(mixer.PARAM_COUNT))
  check("the master closes the faders", mixer.PARAMS[5].key == "master")
  check("then Space, Delay and Regen",
        mixer.PARAMS[6].key == "gust_space"
        and mixer.PARAMS[7].key == "gust_delay"
        and mixer.PARAMS[8].key == "gust_regen")

  check("every loop starts silent",
        mixer.get_level("rain") == 0 and mixer.get_level("sea") == 0)

  mixer.nudge(2, 10000, true)            -- Cicada, all the way up
  check("a fader clamps at 1", mixer.get_level("cicada") == 1,
        tostring(mixer.get_level("cicada")))
  check("and reached the engine at its own index",
        last_for(CALLS.amb_volume, 1)
        and math.abs(last_for(CALLS.amb_volume, 1).v - 1) < 1e-6,
        tostring(last_for(CALLS.amb_volume, 1)
                 and last_for(CALLS.amb_volume, 1).v))
  check("without moving anybody else", mixer.get_level("rain") == 0
        and mixer.get_level("thunder") == 0 and mixer.get_level("sea") == 0)

  mixer.nudge(2, -10000, true)
  check("and clamps at 0 on the way back", mixer.get_level("cicada") == 0)

  -- coarse and fine are the same two steps every other page uses
  mixer.nudge(3, 8, true)
  local coarse = mixer.get_level("thunder")
  check("coarse is 1/80 a detent", math.abs(coarse - 8 / 80) < 1e-9,
        tostring(coarse))
  mixer.nudge(3, 8, false)
  check("fine is 1/500", math.abs(mixer.get_level("thunder")
                                  - (coarse + 8 / 500)) < 1e-9,
        tostring(mixer.get_level("thunder")))

  -- the master is the same number K1+E3 has always moved
  state.global.level = 0.8
  mixer.nudge(5, 16, true)
  check("the master fader is master level", math.abs(state.global.level - 1.0) < 1e-9,
        tostring(state.global.level))

  -- and no fader has an excite of any kind: the loops are a dry mix
  local excite_row = false
  for _, p in ipairs(mixer.PARAMS) do
    if p.key:match("exc") then excite_row = true end
  end
  check("no loop excites the voices", not excite_row)
  check("and the engine was never asked to", engine.amb_excite == nil
        or CALLS.amb_excite == nil)
end

-- 3: K3 there, K2 back -------------------------------------------------------

print("\n-- K3 to the mixer, K2 back --")
do
  state.view = "global"
  state.cell_edit = nil
  state.held = {}

  press(3)
  check("K3 opens the mixer", state.view == "mixer", state.view)
  press(2)
  check("K2 closes it again", state.view == "global", state.view)

  -- from an open cell page: K3 goes to the mixer AND drops the focus
  state.cell_edit = "oak"
  press(3)
  check("K3 from a cell page reaches the mixer", state.view == "mixer",
        state.view)
  check("and disconnects that cell's focus", state.cell_edit == nil,
        tostring(state.cell_edit))

  -- K2 from an open cell page goes to the main screen, not to Still
  state.view = "global"
  state.cell_edit = "hazel"
  state.global.still = false
  press(2)
  check("K2 from a cell page closes it", state.cell_edit == nil,
        tostring(state.cell_edit))
  check("and does not freeze the patch on the way", state.global.still == false)

  -- K2 off the mixer likewise leaves Still alone
  press(3)
  press(2)
  check("K2 off the mixer does not freeze it either",
        state.global.still == false and state.view == "global")

  -- only with nothing to come back from is K2 Still
  press(2)
  check("K2 on the main screen is Still", state.global.still == true)
  press(2)
  check("and resumes", state.global.still == false)

  -- the encoders follow the screen
  state.view = "mixer"
  state.mparam_focus = 1
  enc(1, 3)
  check("E1 walks the mixer's own focus", state.mparam_focus == 4,
        tostring(state.mparam_focus))
  enc(1, 99)
  check("clamped to the last row", state.mparam_focus == 8,
        tostring(state.mparam_focus))
  local before = state.global.bpm
  enc(2, 5)
  check("E2 on the mixer does not touch the global page",
        state.global.bpm == before, tostring(state.global.bpm))
  state.view = "global"
end

-- 4: the external transport --------------------------------------------------

print("\n-- an external Start and Stop --")
do
  params:set("clock_source", 2)          -- MIDI

  state.global.still = false
  state.held = {}
  state.cell_edit = nil
  patch.clear()

  state.global.still = false
  clock.transport.stop()
  check("a Stop freezes the gaits", state.global.still == true)
  -- and it is the SAME flag K2 writes, not a parallel record of its own:
  -- a remote stop and a local freeze cannot get out of step because there
  -- is only one of them.
  press(2)
  check("so K2 resumes from an external stop", state.global.still == false)
  clock.transport.stop()

  clock.transport.start()
  check("a Start unfreezes them", state.global.still == false)

  -- a song-position jump with no stop: the queues clear, nothing freezes.
  -- there is no playhead left on the panel to put back -- the step lanes are
  -- gone and the gusts that replaced them hold a pitch, not a position.
  clock.transport.reset()
  check("a reset clears the queues without stopping anything",
        state.global.still == false)

  -- and a ringing gust is left ringing: a transport message is about time,
  -- and a swell that is part-way through is not a queue to be flushed.
  local before = #CALLS.gust_note
  M.gust.press("gu.haar")
  clock.transport.reset()
  clock.transport.start()
  check("neither a reset nor a Start re-sounds or silences one",
        #CALLS.gust_note == before + 1, tostring(#CALLS.gust_note - before))

  -- the resume must not flush a backlog. freeze with a clock-rooted trigger
  -- cabled to a voice, let wall time run past several of its beats, and
  -- confirm the Start does not fire all of them at once.
  patch.clear()
  M.rambler.set_gait("d.hob", "metric")
  M.rambler.set_rooted("d.hob", true)
  state.character["d.hob"] = 1.0
  patch.add("d.hob", "oak", 1.0)
  clock.transport.start()
  run(M, 1.0)
  local before_stop = #CALLS.strike
  check("it was playing", before_stop > 0, tostring(before_stop))

  clock.transport.stop()
  run(M, 4.0)                            -- four seconds of frozen wall time
  check("and nothing sounded while stopped", #CALLS.strike == before_stop,
        #CALLS.strike .. " vs " .. before_stop)

  clock.transport.start()
  M.rambler.tick()                       -- exactly one tick after the Start
  check("the first tick after a Start is not a flood",
        #CALLS.strike - before_stop <= 1,
        tostring(#CALLS.strike - before_stop))

  -- the weave keeps its own queue behind the same tick and is frozen by the
  -- same flag, so it needs the same guarantee. `roll` is the rule that
  -- schedules the most: one pulse in, a burst of taps out over the next
  -- beat, all sitting in weave's `pending` with timestamps that a four-
  -- second freeze puts firmly in the past.
  clock.transport.start()
  patch.clear()
  M.weave.set_rule("r.tangle", "roll")
  state.character["r.tangle"] = 0.9
  patch.add("d.hob", "r.tangle", 1.0)
  patch.add("r.tangle", "hazel", 1.0)
  run(M, 1.0)
  check("the weave is scheduling taps", M.weave.pending_count() > 0,
        tostring(M.weave.pending_count()))

  clock.transport.stop()
  local frozen = #CALLS.strike
  local held = M.weave.pending_count()
  run(M, 4.0)
  check("and they stay frozen with everything else",
        M.weave.pending_count() == held and #CALLS.strike == frozen,
        M.weave.pending_count() .. "/" .. held)

  clock.transport.start()
  check("a Start drops them rather than firing them all at once",
        M.weave.pending_count() == 0, tostring(M.weave.pending_count()))
  M.rambler.tick()
  check("so the first tick after it is not a flood either",
        #CALLS.strike - frozen <= 1, tostring(#CALLS.strike - frozen))

  params:set("clock_source", 1)
end

report()
