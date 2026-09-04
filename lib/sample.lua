-- sample.lua
-- §2.5: the four Sample cells -- Rain, Cicada, Thunder and Sea -- and the
-- settings page for one.
--
-- these four seats used to be the heartwood: a diffusion lattice whose whole
-- control surface was one "conductance" knob standing in for a hop delay and
-- a loss at once, and whose output was a pulse emerging from a different cell
-- some time later. it was the hardest family on the panel to hear the shape
-- of and the hardest to aim, and it is gone.
--
-- what is here instead is the plainest sounding cell the script has. each
-- cell owns one field recording under audio/. a pulse down a cable plays it;
-- so does K1+tap. it plays under an envelope with a slow attack and a slow
-- fall, both set per cell, so a thunder roll can take four seconds to arrive
-- and twelve to leave -- that swell is the whole instrument, and it is the
-- one thing the page is about.
--
-- two things it shares with a gust (§2.11) rather than with a voice:
--
--   * it is heard without being cabled to the Output row. the engine pans it
--     by where the cell sits and mixes it in, so a sample cell that has been
--     triggered is audible with no output patching at all.
--   * it holds its own level, because there is no Output cable whose gain
--     would otherwise be deciding that.
--
-- the four loops these samples used to play as an always-on bed (the mixer's
-- old Rain/Cicada/Thunder/Sea faders) are gone with the same change: the same
-- four recordings are these four cells now, played rather than left running.
--
-- the page object is the same shape voice.lua/gust.lua/lfo.lua expose --
-- PARAMS with get/set/text/push, plus nudge/param/PARAM_COUNT -- so
-- cellparam.lua hands it to screenui and gridui through the one code path
-- they already have.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local sample = {}

-- deliberately much longer at the top than a gust's: "slow" here means the
-- length of a whole passage, not the length of a note. a swell that takes
-- twenty seconds to arrive is the reason this family exists.
sample.ATTACK_MIN, sample.ATTACK_MAX = 0.02, 20.0
sample.DECAY_MIN, sample.DECAY_MAX = 0.10, 40.0

-- log-mapped, both of them, and around the cell's own default rather than
-- around the middle of the range: the useful half of a swell time is its
-- bottom, exactly as in gust.lua.
sample.ATTACK_OCTAVES = 3
sample.DECAY_OCTAVES = 2.5

-- playback rate, in octaves either side of the recording's own speed. a
-- thunder roll at half speed is a different weather system, and pitching
-- cicadas up is the cheapest new sound on the panel.
sample.SPEED_OCTAVES = 1.5

-- a sample is a long sound and a key is a fast gesture, so -- like a gust --
-- a re-press part way up the swell is a legitimate thing to want and gets
-- only a floor short enough to be inaudible.
sample.REFRACTORY = 0.02

local last_note = {}   -- id -> util.time() of the last note that landed

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

-- envelope ------------------------------------------------------------------

function sample.attack_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return nil end
  local a = state.get_vparam(id, "attack", 0.5)
  return util.clamp(cell.attack * (2 ^ ((a - 0.5) * 2 * sample.ATTACK_OCTAVES)),
                    sample.ATTACK_MIN, sample.ATTACK_MAX)
end

-- Decay rides on state.decay rather than on a vparam of its own, the way a
-- voice's, a GVOICE cell's and a gust's all do, so the global Decay macro
-- (§4.1) reaches these four as well.
function sample.decay_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return nil end
  local d = state.get_decay(id)
  return util.clamp(cell.decay * (2 ^ ((d - 0.5) * 2 * sample.DECAY_OCTAVES))
                      * wl("voice").decay_mult_ratio(),
                    sample.DECAY_MIN, sample.DECAY_MAX)
end

function sample.speed_ratio(id)
  local v = state.get_vparam(id, "speed", 0.5)
  return 2 ^ ((v - 0.5) * 2 * sample.SPEED_OCTAVES)
end

function sample.level(id)
  return state.get_vparam(id, "level", 0.7)
end

-- sounding --------------------------------------------------------------------

