-- synth.lua
-- §2.13: the four cells at the right-hand end of the instrument row, and the
-- settings page for one. two families, one file:
--
--   FM (the panel's "X")  a two-operator FM voice. one sine modulating the
--                         phase of another, at a Ratio you set, by an Index
--                         you set, with the modulator able to feed back into
--                         itself. no operator stack and no algorithm menu.
--   VA (the panel's "V")  a variable-waveform virtual-analogue voice. one
--                         oscillator walking from sine through triangle to
--                         saw, pink noise blended alongside it, a Buchla-
--                         style wavefolder, and then a resonant low-pass with
--                         its own envelope amount.
--
-- one file because they are one idea -- a struck synth voice with an envelope
-- of its own -- differing in what makes the tone, and because everything
-- outside the PARAMS lists (pitch, the strike, the refractory, the engine
-- push, the grid indicator) is identical between them. two files would have
-- been the same two hundred lines twice.
--
-- what they have in common with a modal voice, and what they do not.
--
--   * they are STRUCK. a pulse cabled in plays a note, K1+tap plays a note,
--     and a High clock holds one open -- exactly the vocabulary a voice or a
--     drum has. they are not gusts: a gust is a key you press and a drone
--     that routes itself, and these are neither.
--   * their pitch runs through grove.lua, the same route a modal voice's
--     does. a field or a register cabled in tunes them, the global Pitch
--     transposes them, and the global Scale has the last word. that is the
--     whole reason to put them through grove rather than give them a private
--     note like a gust has: a TM cabled to one has to play it in the same key
--     the rest of the panel is in.
--   * they are heard only through an Output cable, like everything except a
--     gust.
--   * they have no glide and no drift of their own. a modal voice has both
--     because it is a bank of ringing resonators whose pitch moves under a
--     note that is already sounding; these two are oscillators, and a
--     portamento on one is a knob nobody asked for.
--
-- the page object is the same shape voice.lua, gvoice.lua and gust.lua expose
-- -- PARAMS with get/set/text/push, plus nudge/param/PARAM_COUNT -- so
-- cellparam.lua hands it to screenui and gridui through the one code path
-- they already have. `synth.page(kind)` picks which of the two.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")
local voice    = wl("voice")
local blend    = wl("blend") -- the Blend page's Tilt: this pair's own share

local synth = {}

-- the two families, by cell type. everything in this file that has to know
-- which engine command to call reaches for one of these rather than
-- branching on the type in line.
synth.KINDS = {
  FM = {
    note  = function(i, hz, f) bridge.fm_note(i, hz, f) end,
    pitch = function(i, hz) bridge.fm_pitch(i, hz) end,
    set   = function(i, k, v) bridge.fm_set(i, k, v) end,
    hold  = function(i, on) bridge.fm_hold(i, on) end,
  },
  VA = {
    note  = function(i, hz, f) bridge.va_note(i, hz, f) end,
    pitch = function(i, hz) bridge.va_pitch(i, hz) end,
    set   = function(i, k, v) bridge.va_set(i, k, v) end,
    hold  = function(i, on) bridge.va_hold(i, on) end,
  },
}

function synth.is(id)
  local cell = topology.get(id)
  return (cell and synth.KINDS[cell.type]) and cell or nil
end

-- the same ±2 octaves a gust's and a drum's Pitch has, and for the same
-- reason: wide enough to move a cell into another register entirely, fine
-- enough at the centre to nudge one note. grove.lua reads this exactly the
-- way it reads voice.tune_semitones -- see PITCHED there.
synth.TUNE_RANGE_ST = 24

function synth.tune_semitones(id)
  return (state.get_vparam(id, "pitch", 0.5) - 0.5) * 2 * synth.TUNE_RANGE_ST
end

-- how far a field or a register moves this cell's pitch. a modal voice has a
-- Depth row for this; these two do not, and sit at the same x1 that row's own
-- centre detent means -- there are already eleven or twelve rows on these
-- pages and a second scaling knob under the one the field itself has is the
-- first thing that would come off again.
function synth.depth()
  return 1.0
end

-- envelope -------------------------------------------------------------------
-- the same log mapping and the same shape as a gust's -- 0.5 is the cell's
-- own default and the knob sweeps octaves of ratio either side of it -- with
-- one difference: the two halves of the knob are not the same width.
--
-- they used to be, three octaves of Attack each way off a 10 ms centre, and
-- that put the top of the row at 80 milliseconds. eighty milliseconds is a
-- soft strike, not a swell: these two are the only oscillator voices on the
-- panel and there was no way to make either of them arrive slowly, which is
-- half of what an oscillator with an envelope is for. the same held below on
-- Decay -- two octaves off a cell's own default is under four seconds.
--
-- so the range is opened UPWARD and only upward. an attack of a
-- ten-thousandth of a second is not a different sound from a thousandth, and
-- a knob that spends its bottom third clamped against a floor is a knob whose
-- bottom third does nothing -- which is exactly what a symmetric widening
-- would have bought. down is what it always was, so a struck FM cell at the
-- bottom of the row is bit-identical to the one that was there before; up
-- reaches a slow swell.
synth.ATTACK_OCTAVES_DOWN = 3
synth.ATTACK_OCTAVES_UP = 9.6     -- 0.01 s * 2^9.6 ~= the 8 s ceiling below
synth.DECAY_OCTAVES_DOWN = 2
synth.DECAY_OCTAVES_UP = 4.5      -- a 1.1 s cell reaches ~25 s

synth.ATTACK_MIN, synth.ATTACK_MAX = 0.001, 8.0
synth.DECAY_MIN, synth.DECAY_MAX = 0.02, 30.0

-- the centre of the Attack knob, in seconds. short, because these two are
-- struck: the default has to be a note that speaks on the hit, and the knob
-- reaches most of ten octaves up from here for anyone who wants a pad.
synth.ATTACK_BASE = 0.01

-- 0..1 -> a ratio, `down` octaves below the centre and `up` above it. one
-- place, because Attack and Decay both do it and getting the two halves out
-- of step between them is the kind of bug that reads as "the knob feels
-- wrong" rather than as a fault.
local function octave_ratio(v, down, up)
  local x = (util.clamp(v, 0, 1) - 0.5) * 2
  return 2 ^ (x * ((x < 0) and down or up))
end

synth.octave_ratio = octave_ratio

function synth.attack_seconds(id)
  local a = state.get_vparam(id, "attack", 0.5)
  return util.clamp(
    synth.ATTACK_BASE
      * octave_ratio(a, synth.ATTACK_OCTAVES_DOWN, synth.ATTACK_OCTAVES_UP),
    synth.ATTACK_MIN, synth.ATTACK_MAX)
end

-- Decay rides on state.decay rather than on a vparam of its own, exactly the
-- way a voice's, a drum's and a gust's do, so the global Decay macro (§4.1)
-- reaches these two as well.
function synth.decay_seconds(id)
  local cell = synth.is(id)
  if not cell then return nil end
  local d = state.get_decay(id)
  return util.clamp(
    cell.decay
      * octave_ratio(d, synth.DECAY_OCTAVES_DOWN, synth.DECAY_OCTAVES_UP)
      * voice.decay_mult_ratio(),
    synth.DECAY_MIN, synth.DECAY_MAX)
end

-- sounding -------------------------------------------------------------------

-- the same refractory a modal voice and a drum head get (dispatch.lua's own
-- VOICE_REFRACTORY, kept as its own number here for the same reason every
-- other module keeps its own copy of a small constant): these are struck
-- cells, a cable looped back round into one is a legal patch, and this is
-- what keeps it from being a machine gun.
synth.REFRACTORY = 0.028

local last_note = {}

-- play this cell's note. `force` is how hard. returns true if the note went
-- out, false if the refractory swallowed it, so callers can decide whether to
-- flash and whether to answer -- the same contract gust.play has.
function synth.play(id, force)
  local cell = synth.is(id)
  if not cell then return false end
  local now = util.time()
  -- `>= 0` as well as `< refractory`, same as dispatch.strike_voice: a clock
  -- that has gone backwards (a reload, the test harness rewinding its virtual
  -- time) must read as "long ago" rather than latch the cell silent.
  local since = now - (last_note[id] or -1)
  if since >= 0 and since < synth.REFRACTORY then return false end
  last_note[id] = now

  local f = util.clamp(force or 1, 0, 1)
  -- the pitch this cell is actually on, fields and registers and the global
  -- Scale included. grove owns that sum; asking it here means a strike lands
  -- on the note whatever moved it last.
  --
  -- §4.1c with this strike's own Plonks detune summed in before the quantise,
  -- the same way a modal voice gets one (grove.on_strike). these two were the
  -- one struck family the macro did not reach, and not for a reason -- the
  -- detune grove pushes on a strike lands on `freq`, and then the note
  -- command below writes `freq` again with the undetuned number, so the offset
  -- was being sent and then overwritten a moment later. asking for it here is
  -- what makes the note that sounds the detuned one.
  local grove = wl("grove")
  local hz = grove.hz(id, grove.strike_detune()) or cell.root
  synth.KINDS[cell.type].note(cell.index - 1, hz, f)
  state.flash(id, f)
  return true
end

-- the page ---------------------------------------------------------------------

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

-- one plain 0..1 row that pushes a named engine argument. `arg` is the
-- SynthDef argument name and has to match Engine_Canopy.sc's fmKeys/vaKeys.
-- `map` turns the knob into whatever the engine wants; without one the knob
-- goes straight through, which is what most of these want.
local function knob(key, label, gl, default, arg, map, text_fn)
  return {
    key = key, label = label, glyph = gl, default = default,
    get = vp_get(key, default), set = vp_set(key),
    text = text_fn or function(id)
      return string.format("%.2f", state.get_vparam(id, key, default))
    end,
    push = function(id)
      local cell = topology.get(id)
      local v = state.get_vparam(id, key, default)
      synth.KINDS[cell.type].set(cell.index - 1, arg, map and map(v) or v)
    end,
  }
end

-- Pitch and the two envelope rows are shared verbatim between the two
-- families: they are the part of a struck synth voice that is not about what
-- makes the tone.

-- the note this cell will actually sound, rather than the knob's own offset:
-- with a Scale selected and a register cabled in, what is worth reading is
-- where the cell has landed. as a NOTE and not in hertz (§5.2e,
-- grove.note_name) -- the same rule the gust page's Pitch row follows.
local function pitch_row()
  return {
    key = "pitch", label = "Pitch", glyph = "marker", default = 0.5,
    get = vp_get("pitch", 0.5), set = vp_set("pitch"),
    text = function(id)
      return wl("grove").note_name(wl("grove").hz(id)) or "-"
    end,
    -- grove owns the sum -- this offset plus every field and register cabled
    -- in plus the global transpose, quantised to the Scale -- so it is grove
    -- that sends it, exactly as it is for a modal voice's Tune row.
    push = function(id) wl("grove").push_voice_now(id) end,
  }
end

local function attack_row()
  return {
    key = "attack", label = "Attack", glyph = "rampup", default = 0.5,
    get = vp_get("attack", 0.5), set = vp_set("attack"),
    text = function(id) return string.format("%.3f s", synth.attack_seconds(id)) end,
    push = function(id)
      local cell = topology.get(id)
      synth.KINDS[cell.type].set(cell.index - 1, "atk", synth.attack_seconds(id))
    end,
  }
end

local function decay_row()
  return {
    key = "decay", label = "Decay", glyph = "ramp", default = 0.5,
    get = function(id) return state.get_decay(id) end,
    set = function(id, v)
      state.decay[id] = util.clamp(v, 0, 1)
      return state.decay[id]
    end,
    text = function(id) return string.format("%.2f s", synth.decay_seconds(id)) end,
    push = function(id)
      local cell = topology.get(id)
      synth.KINDS[cell.type].set(cell.index - 1, "dcy", synth.decay_seconds(id))
    end,
  }
end

-- how deeply whatever is cabled in modulates this cell -- its pitch and, on
-- each family, the thing that decides its brightness (the FM index, the VA
-- fold). the same knob and the same name a gust's Cross is, doing the same
-- job, so a cable into any of the three reads the same way.
local function cross_row()
  return knob("cross", "Cross", "link", 0.3, "cross")
end

-- the Blend page's Tilt (lib/blend.lua) folds in here on the way to the
-- engine, the same way trim folds into voice.amp/gvoice.amp -- the knob
-- itself still reads the player's own setting; only the push is scaled.
local function level_row()
  return knob("level", "Level", "fader", 0.7, "amp",
              function(v) return v * blend.tonal_mult() end)
end

-- FM ---------------------------------------------------------------------------

-- the modulator's ratio to the carrier. a fixed ladder rather than a
-- continuous sweep, because in two-operator FM the ratio is the single thing
-- that decides whether a note is a bell, a horn or a clang, and the ones
-- worth landing on are exact. the integers are in because they are harmonic;
-- the halves are in because they are the classic inharmonic ones; 16 is the
-- top because past it the sidebands are wider than the ear cares about.
--
-- the knob stays a plain continuous 0..1 and the position is DERIVED from it
-- rather than stored -- so the row round-trips through its own getter and
-- needs none of the unrounded-accumulator machinery a genuinely stepped row
-- does (see cellparam.lua's `acc`).
synth.RATIOS = {0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 11, 13, 16}

function synth.ratio_index(id)
  local v = state.get_vparam(id, "ratio", 3 / #synth.RATIOS)
  return util.clamp(math.floor(v * #synth.RATIOS) + 1, 1, #synth.RATIOS)
end

function synth.ratio(id)
  return synth.RATIOS[synth.ratio_index(id)]
end

-- 2:1 -- the plainest useful FM ratio and the one that reads as a tone rather
-- than as an effect. that is entry 4 of the ladder, and this is the knob
-- position whose floor() lands on it.
local RATIO_DEFAULT = 3.5 / 16

synth.FM_PARAMS = {
  pitch_row(),
  {
    key = "ratio", label = "Ratio", glyph = "stack", default = RATIO_DEFAULT,
    get = vp_get("ratio", RATIO_DEFAULT), set = vp_set("ratio"),
    text = function(id) return string.format("x%.1f", synth.ratio(id)) end,
    glyph_data = function(id)
      return {n = #synth.RATIOS, lit = synth.ratio_index(id)}
    end,
    push = function(id)
      local cell = topology.get(id)
      bridge.fm_set(cell.index - 1, "ratio", synth.ratio(id))
    end,
  },
  -- how deep the modulation is. this is the brightness knob: at 0 the cell is
  -- a plain sine whatever the Ratio says, and at 1 it is noise.
  knob("index", "Index", "tilt", 0.3, "index"),
  -- the modulator's own feedback, which walks it from a sine up through a
  -- saw-like shape and on into noise. the DX's own feedback operator, and the
  -- cheapest way to get an operator that is not a pure sine.
  knob("fbk", "Fbk", "combs", 0, "fbk"),
  attack_row(),
  decay_row(),
  cross_row(),
  level_row(),
  -- §2.11c how much of this cell goes to the shared send effect.
  wl("send").row(),
}

-- VA ---------------------------------------------------------------------------

synth.VA_PARAMS = {
  pitch_row(),
  -- sine at 0, triangle at the middle, saw at 1. one knob, one continuous
  -- walk, no waveform switch -- which is the point of calling it variable.
  knob("shape", "Shape", "wave", 0.3, "shape"),
  -- pink noise blended in alongside the core, from none of it to all of it.
  -- with Shape irrelevant at the top of this one, that end of the knob is a
  -- noise voice with a folder and a filter on it, which is a perfectly good
  -- second instrument to have on the cell.
  knob("noise", "Noise", "dots", 0, "noise"),
  -- the wavefolder, ahead of the filter. it makes harmonics the filter then
  -- decides what to do with, which is the Buchla ordering and the reason this
  -- is not a saw through a low-pass with extra steps.
  knob("fold", "Fold", "wander", 0.2, "fold"),
  knob("cutoff", "Cutoff", "tilt", 0.6, "cutoff"),
  knob("res", "Res", "peak", 0.3, "res"),
  -- how far the amplitude envelope opens the filter. a struck voice with a
  -- static filter speaks the same on every note; this is the knob that makes
  -- it move.
  knob("envamt", "Env", "span", 0.4, "envAmt"),
  attack_row(),
  decay_row(),
  cross_row(),
  level_row(),
  wl("send").row(),
}

-- the page object -----------------------------------------------------------
-- one per family, built once and shared, the same shape every other page in
-- this script is.

local pages = {}

local function build(kind, params)
  local page = {PARAMS = params, PARAM_COUNT = #params}
  function page.param(i)
    return params[util.clamp(i, 1, #params)]
  end
  function page.nudge(id, i, delta)
    local p = page.param(i)
    p.set(id, util.clamp(p.get(id) + delta, 0, 1))
    p.push(id)
    return p
  end
  function page.push_all(id)
    for _, p in ipairs(params) do p.push(id) end
  end
  return page
end

function synth.page(kind)
  if not synth.KINDS[kind] then return nil end
  if not pages[kind] then
    pages[kind] = build(kind, (kind == "FM") and synth.FM_PARAMS or synth.VA_PARAMS)
  end
  return pages[kind]
end

-- so callers that have an id rather than a type do not have to look the cell
-- up themselves.
function synth.page_for(id)
  local cell = synth.is(id)
  return cell and synth.page(cell.type) or nil
end

function synth.push_all(id)
  local page = synth.page_for(id)
  if page then page.push_all(id) end
end

-- Tilt re-pushes Level across both families through here rather than
-- waiting for the next per-cell touch -- gust.push_key's shape, over the
-- two PARAMS lists this file keeps instead of one.
function synth.push_level()
  for _, id in ipairs(synth.each()) do
    local page = synth.page_for(id)
    for _, p in ipairs(page.PARAMS) do
      if p.key == "level" then p.push(id) end
    end
  end
end

function synth.each(kind)
  local ids = {}
  for id, cell in topology.each() do
    if synth.KINDS[cell.type] and ((not kind) or cell.type == kind) then
      table.insert(ids, id)
    end
  end
  return ids
end

-- §5.1 the grid indicator: the same shape a drum's and a gust's have -- open
-- page brightest, cabled next, idle dim -- with the strike flash on top.
function synth.level_at(id, base)
  base = base or 2
  local lvl = (state.cell_edit == id) and 10
           or (wl("patch").degree(id) > 0 and 5 or base)
  return state.flash_level(id, lvl)
end

function synth.init()
  for _, id in ipairs(synth.each()) do
    synth.push_all(id)
  end
end

-- the global Decay macro and a per-cell Decay row both land here.
state.on_decay_change(function(id)
  local cell = synth.is(id)
  if cell then
    synth.KINDS[cell.type].set(cell.index - 1, "dcy", synth.decay_seconds(id))
  end
end)

return synth
