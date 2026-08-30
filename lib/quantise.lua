-- quantise.lua
-- the Weather groove machine (§4.1 E2): *when* a pulse is allowed to land.
--
-- rambler.lua decides when a gait wants to speak. this decides when it
-- actually does, and one knob sweeps the whole continuum:
--
--   W = 0        every emission snaps to a straight grid line and the patch
--                locks into a groove, whatever rates the cells free-run at
--   W 0 -> 0.5   swing ramps in, delaying the off-grid positions, until at
--                0.5 the off-beats sit as late as they are ever going to
--   W 0.5 -> 1   the snap loosens and jitter grows in its place, until at 1
--                nothing is held at all and the patch is rain in a forest
--
-- the grid is per cell, not global: each one is quantised to the coarsest of
-- 8th / 16th / 32nd / 64th that still fits inside one cycle of its own rate,
-- so a Shuck lands on 8ths and a Gabriel on 64ths and both stay in time with
-- each other. a burst overrides that and is triggered on the beat, with its
-- ratchet spaced on a subdivision so the whole flam sits on grid lines too.
--
-- snapping is *forward* to the next grid line, never back to the nearest.
-- there is no going back to the nearest: a wrap is only known about once it
-- has happened, and firing "the nearest line" when that line is behind you
-- means firing off the grid, which is the one thing this is for. the cost is
-- latency of up to one grid interval, and since the grid is never coarser
-- than the cell's own cycle, that never costs the cell a pulse -- the
-- pattern shifts onto the grid and stays there. the CAPTURE window below is
-- the exception that makes an already-on-grid gait (a rooted metric one,
-- say) fire immediately rather than being pushed a whole grid late.

local state = wl("state")

local quantise = {}

-- the four divisions §4.1 asks for, in beats, coarsest first.
quantise.DIVISIONS = {0.5, 0.25, 0.125, 0.0625}

local DIVISION_NAMES = {
  [1]      = "beat",
  [0.5]    = "1/8",
  [0.25]   = "1/16",
  [0.125]  = "1/32",
  [0.0625] = "1/64",
}

-- a wrap is detected at the first tick at or after it happened, so a line up
-- to this far *behind* `now` still counts as one we are on, and the emission
-- goes out immediately rather than waiting a whole grid interval. it is one
-- scheduler tick's worth (rambler.TICK is 2ms) and no more -- the window is
-- the detection lag, and anything wider than that lag is itself a source of
-- off-grid emissions rather than a cure for them. backward only, for the
-- same reason: a line ahead of us is always waited for, however close.
quantise.CAPTURE = 0.0025

-- swing is a feel on the 8ths whatever grid a cell happens to be on, so it
-- is applied as a warp of the beat line in these units rather than as a
-- displacement of every nth line -- a cell on 32nds rides the swung 8th it
-- sits inside instead of swinging against it, and beats never move at all.
quantise.SWING_UNIT = 0.5

-- how far the pair of 8ths is stretched at full swing. 0.5 makes the first
-- of the pair one and a half units long and the second half of one -- a 3:1
-- long-short, about as hard as swing goes. the triplet 2:1 feel sits at two
-- thirds of the knob.
quantise.SWING_MAX = 0.5

-- the widest random displacement at full chaos, also in grid units.
quantise.JITTER_MAX = 0.9

-- macro readings ------------------------------------------------------------

function quantise.weather()
  return util.clamp(state.global.weather or 0, 0, 1)
end

-- 0 at W=0, 1 from W=0.5 up. swing is fully in by the halfway point and then
-- stays in while chaos takes over dissolving the grid it swings against.
function quantise.swing()
  return util.clamp(quantise.weather() / 0.5, 0, 1)
end

-- 0 up to W=0.5, then 0..1 across the top half.
function quantise.chaos()
  return util.clamp((quantise.weather() - 0.5) / 0.5, 0, 1)
end

function quantise.spb()
  return 60 / (clock.get_tempo() or 120)
end

-- grid selection ------------------------------------------------------------

