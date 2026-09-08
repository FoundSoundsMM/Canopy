-- blend.lua
-- the page between the gusts and the mixer: one fader that leans the
-- instrument's own struck voices toward their percussion half or their
-- tonal half, and two plain volume knobs for the two families that sit
-- outside that argument -- the gusts, which are drones rather than notes,
-- and the samples, which are recordings rather than a synth at all.
--
-- it sits here, upstream of the mixer, rather than with the master pages
-- past it, because what it moves is not a channel. like a cell's own Level
-- knob, it changes what a source hands the patch cables in the first
-- place, not what the cables deliver once they land -- exactly the
-- argument the gusts page (§2.11b) already makes for its own family, run
-- here across two families instead of one.
--
-- Tilt ------------------------------------------------------------------
-- "percussion" is the six pinged/noise drums (§2.7b, GVOICE) and the four
-- modal voices (§2.2) -- struck, decaying, made of an attack and a
-- resonance. "tonal" is the FM and VA pair (§2.13) -- held tones built on
-- an oscillator. a gust is neither (it routes and drones on its own
-- schedule, not a note's) and a sample is not a voice at all, which is why
-- both keep their own separate fader below rather than a side of this one.
--
-- centre is 0.5 and is even: every cell at its own knob's level, untouched.
-- above centre the percussion multiplier slides to zero at the top; below
-- centre the tonal one slides to zero at the bottom. each half only ever
-- touches its own side -- there is no "louder" on this fader, only "this
-- side or that side gives way" -- so leaning all the way over does not also
-- turn the far side up.
local state = wl("state")

local blend = {}

function blend.tilt()
  return state.global.mix_tilt or 0.5
end

function blend.set_tilt(v)
  state.global.mix_tilt = util.clamp(v, 0, 1)
  return state.global.mix_tilt
end

-- folded into gvoice.amp and voice.amp: 1 from centre down to the bottom --
-- the tonal side giving way is none of this side's business -- sliding to 0
-- above it.
function blend.perc_mult()
  return util.clamp(1 - math.max(0, (blend.tilt() - 0.5) * 2), 0, 1)
end

-- the FM/VA pair's copy of the above, folded into synth.lua's level row.
function blend.tonal_mult()
  return util.clamp(1 - math.max(0, (0.5 - blend.tilt()) * 2), 0, 1)
end

-- moving the fader has to reach cells that are already sounding, the same
-- reason a gust's own Level macro re-pushes its family (gust.push_key)
-- rather than waiting for the next per-cell knob touch to carry the new
-- number.
function blend.repush_tilt()
  wl("gvoice").push_key("level")
  wl("voice").push_key("level")
  wl("synth").push_level()
end

-- Gusts / Samples ---------------------------------------------------------
-- the gusts already have a family Level fader of their own (§2.11b,
-- gust.macro("level")) -- this row is that same number, not a second one
-- stacked on top of it, reachable here for the same reason the master
-- level is reachable from every screen: it is one thing, and it is useful
-- in more than one place.
--
-- the samples have no family fader yet, so this page is where one starts.
-- unlike the gusts' Level, which doubles as one of several offsets a knob
-- can ride (gust.lua's MACRO_OVER), a sample's own Level knob carries
-- nothing else, so its family fader can be the plain thing it looks like:
-- a linear volume from silent to unity, nothing hiding in the bottom half.

local COARSE, FINE = 1 / 80, 1 / 500

blend.PARAMS = {
  {
    key = "mix_tilt", label = "Tilt", glyph = "crossfade",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = blend.tilt, set = blend.set_tilt,
    text = function()
      local t = blend.tilt()
      -- a fine step is 1/500; anything closer than that to centre still
      -- reads as "even" rather than as a x0.998 nobody asked to see.
      if math.abs(t - 0.5) < FINE then return "even" end
      if t > 0.5 then return string.format("perc x%.2f", blend.perc_mult()) end
      return string.format("tonal x%.2f", blend.tonal_mult())
    end,
    frac = blend.tilt,
    push = blend.repush_tilt,
  },
  {
    key = "gust_level", label = "Gusts", glyph = "fader",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return wl("gust").macro("level") end,
    set = function(v) wl("gust").set_macro("level", v) end,
    text = function()
      local m = wl("gust").macro("level")
      if m <= 0 then return "off" end
      if m < 0.5 then return string.format("x%.2f", m * 2) end
      return string.format("%+.2f", m - 0.5)
    end,
    frac = function() return wl("gust").macro("level") end,
    push = function() wl("gust").push_key("level") end,
  },
  {
    key = "smp_master", label = "Samples", glyph = "fader",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return wl("sample").master() end,
    set = function(v) wl("sample").set_master(v) end,
    text = function() return string.format("%.2f", wl("sample").master()) end,
    frac = function() return wl("sample").master() end,
    push = function() wl("sample").push_key("level") end,
  },
}

blend.PARAM_COUNT = #blend.PARAMS

function blend.param(i)
  return blend.PARAMS[util.clamp(i, 1, #blend.PARAMS)]
end

-- the same nudge contract every other macro page has (mixer.nudge,
-- gust.macro_nudge): coarse/fine in the row's own units, clamp, set, push.
function blend.nudge(i, delta, is_coarse)
  local p = blend.param(i)
  if not p then return nil end
  local step = (is_coarse and p.coarse or p.fine) or p.coarse
  local v = p.get() + delta * step
  if p.min then v = util.clamp(v, p.min, p.max) end
  p.set(v)
  p.push()
  return p
end

return blend