-- play this cell's sample from the top. `force` is how hard -- K1+tap is
-- full, a pulse arrives at whatever weight and cable gain it has left.
-- returns true if the note actually went out, so callers can decide whether
-- to flash and whether to answer.
function sample.play(id, force)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return false end
  local now = util.time()
  -- `>= 0` as well as `< refractory`, same as dispatch.strike_voice: a clock
  -- that has gone backwards (a reload, the test harness rewinding its virtual
  -- time) must read as "long ago" rather than latch the cell silent.
  local since = now - (last_note[id] or -1)
  if since >= 0 and since < sample.REFRACTORY then return false end
  last_note[id] = now

  local f = util.clamp(force or 1, 0, 1)
  bridge.smp_note(cell.index, f)
  state.flash(id, f)
  return true
end

-- §5.1: how brightly the cell sits. the same shape a gust's indicator has --
-- open page brightest, cabled next, idle dim -- with the trigger flash on
-- top. the real envelope is seconds long and only SC knows where it is; the
-- flash is the trigger, not the sound.
function sample.level_at(id, base)
  base = base or 2
  local lvl = (state.cell_edit == id) and 10
           or (wl("patch").degree(id) > 0 and 5 or base)
  return state.flash_level(id, lvl)
end

-- the page ---------------------------------------------------------------------
-- four rows, half a screen, which leaves the block underneath free for the
-- cell's own description (screenui.draw_cell_scope).

sample.PARAMS = {
  {
    key = "attack", label = "Attack", glyph = "rampup", default = 0.5,
    get = vp_get("attack", 0.5), set = vp_set("attack"),
    text = function(id) return string.format("%.2f s", sample.attack_seconds(id)) end,
    push = function(id)
      bridge.smp_attack(topology.get(id).index, sample.attack_seconds(id))
    end,
  },
  {
    key = "decay", label = "Decay", glyph = "ramp",
    get = function(id) return state.get_decay(id) end,
    set = function(id, v)
      state.decay[id] = util.clamp(v, 0, 1)
      return state.decay[id]
    end,
    text = function(id) return string.format("%.2f s", sample.decay_seconds(id)) end,
    push = function(id)
      bridge.smp_decay(topology.get(id).index, sample.decay_seconds(id))
    end,
  },
  {
    key = "speed", label = "Speed", glyph = "marker", default = 0.5,
    get = vp_get("speed", 0.5), set = vp_set("speed"),
    text = function(id) return string.format("x%.2f", sample.speed_ratio(id)) end,
    push = function(id)
      bridge.smp_speed(topology.get(id).index, sample.speed_ratio(id))
    end,
  },
  {
    key = "level", label = "Level", glyph = "fader", default = 0.7,
    get = vp_get("level", 0.7), set = vp_set("level"),
    text = function(id) return string.format("%.2f", sample.level(id)) end,
    push = function(id)
      bridge.smp_level(topology.get(id).index, sample.level(id))
    end,
  },
}

sample.PARAM_COUNT = #sample.PARAMS

function sample.param(i)
  return sample.PARAMS[util.clamp(i, 1, #sample.PARAMS)]
end

function sample.nudge(id, i, delta)
  local p = sample.param(i)
  p.set(id, util.clamp(p.get(id) + delta, 0, 1))
  p.push(id)
  return p
end

function sample.push_all(id)
  for _, p in ipairs(sample.PARAMS) do p.push(id) end
end

function sample.each()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "SMP" then table.insert(ids, id) end
  end
  return ids
end

-- init -------------------------------------------------------------------------
-- `dir` is the folder the four .wav files live in (Canopy.lua passes
-- norns.state.path .. "audio/"). the loads are async on the SC side and every
-- knob below is held there whether or not the buffer has landed, so the order
-- of these two does not matter -- see Engine_Canopy.sc's smp_load.

function sample.init(dir)
  for _, id in ipairs(sample.each()) do
    local cell = topology.get(id)
    bridge.smp_load(cell.index, dir .. cell.file)
    -- pan is fixed by where the cell sits and is the only thing here the
    -- player cannot move, so it is pushed once and never again.
    bridge.smp_pan(cell.index, cell.pan or 0)
    sample.push_all(id)
  end
end

-- the global Decay macro and a per-cell Decay row both land here.
state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "SMP" then
    bridge.smp_decay(cell.index, sample.decay_seconds(id))
  end
end)

return sample
