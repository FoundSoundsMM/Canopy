-- glyph.lua
-- one drawn shape per parameter, and nothing else.
--
-- §5.2c. what this replaces: a 4x2 grid of identical 270-degree gauges with
-- the parameter's name under each. that layout came from an Elektron box,
-- where it is the right answer -- a Digitakt has eight physical knobs whose
-- meaning changes per page, so the screen's whole job is to LABEL them, and
-- eight identical widgets is honest about the eight identical knobs under
-- your fingers. norns has no such row. here the screen is not labelling
-- anything; it is the only thing there is. so the drawing has to carry the
-- meaning, which means no two parameters may look alike.
--
-- the rule every shape in here follows: the shape says WHAT the parameter is,
-- its state says WHERE it is set. a Decay draws a falling tail and the tail
-- gets longer; a Prob draws a field of dots and the field gets denser; a
-- Length draws a row of steps and more of them light. you read the picture,
-- not the word underneath -- the word is there for the first week and for the
-- two or three cases (Balance vs Depth) where two shapes are near neighbours.
--
-- three consequences, all of them deliberate:
--
--   * no numbers. a shape that fills, tilts, thickens or slides has already
--     said where the parameter is; printing "0.58" underneath says the same
--     thing again in the slower of the two languages, and it costs 7px per
--     row -- which is exactly what pays for a 19px-tall shape instead of an
--     11px one. the cost is real and named in the header comment of
--     screenui.lua: there is now nowhere on the panel to read an exact value.
--   * no knobs. a gauge is a picture of a physical control this instrument
--     does not have, and it spends a whole circle saying one number. the
--     default here is `fader` -- a column that fills -- which reads at a
--     glance and stacks into a row that scans like a mixer strip.
--   * curves, but only cheap ones. test/soak.lua caps redraw() at 200 screen
--     commands a frame, because a queue matron cannot drain blocks the Lua
--     thread and takes the front panel down with the screen. that budget is
--     what decides how a curve gets drawn here, not taste: screen.curve is
--     ONE command and draws a real cubic, while the same curve sampled into
--     a 26-point polyline is twenty-seven -- eight of those is the whole
--     frame. so Decay, Attack, Body, Bright and Timbre are genuine curves
--     (screen.curve), and everything discrete or positional stays straight
--     because a curve would say nothing there. no screen.arc, though: with a
--     live current point -- and there always is one, left by the previous
--     widget's label -- cairo_arc drags a phantom segment in from wherever
--     the pen was, which is the bug the old draw_knob carried two extra
--     move()s to suppress. curve_to has no such behaviour.
--   * one fill per group. screen.rect only adds to the current path; the
--     fill is what paints. so a dot field or a row of steps issues its rects
--     and then ONE screen.fill(), which is what keeps those shapes inside
--     the per-frame budget instead of costing two commands per cell.
--
-- the contract. every shape is `f(x, y, w, h, v, on, text, d)`:
--   x, y, w, h  the box, always 26 x 19 from screenui's widget grid
--   v           0..1, the parameter's own `get`
--   on          focused. decides brightness only, never geometry -- a widget
--               must be readable dim, since seven of the eight always are.
--   text        the parameter's own `text()`, only used by `word`
--   d           optional extras from a row's `glyph_data(id)`:
--                 d.n            how many slots (steps, stack)
--                 d.idx, d.total position in a bank (word)
--                 d.bits, d.tap  the register itself (register)
--
-- adding one: write the function, put it in DRAW, and name it from a row's
-- `glyph` field. a row with no `glyph` gets `fader`, so the panel is never
-- broken mid-migration.

local glyph = {}

-- the box screenui hands every shape. exported so the tests and the layout
-- arithmetic have one place to read it from.
glyph.W, glyph.H = 26, 19

-- brightness, in three bands. the focused widget is the brightest thing on
-- the panel; an unfocused one has to stay legible at half that, so the dim
-- band is 7 rather than the 5 the old grid used -- a 1px line at 5 on this
-- display is nearly gone.
local function hi(on) return on and 15 or 7 end
local function md(on) return on and 8 or 4 end
local function lo(on) return on and 4 or 2 end

-- a stable value-noise hash for the two shapes that need a fixed scatter
-- (dots, lattice) and the one that needs a fixed wobble (wander). it has to
-- be deterministic -- a field that reshuffles every frame reads as static,
-- not as density -- and it must not touch math.random(), which every other
-- module's offline test depends on the stream position of.
local function hash(i, j)
  local x = math.sin(i * 12.9898 + j * 78.233) * 43758.5453
  return x - math.floor(x)
