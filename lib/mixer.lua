-- mixer.lua
-- §4.1b the mixer page: the master, and a fader for every Output cell the
-- patch is actually using.
--
-- it used to be a fixed list of eight: four always-on soundscape loops, the
-- master, and the gusts' shared delay line. two of those three moved out.
-- the four loops are the four Sample cells now (§2.5, lib/sample.lua) --
-- played rather than left running -- and the delay line went to the global
-- page, where the rest of the patch-wide numbers live. what is left is the
-- one thing a mixer is actually for.
--
-- so: this page has no fixed contents at all. it is built from the patch. an
-- Output cell nothing is cabled to is not a channel -- it is an empty seat --
-- and putting sixteen faders on screen when one of them is carrying audio
-- means reading fifteen labels to find the one that matters. so the list
-- grows: cable a source to Out 5 and Out 5 appears as a fader, pull that
-- cable and it goes again. an unpatched patch shows the master and nothing
-- else; a fully patched one shows all sixteen, which is the cap because the
-- Output row is sixteen cells long.
--
-- the faders here and the cable gains on the Output row are deliberately two
-- different things. a cable's gain says how much of THAT source arrives at
-- THAT pan position -- it belongs to the cable, and several sources can land
-- on one Out cell. this fader is the channel: everything arriving at that
-- position, together, after the fact. it is the knob you reach for when one
-- side of the stereo image is too loud, which is not a question about any one
-- cable.
--
-- the page object is the same shape gparam's and every cell page's is --
-- PARAMS with get/set/text/frac/push, E1 to pick, E2/E3 to move coarse/fine
-- -- so screenui and Canopy.lua drive it through the code path they already
-- had. it is reached with K3 and left with K2 (Canopy.lua's key handler).

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local bridge   = wl("bridge")

local mixer = {}

-- the Output row is sixteen cells and cannot be more, so this is a statement
-- of the shape of the panel rather than a limit anything has to enforce. it
-- is named because the page's whole contract is "up to this many, and they
-- appear as they are used".
mixer.MAX_CHANNELS = topology.GRID_W

local COARSE, FINE = 1 / 80, 1 / 500

-- state ---------------------------------------------------------------------
-- kept on state.global, like every other player-set number, so a PSET can
-- pick the whole table up in one go when §7.5 persistence lands.
--
-- a channel starts at unity rather than at zero: it appears the moment a
-- cable lands on it, and a fader that materialised silent would read as the
-- cable not having worked.

local function levels()
  state.global.out_level = state.global.out_level or {}
  return state.global.out_level
end

function mixer.get_level(id)
  local t = levels()
  if t[id] == nil then t[id] = 1.0 end
  return t[id]
end

function mixer.set_level(id, v)
  local t = levels()
  t[id] = util.clamp(v, 0, 1)
  return t[id]
end

-- which Output cells are carrying anything, in row order (left to right,
-- which is also hard left to hard right in the stereo field -- so the page
-- reads like the image sounds).
function mixer.active_outputs()
  local out = {}
  for id, cell in topology.each() do
    if cell.type == "O" and patch.degree(id) > 0 then
      table.insert(out, id)
      if #out >= mixer.MAX_CHANNELS then break end
    end
  end
  return out
end

-- the page ------------------------------------------------------------------

-- §5.2c: every row on this page deliberately shares one shape where every
-- other page in the script insists on eight different ones. a mixer IS a row
-- of identical columns -- the repetition is what says "these are the same
-- kind of thing, compare them" -- so `fader` over and over is the reading,
-- not a lapse.
local function channel_row(id, cell)
  return {
    key = "out_" .. id, label = cell.name, glyph = "fader",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return mixer.get_level(id) end,
    set = function(v) mixer.set_level(id, v) end,
    text = function() return string.format("%.2f", mixer.get_level(id)) end,
    frac = function() return mixer.get_level(id) end,
    push = function() bridge.out_level(cell.index, mixer.get_level(id)) end,
  }
end

-- the master is the first fader rather than a footnote at the end: it is the
-- one channel that is always there, and a list whose contents change under
-- you wants a fixed thing at the top for the cursor to come back to. K1+E3
-- still moves it from anywhere, exactly as before -- this is the same number,
-- given a face.
local MASTER_ROW = {
  key = "master", label = "Master", glyph = "fader",
  coarse = COARSE, fine = FINE, min = 0, max = 1,
  get = function() return state.global.level or 0.8 end,
  set = function(v) state.global.level = util.clamp(v, 0, 1) end,
  text = function() return string.format("%.2f", state.global.level or 0.8) end,
  frac = function() return state.global.level or 0.8 end,
  push = function() bridge.master_level(state.global.level or 0.8) end,
}

mixer.PARAMS = {MASTER_ROW}
mixer.PARAM_COUNT = 1

-- rebuilt whenever the cable graph moves, which is the only thing that can
-- change what is on this page. cheap (sixteen cells, user-driven) and it
-- keeps every reader -- screenui's grid, Canopy.lua's encoder handler --
-- reading a plain list rather than asking a question per frame.
function mixer.rebuild()
  local params = {MASTER_ROW}
  for _, id in ipairs(mixer.active_outputs()) do
    table.insert(params, channel_row(id, topology.get(id)))
  end
  mixer.PARAMS = params
  mixer.PARAM_COUNT = #params
  -- the cursor cannot be left pointing past the end of a list that just got
  -- shorter, and the page it was on may not exist any more either.
  state.mparam_focus = util.clamp(state.mparam_focus or 1, 1, mixer.PARAM_COUNT)
  return mixer.PARAMS
end

patch.on_change(mixer.rebuild)

function mixer.param(i)
  return mixer.PARAMS[util.clamp(i, 1, #mixer.PARAMS)]
end

-- the same nudge contract gparam has: `coarse`/`fine` are the step in the
-- param's own units. every row here is a plain 0..1 fader, so they all clamp
-- the same way.
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

-- every Output cell's level, not just the ones on the page: a channel that
-- has been cabled and then unpatched keeps its number here, and the engine
-- has to be holding that same number for when it comes back.
function mixer.push_every_output()
  for id, cell in topology.each() do
    if cell.type == "O" then
      bridge.out_level(cell.index, mixer.get_level(id))
    end
  end
end

function mixer.init()
  mixer.rebuild()
  bridge.master_level(state.global.level or 0.8)
  mixer.push_every_output()
end

return mixer
