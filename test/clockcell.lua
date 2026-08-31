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
  -- clockcell.ratio(id) maps state.character (0..1) onto RATIOS by
  -- floor(char * 8 + 0.5); pick a char comfortably inside the band for each
  -- ratio's index so float rounding never lands on a neighbour by accident.
  local RATIOS = {0.125, 0.25, 1/3, 0.5, 1, 2, 3, 4, 8}
  for i, r in ipairs(RATIOS) do
    if math.abs(r - target) < 1e-9 then return (i - 1) / 8 end
  end
  error("no such ratio: " .. tostring(target))
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
