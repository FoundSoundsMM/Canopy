-- topology.lua §2.9 / lib/clockcell.lua: the four Clock cells. Climate is
-- gone and this is unrelated to it in every way except the reused letter --
-- a Clock cell has no gait bank and no phase of its own, the same "no free
-- clock, only moves on the transport" shape test/tm.lua's TM cells have,
-- except a Clock cell's clock is the master transport rather than an
-- incoming pulse: it tracks clock.get_beats() directly at a multiple or
-- division of it (Ratio, the one knob, E2) and fires through rambler.emit_from
-- on every crossing. that they're registered right; that a Clock cell fires
-- at the expected multiple/division of the master clock; that a ratio change
-- takes effect live, with no explicit push needed; and that a Clock cell is
-- a pure source, never a pulse target -- it is deliberately not a member of
-- topology.PULSE_TYPES.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local TOLL, KNELL, CHIME, PEAL = "clk.toll", "clk.knell", "clk.chime", "clk.peal"

local function ratio_char(target)
  -- clockcell owns the ratio list and the mapping onto it (the knob is split
  -- at its centre so 1x sits on the middle detent, see clockcell.index_for),
  -- so ask it rather than keeping a second copy of both here.
  local c = wl("clockcell").char_for_ratio(target)
  if c == nil then error("no such ratio: " .. tostring(target)) end
  return c
end