end

-- drawing helpers. `frame` uses the half-pixel offset norns' own stroked
-- rects need; `bar` and `seg` exist so no shape below has to remember to
-- reset the pen between a fill and the next path.
local function bar(x, y, w, h)
  if w <= 0 or h <= 0 then return end
  screen.rect(x, y, w, h)
  screen.fill()
end

local function frame(x, y, w, h)
  screen.rect(x + 0.5, y + 0.5, w - 1, h - 1)
  screen.stroke()
end

local function seg(x0, y0, x1, y1)
  screen.move(x0, y0)
  screen.line(x1, y1)
  screen.stroke()
end

-- many rects, one paint. see the note on the frame budget above: the rects
-- accumulate in cairo's current path and screen.fill() paints the lot, so a
-- 45-cell dot field costs 46 commands rather than 90.
local function fill_all(list)
  if #list == 0 then return end
  for i = 1, #list do
    local r = list[i]
    screen.rect(r[1], r[2], r[3], r[4])
  end
  screen.fill()
end

-- a cubic from the current point. one command, a real curve.
local function curve(x1, y1, x2, y2, x3, y3)
  screen.curve(x1, y1, x2, y2, x3, y3)
end

-- a connected run of points, drawn as one path
local function path(pts)
  if #pts < 2 then return end
  screen.move(pts[1][1], pts[1][2])
  for i = 2, #pts do screen.line(pts[i][1], pts[i][2]) end
  screen.stroke()
end

local DRAW = {}

-- fader: the column fills. the default, and what replaced every knob on the
-- panel. Level, Drive, Rate, Speed, Master, Amount -- anything that is
-- simply "how much".
function DRAW.fader(x, y, w, h, v, on)
  local bw = 11
  local cx = x + math.floor((w - bw) / 2 + 0.5)
  screen.level(lo(on)); frame(cx, y, bw, h)
  local fh = math.floor(v * (h - 2) + 0.5)
  if fh > 0 then
    screen.level(hi(on))
    bar(cx + 2, y + h - 1 - fh, bw - 4, fh)
  end
end

-- channel: a fader with a meter beside it. the mixer page and nothing else
-- (lib/mixer.lua) -- the one place on the panel where a knob has a live
-- signal behind it, so the widget can say where the fader is AND whether
-- anything is coming through it, which is the question you actually open a
-- mixer to answer. a fader at 0.8 on a channel that is silent and one on a
-- channel that is roaring look identical to every other shape in this file.
--
-- the fader is the outlined column, exactly as `fader` draws it, and the
-- meter is a solid bar down its right-hand side with no outline of its own:
-- the fader is a setting and reads as a control, the meter is a
-- measurement and reads as a level. the meter is post-fader engine-side, so
-- pulling the fader down pulls the bar down with it -- what the widget says
-- and what you hear are one statement.
--
-- `d.meter` is 0..1 and comes from the row's glyph_data; with no data at all
-- (a caller that has not wired the meter up) the bar simply does not draw and
-- what is left is a plain fader.
function DRAW.channel(x, y, w, h, v, on, _, d)
  local bw = 9
  local gap = 2
  local mw = 4
  local cx = x + math.floor((w - (bw + gap + mw)) / 2 + 0.5)
  local mx = cx + bw + gap

  screen.level(lo(on)); frame(cx, y, bw, h)
  local fh = math.floor(v * (h - 2) + 0.5)
  if fh > 0 then
    screen.level(md(on) + (on and 4 or 2))
    bar(cx + 2, y + h - 1 - fh, bw - 4, fh)
  end

  -- the floor the meter stands on, so an idle channel is still a shape
  -- rather than an empty gap next to the fader.
  screen.level(lo(on)); bar(mx, y + h - 1, mw, 1)
  local m = util.clamp((d and d.meter) or 0, 0, 1)
  local mh = math.floor(m * (h - 1) + 0.5)
  if mh > 0 then
    screen.level(hi(on))
    bar(mx, y + h - 1 - mh, mw, mh)
  end
end

