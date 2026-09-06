-- mixer.lua
-- §4.1b the mixer page: one channel for every Output cell the patch is
-- actually using, named after the instrument on it, with a live meter.
--
-- it used to be a fixed list of eight: four always-on soundscape loops, the
-- master, and the gusts' shared delay line. none of those three is here any
-- more. the four loops are the four Sample cells (§2.5, lib/sample.lua) --
-- played rather than left running, and cabled to the Output row like every
-- other source, so they are back on this page as ordinary channels rather
-- than as four rows nothing could remove. the delay line went to the global
-- page, where the rest of the patch-wide numbers live. and the master went
-- because a master is not a channel: it is one number over the whole
-- instrument, it is on K1+E3 from every screen including this one, and a
-- fader for it sitting first in a list of channels made the list read as
-- five things of the same kind when it is one thing and four of another.
--
-- so: this page has no fixed contents at all. it is built from the patch. an
-- Output cell nothing is cabled to is not a channel -- it is an empty seat --
-- and putting sixteen faders on screen when one of them is carrying audio
-- means reading fifteen labels to find the one that matters. so the list
-- grows: cable a source to Out 5 and that source appears as a fader, pull
-- that cable and it goes again. an unpatched patch shows nothing at all,
-- which is the honest picture of a patch that makes no sound; a fully
-- patched one shows all sixteen, which is the cap because the Output row is
-- sixteen cells long.
--
-- the channel is named after the SOURCE, not the seat. an Output cell now
-- carries exactly one source (lib/patch.lua's displace_source), which is what
-- makes that possible and is most of the reason for the rule: "Out 11" names
-- a pan position, and by the time there are six channels open the position is
-- the least useful thing about any of them. "Thunder" is what the player
-- reached for the fader to move.
--
-- the faders here and the cable gains on the Output row are deliberately two
-- different things. a cable's gain says how much of that source arrives at
-- that pan position -- it belongs to the cable, and it is set by holding both
-- ends. this fader is the channel: the level of that instrument in the mix,
-- reachable in a list with everything else that is sounding, which is the
-- knob you reach for when one thing is too loud against the others.
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

-- what is on a channel -------------------------------------------------------

-- the one source cabled to this Output cell, or nil. "the one" is a rule
-- rather than a hope: patch.lua evicts whatever was there when a second
-- source lands, so this can only ever find one. Out<->Out cables are skipped
-- -- they carry no source and would otherwise name a channel after a seat.
function mixer.source_of(id)
  for _, edge in ipairs(patch.edges_at(id)) do
    local other = patch.other(edge, id)
    local cell = topology.get(other)
    if cell and cell.type ~= "O" then return other end
  end
  return nil
end

-- what the channel is called: the instrument on it, falling back to the
-- seat's own name for the one case that can still reach here (an Out cell
-- cabled only to another Out cell -- a legal patch, and a channel, just not
-- one with an instrument behind it).
function mixer.channel_name(id)
  local src = mixer.source_of(id)
  if src then
    local cell = topology.get(src)
    if cell then return cell.name end
  end
  local cell = topology.get(id)
  return cell and cell.name or id
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

-- metering -------------------------------------------------------------------
-- §7.4's back-channel, pointed at the Output row: Engine_Canopy.sc runs one
-- \wl_out_meter envelope follower over the sixteen output buses and exposes
-- each as a poll named "out_lvl_<index>", matching the O cell's own 0-based
-- `index` the same way the exciter meters match theirs.
--
-- the value is read POST-fader engine-side, which is the only reading that
-- makes sense next to a fader: pull a channel down and its meter falls with
-- it, so what the meter says and what you hear are the same statement.

local METER_HZ = 20
-- the same cosmetic gain the exciter meters carry, and for the same reason:
-- every source on the panel ends its output chain with a headroom multiplier,
-- so a channel that is comfortably audible sits well under 1 as a raw
-- amplitude. tuned by eye, like exciter.METER_GAIN.
local METER_GAIN = 4

