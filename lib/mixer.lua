-- mixer.lua
-- §4.1b the mixer page: a fader for each of the four always-on soundscape
-- loops, the master, and the gusts' shared delay line.
--
-- Rain used to be one entry on the global page and one hard-coded sample
-- path in Canopy.lua's init. it is four now -- rain, cicada, thunder, sea --
-- and four faders is a page of its own rather than four more rows pushed
-- onto a global list that was already two screens long. so the Rain row left
-- gparam.lua entirely and lives here.
--
-- the loops are a dry mix and nothing else. gparam's old Excite -- the same
-- rain audio fed continuously into every voice's resonator -- is gone
-- rather than multiplied by four: these are soundscapes to sit the patch
-- inside, not exciters. lib/exciter.lua's six E cells are still the panel's
-- excitation sources and are unaffected.
--
-- it also carries the gusts' shared delay line (§2.11) -- see the comment
-- above those three rows for why it belongs here rather than on the global
-- page.
--
-- the page object is the same shape as gparam's and every cell page's --
-- PARAMS with get/set/text/frac/push, E1 to pick, E2/E3 to move coarse/fine
-- -- so screenui and Canopy.lua drive it through the code path they already
-- had. it is reached with K3 from anywhere and left with K2 (Canopy.lua's
-- key handler); there is nothing modal about it beyond which page the
-- encoders are pointed at.
--
-- eight slots, which is exactly one screen: the four loop faders fill the
-- widget grid's top row (§5.2b), and the master plus the gusts' three
-- delay-line rows fill the second. no paging.

local state  = wl("state")
local bridge = wl("bridge")

local mixer = {}

-- the loops, in engine index order -- `index` here IS Engine_Canopy.sc's
-- amb_load/amb_volume index, and `file` is a name under audio/.
-- Rain keeps index 0 so the one loop that already existed keeps its place.
mixer.LOOPS = {
  {key = "rain",    name = "Rain",    file = "Rain.wav"},
  {key = "cicada",  name = "Cicada",  file = "Cicada.wav"},
  {key = "thunder", name = "Thunder", file = "Thunder.wav"},
  {key = "sea",     name = "Sea",     file = "Sea.wav"},
}

mixer.LOOP_COUNT = #mixer.LOOPS

function mixer.loop(i)
  return mixer.LOOPS[i]
end

-- state ---------------------------------------------------------------------
-- kept on state.global (like every other player-set number) so a PSET can
-- pick the whole table up in one go when §7.5 persistence lands.

local function levels()
  state.global.amb_level = state.global.amb_level or {}
  return state.global.amb_level
end

-- every loop starts silent, the way the single Rain knob did: the script
-- says nothing until it is asked to.
function mixer.get_level(key)
  local t = levels()
  if t[key] == nil then t[key] = 0 end
  return t[key]
end

function mixer.set_level(key, v)
  local t = levels()
  t[key] = util.clamp(v, 0, 1)
  return t[key]
end

-- the page --------------------------------------------------------------------
-- eight rows: Rain, Cicada, Thunder, Sea, Master, then the gusts' Space,
-- Delay and Regen.

local COARSE, FINE = 1 / 80, 1 / 500

-- §5.2c: these five deliberately share one shape where every other page in
-- the script insists on eight different ones. a mixer IS a row of identical
-- columns -- the repetition is what says "these are the same kind of thing,
-- compare them" -- so `fader` five times over is the reading, not a lapse.
local function level_row(loop)
  return {
    key = "lvl_" .. loop.key, label = loop.name, glyph = "fader",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return mixer.get_level(loop.key) end,
    set = function(v) mixer.set_level(loop.key, v) end,
    text = function() return string.format("%.2f", mixer.get_level(loop.key)) end,
    frac = function() return mixer.get_level(loop.key) end,
    push = function()
      bridge.amb_volume(loop.index, mixer.get_level(loop.key))
    end,
  }
end

mixer.PARAMS = {}

for i, loop in ipairs(mixer.LOOPS) do
  loop.index = i - 1
  mixer.PARAMS[i] = level_row(loop)
end