-- bipolar: the same column, filling out of the middle either way. the fill
-- never disappears -- at centre it is a 2px bar sitting on the mid line, so
-- "no bend" reads as a statement rather than as an empty box.
function DRAW.bipolar(x, y, w, h, v, on)
  local bw = 11
  local cx = x + math.floor((w - bw) / 2 + 0.5)
  local my = y + math.floor(h / 2 + 0.5)
  screen.level(lo(on)); frame(cx, y, bw, h)
  screen.level(md(on)); seg(cx, my, cx + bw - 1, my)
  local d = math.floor((v - 0.5) * 2 * (h / 2 - 2) + 0.5)
  screen.level(hi(on))
  if d > 0 then bar(cx + 2, my - d, bw - 4, d + 1)
  elseif d < 0 then bar(cx + 2, my, bw - 4, -d + 1)
  else bar(cx + 2, my - 1, bw - 4, 2) end
end

-- marker: where it sits between the two ends. Tune, Pitch, Pan, a field's
-- current degree -- a position on a scale rather than an amount of something.
function DRAW.marker(x, y, w, h, v, on)
  local base = y + h - 1
  screen.level(md(on)); seg(x, base, x + w - 1, base)
  screen.level(lo(on))
  fill_all({{x, base - 3, 1, 3}, {x + w - 1, base - 3, 1, 3},
            {x + math.floor((w - 1) / 2 + 0.5), base - 2, 1, 2}})
  local px = x + 1 + math.floor(v * (w - 4) + 0.5)
  screen.level(hi(on)); bar(px, y, 3, h - 1)
end

-- ramp: how long the tail is. Decay, Loss.
function DRAW.ramp(x, y, w, h, v, on)
  local base = y + h - 1
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  local len = 2 + v * (w - 5)
  screen.level(hi(on))
  screen.move(x + 1, base)
  screen.line(x + 1, y)
  -- control points held near the start pull the fall in early, which is what
  -- makes it read as a decay rather than as a diagonal
  curve(x + 1 + len * 0.14, y + (h - 1) * 0.52,
        x + 1 + len * 0.42, base,
        x + 1 + len, base)
  screen.stroke()
end

-- rampup: how long the rise is. Attack, Charge.
function DRAW.rampup(x, y, w, h, v, on)
  local base = y + h - 1
  local len = 2 + v * (w - 6)
  local k = x + 1 + len
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  screen.level(hi(on))
  screen.move(x + 1, base)
  curve(x + 1 + len * 0.55, base - (h - 1) * 0.05,
        k - len * 0.10, y,
        k, y)
  screen.line(x + w - 1, y)
  screen.stroke()
end

-- peak: where the peak is. Body, Form, Space -- a resonance whose centre
-- moves rather than a quantity that grows.
function DRAW.peak(x, y, w, h, v, on)
  local base = y + h - 1
  local px = x + 2 + v * (w - 5)
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  screen.level(hi(on))
  screen.move(x, base)
  curve(x + (px - x) * 0.55, base, px - (px - x) * 0.22, y, px, y)
  curve(px + (x + w - 1 - px) * 0.22, y,
        x + w - 1 - (x + w - 1 - px) * 0.55, base,
        x + w - 1, base)
  screen.stroke()
end

-- tilt: where it turns over. Bright, Tone, Colour -- a corner frequency,
-- flat up to it and falling after.
function DRAW.tilt(x, y, w, h, v, on)
  local base = y + h - 1
  local k = x + 1 + v * (w - 3)
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  screen.level(hi(on))
  screen.move(x, y)
  screen.line(k, y)
  curve(k + (x + w - 1 - k) * 0.30, y - 1,
        k + (x + w - 1 - k) * 0.45, base,
        x + w - 1, base)
  screen.stroke()
end

-- spike: sharp and tall, or blunt and short. Strike, Punch, Hop -- the shape
-- of one impulse, which is the thing the knob actually changes.
function DRAW.spike(x, y, w, h, v, on)
  local base = y + h - 1
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  local bw = 1 + math.floor((1 - v) * 8 + 0.5)
  local bh = math.floor((0.3 + v * 0.7) * (h - 1) + 0.5)
  screen.level(hi(on)); bar(x + 2, base - bh, bw, bh)
end