local meters = {}   -- O cell id -> 0..1, last reading

function mixer.meter(id)
  return meters[id] or 0
end

function mixer.start_meters()
  for id, cell in topology.each() do
    if cell.type == "O" then
      local p = poll.set("out_lvl_" .. cell.index, function(v)
        meters[id] = util.clamp((v or 0) * METER_GAIN, 0, 1)
      end)
      if p then
        p.time = 1 / METER_HZ
        p:start()
      end
    end
  end
end

-- the page ------------------------------------------------------------------

-- §5.2c: every row on this page deliberately shares one shape where every
-- other page in the script insists on eight different ones. a mixer IS a row
-- of identical columns -- the repetition is what says "these are the same
-- kind of thing, compare them" -- so `channel` over and over is the reading,
-- not a lapse.
--
-- `channel` rather than `fader` because these are the only faders on the
-- panel with a live signal behind them: the shape is a fader with a meter
-- beside it, and `glyph_data` is where that meter comes from -- read per
-- frame, since a meter that only moved when a cable did would not be one.
--
-- the label is resolved at rebuild time rather than per frame, which is
-- correct because rebuild runs on every change to the cable graph and the
-- cable graph is the only thing that can change a channel's name. a second
-- source landing on an occupied Out cell evicts the first (patch.lua), which
-- is a graph change, so the channel is renamed on the same gesture.
local function channel_row(id)
  return {
    key = "out_" .. id, label = mixer.channel_name(id), glyph = "channel",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return mixer.get_level(id) end,
    set = function(v) mixer.set_level(id, v) end,
    text = function() return string.format("%.2f", mixer.get_level(id)) end,
    frac = function() return mixer.get_level(id) end,
    glyph_data = function() return {meter = mixer.meter(id)} end,
    push = function()
      bridge.out_level(topology.get(id).index, mixer.get_level(id))
    end,
  }
end

mixer.PARAMS = {}
mixer.PARAM_COUNT = 0

-- rebuilt whenever the cable graph moves, which is the only thing that can
-- change what is on this page. cheap (sixteen cells, user-driven) and it
-- keeps every reader -- screenui's grid, Canopy.lua's encoder handler --
-- reading a plain list rather than asking a question per frame.
function mixer.rebuild()
  local params = {}
  for _, id in ipairs(mixer.active_outputs()) do
    table.insert(params, channel_row(id))
  end
  mixer.PARAMS = params
  mixer.PARAM_COUNT = #params
  -- the cursor cannot be left pointing past the end of a list that just got
  -- shorter, and the page it was on may not exist any more either. it floors
  -- at 1 rather than at PARAM_COUNT so an empty mixer leaves it somewhere
  -- legal for the next channel to appear under.
  state.mparam_focus =
    util.clamp(state.mparam_focus or 1, 1, math.max(1, mixer.PARAM_COUNT))
  return mixer.PARAMS
end

patch.on_change(mixer.rebuild)

-- nil on an empty page, which is a state this list can genuinely be in now
-- that there is no master row holding it open. every caller checks.
function mixer.param(i)
  if #mixer.PARAMS == 0 then return nil end
  return mixer.PARAMS[util.clamp(i, 1, #mixer.PARAMS)]
end

-- the same nudge contract gparam has: `coarse`/`fine` are the step in the
-- param's own units. every row here is a plain 0..1 fader, so they all clamp
-- the same way.
function mixer.nudge(i, delta, is_coarse)
  local p = mixer.param(i)
  if not p then return nil end
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
  -- the master has no fader here any more, but it is still a number the
  -- engine has to be holding -- K1+E3 moves it from every screen, this page
  -- included, and nothing else pushes it at startup.
  bridge.master_level(state.global.level or 0.8)
  mixer.push_every_output()
  mixer.start_meters()
end

return mixer