-- the master is the fifth fader, not a footnote, so it sits on the same row
-- as the four loops. K1+E3 still moves it from anywhere, exactly as before
-- -- this is the same number, given a face.
table.insert(mixer.PARAMS, {
  key = "master", label = "Master", glyph = "fader",
  coarse = COARSE, fine = FINE,
  min = 0, max = 1,
  get = function() return state.global.level or 0.8 end,
  set = function(v) state.global.level = util.clamp(v, 0, 1) end,
  text = function() return string.format("%.2f", state.global.level or 0.8) end,
  frac = function() return state.global.level or 0.8 end,
  push = function() bridge.master_level(state.global.level or 0.8) end,
})

-- §2.11 the gusts' one shared delay line -- "a globally defined delayline
-- that gives it space and ambience". it lands here rather than on the global
-- page for two reasons. it is the same kind of thing the four rows above it
-- are: a level and a room, not a macro that reaches into every voice's
-- parameters. and the arithmetic agrees -- four loops, the master and these
-- three is exactly eight, which is one screen (screenui.PARAMS_PER_PAGE),
-- where putting them on the global page would have pushed a seven-row list
-- onto a second page for the sake of three rows.
--
-- the numbers themselves live in lib/gust.lua, which owns their defaults and
-- their ranges; this is only the face.
local function space_row(key, label, glyph, text_fn, frac_fn, coarse, fine)
  return {
    key = "gust_" .. key, label = label, glyph = glyph,
    coarse = coarse, fine = fine,
    get = function() return wl("gust").get_space(key) end,
    set = function(v) wl("gust").set_space(key, v) end,
    text = text_fn, frac = frac_fn,
    push = function() wl("gust").push_space() end,
  }
end

table.insert(mixer.PARAMS, space_row("space", "Space", "peak",
  function() return string.format("%.2f", wl("gust").get_space("space")) end,
  function() return wl("gust").get_space("space") end,
  COARSE, FINE))

-- in milliseconds, not a 0..1 knob: a delay time is a number you want to
-- read, and often one you want to match to the tempo by eye.
--
-- §5.2c took that number off the screen along with every other one, and this
-- is the row where that trade is most obviously a loss -- `steps` says how
-- far up the range you are but not that you are on a dotted eighth. it is
-- left consistent with the rest of the panel rather than made an exception,
-- because one row that prints a number is a row that looks broken. if the
-- exception is ever wanted, the cheap version is in screenui.lua's header
-- note: show the value in the name slot only while an encoder is turning.
table.insert(mixer.PARAMS, space_row("delay", "Delay", "steps",
  function() return string.format("%.0f ms", wl("gust").get_space("delay") * 1000) end,
  function()
    local g = wl("gust")
    return (g.get_space("delay") - g.DELAY_MIN) / (g.DELAY_MAX - g.DELAY_MIN)
  end,
  0.01, 0.002))

table.insert(mixer.PARAMS, space_row("regen", "Regen", "combs",
  function() return string.format("%.2f", wl("gust").get_space("regen")) end,
  function() local g = wl("gust"); return g.get_space("regen") / g.REGEN_MAX end,
  COARSE, FINE))

mixer.PARAM_COUNT = #mixer.PARAMS

function mixer.param(i)
  return mixer.PARAMS[util.clamp(i, 1, #mixer.PARAMS)]
end

-- the same nudge contract gparam has: `coarse`/`fine` are the step in the
-- param's own units. the five faders are plain 0..1 knobs and clamp here;
-- the three delay rows have ranges of their own and clamp inside
-- gust.set_space, so they carry no min/max and this leaves them alone.
function mixer.nudge(i, delta, is_coarse)
  local p = mixer.param(i)
  local step = (is_coarse and p.coarse or p.fine) or p.coarse
  local v = p.get() + delta * step
  if p.min then v = util.clamp(v, p.min, p.max) end
  p.set(v)
  p.push()
  return p
end

function mixer.push_all()
  for _, p in ipairs(mixer.PARAMS) do p.push() end
end

-- ask the engine to load all four samples, then push every fader. the loads
-- are async on the SC side and the faders are held there whether or not the
-- buffer has landed, so the order of these two does not matter -- see
-- Engine_Canopy.sc's amb_load.
function mixer.init(dir)
  for _, loop in ipairs(mixer.LOOPS) do
    bridge.amb_load(loop.index, dir .. loop.file)
  end
  mixer.push_all()
end

return mixer
