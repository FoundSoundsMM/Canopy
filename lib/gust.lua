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
--     by where it physically sits (topology's `pan`), through the shared send
--     effect (§2.11c, lib/send.lua -- which was this family's own delay line
--     until every other family got a Send knob into it). a cable
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
--
-- §2.11b this file carries a SECOND page as well: the family's own, reached
-- with K3 from the main screen and sitting just before the mixer: six
-- offsets that move all twelve cells together (gust.MACRO, below). it is
-- `gust.MACROS`, in the same shape gparam.PARAMS and mixer.PARAMS are, so
-- screenui and Canopy.lua drive all three identically.

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

-- Pitch: +-4 octaves. it was +-2, matched to a GVOICE cell's, on the
-- reasoning that a cell only ever wants to be moved into a neighbouring
-- register -- but a gust is the family whose seat IS its note (the twelve
-- roots span barely two octaves between them, §2.11's keyboard), and the
-- thing anyone reaches for on this row is not "a little higher", it is a
-- sub-bass under the bed or a whistle over the top of it. four octaves each
-- way reaches both from any seat, and the whole eight-octave sweep still
-- passes through the cell's own root at the centre detent, so nothing that
-- was dialled in before this changed has moved.
--
-- what stops it running off the end of the audible band is downstream and
-- unchanged: \wl_gust clips its own oscillator to 8..8000 Hz.
gust.PITCH_RANGE_ST = 48

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

local last_note = {}   -- id -> util.time() of the last one that landed

-- the family macros (§2.11b) --------------------------------------------------
-- the gusts got a page of their own, before the mixer, and this is the half
-- of it that is not the delay line: one Pitch, Timbre, Attack, Vib, Cross
-- and Level over all twelve cells at once.
--
-- they are OFFSETS, not values. twelve cells you have spent a while setting
-- individually are the whole point of having twelve, and a unified knob that
-- wrote absolute values would erase that the first time you touched it --
-- worse, it would erase it invisibly, since the per-cell pages would still
-- be showing numbers nothing was reading any more. so each of these sits at
-- a centre that means "leave them alone", and moving it slides all twelve
-- together, keeping whatever spread the player put between them. turn it
-- back to the middle and the twelve are exactly where they were.
--
-- Pitch is in semitones because that is the unit it is already in everywhere
-- else on the panel; the rest are offsets on the 0..1 knobs they ride, so
-- 0.5 is the neutral position and the sum is clamped per cell -- which is
-- what makes the macro run out of travel gracefully at the ends rather than
-- wrapping or shoving cells past each other. Vib is the one exception and
-- says why in the table itself.
--
-- there is no family Decay here, because
-- there already is one. the global page's Decay macro scales every gust's
-- fall along with every voice's and every drum's (gust.decay_seconds folds
-- voice.decay_mult_ratio in), and it is one K2 press away. a second knob
-- doing the same job on the next page would be two controls fighting over
-- one number and no way to tell from either which of them was responsible.
-- Attack has no such macro anywhere and stays.
gust.MACRO = {
  pitch  = 0,     -- semitones, +-MACRO_PITCH_ST
  timbre = 0.5,   -- offsets on the per-cell knob, 0.5 = no change
  attack = 0.5,
  cross  = 0.5,
  level  = 0.5,
  -- Vib is the one offset here whose neutral is NOT the centre of its knob.
  -- every other row on this page rides a per-cell knob whose default is
  -- somewhere in the middle of its travel, so "leave them alone" is the
  -- middle of the macro too. vibrato has a real zero -- none of it -- and
  -- both the cell knob and this one start there, so the family knob ADDS
  -- rather than slides: at 0 the twelve are wherever they were put, and
  -- turning it up puts vibrato on all twelve without having to visit each.
  vib    = 0,
}

-- the macro rows whose neutral is 0 rather than 0.5, and therefore add to
-- the per-cell knob instead of sliding it. see gust.effective.
local MACRO_ADDITIVE = {vib = true}

-- and the one whose bottom half is a FADE rather than a slide. Level is the
-- family's fader, and a fader that cannot reach silence is not one: sliding
-- twelve cells down by half a knob leaves a cell that was at 0.7 sitting at
-- 0.2, which is quieter and audibly still there. so below the centre detent
-- this MULTIPLIES -- 0.5 is the cells' own levels untouched, and 0 is
-- genuinely nothing, whatever the twelve were individually set to. above the
-- centre it slides as every other row here does, because the top half is
-- "all of them louder" and there is no equivalent of silence at that end.
--
-- it is only Level. Timbre, Attack and Cross have no zero worth reaching in
-- one gesture, and a bottom half that behaved differently from the top on
-- those would be a knob that changes meaning halfway along for nothing.
local MACRO_FADE = {level = true}

-- four octaves either way -- the same span a single cell's own Pitch row has,
-- rather than the narrower one this used to keep. the argument for narrower
-- was that this moves twelve cells at once and the useful gesture is shifting
-- the family into a neighbouring register; the argument against is that the
-- family IS the bed, and dropping the whole of it an octave under everything
-- else, or lifting it into a register nothing else on the panel occupies, is
-- exactly the gesture a knob over all twelve is for. the engine's own 8..8000
-- Hz clip is what stops it running off the end.
gust.MACRO_PITCH_ST = 48

-- which per-cell knob each offset rides, and what that knob's own default is.
local MACRO_OVER = {
  timbre = 0.35,
  attack = 0.5,
  cross  = 0.3,
  level  = 0.7,
  vib    = 0,
}

local function macro_defaults()
  state.global.gust_macro = state.global.gust_macro or {}
  local t = state.global.gust_macro
  for k, v in pairs(gust.MACRO) do
    if t[k] == nil then t[k] = v end
  end
  return t
end

function gust.macro(key)
  return macro_defaults()[key]
end

function gust.set_macro(key, v)
  local t = macro_defaults()
  if key == "pitch" then
    t[key] = util.clamp(v, -gust.MACRO_PITCH_ST, gust.MACRO_PITCH_ST)
  else
    t[key] = util.clamp(v, 0, 1)
  end
  return t[key]
end

-- what a cell actually runs on: its own knob, slid by the family offset and
-- clamped back into range. every reader below goes through here rather than
-- through state.get_vparam directly, so there is one place the two numbers
-- are combined and no way for a push and a readout to disagree about it.
function gust.effective(id, key)
  local base = state.get_vparam(id, key, MACRO_OVER[key] or 0.5)
  local m = gust.macro(key)
  if MACRO_ADDITIVE[key] then return util.clamp(base + m, 0, 1) end
  if MACRO_FADE[key] and m < 0.5 then return util.clamp(base * (m * 2), 0, 1) end
  return util.clamp(base + (m - 0.5), 0, 1)
end

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
           + gust.macro("pitch")
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
  local a = gust.effective(id, "attack")
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
  return gust.effective(id, "level")
end

function gust.timbre(id)
  return gust.effective(id, "timbre")
end

function gust.cross(id)
  return gust.effective(id, "cross")
end

-- vibrato ---------------------------------------------------------------------
-- §2.11d one knob, and deliberately one: depth. a second knob for rate would
-- be the difference between a shimmer and a warble, which is worth having on
-- a lead voice -- but twelve drones all warbling at one rate is a chorus
-- pedal stuck on, and twelve at rates a player set individually is twelve
-- knobs nobody is going to visit. so the rate is fixed per cell and spread
-- across the family (gust.vib_rate below), and what the player sets is how
-- much.
--
-- a semitone at the top of the knob. wider than that stops reading as vibrato
-- and starts reading as a siren, and the cell already has a Cross input for
-- anyone who wants pitch modulation on that scale.
gust.VIB_MAX_ST = 1.0

-- how fast, per cell, in Hz. one base rate with a small spread across the
-- twelve seats, so the family never breathes in lockstep -- the same
-- reasoning grove.lua's DRIFT_RATES has, and the same fix: a fixed, uneven
-- ladder rather than a random one, so a patch sounds the same twice.
gust.VIB_RATE_BASE = 4.9
gust.VIB_RATE_SPREAD = 0.11

function gust.vib_rate(id)
  local cell = topology.get(id)
  local i = (cell and cell.index or 1) - 1
  -- an irrational-ish step so twelve cells land on twelve rates that never
  -- come back into phase with each other.
  return gust.VIB_RATE_BASE * (1 + ((i * 0.37) % 1) * gust.VIB_RATE_SPREAD)
end

-- the depth this cell is actually running at, its own knob plus the family's.
function gust.vib(id)
  return gust.effective(id, "vib")
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
    -- shown as the NOTE it will actually sound, not as the knob's own offset
    -- and not in hertz: with a Scale selected the knob moves in steps the
    -- offset does not, and what is worth reading off a drone's page is which
    -- note it is holding. §5.2e -- grove.note_name owns the spelling.
    key = "pitch", label = "Pitch", glyph = "marker", default = 0.5,
    get = vp_get("pitch", 0.5), set = vp_set("pitch"),
    text = function(id)
      return wl("grove").note_name(gust.note_hz(id)) or "-"
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
    -- what the row READS is the effective value -- the knob plus whatever the
    -- family macro is adding to it (§2.11b) -- while what E2/E3 MOVE is the
    -- cell's own stored knob. exactly the arrangement Pitch above already
    -- had, where the reading has always been the note that will sound rather
    -- than the offset that was dialled in.
    key = "timbre", label = "Timbre", glyph = "wave", default = 0.35,
    get = vp_get("timbre", 0.35), set = vp_set("timbre"),
    text = function(id) return string.format("%.2f", gust.timbre(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_timbre(cell.index - 1, gust.timbre(id))
    end,
  },
  {
    -- §2.11d vibrato depth, in semitones at the top of the knob. zero by
    -- default, here and on the family page, so a fresh patch sounds exactly
    -- as it did before this row existed.
    --
    -- `wander` rather than `wave`: Timbre above already draws a waveform on
    -- this page, and the thing this row sets is not a shape -- it is how far
    -- the note strays from the line it is meant to be sitting on, which is
    -- what that glyph draws.
    key = "vib", label = "Vib", glyph = "wander", default = 0,
    get = vp_get("vib", 0), set = vp_set("vib"),
    text = function(id)
      return string.format("%.2f st", gust.vib(id) * gust.VIB_MAX_ST)
    end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_vib(cell.index - 1, gust.vib(id) * gust.VIB_MAX_ST,
                      gust.vib_rate(id))
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
    text = function(id) return string.format("%.2f", gust.cross(id)) end,
    push = function(id)
      local cell = topology.get(id)
      bridge.gust_cross(cell.index - 1, gust.cross(id))
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
  -- §2.11c how much of this cell goes to the send effect. a gust already
  -- reaches that line dry-plus-wet on its own automatic route, so this is a
  -- second, deliberate helping on top of it -- worth having, because the
  -- automatic one is at whatever Space is set to for the whole family.
  wl("send").row(),
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

-- re-push one knob on every cell. what a family macro's own `push` does:
-- moving Timbre on the gust page has to reach all twelve engine-side, and
-- doing it by key rather than by re-pushing whole pages keeps that to twelve
-- messages instead of seventy-two.
function gust.push_key(key)
  for _, p in ipairs(gust.PARAMS) do
    if p.key == key then
      for _, id in ipairs(gust.each()) do p.push(id) end
      return
    end
  end
end

function gust.each()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "GUST" then table.insert(ids, id) end
  end
  return ids
end

-- the shared send effect (§2.11c) --------------------------------------------
-- the delay line all twelve gusts are heard through used to be set from this
-- module: gust.SPACE held its three numbers and the gusts page carried its
-- three rows. it is a SEND now -- every family on the panel can reach it, at
-- whatever its own Send knob says -- so the numbers, the ranges and the rows
-- all moved to lib/send.lua and onto a page of their own past the mixer.
-- nothing about the gusts' own route through it changed: they still arrive
-- dry-plus-wet, exactly as before, and the state is still the same table on
-- state.global so a patch saved before the move comes back on its settings.
--
-- these three forward rather than being deleted outright: gust.init and a
-- handful of callers ask for them by name, and one indirection here is
-- cheaper than teaching each of them where the numbers went.
function gust.get_space(key)
  return wl("send").get_fx(key)
end

function gust.set_space(key, v)
  return wl("send").set_fx(key, v)
end

function gust.push_space()
  wl("send").push_fx()
end

-- the gusts page (§2.11b) -----------------------------------------------------
-- exactly one screen, sitting between the main page and the mixer: the five
-- family offsets above, and nothing else. the whole family in one look.
--
-- it used to carry three more rows -- the Space/Delay/Regen of the delay line
-- all twelve are heard through -- which was right for exactly as long as that
-- line belonged to the gusts. it is a send every family can reach now
-- (§2.11c) and its rows are on their own page past the mixer; a knob that has
-- stopped being about one family has no business on that family's page.
--
-- the page object is the same shape gparam's and mixer's are -- PARAMS with
-- get/set/text/frac/push, E1 to pick, E2/E3 coarse/fine -- so screenui and
-- Canopy.lua drive it through the code path they already have.

local COARSE, FINE = 1 / 80, 1 / 500

-- each family offset keeps the glyph its per-cell row has, rather than six
-- identical bipolar shapes: the drawing says WHAT the knob is (glyph.lua's
-- one rule) and an offset sitting at its centre reads as half-travel, which
-- is what an offset at its centre is.
local function macro_row(key, label, gl)
  return {
    key = "gust_" .. key, label = label, glyph = gl,
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return gust.macro(key) end,
    set = function(v) gust.set_macro(key, v) end,
    text = function() return string.format("%+.2f", gust.macro(key) - 0.5) end,
    frac = function() return gust.macro(key) end,
    push = function() gust.push_key(key) end,
  }
end

gust.MACROS = {
  {
    -- in semitones, like every other pitch on the panel, and shown as the
    -- transpose rather than as a knob position: "+7 st" is a thing you can
    -- act on and "0.79" is not.
    key = "gust_pitch", label = "Pitch", glyph = "marker",
    coarse = 1, fine = 0.1,
    min = -gust.MACRO_PITCH_ST, max = gust.MACRO_PITCH_ST,
    get = function() return gust.macro("pitch") end,
    set = function(v) gust.set_macro("pitch", v) end,
    text = function() return string.format("%+.1f st", gust.macro("pitch")) end,
    frac = function()
      return (gust.macro("pitch") + gust.MACRO_PITCH_ST)
             / (2 * gust.MACRO_PITCH_ST)
    end,
    push = function() gust.repush_pitch() end,
  },
  macro_row("timbre", "Timbre", "wave"),
  macro_row("attack", "Attack", "rampup"),
  {
    -- §2.11d the one row on this page that is an AMOUNT rather than an
    -- offset, because vibrato has a real zero and every other row here does
    -- not (see gust.MACRO). it reads in semitones -- the unit the per-cell
    -- row reads in -- rather than as a signed offset, since "+0.30" off a
    -- centre nobody can see would be a number about the knob instead of a
    -- number about the sound.
    key = "gust_vib", label = "Vib", glyph = "wander",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return gust.macro("vib") end,
    set = function(v) gust.set_macro("vib", v) end,
    text = function()
      return string.format("%.2f st", gust.macro("vib") * gust.VIB_MAX_ST)
    end,
    frac = function() return gust.macro("vib") end,
    push = function() gust.push_key("vib") end,
  },
  macro_row("cross",  "Cross",  "link"),
  {
    -- the family fader. its bottom half fades to silence rather than sliding
    -- (see MACRO_FADE), so it reads as a fader's own travel -- "off" at the
    -- bottom, "0.00" at the centre detent where the twelve are exactly where
    -- they were put, and a signed offset above it.
    key = "gust_level", label = "Level", glyph = "fader",
    coarse = COARSE, fine = FINE, min = 0, max = 1,
    get = function() return gust.macro("level") end,
    set = function(v) gust.set_macro("level", v) end,
    text = function()
      local m = gust.macro("level")
      if m <= 0 then return "off" end
      if m < 0.5 then return string.format("x%.2f", m * 2) end
      return string.format("%+.2f", m - 0.5)
    end,
    frac = function() return gust.macro("level") end,
    push = function() gust.push_key("level") end,
  },
}

gust.MACRO_COUNT = #gust.MACROS

function gust.macro_param(i)
  return gust.MACROS[util.clamp(i, 1, #gust.MACROS)]
end

-- the same nudge contract gparam.nudge and mixer.nudge have: `coarse`/`fine`
-- are the step in the row's own units, and a row with a `min` clamps with it
-- (Pitch clamps itself in `set`, so it declares one only for the encoder's
-- benefit).
function gust.macro_nudge(i, delta, is_coarse)
  local p = gust.macro_param(i)
  if not p then return nil end
  local step = (is_coarse and p.coarse or p.fine) or p.coarse
  local v = p.get() + delta * step
  if p.min then v = util.clamp(v, p.min, p.max) end
  p.set(v)
  p.push()
  return p
end

function gust.push_macros()
  for _, p in ipairs(gust.MACROS) do p.push() end
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
