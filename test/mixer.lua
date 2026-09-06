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

print("\n-- with nothing patched, the mixer is empty --")
do
  patch.clear()
  -- there is no master row any more: a master is one number over the whole
  -- instrument rather than a channel, and it lives on K1+E3 alone. so a
  -- patch that makes no sound has a mixer with nothing on it, which is the
  -- honest picture rather than a lonely fader.
  check("no rows at all", mixer.PARAM_COUNT == 0, tostring(mixer.PARAM_COUNT))
  check("and no row anywhere calls itself the master", (function()
    for _, p in ipairs(mixer.PARAMS) do
      if p.key == "master" then return false end
    end
    return true
  end)())
  check("the cursor stays somewhere legal", state.mparam_focus == 1,
        tostring(state.mparam_focus))
  check("and asking for a row there is nil, not a crash",
        mixer.param(1) == nil)
  check("as is nudging one", mixer.nudge(1, 10, true) == nil)
end

print("\n-- a channel appears as its output is used, and goes when it is not --")
do
  patch.clear()
  patch.add("oak", "o.5", 0.8)
  check("one row now", mixer.PARAM_COUNT == 1, tostring(mixer.PARAM_COUNT))
  -- the channel is named after the instrument on it, not after the seat: an
  -- Out cell carries one source (patch.lua), and "Out 5" names a pan
  -- position, which is the least useful thing about a channel by the time
  -- there are six of them.
  check("and it is called Oak, not Out 5", mixer.PARAMS[1].label == "Oak",
        mixer.PARAMS[1].label)
  check("it comes up at unity, not silent",
        mixer.get_level("o.5") == 1, tostring(mixer.get_level("o.5")))

  patch.add("hazel", "o.2", 0.8)
  check("a second output, a second row", mixer.PARAM_COUNT == 2,
        tostring(mixer.PARAM_COUNT))
  -- row order is Output-row order, which is also left-to-right in the stereo
  -- field: the page reads the way the image sounds.
  check("in row order, not the order they were patched",
        mixer.PARAMS[1].label == "Hazel" and mixer.PARAMS[2].label == "Oak",
        mixer.PARAMS[1].label .. " " .. mixer.PARAMS[2].label)

  -- a second source landing on an occupied output evicts the first, so a
  -- channel is renamed rather than doubled up.
  patch.add("alder", "o.2", 0.8)
  check("a second source on one output is still one channel",
        mixer.PARAM_COUNT == 2, tostring(mixer.PARAM_COUNT))
  check("under the new source's name", mixer.PARAMS[1].label == "Alder",
        mixer.PARAMS[1].label)
  check("and the one it evicted is off the row entirely",
        patch.has("hazel", "o.2") == nil)

  patch.remove("oak", "o.5")
  check("pulling the cable takes the channel with it", mixer.PARAM_COUNT == 1,
        tostring(mixer.PARAM_COUNT))
  check("but the level it was left at is remembered",
        mixer.get_level("o.5") == 1)

  patch.clear()
  check("clearing every cable empties the page",
        mixer.PARAM_COUNT == 0, tostring(mixer.PARAM_COUNT))
end

print("\n-- the four SFX loops are channels like everything else --")
do
  patch.clear()
  patch.add("smp.thunder", "o.12", 0.8)
  check("a sample cell cabled to an output is a channel",
        mixer.PARAM_COUNT == 1, tostring(mixer.PARAM_COUNT))
  check("named after the recording", mixer.PARAMS[1].label == "Thunder",
        mixer.PARAMS[1].label)
  patch.clear()
end