print("\n-- four Clock cells, registered right --")
do
  local M = fresh(1)
  local ids = {}
  for id, cell in M.topology.each() do
    if cell.type == "C" then table.insert(ids, id) end
  end
  check("four of them", #ids == 4, "#" .. #ids)
  local at = {}
  for _, id in ipairs(ids) do
    local c = M.topology.get(id)
    at[c.coords[1][1] .. "," .. c.coords[1][2]] = id
  end
  check("Toll (6,4) and Peal (11,5) are counterparts",
        at["6,4"] == TOLL and at["11,5"] == PEAL
        and M.topology.get(TOLL).counterpart == PEAL
        and M.topology.get(PEAL).counterpart == TOLL)
  check("Knell (11,4) and Chime (6,5) are counterparts",
        at["11,4"] == KNELL and at["6,5"] == CHIME
        and M.topology.get(KNELL).counterpart == CHIME
        and M.topology.get(CHIME).counterpart == KNELL)
  check("a Clock cell is a pure source, never a pulse target",
        M.topology.PULSE_TYPES.C == nil and
        M.topology.is_pulse_cell(M.topology.get(TOLL)) == false)
end

print("\n-- Ratio (E2): default is 1x beat --")
do
  local M = fresh(1)
  local ratio, text = M.clockcell.ratio(TOLL)
  check("0.5 (the character default) reads 1x", ratio == 1 and text == "1 x",
        tostring(ratio) .. " " .. tostring(text))
end

print("\n-- a Clock cell fires at the expected multiple of the master clock --")
do
  -- 120bpm (the harness's TEMPO): a beat is 0.5s. at ratio 1x, a crossing
  -- happens once a beat, so 10s of transport is exactly 20 fires.
  local M = fresh(1)
  M.patch.add(TOLL, "oak", 1.0)
  run(M, 10)
  check("1x: 10s of transport is 20 fires", #CALLS.strike == 20,
        "got " .. #CALLS.strike)
end

print("\n-- and at a division of it --")
do
  -- 1/8 x beat: a crossing every 8 beats = every 4s at 120bpm. 40s is 10.
  local M = fresh(1)
  M.patch.add(TOLL, "oak", 1.0)
  M.state.character[TOLL] = ratio_char(0.125)
  local ratio = M.clockcell.ratio(TOLL)
  check("character maps to 1/8 x", ratio == 0.125, tostring(ratio))
  run(M, 40)
  check("1/8x: 40s of transport is 10 fires", #CALLS.strike == 10,
        "got " .. #CALLS.strike)
end

print("\n-- and at a multiple of it --")
do
  -- 8x beat: a crossing every 1/8 beat = every 0.0625s at 120bpm. 10s is 160.
  local M = fresh(1)
  M.patch.add(TOLL, "oak", 1.0)
  M.state.character[TOLL] = ratio_char(8)
  local ratio = M.clockcell.ratio(TOLL)
  check("character maps to 8x", ratio == 8, tostring(ratio))
  run(M, 10)
  check("8x: 10s of transport is 160 fires", #CALLS.strike == 160,
        "got " .. #CALLS.strike)
end

print("\n-- a ratio change takes effect live, with no explicit push --")
do
  -- 5.01s / 4.99s rather than an even 5/5 split: an even split lands the
  -- window boundary exactly on a beat crossing, where float accumulation
  -- over 2500 ticks can tip it either side of the line; nudging it clear of
  -- the boundary keeps the count deterministic without changing what's
  -- actually being tested.
  local M = fresh(1)
  M.patch.add(TOLL, "oak", 1.0)
  run(M, 5.01)                             -- 1x for ~5s -> 10 fires
  local before = #CALLS.strike
  check("1x for ~5s is 10 fires", before == 10, "got " .. before)

  M.state.character[TOLL] = ratio_char(8)  -- jump straight to 8x
  run(M, 4.99)                             -- 8x for ~5s -> 80 more
  local after = #CALLS.strike - before
  check("8x for another ~5s adds 80 more, immediately", after == 80,
        "got " .. after)
end

print("\n-- each Clock cell tracks the transport independently --")
do
  local M = fresh(1)
  M.patch.add(TOLL, "oak", 1.0)
  M.patch.add(KNELL, "rowan", 1.0)
  M.state.character[KNELL] = ratio_char(2)   -- twice Toll's default rate
  run(M, 10)
  local toll_hits, knell_hits = 0, 0
  for _, s in ipairs(CALLS.strike) do
    if s.voice == 0 then toll_hits = toll_hits + 1 end
    if s.voice == 3 then knell_hits = knell_hits + 1 end
  end
  check("Toll at 1x: 20 in 10s", toll_hits == 20, "got " .. toll_hits)
  check("Knell at 2x: 40 in 10s, independently", knell_hits == 40, "got " .. knell_hits)
end

print("\n-- info() and level() read out cleanly --")
do
  local M = fresh(1)
  local info = M.clockcell.info(TOLL)
  check("info names the ratio", info.param == "1 x", tostring(info.param))
  check("info returns nil for a non-Clock id", M.clockcell.info("oak") == nil)
  check("level() is a legal 0..15 base without erroring",
        M.clockcell.level(TOLL, 4) >= 0 and M.clockcell.level(TOLL, 4) <= 15)
end

-- §2.9b Mode: High ------------------------------------------------------------

print("\n-- set High, a clock cell stops clocking and starts holding --")
do
  local M = fresh(1)
  local RAIN = "smp.rain"
  check("a fresh cell is a clock", M.clockcell.is_high(TOLL) == false)

  M.patch.add(TOLL, RAIN, 1.0)
  run(M, 4)
  check("as a clock it plays the sample over and over", #CALLS.smp_note > 1,
        tostring(#CALLS.smp_note))
  check("and holds nothing", #CALLS.smp_hold == 0, tostring(#CALLS.smp_hold))

  local notes = #CALLS.smp_note
  M.clockcell.set_high(TOLL, true)
  check("switching to High holds the cell it is cabled to",
        #CALLS.smp_hold == 1 and CALLS.smp_hold[1].on == 1,
        tostring(#CALLS.smp_hold))
  run(M, 8)
  check("and it stops firing entirely", #CALLS.smp_note == notes,
        "grew by " .. (#CALLS.smp_note - notes))
  check("the panel shows it lit rather than blinking",
        M.clockcell.level(TOLL, 2) == 12, tostring(M.clockcell.level(TOLL, 2)))
  check("and its readout says so", M.clockcell.info(TOLL).param == "high",
        M.clockcell.info(TOLL).param)

  -- letting go, three ways: the mode, the cable, and a clear.
  M.clockcell.set_high(TOLL, false)
  check("back to Clock, it lets go", #CALLS.smp_hold == 2
        and CALLS.smp_hold[2].on == 0, tostring(#CALLS.smp_hold))
  run(M, 4)
  check("and clocks again", #CALLS.smp_note > notes)

  M.clockcell.set_high(TOLL, true)
  M.patch.remove(TOLL, RAIN)
  check("pulling the cable lets go too",
        CALLS.smp_hold[#CALLS.smp_hold].on == 0,
        tostring(CALLS.smp_hold[#CALLS.smp_hold].on))
end

print("\n-- a High cell holds whatever family is at the other end --")
do
  local M = fresh(2)
  M.clockcell.set_high(TOLL, true)

  M.patch.add(TOLL, "oak", 1.0)
  check("a modal voice", #CALLS.voice_hold == 1 and CALLS.voice_hold[1].on == 1,
        tostring(#CALLS.voice_hold))
  M.patch.add(TOLL, "gu.gale", 1.0)
  check("a gust", #CALLS.gust_hold == 1 and CALLS.gust_hold[1].on == 1,
        tostring(#CALLS.gust_hold))
  M.patch.add(TOLL, "gv.yaffle", 1.0)
  check("a drum", #CALLS.g_hold == 1 and CALLS.g_hold[1].on == 1,
        tostring(#CALLS.g_hold))

  -- and the families with no envelope to hold are silently skipped rather
  -- than erroring: a field takes a note, a register takes a trigger.
  local before = #CALLS.voice_hold + #CALLS.gust_hold + #CALLS.g_hold
                 + #CALLS.smp_hold
  M.patch.add(TOLL, "cuckoo", 1.0)
  M.patch.add(TOLL, "tm.stitch", 1.0)
  check("a field and a register are held by nothing",
        #CALLS.voice_hold + #CALLS.gust_hold + #CALLS.g_hold
        + #CALLS.smp_hold == before)

  M.patch.clear()
  check("and clearing the patch lets go of all three",
        CALLS.voice_hold[#CALLS.voice_hold].on == 0
        and CALLS.gust_hold[#CALLS.gust_hold].on == 0
        and CALLS.g_hold[#CALLS.g_hold].on == 0)
end

print("\n-- two High cells on one target is one grip, not two --")
do
  local M = fresh(3)
  M.clockcell.set_high(TOLL, true)
  M.clockcell.set_high(KNELL, true)
  M.patch.add(TOLL, "oak", 1.0)
  M.patch.add(KNELL, "oak", 1.0)
  check("the second one sends nothing new", #CALLS.voice_hold == 1,
        tostring(#CALLS.voice_hold))
  M.clockcell.set_high(TOLL, false)
  check("and letting go of one does not release the voice",
        #CALLS.voice_hold == 1, tostring(#CALLS.voice_hold))
  M.clockcell.set_high(KNELL, false)
  check("only the last one does", #CALLS.voice_hold == 2
        and CALLS.voice_hold[2].on == 0, tostring(#CALLS.voice_hold))
end

print("\n-- the Mode row on the cell page is the switch --")
do
  local M = fresh(4)
  local page = M.cellparam.page(TOLL)
  check("the clock page has two rows now", page.PARAM_COUNT == 2,
        tostring(page.PARAM_COUNT))
  local mode = page.PARAMS[2]
  check("the second is Mode", mode.label == "Mode", tostring(mode.label))
  check("reading clock", mode.text(TOLL) == "clock", mode.text(TOLL))
  mode.set(TOLL, 1)
  check("setting it flips the cell", M.clockcell.is_high(TOLL) == true)
  check("and the row says so", mode.text(TOLL) == "high", mode.text(TOLL))
  mode.set(TOLL, 0)
  check("and back", M.clockcell.is_high(TOLL) == false)
end

print("\n-- Still freezes it, same as everything else --")
do
  local M = fresh(1)
  M.patch.add(TOLL, "oak", 1.0)
  run(M, 5)
  local before = #CALLS.strike
  M.state.global.still = true
  run(M, 5)
  check("nothing fires while Still", #CALLS.strike == before,
        "grew by " .. (#CALLS.strike - before))
  M.state.global.still = false
  run(M, 5)
  check("and picks up again after it", #CALLS.strike > before)
end

report()
