-- §4.1b the mixer page (lib/mixer.lua) and §4.3 the external transport
-- (Canopy.lua's clock.transport handlers).
--
-- covers: (1) the four field recordings load once each at init, at the engine
-- indices the .sc file expects -- they belong to the Sample cells now (§2.5)
-- rather than to this page; (2) the page is built from the patch, growing a
-- fader as an Output cell is cabled to and losing it again when the cable is
-- pulled, with the master always first and never more than sixteen channels
-- after it; (3) K3 and
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

-- 1: the sample cells' recordings load once each ----------------------------

print("\n-- the four recordings load once each, at the engine's own slots --")
do
  -- these used to be the mixer's four always-on loops. they are the four
  -- Sample cells now (§2.5, lib/sample.lua) and the mixer knows nothing about
  -- them -- but they still have to be loaded exactly once at init, at the
  -- indices the .sc file expects, which is what this checks.
  check("init loaded exactly four samples", #CALLS.smp_load == 4,
        tostring(#CALLS.smp_load))
  local seen, paths_ok = {}, true
  for _, c in ipairs(CALLS.smp_load) do
    seen[c.index] = true
    if not c.path:match("/audio/[A-Za-z]+%.wav$") then paths_ok = false end
  end
  check("at indices 0..3", seen[0] and seen[1] and seen[2] and seen[3])
  check("each an absolute path under audio/", paths_ok,
        CALLS.smp_load[1] and CALLS.smp_load[1].path)

  check("and no ambience loop is left anywhere", engine.amb_load == nil
        or CALLS.amb_load == nil)
end

-- 2: the page is built from the patch ----------------------------------------

print("\n-- with nothing patched, the mixer is the master and nothing else --")
do
  patch.clear()
  check("one row", mixer.PARAM_COUNT == 1, tostring(mixer.PARAM_COUNT))
  check("and it is the master", mixer.PARAMS[1].key == "master")
end

print("\n-- a fader appears as its output is used, and goes when it is not --")
do
  patch.clear()
  patch.add("oak", "o.5", 0.8)
  check("two rows now", mixer.PARAM_COUNT == 2, tostring(mixer.PARAM_COUNT))
  check("the new one is Out 5", mixer.PARAMS[2].label == "Out 5",
        mixer.PARAMS[2].label)
  check("and it comes up at unity, not silent",
        mixer.get_level("o.5") == 1, tostring(mixer.get_level("o.5")))

  patch.add("hazel", "o.2", 0.8)
  check("a second output, a third row", mixer.PARAM_COUNT == 3,
        tostring(mixer.PARAM_COUNT))
  -- row order is Output-row order, which is also left-to-right in the stereo
  -- field: the page reads the way the image sounds.
  check("in row order, not the order they were patched",
        mixer.PARAMS[2].label == "Out 2" and mixer.PARAMS[3].label == "Out 5",
        mixer.PARAMS[2].label .. " " .. mixer.PARAMS[3].label)

  -- two sources landing on one output is one channel, not two.
  patch.add("alder", "o.2", 0.8)
  check("two sources on one output is still one fader",
        mixer.PARAM_COUNT == 3, tostring(mixer.PARAM_COUNT))

  patch.remove("oak", "o.5")
  check("pulling the cable takes the fader with it", mixer.PARAM_COUNT == 2,
        tostring(mixer.PARAM_COUNT))
  check("but the level it was left at is remembered",
        mixer.get_level("o.5") == 1)

  patch.clear()
  check("clearing every cable leaves the master alone",
        mixer.PARAM_COUNT == 1, tostring(mixer.PARAM_COUNT))
end

print("\n-- and never more than sixteen of them --")
do
  patch.clear()
  for x = 1, 16 do patch.add("oak", "o." .. x, 0.5) end
  -- the Output row is exclusive (patch.lua's displace_output): one source
  -- sits at one pan position, so sixteen cables from one voice is one
  -- channel. cable a different source to each to fill the row.
  check("one source can only ever be on one output", mixer.PARAM_COUNT == 2,
        tostring(mixer.PARAM_COUNT))

  patch.clear()
  local sources = {"oak", "hazel", "alder", "rowan",
                   "gv.yaffle", "gv.knap", "gv.clapper",
                   "gv.scree", "gv.chaff", "gv.rattle",
                   "e.bracken", "e.gorse", "e.ember",
                   "e.windfall", "e.mistle", "e.wisp"}
  for x, src in ipairs(sources) do patch.add(src, "o." .. x, 0.5) end
  check("a full row is sixteen faders and the master",
        mixer.PARAM_COUNT == 17, tostring(mixer.PARAM_COUNT))
  check("which is the cap the Output row itself sets",
        mixer.PARAM_COUNT - 1 == mixer.MAX_CHANNELS)
  patch.clear()
end

-- 3: the faders themselves ---------------------------------------------------

print("\n-- each channel is an independent 0..1 knob that reaches the engine --")
do
  patch.clear()
  patch.add("oak", "o.3", 0.8)
  patch.add("hazel", "o.9", 0.8)
  -- rows: 1 master, 2 Out 3, 3 Out 9
  local o3 = mixer.PARAMS[2]
  check("row 2 is Out 3", o3.label == "Out 3", o3.label)

  mixer.nudge(2, -10000, true)
  check("a fader clamps at 0", mixer.get_level("o.3") == 0,
        tostring(mixer.get_level("o.3")))
  check("and reached the engine at that output's own index",
        last_for(CALLS.out_level, 2)
        and math.abs(last_for(CALLS.out_level, 2).v) < 1e-6,
        tostring(last_for(CALLS.out_level, 2)
                 and last_for(CALLS.out_level, 2).v))
  check("without moving anybody else", mixer.get_level("o.9") == 1)

  mixer.nudge(2, 10000, true)
  check("and clamps at 1 on the way back", mixer.get_level("o.3") == 1)

  -- coarse and fine are the same two steps every other page uses
  mixer.set_level("o.9", 0)
  mixer.nudge(3, 8, true)
  local coarse = mixer.get_level("o.9")
  check("coarse is 1/80 a detent", math.abs(coarse - 8 / 80) < 1e-9,
        tostring(coarse))
  mixer.nudge(3, 8, false)
  check("fine is 1/500", math.abs(mixer.get_level("o.9")
                                  - (coarse + 8 / 500)) < 1e-9,
        tostring(mixer.get_level("o.9")))

  -- the master is the same number K1+E3 has always moved
  state.global.level = 0.8
  mixer.nudge(1, 16, true)
  check("the master fader is master level",
        math.abs(state.global.level - 1.0) < 1e-9, tostring(state.global.level))

  -- and the gusts' delay line is not here any more: it is a room, not a
  -- channel, and it went to the global page (gparam.lua).
  local room_row = false
  for _, p in ipairs(mixer.PARAMS) do
    if p.key:match("^gust") then room_row = true end
  end
  check("no delay-line row is left on this page", not room_row)
  patch.clear()
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

  -- the encoders follow the screen. the page is built from the patch, so
  -- give it something to show first -- with nothing cabled it is one row and
  -- there is nothing for E1 to walk.
  patch.clear()
  patch.add("oak", "o.4", 0.8)
  patch.add("hazel", "o.8", 0.8)
  patch.add("alder", "o.12", 0.8)
  state.view = "mixer"
  state.mparam_focus = 1
  enc(1, 3)
  check("E1 walks the mixer's own focus", state.mparam_focus == 4,
        tostring(state.mparam_focus))
  enc(1, 99)
  check("clamped to the last row", state.mparam_focus == mixer.PARAM_COUNT,
        tostring(state.mparam_focus) .. "/" .. tostring(mixer.PARAM_COUNT))
  local before = state.global.bpm
  enc(2, 5)
  check("E2 on the mixer does not touch the global page",
        state.global.bpm == before, tostring(state.global.bpm))
  patch.clear()
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