print("\n-- and never more than sixteen of them --")
do
  patch.clear()
  for x = 1, 16 do patch.add("oak", "o." .. x, 0.5) end
  -- the Output row is exclusive (patch.lua's displace_output): one source
  -- sits at one pan position, so sixteen cables from one voice is one
  -- channel. cable a different source to each to fill the row.
  check("one source can only ever be on one output", mixer.PARAM_COUNT == 1,
        tostring(mixer.PARAM_COUNT))

  patch.clear()
  local sources = {"oak", "hazel", "alder", "rowan",
                   "gv.yaffle", "gv.knap", "gv.clapper",
                   "gv.scree", "gv.chaff", "gv.rattle",
                   "e.bracken", "e.gorse", "e.ember",
                   "e.windfall", "e.mistle", "e.wisp"}
  for x, src in ipairs(sources) do patch.add(src, "o." .. x, 0.5) end
  check("a full row is sixteen channels", mixer.PARAM_COUNT == 16,
        tostring(mixer.PARAM_COUNT))
  check("which is the cap the Output row itself sets",
        mixer.PARAM_COUNT == mixer.MAX_CHANNELS)
  check("and every one of them is named after its instrument", (function()
    for i, src in ipairs(sources) do
      if mixer.PARAMS[i].label ~= M.topology.get(src).name then return false end
    end
    return true
  end)())
  patch.clear()
end

-- 3: the faders themselves ---------------------------------------------------

print("\n-- each channel is an independent 0..1 knob that reaches the engine --")
do
  patch.clear()
  patch.add("oak", "o.3", 0.8)
  patch.add("hazel", "o.9", 0.8)
  -- rows: 1 Oak (on Out 3), 2 Hazel (on Out 9)
  check("row 1 is Oak", mixer.PARAMS[1].label == "Oak", mixer.PARAMS[1].label)

  mixer.nudge(1, -10000, true)
  check("a fader clamps at 0", mixer.get_level("o.3") == 0,
        tostring(mixer.get_level("o.3")))
  check("and reached the engine at that output's own index",
        last_for(CALLS.out_level, 2)
        and math.abs(last_for(CALLS.out_level, 2).v) < 1e-6,
        tostring(last_for(CALLS.out_level, 2)
                 and last_for(CALLS.out_level, 2).v))
  check("without moving anybody else", mixer.get_level("o.9") == 1)

  mixer.nudge(1, 10000, true)
  check("and clamps at 1 on the way back", mixer.get_level("o.3") == 1)

  -- coarse and fine are the same two steps every other page uses
  mixer.set_level("o.9", 0)
  mixer.nudge(2, 8, true)
  local coarse = mixer.get_level("o.9")
  check("coarse is 1/80 a detent", math.abs(coarse - 8 / 80) < 1e-9,
        tostring(coarse))
  mixer.nudge(2, 8, false)
  check("fine is 1/500", math.abs(mixer.get_level("o.9")
                                  - (coarse + 8 / 500)) < 1e-9,
        tostring(mixer.get_level("o.9")))

  -- every channel carries a meter, which is the other half of what this page
  -- is for: a fader at 0.8 on a silent channel and one on a roaring channel
  -- look identical without it (lib/glyph.lua's `channel`).
  check("every row draws the metered shape", (function()
    for _, p in ipairs(mixer.PARAMS) do
      if p.glyph ~= "channel" then return false end
      local d = p.glyph_data and p.glyph_data()
      if not d or type(d.meter) ~= "number" then return false end
    end
    return true
  end)())

  -- and the gusts' delay line is not here any more: it is a room, not a
  -- channel, and it went to the gusts' own page (gust.lua's MACROS).
  local room_row = false
  for _, p in ipairs(mixer.PARAMS) do
    if p.key:match("^gust") then room_row = true end
  end
  check("no delay-line row is left on this page", not room_row)
  patch.clear()
end

-- 3: K3 there, K2 back -------------------------------------------------------
-- the stack is five deep now -- global, gusts, mixer, colour, map -- so the
-- mixer is two K3s in rather than one, and what this section is really
-- checking is that the walk is a walk: strictly one page per press, in one
-- fixed order, stopping dead at both ends.

local VIEWS = {"global", "gusts", "mixer", "colour", "map"}

print("\n-- K3 forward, K2 back, one page at a time --")
do
  state.view = "global"
  state.cell_edit = nil
  state.held = {}

  for i = 2, #VIEWS do
    press(3)
    check("K3 steps to " .. VIEWS[i], state.view == VIEWS[i], state.view)
  end
  press(3)
  check("and stops on the map rather than wrapping", state.view == "map",
        state.view)

  for i = #VIEWS - 1, 1, -1 do
    press(2)
    check("K2 steps back to " .. VIEWS[i], state.view == VIEWS[i], state.view)
  end

  -- from an open cell page: K3 steps the page underneath AND drops the focus
  state.view = "global"
  state.cell_edit = "oak"
  press(3)
  check("K3 from a cell page steps the page under it", state.view == "gusts",
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

  -- K2 off any page above the main screen likewise leaves Still alone
  press(3)
  press(2)
  check("K2 off the gusts page does not freeze it either",
        state.global.still == false and state.view == "global")

  -- only with nothing to come back from is K2 Still
  press(2)
  check("K2 on the main screen is Still", state.global.still == true)
  press(2)
  check("and resumes", state.global.still == false)

  -- the encoders follow the screen. the page is built from the patch, so
  -- give it something to show first -- with nothing cabled it is empty and
  -- there is nothing for E1 to walk.
  patch.clear()
  patch.add("oak", "o.4", 0.8)
  patch.add("hazel", "o.8", 0.8)
  patch.add("alder", "o.12", 0.8)
  patch.add("rowan", "o.16", 0.8)
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