-- combs: how fast the ringing dies. Damp, Conduct. nine bars whose envelope
-- steepens -- the same information a decay curve carries, drawn in rects.
function DRAW.combs(x, y, w, h, v, on)
  local base = y + h - 1
  local k = 0.1 + v * 0.85
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  local rs = {}
  for j = 0, 6 do
    local bh = math.max(1, math.floor((h - 2) * math.exp(-j * k) + 0.5))
    rs[#rs + 1] = {x + j * 4, base - bh, 3, bh}
  end
  screen.level(hi(on)); fill_all(rs)
end

-- dots: the field thickens with the number. Prob, Drops, Scatter, Noise.
-- unlit cells stay as single pixels rather than going blank, so the field
-- keeps its shape at zero and you can see it is a field.
function DRAW.dots(x, y, w, h, v, on)
  local cols, rows = 9, 5
  local dx, dy = 3, 4
  local x0 = x + math.floor((w - (cols - 1) * dx - 2) / 2 + 0.5)
  local lit = {}
  for j = 0, rows - 1 do
    for i = 0, cols - 1 do
      if hash(i, j) < v then
        lit[#lit + 1] = {x0 + i * dx, y + 1 + j * dy, 2, 2}
      end
    end
  end
  -- only the lit cells are drawn. an earlier cut put a dim pixel in every
  -- empty slot so the field kept its shape at zero, which cost 45 rects a
  -- frame whatever the value was and took the global page to 186 of its 200
  -- -- one new parameter from breaking. four corner marks say "this is a
  -- field, and it is empty" for four commands, which is the same sentence.
  screen.level(lo(on))
  local x9, y9 = x0 + (cols - 1) * dx, y + 1 + (rows - 1) * dy
  fill_all({{x0, y + 1, 1, 1}, {x9, y + 1, 1, 1},
            {x0, y9, 1, 1}, {x9, y9, 1, 1}})
  screen.level(hi(on)); fill_all(lit)
end

-- steps: a count of steps, drawn as steps. Length, Sources -- where the
-- number IS a count of discrete things, so drawing that many of them is
-- both the value and the unit.
function DRAW.steps(x, y, w, h, v, on, _, d)
  local n = (d and d.n) or 13
  local step = w / n
  local bw = math.max(1, math.floor(step) - 1)
  -- a row that knows its own count (tm.length, an Out cell's feeds) hands it
  -- over; everything else derives it from the fraction.
  local lit = (d and d.lit) or math.max(1, math.floor(v * n + 0.5))
  local base = y + h - 1
  local on_r, off_r = {}, {}
  for j = 0, n - 1 do
    local bx = x + math.floor(j * step + 0.5)
    if j < lit then on_r[#on_r + 1] = {bx, y, bw, h - 1}
    else off_r[#off_r + 1] = {bx, base - 3, bw, 3} end
  end
  screen.level(lo(on))
  seg(x, base, x + w - 1, base)
  fill_all(off_r)
  screen.level(hi(on)); fill_all(on_r)
end

-- stack: how many of them, stacked. Bits. eight rows in nineteen pixels
-- leaves no room to separate lit from unlit by height, so an empty row is
-- narrower as well as dimmer -- and the 1px-bar/1px-gap pitch keeps them
-- countable rather than merging into a block.
function DRAW.stack(x, y, w, h, v, on, _, d)
  local n = (d and d.n) or 8
  local bw = 15
  local cx = x + math.floor((w - bw) / 2 + 0.5)
  local lit = (d and d.lit) or math.floor(v * n + 0.5)
  local on_r, off_r = {}, {}
  for j = 0, n - 1 do
    local by = y + h - 1 - j * 2
    if j < lit then on_r[#on_r + 1] = {cx, by, bw, 1}
    else off_r[#off_r + 1] = {cx + 5, by, bw - 10, 1} end
  end
  screen.level(lo(on)); fill_all(off_r)
  screen.level(hi(on)); fill_all(on_r)
end

-- register: the register, and the bit being read. Tap. this is the one shape
-- that draws another module's live state rather than its own parameter --
-- d.bits is tm.get(id).bits -- because "bit 4" is meaningless without the
-- eight bits next to it, and with them it needs no caption at all.
function DRAW.register(x, y, w, h, v, on, _, d)
  local n, bw, gap = 8, 2, 1
  local x0 = x + math.floor((w - (n * (bw + gap) - gap)) / 2 + 0.5)
  local base = y + h - 6
  local bits = d and d.bits
  local set_r, clr_r = {}, {}
  for j = 0, n - 1 do
    local set
    if bits then set = (bits[j + 1] == 1) else set = hash(j, 3) > 0.5 end
    local bx = x0 + j * (bw + gap)
    if set then set_r[#set_r + 1] = {bx, y, bw, h - 6}
    else clr_r[#clr_r + 1] = {bx, base - 3, bw, 3} end
  end
  screen.level(md(on)); fill_all(clr_r)
  screen.level(hi(on)); fill_all(set_r)
  screen.level(lo(on))
  seg(x0, base + 1, x0 + n * (bw + gap) - gap - 1, base + 1)
  -- the tap, as a caret underneath rather than a box around: a box around
  -- one 2px bit collides with the bits either side of it at this pitch.
  local tap = d and d.tap
  if tap == nil then tap = math.floor(v * (n - 1) + 0.5) end
  screen.level(hi(on))
  local bx = x0 + tap * (bw + gap)
  path({{bx - 1, base + 5}, {bx + 1, base + 3}, {bx + 3, base + 5}})
end

-- span: how wide, out from the middle. Range, Width -- a symmetric extent,
-- which a fader cannot say and a bracket can.
function DRAW.span(x, y, w, h, v, on)
  local my = y + math.floor(h / 2 + 0.5)
  local cx = x + math.floor((w - 1) / 2 + 0.5)
  local half = math.floor(1 + v * (w / 2 - 2) + 0.5)
  screen.level(lo(on)); seg(x, my, x + w - 1, my)
  screen.level(md(on)); seg(cx, my - 2, cx, my + 2)
  screen.level(hi(on))
  seg(cx - half, my, cx + half, my)
  bar(cx - half, y + 2, 2, h - 5)
  bar(cx + half - 1, y + 2, 2, h - 5)
end

-- wander: how far it wanders. Drift, Swing, Scatter -- deviation from a
-- line, so the line stays drawn underneath it.
function DRAW.wander(x, y, w, h, v, on)
  local my = y + math.floor(h / 2 + 0.5)
  local amp = v * (h / 2 - 1)
  screen.level(lo(on)); seg(x, my, x + w - 1, my)
  local pts = {}
  for i = 0, 6 do
    local t = i / 6
    local sign = (i % 2 == 1) and 1 or -1
    pts[#pts + 1] = {x + t * (w - 1),
                     my + sign * amp * (0.5 + hash(i, 9) * 0.5)}
  end
  screen.level(hi(on)); path(pts)
end

-- rain: rainfall, falling. the one parameter on the panel actually named
-- after weather, so it is the one shape here that draws the thing rather than
-- an abstraction of it -- and the only one that MOVES on its own.
--
-- three quantities rise together with the knob, which is what makes light
-- rain and heavy rain read as the same weather at two strengths rather than
-- as two different pictures: how many streaks there are (3 -> 14), how long
-- each one is (2px -> 7px), and how fast they fall (about half a box a
-- second at the bottom, three and a half at the top). the slant comes in
-- with the speed as well, so heavy rain is being driven rather than
-- dropped.
--
-- animated, unlike everything else in this file, and deliberately so: the
-- other twenty-seven shapes are functions of their parameter alone, because a
-- widget that moves when the value has not is a widget that cannot be read.
-- rainfall is the exception where standing still is the misreading -- frozen
-- streaks are hatching, not rain -- and the motion is unconditional, so it
-- never competes with the value for the eye. it costs the frame budget
-- nothing extra: the streaks accumulate into one path and paint once (see
-- fill_all), so this is the same order of commands as `wander`, which it
-- replaced on the global page.
--
-- the columns and the per-streak head start are hashed, not random, so the
-- shower has a fixed shape that scrolls through the box rather than
-- reshuffling itself every frame -- and math.random() is untouched, which
-- every module's offline test depends on the stream position of.
local RAIN_MIN, RAIN_MAX = 3, 14

-- the order the streaks are switched on in, as slot numbers across the box.
-- adding one at a time from left to right would make light rain a puddle in
-- the corner; this walks the box wide-then-fine, so three streaks are spread
-- across it and fourteen fill it evenly, and -- because a streak keeps its
-- slot once it has one -- turning the knob up ADDS rain between what is
-- already falling rather than reshuffling the shower.
local RAIN_ORDER = {1, 8, 4, 12, 2, 10, 6, 14, 3, 11, 7, 13, 5, 9}

function DRAW.rain(x, y, w, h, v, on)
  local n = math.floor(RAIN_MIN + v * (RAIN_MAX - RAIN_MIN) + 0.5)
  local len = 2 + v * 5
  local speed = 0.5 + v * 3.0
  local slant = v * 2.2
  -- the fall runs past the bottom of the box by a streak's length, so a
  -- streak leaves the frame instead of blinking out at the last row.
  local span = h + len
  local t = (util.time and util.time() or 0) * speed

  -- the ground the rain is falling onto. dim, and drawn first, so a streak
  -- reaching the bottom crosses it rather than stopping short of it.
  screen.level(lo(on)); seg(x, y + h - 1, x + w - 1, y + h - 1)

  local drops = {}
  for i = 1, n do
    local slot = RAIN_ORDER[i]
    -- each streak owns a column and a head start; both are fixed for the
    -- life of the panel, so what moves is only where in its own fall it is.
    local phase = (t + hash(slot, 3)) % 1
    -- a third of a streak either side of the nominal length. without it
    -- fourteen identical dashes read as a texture rather than as weather.
    local llen = len * (0.7 + hash(slot, 5) * 0.6)
    local top = phase * span - llen
    -- evenly spaced, then nudged a pixel either way by the hash: an even
    -- comb reads as hatching and a purely hashed scatter clumps at this
    -- width, and neither of those is rain.
    local col = math.floor((slot - 0.5) / RAIN_MAX * (w - 1)
                           + (hash(slot, 11) - 0.5) * 2.4 + 0.5)
    -- the slant is applied per streak, from its own top: a column of rain
    -- leaning over as it falls, not a box of rain sheared sideways.
    local dx = math.floor(phase * slant + 0.5)
    local y0 = math.max(y, y + top)
    local y1 = math.min(y + h - 1, y + top + llen)
    if y1 > y0 then
      drops[#drops + 1] = {util.clamp(x + col + dx, x, x + w - 1),
                           y0, 1, y1 - y0}
    end
  end
  screen.level(hi(on)); fill_all(drops)
end

-- word: the word, and where it sits in its bank. Gait, Rule, Mode, Scale.
-- a pointer angle says nothing about "euclidean", so these keep a boxed
-- reading -- but the box now carries what the old one could not: tick marks
-- saying there are nine gaits and you are on the second.
function DRAW.word(x, y, w, h, v, on, text, d)
  local bh = 13
  local by = y + 1
  if on then
    screen.level(15); screen.rect(x, by, w, bh); screen.fill()
  else
    screen.level(4); frame(x, by, w, bh)
  end
  screen.level(on and 0 or 10)
  glyph.centred(x + w / 2, by + 9, text or "", w - 4)
  local total = d and d.total
  local idx = d and d.idx
  if total and total > 1 and idx then
    local step = math.max(2, math.floor((w - 2) / total))
    local x0 = x + math.floor((w - step * (total - 1)) / 2 + 0.5)
    for i = 0, total - 1 do
      screen.level(i == idx and hi(on) or lo(on))
      local s = (i == idx) and 2 or 1
      bar(x0 + i * step, y + h - 2, s, s)
    end
  end
end

-- flag: on, or off. Clock, Snap, Gate. a filled block or an empty one --
-- the one place where two states is the whole vocabulary.
function DRAW.flag(x, y, w, h, v, on)
  local s = 13
  local x0 = x + math.floor((w - s) / 2 + 0.5)
  local y0 = y + math.floor((h - s) / 2 + 0.5)
  if v >= 0.5 then
    screen.level(hi(on)); bar(x0, y0, s, s)
  else
    screen.level(md(on)); frame(x0, y0, s, s)
  end
end

-- link: one thing reaching another, by this much. Balance, Depth, Cross --
-- all three are "how much of A arrives at B", which is a path between two
-- points rather than a level.
function DRAW.link(x, y, w, h, v, on)
  local my = y + math.floor(h / 2 + 0.5)
  local ax, bx = x + 1, x + w - 4
  screen.level(md(on))
  bar(ax, my - 1, 3, 3)
  bar(bx, my - 1, 3, 3)
  local d = math.floor((v - 0.5) * 2 * (h / 2 - 2) + 0.5)
  screen.level(hi(on))
  path({{ax + 3, my}, {x + w / 2, my - d}, {bx, my}})
end

-- wave: the shape of the tone itself. Timbre, Shape -- a triangle that
-- squares up as the value rises, which is what the parameter does.
function DRAW.wave(x, y, w, h, v, on)
  local my = y + (h - 1) / 2
  local amp = h / 2 - 1
  screen.level(lo(on)); seg(x, my, x + w - 1, my)
  -- two cycles, four half-cycles, one cubic each. the control points start
  -- on the straight line between the peaks (a triangle) and slide out to the
  -- ends of it as v rises, which squares the corners off -- the same morph
  -- the parameter does, in four commands instead of twenty-six.
  local q = (w - 1) / 4
  local k = 0.18 + v * 0.68
  screen.level(hi(on))
  screen.move(x, my)
  local sign = -1
  for i = 0, 3 do
    local x0 = x + i * q
    local top = my + sign * amp
    curve(x0 + q * k, (i == 0) and my or (my - sign * amp * (1 - k * 0.6)),
          x0 + q * (1 - k * 0.35), top,
          x0 + q, top)
    -- the run along the top of a square wave: at v = 0 it has no length
    sign = -sign
  end
  screen.stroke()
end

-- lattice: a lattice, with charge in it. the weave -- cells
-- whose one knob is about how freely something crosses a mesh.
function DRAW.lattice(x, y, w, h, v, on)
  local cols, rows = 5, 4
  local dx = (w - 3) / (cols - 1)
  local dy = (h - 3) / (rows - 1)
  local rails, lit, dim = {}, {}, {}
  for j = 0, rows - 1 do
    rails[#rails + 1] = {x + 1, y + 1 + j * dy, w - 2, 1}
    for i = 0, cols - 1 do
      local px, py = x + 1 + i * dx, y + 1 + j * dy
      if hash(i, j) < v then lit[#lit + 1] = {px - 1, py - 1, 3, 3}
      else dim[#dim + 1] = {px, py, 1, 1} end
    end
  end
  screen.level(lo(on)); fill_all(rails)
  screen.level(md(on)); fill_all(dim)
  screen.level(hi(on)); fill_all(lit)
end

-- knee: the transfer curve, bending over. Drive, Punch -- saturation, where
-- the parameter is the shape of the bend and not an amount of anything. the
-- dim diagonal behind it is unity gain, so how far the curve has left it is
-- the reading.
function DRAW.knee(x, y, w, h, v, on)
  local base = y + h - 1
  screen.level(lo(on)); seg(x, base, x + w - 1, y)
  screen.level(hi(on))
  screen.move(x, base)
  curve(x + (w - 1) * (0.42 - v * 0.30), base - (h - 1) * (0.42 + v * 0.34),
        x + (w - 1) * (0.58 - v * 0.26), y,
        x + w - 1, y)
  screen.stroke()
end

-- swing: every second step slides late. Swing, and nothing else -- it is a
-- systematic displacement of alternate positions, which `wander` (a random
-- one) would misreport.
function DRAW.swing(x, y, w, h, v, on)
  local n = 6
  local gap = (w - 2) / (n - 1)
  local base = y + h - 1
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  -- the on-beat steps are tall and fixed; the off-beat ones are short and
  -- slide late. the height difference is what keeps the pairing readable at
  -- zero swing, where the two rows are otherwise evenly spaced and identical.
  local even, odd = {}, {}
  for i = 0, n - 1 do
    local px = x + i * gap
    if i % 2 == 0 then even[#even + 1] = {px, y + 1, 2, h - 2}
    else odd[#odd + 1] = {px + v * gap * 0.70, y + 8, 2, h - 9} end
  end
  screen.level(md(on)); fill_all(even)
  screen.level(hi(on)); fill_all(odd)
end

-- §4.4 the Colour page's four own shapes. the other four rows there borrow
-- shapes that already exist and already say the right thing (`knee` for tape
-- saturation, `span` for a chorus's detune spread, `fader` for its rate,
-- `spike` for a transient shaper); these four had no neighbour close enough
-- to borrow from, and two of them -- Crush and Alias -- are near enough to
-- each other that drawing them alike would have been the exact failure this
-- file exists to avoid. so one quantises vertically and one quantises
-- horizontally, which is the actual difference between them.

-- crush: word length, drawn as a staircase across the transfer line. the
-- steps get taller and fewer as the knob rises, which is what losing bits
-- is; the dim diagonal behind is the signal they are approximating.
function DRAW.crush(x, y, w, h, v, on)
  local base = y + h - 1
  screen.level(lo(on)); seg(x, base, x + w - 1, y)
  local n = math.max(2, math.floor(8 - v * 6 + 0.5))
  local sw = (w - 1) / n
  local rs = {}
  for j = 0, n - 1 do
    local top = base - math.floor((j / (n - 1)) * (h - 2) + 0.5)
    rs[#rs + 1] = {x + math.floor(j * sw + 0.5), top,
                   math.max(1, math.floor(sw)), base - top + 1}
  end
  screen.level(hi(on)); fill_all(rs)
end

-- alias: sample rate, drawn as a sample-and-hold over the wave it is
-- sampling. the held segments get wider and fewer as the knob rises and the
-- dim curve underneath stays where it was, so what the shape says is "this
-- many samples of that".
function DRAW.alias(x, y, w, h, v, on)
  local my = y + (h - 1) / 2
  local amp = h / 2 - 2
  screen.level(lo(on))
  screen.move(x, my)
  curve(x + w * 0.14, my - amp * 1.3, x + w * 0.36, my - amp * 1.3,
        x + w * 0.5, my)
  curve(x + w * 0.64, my + amp * 1.3, x + w * 0.86, my + amp * 1.3,
        x + w - 1, my)
  screen.stroke()
  local n = math.max(3, math.floor(13 - v * 10 + 0.5))
  local sw = (w - 1) / n
  local rs = {}
  for j = 0, n - 1 do
    local t = (j + 0.5) / n
    local sy = my - math.sin(t * 2 * math.pi) * amp
    rs[#rs + 1] = {x + math.floor(j * sw + 0.5), math.floor(sy + 0.5),
                   math.max(1, math.floor(sw)), 1}
  end
  screen.level(hi(on)); fill_all(rs)
end

-- loss: a codec eating a spectrum. a row of partials falling away to the
-- right; as the knob rises the top of the band goes first and then holes
-- open in what is left, which is the two things a low-bitrate encoder
-- audibly does. the stumps of the dropped ones stay drawn, dim, so the shape
-- is "what was taken" rather than "a shorter row of bars".
function DRAW.loss(x, y, w, h, v, on)
  local base = y + h - 1
  local n, bw, gap = 8, 2, 1
  local x0 = x + math.floor((w - (n * (bw + gap) - gap)) / 2 + 0.5)
  screen.level(lo(on)); seg(x, base, x + w - 1, base)
  local keep, gone = {}, {}
  for j = 0, n - 1 do
    local t = j / (n - 1)
    local full = math.max(2, math.floor((h - 3) * (1 - t * 0.55) + 0.5))
    local bx = x0 + j * (bw + gap)
    if t > (1 - v * 0.62) or hash(j, 5) < v * 0.32 then
      gone[#gone + 1] = {bx, base - 2, bw, 2}
    else
      keep[#keep + 1] = {bx, base - full, bw, full}
    end
  end
  screen.level(md(on)); fill_all(gone)
  screen.level(hi(on)); fill_all(keep)
end

-- squash: dynamics, being flattened. a run of peaks at their own heights
-- behind, and the same run pulled toward one height in front -- loud ones
-- down, quiet ones up. at zero the two coincide and it reads as a plain
-- waveform, which is what no compression is.
local SQUASH_PEAKS = {1.0, 0.32, 0.78, 0.22, 0.95, 0.4, 0.68}

function DRAW.squash(x, y, w, h, v, on)
  local my = y + math.floor(h / 2 + 0.5)
  local n = #SQUASH_PEAKS
  local step = (w - 2) / (n - 1)
  local top = h / 2 - 1
  local dim, lit = {}, {}
  for j = 1, n do
    local px = x + math.floor((j - 1) * step + 0.5)
    local a = SQUASH_PEAKS[j]
    local c = a + (0.8 - a) * v
    local ah = math.max(1, math.floor(a * top + 0.5))
    local ch = math.max(1, math.floor(c * top + 0.5))
    dim[#dim + 1] = {px, my - ah, 2, ah * 2}
    lit[#lit + 1] = {px, my - ch, 2, ch * 2}
  end
  screen.level(lo(on)); fill_all(dim)
  screen.level(hi(on)); fill_all(lit)
end

glyph.DRAW = DRAW

-- screenui owns the text metrics (screen.text_extents, with the offline
-- fallback), and `word` is the only shape that draws any. rather than have
-- two copies of that measuring code, screenui installs its own centred/clip
-- here at load. the default is a plain move+text so this file is still
-- runnable on its own.
function glyph.centred(cx, y, str, limit)
  if str == nil or str == "" then return end
  screen.move(cx, y)
  screen.text_center(str)
end

function glyph.draw(name, x, y, w, h, v, on, text, d)
  local f = DRAW[name] or DRAW.fader
  f(x, y, w, h, util.clamp(v or 0, 0, 1), on and true or false, text, d)
end

function glyph.exists(name)
  return DRAW[name] ~= nil
end

return glyph
