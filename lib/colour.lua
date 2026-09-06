-- colour.lua
-- §4.4 the Colour page: one chain of eight processors across the master
-- output, sitting one K3 press past the mixer.
--
-- why it is here and not on a cell. everything else on this panel is a thing
-- you patch: a source, a transform, a seat in the stereo field. these eight
-- are none of those -- they are what the whole instrument sounds like coming
-- out of it, and a cable that had to be drawn to reach them would be a cable
-- every patch drew identically. so they live on a page, after the mixer,
-- which is the order the signal actually goes in: the faders decide the
-- balance, and this decides the surface.
--
-- the order in the engine is fixed and is not the order on the page. the page
-- reads in the order you reach for the knobs -- the four degradations first,
-- because they are what this page is FOR, then the two chorus rows, then the
-- two dynamics rows. the chain runs transient -> compressor -> tape ->
-- chorus -> crush -> alias -> loss, which is the order that sounds like a
-- signal path rather than a list: shape the hits, level them, warm them,
-- widen them, and only then take the resolution away. see \wl_colour's own
-- comment in Engine_Canopy.sc.
--
-- every row is a plain 0..1 knob and every one of them is a no-op at its
-- default, except Shape, which is bipolar and neutral at 0.5, and Swirl,
-- which is a rate and therefore inaudible until Chorus is up. that matters:
-- a fresh patch has to sound exactly as it did before this page existed, and
-- the way you get that is a page of zeroes rather than a page of tasteful
-- starting values nobody chose.
--
-- the page object is the same shape gparam's, gust's macro page's and
-- mixer's are -- PARAMS with get/set/text/frac/push, E1 to pick, E2/E3 to
-- move coarse/fine -- so screenui and Canopy.lua drive all four identically.

local state  = wl("state")
local bridge = wl("bridge")

local colour = {}

local COARSE, FINE = 1 / 80, 1 / 500

-- the defaults, which are also the bypass positions. `swirl` is the one
-- number here that is not zero: it is the chorus's rate, it does nothing
-- while Chorus is at zero, and starting it at zero would mean the first
-- thing anyone hears on turning Chorus up is a static comb filter rather
-- than a chorus.
colour.DEFAULTS = {
  tape   = 0,
  crush  = 0,
  alias  = 0,
  loss   = 0,
  chorus = 0,
  swirl  = 0.3,
  shape  = 0.5,
  comp   = 0,
}

local function values()
  state.global.colour = state.global.colour or {}
  local t = state.global.colour
  for k, v in pairs(colour.DEFAULTS) do
    if t[k] == nil then t[k] = v end
  end
  return t
end

function colour.get(key)
  return values()[key]
end

function colour.set(key, v)
  local t = values()
  t[key] = util.clamp(v, 0, 1)
  return t[key]
end

-- one row. `text_fn` is optional -- most of these are plain amounts and read
-- as plain numbers; the two that mean something else (Shape's bipolar
-- position, Swirl's rate in Hz) say so.
local function row(key, label, gl, text_fn)
  return {
    key = key, label = label, glyph = gl,
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return colour.get(key) end,
    set = function(v) colour.set(key, v) end,
    text = text_fn or function()
      return string.format("%.2f", colour.get(key))
    end,
    frac = function() return colour.get(key) end,
    push = function() bridge.colour(key, colour.get(key)) end,
  }
end

-- Swirl in Hz on the screen: it is a speed, and "0.44" says nothing about
-- whether that is a shimmer or a warble. keep this mapping identical to
-- \wl_colour's own chRate.
colour.SWIRL_MIN, colour.SWIRL_MAX = 0.05, 3.5

function colour.swirl_hz()
  return colour.SWIRL_MIN
       + colour.get("swirl") * (colour.SWIRL_MAX - colour.SWIRL_MIN)
end

colour.PARAMS = {
  -- Tape: soft saturation with a little of what a machine does around it --
  -- top end coming off as it is driven, and a slow wow on the wet path.
  -- `knee` because the parameter is the shape of the bend, not an amount of
  -- anything, which is exactly what that glyph draws.
  row("tape", "Tape", "knee"),
  -- Crush: word length, sixteen bits down to about three.
  row("crush", "Crush", "crush"),
  -- Alias: sample rate, held down from the top of the band to a few hundred
  -- hertz. named Alias rather than Rate because there is already a Rate on
  -- this instrument and because aliasing is the thing you actually hear.
  row("alias", "Alias", "alias"),
  -- LOSS: a codec, not a filter. the band closes from the top, the partials
  -- that survive get unstable, and a short smear runs ahead of every
  -- transient -- which is the pre-echo that gives a low-bitrate file away.
  row("loss", "Loss", "loss"),
  -- the two chorus rows. depth and rate, which are the two things worth
  -- having separately: depth decides whether it is a thickener or a seasick
  -- one, and rate decides whether it is a shimmer or a wobble.
  row("chorus", "Chorus", "span"),
  row("swirl", "Swirl", "fader",
      function() return string.format("%.2f Hz", colour.swirl_hz()) end),
  -- Shape: the transient designer, bipolar. below the middle it softens the
  -- attack and lets the body through; above it, the attack gets its own
  -- boost and the tail is pulled back. neutral at 0.5, which is why it is
  -- the one row here whose default is not zero-as-bypass.
  row("shape", "Shape", "spike",
      function() return string.format("%+.2f", colour.get("shape") - 0.5) end),
  -- Comp: fast enough to catch a drum, slow enough to let its click out
  -- first. one knob doing threshold, ratio and makeup together, because
  -- three knobs on a master bus compressor is three knobs nobody moves.
  row("comp", "Comp", "squash"),
}

colour.PARAM_COUNT = #colour.PARAMS

function colour.param(i)
  return colour.PARAMS[util.clamp(i, 1, #colour.PARAMS)]
end

-- the same nudge contract gparam.nudge and mixer.nudge have.
function colour.nudge(i, delta, is_coarse)
  local p = colour.param(i)
  if not p then return nil end
  local step = (is_coarse and p.coarse or p.fine) or p.coarse
  local v = p.get() + delta * step
  if p.min then v = util.clamp(v, p.min, p.max) end
  p.set(v)
  p.push()
  return p
end

function colour.push_all()
  for _, p in ipairs(colour.PARAMS) do p.push() end
end

-- the engine holds every one of these whether or not anyone has touched it,
-- so this runs at startup like gparam.init and mixer.init do -- a chain
-- nothing had pushed at would come up on \wl_colour's own defaults, which is
-- a second set of numbers to keep in step with this one.
function colour.init()
  colour.push_all()
end

return colour
