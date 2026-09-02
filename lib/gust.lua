-- gust.lua
-- §2.11: the twelve Gust cells -- a small drone synth per cell, and the settings
-- page for one.
--
-- what a gust is, in one paragraph. a triangle core, folded at its edges so
-- it is raw rather than sterile, under an envelope with a slow attack and a
-- slow decay that the player sets per cell. it sounds when you press its
-- key, and it sounds when a pulse reaches it down a cable, and it answers
-- with a pulse of its own a tick later like every other struck cell on the
-- panel. what is patched into it bends its timbre and its pitch rather than
-- just being mixed with it, so two gusts cabled together cross-modulate --
-- which is the one thing about a Ciat-Lonbarde Deerhorn worth taking whole.
--
-- it is a reference, not a schematic. there is no antenna, no four-quadrant
-- multiplier, and no attempt at the original's exact circuit -- the grid key
-- does the job an approaching hand did there.
--
-- two things a gust does that nothing else on the panel does:
--
--   * it is heard uncabled. every other source is silent until it reaches
--     the Output row; a gust is routed to the main mix by the engine, panned
--     by where it physically sits (topology's `pan`), through a delay line
--     shared by all twelve (gust.SPACE, driven from the global page). a cable
--     into an Output cell is still allowed and still means what it means --
--     it just places a second copy rather than being the only way to hear
--     the first.
--   * its pitch is not its own. `root` is where the cell sits, Pitch moves
--     it, and the sum is then pulled onto the global Scale (§4.1) before it
--     is sounded -- so all twelve keys land in one scale, whichever notes the
--     player has moved them to.
--
-- the page is the same object voice.lua and gvoice.lua expose -- PARAMS with
-- get/set/text/push, plus nudge/param/PARAM_COUNT -- so cellparam.lua hands
-- it to screenui and gridui through the one code path they already have.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local voice    = wl("voice")

local gust = {}

-- the reference the global Scale is rooted on, and the pitch every cell's
-- `root` is measured against. A1: low enough that every gust sits a whole
-- number of scale degrees above it rather than being quantised down into a
-- register nothing else on the panel occupies.
gust.REF_HZ = 55.0

-- Pitch: the same +-2 octaves a GVOICE cell's Pitch has, and for the same
-- reason -- wide enough to move a cell into another register entirely, fine
-- enough at the centre to nudge one note.
gust.PITCH_RANGE_ST = 24

-- Attack and Decay are logarithmic: the useful half of a swell time is the
-- bottom of it, and a knob linear in seconds spends most of its travel
-- between "very slow" and "slightly slower". 0.5 is the cell's own default
-- (topology's `attack`/`decay`) and the knob sweeps this many octaves of
-- ratio either side -- the same shape voice.DECAY_OCTAVES has.
gust.ATTACK_OCTAVES = 2.5
gust.DECAY_OCTAVES = 2

-- hard limits, matching \wl_gust's own clips in Engine_Canopy.sc.
gust.ATTACK_MIN, gust.ATTACK_MAX = 0.01, 12.0
gust.DECAY_MIN, gust.DECAY_MAX = 0.05, 30.0

-- a gust is a slow sound and a key is a fast gesture, so a re-press does not
-- get the strike refractory a drum head does (dispatch.VOICE_REFRACTORY):
-- retriggering a swell part-way up is a legitimate thing to want, and the
-- engine lags the envelope's restart so it is a lift rather than a click.
-- what it does get is a floor short enough to be inaudible and long enough
-- that a cable looped back round into a gust cannot machine-gun it.
gust.REFRACTORY = 0.012

local last_note = {}   -- id -> util.time() of the last note that landed

-- pitch ---------------------------------------------------------------------

-- where this cell sits, in semitones above gust.REF_HZ. topology stores the
-- root in Hz (the same field every other sounding cell uses); this is the
-- conversion back, so the roots there stay readable as pitches.
function gust.root_semitones(id)
  local cell = topology.get(id)
  if not cell or not cell.root then return 0 end
  return 12 * math.log(cell.root / gust.REF_HZ) / math.log(2)
end

-- the note a press actually sounds: the cell's own seat, plus its Pitch
-- knob, plus the global transpose -- and then the whole sum quantised, so
-- the Scale decides the note rather than merely colouring it. with Scale on
-- "free" (index 0) grove.quantise_semitones is the identity and a gust plays
-- exactly where it was put.
function gust.note_semitones(id)
  local v = state.get_vparam(id, "pitch", 0.5)
  local st = gust.root_semitones(id)
           + (v - 0.5) * 2 * gust.PITCH_RANGE_ST
           + (state.global.pitch_offset or 0)
  return wl("grove").quantise_semitones(st)
end

function gust.note_hz(id)
  return gust.REF_HZ * (2 ^ (gust.note_semitones(id) / 12))
end

-- envelope -------------------------------------------------------------------

function gust.attack_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "GUST" then return nil end
  local a = state.get_vparam(id, "attack", 0.5)
  return util.clamp(cell.attack * (2 ^ ((a - 0.5) * 2 * gust.ATTACK_OCTAVES)),
                    gust.ATTACK_MIN, gust.ATTACK_MAX)
end

-- Decay rides on state.decay rather than on a vparam of its own, exactly the
-- way a voice's and a GVOICE cell's do, so the global Decay macro (§4.1)
-- reaches the gusts too -- "every voice" in that macro's description was
-- never meant to stop at the ones that get struck.
function gust.decay_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "GUST" then return nil end
  local d = state.get_decay(id)
  return util.clamp(cell.decay * (2 ^ ((d - 0.5) * 2 * gust.DECAY_OCTAVES))
                      * voice.decay_mult_ratio(),
                    gust.DECAY_MIN, gust.DECAY_MAX)
end

function gust.level(id)
  return state.get_vparam(id, "level", 0.7)
end

-- sounding --------------------------------------------------------------------

-- play this cell's note. `force` is how hard -- a key press is full, a pulse
-- arrives at whatever weight and cable gain it has left. returns true if the
-- note actually went out, false if the refractory swallowed it, so callers
-- can decide whether to flash and whether to answer.
function gust.play(id, force)
  local cell = topology.get(id)
  if not cell or cell.type ~= "GUST" then return false end
  local now = util.time()
  -- `>= 0` as well as `< refractory`, same as dispatch.strike_voice: a clock
  -- that has gone backwards (a reload, the test harness rewinding its
  -- virtual time) must read as "long ago" rather than latch the cell silent.
  local since = now - (last_note[id] or -1)
  if since >= 0 and since < gust.REFRACTORY then return false end
  last_note[id] = now

  local f = util.clamp(force or 1, 0, 1)
  bridge.gust_note(cell.index - 1, gust.note_hz(id), f)
  state.flash(id, f)
  return true
end

-- the grid key itself (gridui, on key *down* -- a key that waits for the
-- release to sound is not a key). full force: how hard you pressed is not
-- something a monome grid knows.
function gust.press(id)
  return gust.play(id, 1.0)
end

-- §5.1: how brightly the cell sits when nothing is being patched. the same
-- shape a GVOICE cell's indicator has -- open page brightest, cabled next,
-- idle dim -- with the note flash on top. a gust's real envelope is seconds
-- long and only SC knows where it is; the flash is the press, not the sound.
function gust.level_at(id, base)
  base = base or 2
  local lvl = (state.cell_edit == id) and 10
           or (wl("patch").degree(id) > 0 and 5 or base)
  return state.flash_level(id, lvl)
end

-- the page ---------------------------------------------------------------------
-- six rows, one screen. Pitch and the two envelope times are the three that
-- define the note; Timbre, Cross and Level are what it sounds like.

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

gust.PARAMS = {
  {
    -- shown as the note it will actually sound, not as the knob's own
    -- offset: with a Scale selected the knob moves in steps the offset does
    -- not, and the number worth reading is where the key has landed.
    key = "pitch", label = "Pitch", glyph = "marker", default = 0.5,
    get = vp_get("pitch", 0.5), set = vp_set("pitch"),
    text = function(id)
      return string.format("%.1f Hz", gust.note_hz(id))
    end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_pitch(cell.index - 1, gust.note_hz(id))
    end,
  },
  {
    key = "attack", label = "Attack", glyph = "rampup", default = 0.5,
    get = vp_get("attack", 0.5), set = vp_set("attack"),
    text = function(id) return string.format("%.2f s", gust.attack_seconds(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_attack(cell.index - 1, gust.attack_seconds(id))
    end,
  },
  {
    key = "decay", label = "Decay", glyph = "ramp", default = 0.5,
    get = function(id) return state.get_decay(id) end,
    set = function(id, v)
      state.decay[id] = util.clamp(v, 0, 1)
      return state.decay[id]
    end,
    text = function(id) return string.format("%.2f s", gust.decay_seconds(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_decay(cell.index - 1, gust.decay_seconds(id))
    end,
  },
  {
    -- how hard the triangle is folded on its way out: 0 is close to a plain
    -- triangle, 1 is the reedy, buzzing end of the same oscillator. this is
    -- the knob that decides whether a gust is a flute or a horn.
    key = "timbre", label = "Timbre", glyph = "wave", default = 0.35,
    get = vp_get("timbre", 0.35), set = vp_set("timbre"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "timbre", 0.35)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_timbre(cell.index - 1, state.get_vparam(id, "timbre", 0.35))
    end,
  },
  {
    -- how deeply whatever is cabled in modulates this gust -- its pitch and
    -- its fold together, which is what makes two gusts cabled to each other
    -- cross-modulate rather than merely sum. at 0 a cable into this cell is
    -- inaudible, so the knob is also the cell's own "listen to the patch"
    -- switch.
    key = "cross", label = "Cross", glyph = "link", default = 0.3,
    get = vp_get("cross", 0.3), set = vp_set("cross"),
    text = function(id) return string.format("%.2f", state.get_vparam(id, "cross", 0.3)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_cross(cell.index - 1, state.get_vparam(id, "cross", 0.3))
    end,
  },
  {
    key = "level", label = "Level", glyph = "fader", default = 0.7,
    get = vp_get("level", 0.7), set = vp_set("level"),
    text = function(id) return string.format("%.2f", gust.level(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_amp(cell.index - 1, gust.level(id))
    end,
  },
}

gust.PARAM_COUNT = #gust.PARAMS

function gust.param(i)
  return gust.PARAMS[util.clamp(i, 1, #gust.PARAMS)]
end

function gust.nudge(id, i, delta)
  local p = gust.param(i)
  p.set(id, util.clamp(p.get(id) + delta, 0, 1))
  p.push(id)
  return p
end

function gust.push_all(id)
  for _, p in ipairs(gust.PARAMS) do p.push(id) end
end

function gust.each()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "GUST" then table.insert(ids, id) end
  end
  return ids
end

-- the shared delay line (§4.1, the global page's Space / Delay / Regen rows).
-- one line for all twelve cells rather than one each: what it is for is putting
-- the family in a room, and ten rooms is not a room. the numbers live on
-- state.global so a PSET picks them up with everything else.
gust.SPACE = {
  space = 0.35,   -- how much of the delayed signal is heard, 0..1
  delay = 0.38,   -- the line's own time in seconds
  regen = 0.45,   -- how much comes back round, 0..1
}

gust.DELAY_MIN, gust.DELAY_MAX = 0.02, 2.0
gust.REGEN_MAX = 0.92

local function space_defaults()
  state.global.gust_space = state.global.gust_space or {}
  local t = state.global.gust_space
  for k, v in pairs(gust.SPACE) do
    if t[k] == nil then t[k] = v end
  end
  return t
end

function gust.get_space(key)
  return space_defaults()[key]
end

function gust.set_space(key, v)
  local t = space_defaults()
  if key == "delay" then
    t[key] = util.clamp(v, gust.DELAY_MIN, gust.DELAY_MAX)
  elseif key == "regen" then
    t[key] = util.clamp(v, 0, gust.REGEN_MAX)
  else
    t[key] = util.clamp(v, 0, 1)
  end
  return t[key]
end

function gust.push_space()
  bridge.gust_space(gust.get_space("space"), gust.get_space("delay"),
                    gust.get_space("regen"))
end

-- init -------------------------------------------------------------------------

function gust.init()
  for _, id in ipairs(gust.each()) do
    local cell = topology.get(id)
    -- pan is fixed by where the cell sits and is the only thing here the
    -- player cannot move, so it is pushed once and never again.
    bridge.gust_pan(cell.index - 1, cell.pan or 0)
    gust.push_all(id)
  end
  gust.push_space()
end

-- the global Decay macro and a per-cell Decay row both land here.
state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "GUST" then
    bridge.gust_decay(cell.index - 1, gust.decay_seconds(id))
  end
end)

-- a Scale or global-Pitch change moves every gust's note, and unlike a voice
-- a gust holds its pitch between presses -- so re-push them all rather than
-- waiting for the next key.
function gust.repush_pitch()
  for _, id in ipairs(gust.each()) do
    local cell = topology.get(id)
    bridge.gust_pitch(cell.index - 1, gust.note_hz(id))
  end
end

return gust
