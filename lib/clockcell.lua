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

-- E2 (Ratio): a small integer division/multiplication of the master clock,
-- log-ish spaced around "1 x beat" so both directions get a fair share of
-- the knob.
local RATIOS = {
  {1/8, "1/8 x"}, {1/4, "1/4 x"}, {1/3, "1/3 x"}, {1/2, "1/2 x"}, {1, "1 x"},
  {2, "2 x"}, {3, "3 x"}, {4, "4 x"}, {8, "8 x"},
}

local cells = {}   -- id -> record
local order = {}   -- ids, stable iteration order

local function char(c)
  return state.get_character(c.id, c.cell, 0, 1)
end

function clockcell.ratio(id)
  local c = cells[id]
  if not c then return 1, "1 x" end
  local i = util.clamp(math.floor(char(c) * (#RATIOS - 1) + 0.5), 0, #RATIOS - 1) + 1
  return RATIOS[i][1], RATIOS[i][2]
end

for id, cell in topology.each() do
  if cell.type == "C" then
    cells[id] = {id = id, cell = cell, abs = nil, flash = -1}
    table.insert(order, id)
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
