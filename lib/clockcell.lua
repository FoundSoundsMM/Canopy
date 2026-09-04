-- clockcell.lua
-- the new Clock cells (topology.lua §2.9, type "C"). Climate used to live
-- under this letter; it's gone, and this is unrelated to it in every way
-- except the reused letter.
--
-- a clock cell has no phase and no gait bank -- deliberately not built on
-- rambler.lua's D-cell machinery, which would wrongly inherit the 8-gait
-- K1+E2 cycle and Kuramoto coupling neither of which apply here. it just
-- tracks the norns transport directly (clock.get_beats()) at a multiple or
-- division of it (Ratio, the one knob, E2) and calls rambler.emit_from on
-- every crossing -- the same "one door every pulse leaves by" everything
-- else on the panel uses, so fan-out/inbox-deferral are correct for free.
--
-- dependency note: rambler.lua requires this file at load (its tick() needs
-- a call site here, exactly where climate.tick used to be), so this one must
-- not require rambler at load -- fetched lazily inside tick(), same as
-- tm.lua does with grove/rambler.

local topology = wl("topology")
local state    = wl("state")

local clockcell = {}

-- E2 (Ratio): a division or multiplication of the master clock, log-ish
-- spaced around "1 x beat" so both directions get a fair share of the knob.
--
-- the slow end used to stop at 1/8 -- one pulse every eight beats, which at
-- 120 BPM is a pulse every four seconds. that is nowhere near slow enough for
-- what these cells are best at: a clock that fires once a bar is a rhythm,
-- and a clock that fires once every thirty-two bars is an event you build a
-- piece around. so it runs down to 1/128 now, which is one pulse every
-- sixty-four seconds at 120 BPM, and the whole span reads in bars as well as
-- in beats -- 1/4 is a bar in four, 1/16 is four bars, 1/64 is sixteen.
--
-- the fast end is unchanged. above 8x a clock cell stops being a clock and
-- becomes a buzz, and there are eight free-running gaits (§2.3) for that.
-- one more thing the low end costs: the list is no longer symmetric, and a
-- knob that maps evenly across an asymmetric list does not put 1x at its
-- centre. thirteen divisions and five multiples would leave the default (a
-- fresh cell sits at 0.5) on 1/6, which is not a default anybody wants.
--
-- so the knob is split at the middle instead of spread evenly: the bottom
-- half walks the divisions, the top half walks the multiples, and 1x sits
-- exactly on the centre detent whatever is on either side of it. that is
-- also the better feel -- "slower" is one direction and "faster" is the
-- other, from a middle you can find without looking.
local RATIOS = {
  {1/128, "1/128"}, {1/96, "1/96"}, {1/64, "1/64"}, {1/48, "1/48"},
  {1/32, "1/32"},   {1/24, "1/24"}, {1/16, "1/16"}, {1/12, "1/12"},
  {1/8, "1/8"},     {1/6, "1/6"},   {1/4, "1/4"},   {1/3, "1/3"},
  {1/2, "1/2"},
  {1, "1 x"},                      -- UNITY, the centre of the knob
  {2, "2 x"},       {3, "3 x"},     {4, "4 x"},     {6, "6 x"}, {8, "8 x"},
}

local UNITY = 14   -- index of {1, "1 x"} above

clockcell.RATIOS = RATIOS
clockcell.UNITY = UNITY

-- 0..1 knob -> index into RATIOS, with 1x on the middle detent.
function clockcell.index_for(v)
  v = util.clamp(v or 0.5, 0, 1)
  if v <= 0.5 then
    return util.clamp(math.floor(1 + (v * 2) * (UNITY - 1) + 0.5), 1, UNITY)
  end
  return util.clamp(
    math.floor(UNITY + ((v - 0.5) * 2) * (#RATIOS - UNITY) + 0.5), UNITY, #RATIOS)
end

-- the inverse, at the centre of that index's band -- what a test or a preset
-- writes into state.character to land on a named ratio.
function clockcell.char_for_index(i)
  i = util.clamp(i, 1, #RATIOS)
  if i <= UNITY then return (i - 1) / (2 * (UNITY - 1)) end
  return 0.5 + (i - UNITY) / (2 * (#RATIOS - UNITY))
end

function clockcell.char_for_ratio(r)
  for i, entry in ipairs(RATIOS) do
    if math.abs(entry[1] - r) < 1e-9 then return clockcell.char_for_index(i) end
  end
  return nil
end

local cells = {}   -- id -> record
local order = {}   -- ids, stable iteration order

local function char(c)
  return state.get_character(c.id, c.cell, 0, 1)
end

function clockcell.ratio(id)
  local c = cells[id]
  if not c then return 1, "1 x" end
  local entry = RATIOS[clockcell.index_for(char(c))]
  return entry[1], entry[2]
end

for id, cell in topology.each() do
  if cell.type == "C" then
    cells[id] = {id = id, cell = cell, abs = nil, flash = -1}
    table.insert(order, id)
  end
end

-- §4.3 an external transport Start: forget where each cell was in the beat,
-- so tick() re-seeds it from the clock silently. without this a stop of
-- exactly eight beats sits just inside the catch-up window below and fires
-- four pulses at once on resume.
function clockcell.resync()
  for _, id in ipairs(order) do
    cells[id].abs = nil
  end
end

-- called from rambler.tick, on the far side of the Still check -- a clock
-- cell freezes with everything else rather than drifting out from under it.
function clockcell.tick(now)
  local rambler = wl("rambler")
  for _, id in ipairs(order) do
    local c = cells[id]
    local ratio = clockcell.ratio(id)
    local pos = clock.get_beats() * ratio
    local cyc = math.floor(pos)
    -- first tick, or the ratio just changed under us: resync silently rather
    -- than firing a burst of catch-up pulses.
    if c.abs == nil or math.abs(cyc - c.abs) > 8 then c.abs = cyc end
    local fired = 0
    while c.abs < cyc and fired < 4 do
      c.abs = c.abs + 1
      c.flash = now
      state.flash(id, 1)
      rambler.emit_from(id, 1.0)
      fired = fired + 1
    end
    c.abs = cyc
  end
end

-- read/control surface -------------------------------------------------------

function clockcell.level(id, base)
  return state.flash_level(id, base)
end

function clockcell.info(id)
  local c = cells[id]
  if not c then return nil end
  local _, text = clockcell.ratio(id)
  return {param = text}
end

function clockcell.get(id)
  return cells[id]
end

return clockcell
