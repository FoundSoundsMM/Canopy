-- topology.lua §2.11 / lib/gust.lua: the twelve Gust cells that replaced the
-- Q4/Q6 step-sequencer lanes (originally ten -- two more were added later to
-- bring the top row level with the bottom one).
--
-- what this file is actually checking, in order: that the twelve cells landed
-- where the lanes were and are panned by their columns; that a press sounds
-- a note and that the note obeys the global Scale and transpose; that the
-- envelope knobs and the global Decay macro reach the engine in seconds;
-- that a pulse down a cable sounds one and that it answers with a pulse of
-- its own; that a gust<->gust cable produces the mutual cross-mod pair the
-- Deerhorn reference is here for; and that a cable loop through two of them
-- stays bounded -- the same runaway question test/tm.lua asks of TM<->TM.

dofile((os.getenv("SP") or "test") .. "/harness.lua")

print("== gust ==")

print("\n-- the twelve cells sit where the lanes were, panned by column --")
do
  local M = fresh(1)
  local ids, by_coord = {}, {}
  for id, cell in M.topology.each() do
    if cell.type == "GUST" then
      table.insert(ids, id)
      by_coord[cell.coords[1][1] .. "," .. cell.coords[1][2]] = cell
    end
  end
  check("there are twelve of them", #ids == 12, tostring(#ids))
  check("no SEQ cell is left on the panel", (function()
    for _, cell in M.topology.each() do
      if cell.type == "SEQ" then return false end
    end
    return true
  end)())

  -- the two rows the lanes filled: six on row 7 (cols 6-11), six on row 8
  -- (cols 6-11) -- the same span, one directly above the other.
  local row7, row8 = 0, 0
  for _, id in ipairs(ids) do
    local c = M.topology.get(id)
    if c.coords[1][2] == 7 then row7 = row7 + 1 else row8 = row8 + 1 end
  end
  check("six on row 7, six on row 8", row7 == 6 and row8 == 6,
        string.format("%d/%d", row7, row8))

  -- pan is the whole reason these are laid out by column, so it is worth an
  -- assertion rather than a glance: the outermost pair is at +-0.8 and the
  -- order across the bottom row is strictly left to right.
  local left = by_coord["6,8"]
  local right = by_coord["11,8"]
  check("the leftmost gust is panned hard-ish left", math.abs(left.pan + 0.8) < 1e-9,
        tostring(left.pan))
  check("the rightmost is its mirror", math.abs(right.pan - 0.8) < 1e-9,
        tostring(right.pan))

  local prev = -2
  local ok = true
  for x = 6, 11 do
    local c = by_coord[x .. ",8"]
    if not (c.pan > prev) then ok = false end
    prev = c.pan
  end
  check("pan rises strictly left to right along the bottom row", ok)

  -- the top row now spans the same six columns as the bottom one, so its own
  -- outer pair should land at the same hard-left/hard-right pan.
  local top_left = by_coord["6,7"]
  local top_right = by_coord["11,7"]
  check("the top row's outer pair matches the bottom row's pan",
        math.abs(top_left.pan - left.pan) < 1e-9
        and math.abs(top_right.pan - right.pan) < 1e-9,
        top_left.pan .. "/" .. top_right.pan)

  check("a gust is not a pulse cell", M.topology.PULSE_TYPES.GUST == nil)
end

print("\n-- init pushes every cell's pan, envelope and the shared delay --")
do
  local M = fresh(2)
  M.gust.init()
  check("all twelve pans went out", #CALLS.gust_pan == 12, tostring(#CALLS.gust_pan))
  check("all twelve attacks went out", #CALLS.gust_attack == 12,
        tostring(#CALLS.gust_attack))
  check("all twelve decays went out", #CALLS.gust_decay == 12,
        tostring(#CALLS.gust_decay))
  check("the delay line was pushed once", #CALLS.gust_space == 1,
        tostring(#CALLS.gust_space))
  -- the engine indexes 0-based; twelve cells means 0..11 with none missing.
  local seen = {}
  for _, c in ipairs(CALLS.gust_pan) do seen[c.index] = true end
  local all = true
  for i = 0, 11 do if not seen[i] then all = false end end
  check("indices 0..11, none missing or doubled", all)
end

print("\n-- a press sounds a note --")
do
  local M = fresh(3)
  local ok = M.gust.press("gu.squall")
  check("the press landed", ok == true)
  check("one note went to the engine", #CALLS.gust_note == 1)
  check("at full force", CALLS.gust_note[1].force == 1.0,
        tostring(CALLS.gust_note[1].force))
  check("at the cell's own root", math.abs(CALLS.gust_note[1].hz - 110) < 0.01,
        tostring(CALLS.gust_note[1].hz))

  -- the refractory is short by design (a gust's attack is seconds long and
  -- retriggering a swell is musical) but it is not zero: it is the rail on a
  -- cable looped back into the cell.
  local again = M.gust.press("gu.squall")
  check("an instant re-press is swallowed", again == false)
  check("and sent nothing", #CALLS.gust_note == 1)
  T = T + 0.05
  check("a press after the refractory lands", M.gust.press("gu.squall") == true)
end

print("\n-- the note locks into the global Scale --")
do
  local M = fresh(4)
  -- Pitch up a little, off any scale degree, with Scale on "free": what
  -- comes out is exactly where the knob was put.
  M.state.set_vparam("gu.squall", "pitch", 0.5 + (1 / 24) / 2)  -- +1 semitone
  M.state.global.scale_i = 0
  local free = M.gust.note_semitones("gu.squall")
  check("free tuning passes the offset through", math.abs(free - 13) < 1e-6,
        tostring(free))

  -- minor pentatonic on A: 0 3 5 7 10. one semitone above A2 (12) is 13,
  -- which is not a degree -- it has to be pulled to the nearest one that is.
  M.state.global.scale_i = 2
  local snapped = M.gust.note_semitones("gu.squall")
  local rem = snapped % 12
  local on_scale = false
  for _, d in ipairs(M.grove.SCALES[2]) do if math.abs(rem - d) < 1e-6 then on_scale = true end end
  check("a scale pulls the note onto a degree", on_scale, tostring(snapped))
  check("and it moved from where the knob was", math.abs(snapped - free) > 0.5)

  -- every cell, not just the one that was moved: twelve keys pressed at
  -- random should be twelve notes of one scale, which is the whole point.
  local all_on = true
  for _, id in ipairs(M.gust.each()) do
    local r = M.gust.note_semitones(id) % 12
    local hit = false
    for _, d in ipairs(M.grove.SCALES[2]) do if math.abs(r - d) < 1e-6 then hit = true end end
    if not hit then all_on = false end
  end
  check("all twelve cells land on the scale", all_on)

  -- and a transpose moves the lot.
  CALLS = (function() local c = CALLS; return c end)()
  local before = #CALLS.gust_pitch
  M.state.global.pitch_offset = 5
  M.gust.repush_pitch()
  check("a transpose re-pushes every cell", #CALLS.gust_pitch - before == 12,
        tostring(#CALLS.gust_pitch - before))
end

print("\n-- the envelope knobs, and the global Decay macro --")
do
  local M = fresh(5)
  local base_a = M.gust.attack_seconds("gu.squall")
  local base_d = M.gust.decay_seconds("gu.squall")
  check("attack defaults to the cell's own", math.abs(base_a - 1.4) < 1e-6,
        tostring(base_a))
  check("decay defaults to the cell's own", math.abs(base_d - 6.0) < 1e-6,
        tostring(base_d))
  check("these are slow by design -- both over a second",
        base_a > 1.0 and base_d > 1.0)

  M.state.set_vparam("gu.squall", "attack", 1.0)
  check("the top of the Attack knob is slower still",
        M.gust.attack_seconds("gu.squall") > base_a * 3,
        tostring(M.gust.attack_seconds("gu.squall")))
  M.state.set_vparam("gu.squall", "attack", 0.0)
  check("and the bottom is much faster",
        M.gust.attack_seconds("gu.squall") < base_a / 3,
        tostring(M.gust.attack_seconds("gu.squall")))
  check("but never past the engine's own floor",
        M.gust.attack_seconds("gu.squall") >= M.gust.ATTACK_MIN)

  -- the global Decay macro rides on top of the per-cell knob, exactly as it
  -- does for a voice and a GVOICE cell.
  M.state.global.decay_mult = 1.0
  check("the global Decay macro lengthens it too",
        M.gust.decay_seconds("gu.squall") > base_d,
        tostring(M.gust.decay_seconds("gu.squall")))

  -- and moving state.decay notifies, which is what pushes it at the engine.
  local before = #CALLS.gust_decay
  M.state.decay["gu.haar"] = 0.8
  M.state.notify_decay_change("gu.haar")
  check("a decay change reaches the engine", #CALLS.gust_decay > before)
end

print("\n-- a pulse down a cable sounds one, and it answers --")
do
  local M = fresh(6)
  M.patch.add("d.hob", "gu.whorl", 0.9, false)
  M.patch.add("gu.whorl", "gu.flaw", 0.8, false)
  M.rambler.emit_from("d.hob", 1.0)
  check("the pulse sounded the gust", #CALLS.gust_note == 1)
  check("scaled by the cable's gain", CALLS.gust_note[1].force < 1.0
        and CALLS.gust_note[1].force > 0.7, tostring(CALLS.gust_note[1].force))

  -- the answering pulse is queued, not walked, so it costs a tick like every
  -- other lap on the panel -- and it must not go back down the cable it
  -- arrived on.
  run(M, 0.05)
  check("it answered onward into the next gust", #CALLS.gust_note >= 2,
        tostring(#CALLS.gust_note))
end

print("\n-- gust <-> gust is cross-modulation, both ways --")
do
  local M = fresh(7)
  M.patch.add("gu.sough", "gu.eddy", 0.7, false)
  local into = {}
  for _, c in ipairs(CALLS.patch_add) do
    -- gust_mod is the receiving half; gust_out the sending half.
    if c.dst >= M.bridge.BUS.gust_mod.base then
      into[c.dst - M.bridge.BUS.gust_mod.base] = c.src - M.bridge.BUS.gust_out.base
    end
  end
  local a = M.topology.get("gu.sough").index - 1
  local b = M.topology.get("gu.eddy").index - 1
  check("each one's output lands on the other's mod input",
        into[a] == b and into[b] == a)

  -- one-way means one way, the same as it does for voice<->voice.
  local N = fresh(8)
  N.patch.add("gu.sough", "gu.eddy", 0.7, true)
  local n = 0
  for _, c in ipairs(CALLS.patch_add) do
    if c.dst >= N.bridge.BUS.gust_mod.base then n = n + 1 end
  end
  check("a one-way cable makes one link, not two", n == 1, tostring(n))
end

print("\n-- a gust is heard without a cable, and cabling to Out adds to it --")
do
  local M = fresh(9)
  -- nothing at all is patched, and there is still no Output cable to draw:
  -- the engine pans each gust itself. all this side can assert is that the
  -- pan reached it and that no Output patch synth was invented for it.
  M.gust.init()
  local outs = 0
  for _, c in ipairs(CALLS.patch_add) do
    if c.dst >= M.bridge.BUS.out.base and c.dst < M.bridge.BUS.gust_out.base then
      outs = outs + 1
    end
  end
  check("an unpatched gust needs no Output cable", outs == 0, tostring(outs))

  M.patch.add("gu.flaw", "o.3", 0.8, false)
  local placed = false
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("gust_out", M.topology.get("gu.flaw").index - 1)
       and c.dst == M.bridge.bus("out", M.topology.get("o.3").index) then
      placed = true
    end
  end
  check("but an Output cable still places a second copy", placed)
end

print("\n-- a cable loop through two gusts stays bounded --")
do
  local M = fresh(10)
  -- a ring: a trigger into one gust, that gust into the other, and the other
  -- back to the first. every lap costs a scheduler tick (rambler.post_source
  -- queues rather than walks), and the refractory caps the rest.
  M.patch.add("d.hob", "gu.sough", 1.0, false)
  M.patch.add("gu.sough", "gu.eddy", 1.0, false)
  M.patch.add("gu.eddy", "gu.sough", 1.0, false)
  M.rambler.emit_from("d.hob", 1.0)
  run(M, 2.0)
  check("the ring did not run away", #CALLS.gust_note < 400,
        tostring(#CALLS.gust_note))
  check("but it did keep going round", #CALLS.gust_note > 2,
        tostring(#CALLS.gust_note))
end

print("\n-- the shared delay line clamps to its own range --")
do
  local M = fresh(11)
  M.gust.set_space("delay", 99)
  check("delay time is capped", M.gust.get_space("delay") == M.gust.DELAY_MAX,
        tostring(M.gust.get_space("delay")))
  M.gust.set_space("regen", 1.0)
  check("feedback stops short of unity",
        M.gust.get_space("regen") == M.gust.REGEN_MAX,
        tostring(M.gust.get_space("regen")))
  M.gust.set_space("space", -3)
  check("mix cannot go negative", M.gust.get_space("space") == 0)

  -- and the global page drives all three. they used to sit on the mixer,
  -- back when that page had a fixed eight-row list to fill; the mixer is
  -- built from the patch now (one fader per active output) and a room is not
  -- a channel, so these three moved to where the rest of the patch-wide
  -- numbers already were.
  local before = #CALLS.gust_space
  local rows = 0
  for i = 1, M.gparam.PARAM_COUNT do
    if M.gparam.param(i).key:match("^gust_") then
      rows = rows + 1
      M.gparam.nudge(i, 1, true)
    end
  end
  check("the global page carries all three rows", rows == 3, tostring(rows))
  check("and each pushes the line", #CALLS.gust_space - before == 3,
        tostring(#CALLS.gust_space - before))
  check("and none of them is on the mixer", (function()
    for i = 1, M.mixer.PARAM_COUNT do
      if M.mixer.param(i).key:match("^gust_") then return false end
    end
    return true
  end)(), "a gust_ row is still on the mixer")

  -- the delay row's coarse step is in seconds, so nudging it up from the
  -- default must not blow past the cap or land somewhere unreadable.
  local t = M.gust.get_space("delay")
  check("nudging Delay leaves it in range",
        t >= M.gust.DELAY_MIN and t <= M.gust.DELAY_MAX, tostring(t))
end

print("\n-- the page is the same object every other cell type exposes --")
do
  local M = fresh(12)
  local page = M.cellparam.page("gu.buffet")
  check("cellparam hands out the gust page", page == M.gust)
  check("six rows, one screen", page.PARAM_COUNT == 6, tostring(page.PARAM_COUNT))
  for i = 1, page.PARAM_COUNT do
    local p = page.param(i)
    local v = p.get("gu.buffet")
    check("row " .. i .. " (" .. p.label .. ") reads 0..1 and prints",
          type(v) == "number" and v >= 0 and v <= 1 and type(p.text("gu.buffet")) == "string")
  end
  local p = page.nudge("gu.buffet", 1, 0.1)
  check("nudging row 1 moves it and pushes", p.key == "pitch" and #CALLS.gust_pitch > 0)
end

report()
