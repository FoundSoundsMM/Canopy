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
local patch    = wl("patch")

local clockcell = {}

-- §2.9b Mode. a clock cell has a second thing it can be: not a clock at all,
-- but a trigger that is simply always up.
--
-- the reason it lives here rather than as a family of its own is that this
-- is what a clock cell already is with the division taken away. everything
-- on the panel that makes a sound is struck: a pulse arrives, the sound
-- swells and falls, and to hold a drone you have to keep striking it, which
-- is a rhythm whether you wanted one or not. High is the missing half of
-- that -- cable one to a modal voice and the bank rings continuously, to a
-- sample cell and the recording plays on rather than swelling and going, to
-- a gust and the swell arrives and stays. an exciter needs nothing from this
-- at all: it free-runs unless a trigger cell gates it (exciter.lua's
-- GATING_TYPES), so a clock cell has always left it sounding.
--
-- what a High cell does NOT do is fire. it emits no pulses at all -- tick()
-- skips it -- because a gate that also clocked would be two things, and the
-- Ratio knob it would clock at is exactly the thing High is for turning off.
clockcell.MODES = {"Clock", "High"}

-- stored as a per-cell vparam rather than as a second `character`: character
-- is the Ratio knob and is read by five other files through
-- state.get_character, and a mode is a switch rather than a value on a
-- knob.
function clockcell.is_high(id)
  return state.get_vparam(id, "high", 0) >= 0.5
end

function clockcell.mode_name(id)
  return clockcell.is_high(id) and "High" or "Clock"
end

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

-- the gates -------------------------------------------------------------------
-- what a High cell actually does. it has no pulse to send, so instead it
-- holds every cell it is cabled to open, and lets go when the cable is
-- pulled or the mode goes back to Clock.
--
-- kept as a set of (clock cell -> target) pairs rather than recomputed at the
-- point of use, for the one reason that matters here: a gate is a level and
-- not an event, so what the engine has to be told is the CHANGES. re-deriving
-- "everything a High cell touches" and pushing it every time the graph moves
-- would send a hold=1 down the same cable a dozen times over an evening's
-- patching, and -- worse -- would never send the hold=0 for a cable that no
-- longer exists to be looked at.
--
-- two High cells cabled to one voice is one held voice, not two: `held`
-- counts the cells holding each target, so letting go of one leaves the
-- other's grip on it intact.
local held = {}    -- target id -> how many High cells are holding it

local function want_gates()
  local want = {}
  for _, id in ipairs(order) do
    if clockcell.is_high(id) then
      for _, edge in ipairs(patch.edges_at(id)) do
        local other = patch.other(edge, id)
        -- a High cell cabled to another clock cell holds nothing: a clock
        -- cell is a source, and there is no sound in it to hold open.
        local cell = topology.get(other)
        if cell and cell.type ~= "C" then
          want[other] = (want[other] or 0) + 1
        end
      end
    end
  end
  return want
end

-- re-derive every gate from the patch graph and the modes, and send only the
-- targets that crossed between held and not held. called whenever either of
-- those two things moves: patch.on_change below, and set_high.
function clockcell.resync_gates()
  local want = want_gates()
  local dispatch = wl("dispatch")
  for id in pairs(held) do
    if not want[id] then dispatch.set_gate(id, false) end
  end
  for id in pairs(want) do
    if not held[id] then dispatch.set_gate(id, true) end
  end
  held = want
end

function clockcell.holds(id)
  return (held[id] or 0) > 0
end

function clockcell.set_high(id, on)
  local c = cells[id]
  if not c then return end
  if clockcell.is_high(id) == (on and true or false) then return end
  state.set_vparam(id, "high", on and 1 or 0)
  -- leaving High and coming back to Clock has to re-seed the beat position,
  -- or the first tick after it fires the whole stretch it was held for as a
  -- burst of catch-up pulses.
  c.abs = nil
  clockcell.resync_gates()
end

patch.on_change(function() clockcell.resync_gates() end)

-- called from rambler.tick, on the far side of the Still check -- a clock
-- cell freezes with everything else rather than drifting out from under it.
function clockcell.tick(now)
  local rambler = wl("rambler")
  for _, id in ipairs(order) do
    local c = cells[id]
    -- a High cell is not a clock. it sends nothing, and its beat position is
    -- forgotten rather than tracked, so switching back to Clock starts from
    -- wherever the transport is instead of firing what it "missed".
    if clockcell.is_high(id) then
      c.abs = nil
      goto continue
    end
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
    ::continue::
  end
end

-- read/control surface -------------------------------------------------------

-- §5.1: a Clock cell flashes on its own pulse. a High cell has no pulse to
-- flash on and is not idle either -- it is doing its one job continuously --
-- so it sits lit instead. that is the whole reading: on the panel, a clock
-- blinks and a gate is simply on.
function clockcell.level(id, base)
  if clockcell.is_high(id) then return 12 end
  return state.flash_level(id, base)
end

function clockcell.info(id)
  local c = cells[id]
  if not c then return nil end
  if clockcell.is_high(id) then return {param = "high", high = true} end
  local _, text = clockcell.ratio(id)
  return {param = text, high = false}
end

function clockcell.get(id)
  return cells[id]
end

return clockcell