-- the coarsest division that still fits inside one cycle of a cell running
-- at this period (seconds). nil/zero period -- a reactive gait, which has no
-- rate of its own -- gets 16ths.
function quantise.grid_beats(period)
  if not period or period <= 0 then return 0.25 end
  local pb = period / quantise.spb()
  for _, d in ipairs(quantise.DIVISIONS) do
    if d <= pb + 1e-9 then return d end
  end
  return quantise.DIVISIONS[#quantise.DIVISIONS]
end

function quantise.name(gb)
  return DIVISION_NAMES[gb] or string.format("%.3f", gb)
end

-- the subdivision a ratchet of n taps sits on, so a burst triggered on the
-- beat has every tap of its flam on a grid line and finishes inside that
-- beat. §4.1: "the burst must be triggered on beat".
function quantise.ratchet_gap(n)
  local gb = 0.25
  while gb > 0.0625 and gb * math.max(n - 1, 1) >= 1 do gb = gb / 2 end
  return gb
end

-- the grid itself ------------------------------------------------------------

-- swing, as a monotonic warp of the beat line: each pair of 8ths is
-- stretched and then squeezed by the same amount, so the off-8th lands late,
-- the beat it belongs to does not move, and every finer division inside that
-- 8th rides along with it rather than fighting it. warp(x) >= x everywhere,
-- with equality on the beats -- which is what lets next_line below walk
-- forward through warped positions the same way it would through plain ones.
function quantise.warp(beats, sw)
  local s = sw * quantise.SWING_MAX
  if s <= 0 then return beats end
  local u = quantise.SWING_UNIT
  local x = beats / u
  local k = math.floor(x / 2)
  local r = x - 2 * k
  local out
  if r <= 1 then
    out = (2 * k) + r * (1 + s)
  else
    out = (2 * k) + 1 + s + (r - 1) * (1 - s)
  end
  return out * u
end

-- the first swung line at or after `beats`, less the capture window. the
-- scan starts far enough back to cover the widest the warp can push a line
-- late, since a line whose unswung position is behind us may have been swung
-- in front of us.
function quantise.next_line(beats, gb, sw, capture_beats)
  local back = math.ceil(quantise.SWING_UNIT * quantise.SWING_MAX / gb) + 1
  local i = math.floor(beats / gb) - back
  for _ = 0, back + 8 do
    local p = quantise.warp(i * gb, sw)
    if p >= beats - (capture_beats or 0) then return p end
    i = i + 1
  end
  return beats
end

-- `now` is when the cell wanted to speak; the return is when it may. never
-- earlier than `now` -- there is no scheduling into the past.
--
-- `period` is the cell's own cycle length in seconds, used to pick its grid;
-- `gb_override` forces a grid instead (burst passes a whole beat).
function quantise.snap(now, period, gb_override)
  local chaos = quantise.chaos()
  if chaos >= 1 then return now end

  local gb = gb_override or quantise.grid_beats(period)
  local spb = quantise.spb()
  local beats = clock.get_beats()
  local line = quantise.next_line(beats, gb, quantise.swing(),
                                  quantise.CAPTURE / spb)
  local target = now + (line - beats) * spb

  -- past halfway the grid stops being a wall and becomes a suggestion: the
  -- emission is pulled back toward the time the cell actually wanted, and a
  -- widening random displacement is laid on top. squared, so the groove
  -- survives a little way past 0.5 before it starts coming apart.
  local t = now + (target - now) * (1 - chaos)
  if chaos > 0 then
    local j = chaos * chaos * quantise.JITTER_MAX * gb * spb
    t = t + (math.random() * 2 - 1) * j
  end

  if t < now then t = now end
  return t
end

-- §5.2's bottom-line readout: four characters saying where Weather has this.
function quantise.tag()
  local c = quantise.chaos()
  if c > 0 then
    if c >= 0.995 then return "rain" end
    return string.format("ls%02.0f", c * 100)
  end
  local sw = quantise.swing()
  if sw <= 0.005 then return "lock" end
  return string.format("sw%02.0f", sw * 100)
end

return quantise
