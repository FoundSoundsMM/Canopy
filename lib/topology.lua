-- topology.lua
-- the map: cell records, coords, types, adjacency.
-- ids are stable strings (never coordinates) so layout can change without
-- breaking saved patches. see docs/canopy-spec.md §2, §7.5.
--
-- the grid overhaul re-cuts the whole panel again. an explicit Output row
-- replaces the old per-voice fixed panning; each voice's four sockets
-- collapse into one cable endpoint; Climate is gone and its letter is
-- reused for a small Clock family; the six percussion cells become two
-- three-cell groups (the ping ones read "F", the noise ones read "N");
-- the weave/heartwood/exciter families keep
-- their mechanics with a smaller, curated set of default seats; and the two
-- bottom rows carry ten Gust cells -- small drone synths, one per cell (the
-- Q4/Q6 step-sequencer lanes that were briefly there are gone; see §2.11).
-- `cell.letter` is a *display* override only -- code that needs the mechanic
-- still reads `cell.type`.
--
--       1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
--  1    O   O   O   O   O   O   O   O   O   O   O   O   O   O   O   O
--  2    M   M   M   M   .   F   F   F   N   N   N   .   X   X   V   V
--  3    .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .
--  4    S   .   .  TM  TM   C   T   T   T   T   C  TM  TM   .   .   S
--  5    .   S   .   .   .   C   T   T   T   T   C   .   .   .   S   .
--  6    E   .   S   .   .   .   L   L   L   L   .   .   .   S   .   R
--  7    E   E   .   S   .   G   G   G   G   G   G   .   S   .   R   R
--  8    E   E   E   .   .   G   G   G   G   G   G   .   .   R   R   R
--
--   O  output (16)     M  modal voice (4)  F  percussion-ping (3)
--   N  percussion-noise TM Turing Machine  C  clock (4)
--   T  trigger source (8, was D)           S  sample player (8)
--   E  exciter (6, was S)                  R  weave (6)
--   G  gust (12, drone synths)             L  LFO (4, sine modulators)
--   X  2-op FM synth (2)                   V  wavefolding VA synth (2)
--   .  unregistered, dark and inert
--
-- the grove's four pitch fields used to sit on the left-hand diagonal. that
-- family is gone (§2.6): a second diagonal of sample players is there now,
-- mirroring the first, and every one of the eight can be pointed at any
-- recording in the script's audio/ folder.
--
-- row 2 is the instrument row and reads left to right as one sentence: the
-- four modal voices, a gap, the six drums, a gap, the four new synths. it
-- used to interleave them -- two voices, the drums, two more voices -- which
-- put the same family on both sides of the kit and left no seat anywhere for
-- a family that was not already on the panel. grouped, every family is one
-- run of adjacent cells and the two gaps are the only punctuation the row
-- needs.

local topology = {}

topology.cells = {}      -- id -> record
topology.coord = {}      -- coord[x][y] -> id
topology.order = {}      -- ids in registration order (stable iteration)

local function reg(kind, id, name, coords, extra)
  local rec = {id = id, type = kind, name = name, coords = coords}
  if extra then
    for k, v in pairs(extra) do rec[k] = v end
  end
  topology.cells[id] = rec
  table.insert(topology.order, id)
  for _, c in ipairs(coords) do
    topology.coord[c[1]] = topology.coord[c[1]] or {}
    topology.coord[c[1]][c[2]] = id
  end
  return rec
end

-- 2.1 the output row -- O (16) ---------------------------------------------
-- nothing reaches a speaker by default. position along the row sets pan,
-- hard left at column 1 to hard right at column 16 -- cabling a voice or any
-- other source cell to one of these is the only way it is ever heard.

for x = 1, 16 do
  local id = "o." .. x
  reg("O", id, "Out " .. x, {{x, 1}}, {
    index = x - 1,
    pan = -1 + 2 * (x - 1) / 15,
  })
end

-- 2.2 voices (4) -------------------------------------------------------------
-- the socket cluster is gone. one cell per voice is now the whole thing: the
-- tap-to-open-sound-page target *and* the sole cable endpoint. what a cable
-- means is decided by the type at its other end (dispatch.lua's `voice<-*`
-- handlers), the same "every socket is androgynous" principle the panel
-- already ran on -- just with one socket per voice instead of four.

-- all four sit together at the left end of row 2 now. they used to be split
-- two-and-two either side of the drum block, which read as two separate
-- families of two and left the four new synths (§2.13) nowhere to go; the row
-- is one family per run now, modal voices first.
-- §8.6 `trim` is the per-cell half of the level match. every source on the
-- panel was rendered offline and measured -- K-weighted loudness (BS.1770,
-- the peak of a 100 ms window) and sample peak, one cell at a time at its own
-- defaults -- because "some voices are louder than others" was true across a
-- 42 dB spread and no amount of mixer work fixes that; a fader spent undoing
-- a family's own imbalance is a fader you cannot use to balance a piece.
--
-- the family's share of the correction lives in Engine_Canopy.sc, on each
-- SynthDef's output constant. what is left over is per CELL -- a 55 Hz voice
-- and a 330 Hz one are the same SynthDef and eleven decibels apart -- and
-- that is this number, folded into the level Lua pushes for the cell.
--
-- always <= 1, by construction: the engine constant is set by whichever cell
-- of the family needs the most gain, and every other cell is trimmed down
-- from it. so a trim only ever turns a cell down relative to its siblings,
-- and can never push a level past a clip at the far end.
--
-- for the four modal voices the spread is almost all Damp: Rowan's 0.6 lets
-- its high modes ring where Hazel's 1.3 kills them, and a bank that rings for
-- half a second is far louder than one that does not, at the same peak.
local VOICES = {
  {id = "oak",   name = "Oak",   index = 1, root = 55,  decay = 1.2,  struct = 0.55, damp = 1.1, x = 1, y = 2, trim = 1.00},
  {id = "hazel", name = "Hazel", index = 2, root = 220, decay = 0.28, struct = 0.95, damp = 1.3, x = 2, y = 2, trim = 0.89},
  {id = "alder", name = "Alder", index = 3, root = 98,  decay = 1.6,  struct = 0.50, damp = 0.8, x = 3, y = 2, trim = 0.65},
  {id = "rowan", name = "Rowan", index = 4, root = 330, decay = 1.8,  struct = 0.75, damp = 0.6, x = 4, y = 2, trim = 0.19},
}

for _, v in ipairs(VOICES) do
  reg("voice", v.id, v.name, {{v.x, v.y}},
      {index = v.index, root = v.root, decay = v.decay,
       struct = v.struct, damp = v.damp, trim = v.trim})
end

-- 2.3 trigger sources -- T (8, internally type "D") --------------------------
-- unchanged mechanic (free-running gaits, Kuramoto-coupled) -- just a new
-- display letter, since the clock-locking job the "metric" gait/Knocker used
-- to do now belongs to the Clock cells below. Skriker's "swarm" gait is
-- Knocker's replacement: brief, unpredictable clusters of 2-4 micro-pulses,
-- filling the gait bank back out to eight without duplicating Boggart's fixed
-- ratchet or Spriggan's single Bernoulli gate. see rambler.lua for the gait
-- table itself.

local D_CELLS = {
  {id = "hob",      x = 7,  y = 4, gait = "euclidean",   counterpart = "gabriel"},
  {id = "grim",     x = 8,  y = 4, gait = "figure",      counterpart = "spriggan"},
  {id = "shuck",    x = 9,  y = 4, gait = "slow",        counterpart = "boggart"},
  {id = "boggart",  x = 10, y = 4, gait = "burst",       counterpart = "shuck"},
  {id = "spriggan", x = 7,  y = 5, gait = "stochastic",  counterpart = "grim"},
  {id = "gabriel",  x = 8,  y = 5, gait = "drifter",     counterpart = "hob"},
  {id = "hunt",     x = 9,  y = 5, gait = "accelerando", counterpart = "skriker"},
  {id = "skriker",  x = 10, y = 5, gait = "swarm",       counterpart = "hunt"},
}

for _, d in ipairs(D_CELLS) do
  local id = "d." .. d.id
  local name = d.id:sub(1, 1):upper() .. d.id:sub(2)
  reg("D", id, name, {{d.x, d.y}}, {
    letter = "T",
    gait = d.gait,
    counterpart = "d." .. d.counterpart,
    rooted = false,
  })
end

-- 2.3b Turing Machine cells -- TM (4) ---------------------------------------
-- independent shift-register voltage sources -- the right-hand side of a
-- Marbles. no phase of their own, moved only by an incoming pulse, and they
-- answer with a number rather than with a pulse of their own. see lib/tm.lua.

local TM_CELLS = {
  {id = "padfoot",    x = 4,  y = 4, counterpart = "tatterfoal"},
  {id = "barghest",   x = 5,  y = 4, counterpart = "puck"},
  {id = "puck",       x = 12, y = 4, counterpart = "barghest"},
  {id = "tatterfoal", x = 13, y = 4, counterpart = "padfoot"},
}

for _, t in ipairs(TM_CELLS) do
  local id = "tm." .. t.id
  local name = t.id:sub(1, 1):upper() .. t.id:sub(2)
  reg("TM", id, name, {{t.x, t.y}}, {counterpart = "tm." .. t.counterpart})
end

-- 2.9 clock cells -- C (4, new) ----------------------------------------------
-- Climate is gone; the letter is reused for something unrelated. a clock
-- cell has no shape bank and no free phase of its own -- it just flashes on
-- a multiple or division of the master (norns) clock, feeding the trigger
-- block next to it. see the new lib/clockcell.lua.

local CLOCK_CELLS = {
  {id = "toll",  x = 6,  y = 4, counterpart = "peal"},
  {id = "knell", x = 11, y = 4, counterpart = "chime"},
  {id = "chime", x = 6,  y = 5, counterpart = "knell"},
  {id = "peal",  x = 11, y = 5, counterpart = "toll"},
}

-- named by number rather than by a folk name each: four cells that do exactly
-- the same job differing only in their ratio are four of one thing, and
-- "Clock 3" says which one where "Chime" only says which word. the ids keep
-- the old names so saved patches still load.
for i, c in ipairs(CLOCK_CELLS) do
  local id = "clk." .. c.id
  reg("C", id, "Clock " .. i, {{c.x, c.y}}, {counterpart = "clk." .. c.counterpart})
end

-- 2.5 sample players -- S (8, internally type "SMP") ------------------------
-- what used to be the heartwood diffusion lattice, and -- since the fields
-- came off the panel -- what used to be the grove as well. two mirrored
-- diagonals of four, one running in from each edge.
--
-- a pulse (or K1+tap) plays that cell's recording under an envelope with a
-- slow attack and a slow fall the player sets per cell, so the same
-- soundscapes that used to sit under the patch as always-on loops are
-- something the patch can actually play. see lib/sample.lua.
--
-- what a cell no longer carries is which recording it is. `file` was a field
-- here, one .wav per seat, fixed at load -- which made the family exactly as
-- big as the folder shipped with the script. the recording is a KNOB now
-- (sample.lua's File row, one detent per .wav in audio/), so a cell is a
-- player rather than a sound, anything dropped in that folder is on the
-- panel, and eight seats are eight things that can be playing at once
-- instead of four things that can only ever be those four. what is left here
-- is the seat: where it sits, how it swells, and where it lands in the image.
--
-- `trim` went with `file`, and to the same place. it was a per-cell
-- correction for how loud that cell's recording happened to be -- Rain peaks
-- at -1.4 dBFS and Cicada at about -30 -- which is a property of the
-- RECORDING and not of the seat, and stopped meaning anything the moment a
-- seat could play any of them. sample.lua's FILE_TRIM keys it by filename.
--
-- and, like a gust and unlike everything else that makes a sound here, a
-- sample cell is heard without being cabled: it is routed to the main mix by
-- the engine, panned by the column it sits in (`pan` below). it spent one
-- build cabled to an Output cell like a voice, on the principle that one rule
-- about what is audible beats two -- but a field recording is a bed, the
-- thing you reach for it to do is fill the room underneath a patch, and
-- spending an Output seat and a cable on each of eight of them to get there
-- was a tax on the one family that never wanted the placement. a cable to an
-- Output cell is still allowed and still means what it means; it just places
-- a second copy rather than being the only way to hear the first.
--
-- named by number rather than by their recordings, for the reason the clocks
-- and the gusts are: "Rain" named a .wav that seat no longer permanently
-- owns, and the File row on the page says which one it is holding now. the
-- ids keep the old spellings so saved patches still load.
--
-- pan comes from the column and nothing else, spread across the whole panel
-- rather than the family's own span (which is both edges and would put all
-- eight hard left or hard right). SMP_PAN_MAX keeps the outermost pair short
-- of the edge so the image still has somewhere to go.
local SMP_PAN_MAX = 0.8

local SMP_CELLS = {
  -- the left diagonal, running in from the edge -- the four seats the grove's
  -- pitch fields used to have.
  {id = "fen",     x = 1,  y = 4, attack = 1.2, decay = 6.0},
  {id = "mire",    x = 2,  y = 5, attack = 2.0, decay = 8.0},
  {id = "carr",    x = 3,  y = 6, attack = 0.8, decay = 10.0},
  {id = "holt",    x = 4,  y = 7, attack = 2.5, decay = 9.0},
  -- the right diagonal, the original four.
  {id = "rain",    x = 16, y = 4, attack = 1.2, decay = 6.0},
  {id = "cicada",  x = 15, y = 5, attack = 2.0, decay = 8.0},
  {id = "thunder", x = 14, y = 6, attack = 0.8, decay = 10.0},
  {id = "sea",     x = 13, y = 7, attack = 2.5, decay = 9.0},
}

for i, sm in ipairs(SMP_CELLS) do
  reg("SMP", "smp." .. sm.id, "Sample " .. i, {{sm.x, sm.y}}, {
    letter = "S",
    index = i - 1,
    attack = sm.attack,
    decay = sm.decay,
    pan = (((sm.x - 1) / 15) * 2 - 1) * SMP_PAN_MAX,
  })
end

topology.SAMPLES = SMP_CELLS

-- 2.7 the weave -- R (6) -----------------------------------------------------
-- trimmed from 14 to 6: the rules the panel's own history and prose already
-- single out as the most useful on a kit -- a rest, a ghost, an accent, a
-- sift, a meet and a hocket. every rule not given a seat is still reachable
-- by K1+E2 cycling on any R cell.

local R_CELLS = {
  {id = "thicket", x = 16, y = 6, rule = "rest"},
  {id = "tangle",  x = 15, y = 7, rule = "ghost"},
  {id = "stile",   x = 16, y = 7, rule = "hocket"},
  {id = "sneck",   x = 14, y = 8, rule = "sift"},
  {id = "lych",    x = 15, y = 8, rule = "meet"},
  {id = "drove",   x = 16, y = 8, rule = "accent"},
}

for _, r in ipairs(R_CELLS) do
  local id = "r." .. r.id
  local name = r.id:sub(1, 1):upper() .. r.id:sub(2)
  reg("R", id, name, {{r.x, r.y}}, {rule = r.rule})
end

-- 2.7b percussion cells -- F/N (6, internally type "GVOICE") ----------------
-- unchanged mechanic (§2.7b's small drum voice, struck directly, answers
-- with its own pulse a tick later) -- renamed and repositioned into row 2.
-- the three ping cells read "F" on the panel, the three noise cells read
-- "N"; a `letter` field carries the display override, since the mechanic's
-- own type string is "GVOICE".

-- §8.6 `trim`, as on the modal voices above: the two kinds carry their own
-- output constant in the engine and this is the difference between cells of
-- the same kind. Knap is the quietest ping (620 Hz, a 90 ms decay -- barely
-- there before it is gone) and Chaff the quietest noise cell, so those two
-- set their kind's constant and the rest come down to meet them.
local GVOICE_CELLS = {
  {id = "yaffle",  x = 6,  y = 2, kind = "ping",  letter = "F", root = 180,  decay = 0.28, trim = 0.50},
  {id = "knap",    x = 7,  y = 2, kind = "ping",  letter = "F", root = 620,  decay = 0.09, trim = 1.00},
  {id = "clapper", x = 8,  y = 2, kind = "ping",  letter = "F", root = 95,   decay = 0.40, trim = 0.48},
  {id = "scree",   x = 9,  y = 2, kind = "noise", letter = "N", root = 4200, decay = 0.06, trim = 0.65},
  {id = "chaff",   x = 10, y = 2, kind = "noise", letter = "N", root = 1500, decay = 0.16, trim = 0.82},
  {id = "rattle",  x = 11, y = 2, kind = "noise", letter = "N", root = 750,  decay = 0.22, trim = 1.00},
}

for i, gc in ipairs(GVOICE_CELLS) do
  local id = "gv." .. gc.id
  local name = gc.id:sub(1, 1):upper() .. gc.id:sub(2)
  reg("GVOICE", id, name, {{gc.x, gc.y}}, {
    letter = gc.letter, kind = gc.kind, index = i, root = gc.root, decay = gc.decay,
    trim = gc.trim,
  })
end

-- 2.13 the new synths -- X/V (4, internally "FM" and "VA") -------------------
-- the right-hand end of the instrument row, and the first genuinely new
-- sound-making family since the gusts. four cells, two of each kind:
--
--   X  a two-operator FM voice. one sine modulating another, at a Ratio you
--      set, by an Index you set, with the modulator able to feed back into
--      itself. that is the whole of it -- no operator stack, no algorithm
--      menu. two operators is where FM stops being a preset and starts being
--      something you can hear the shape of while you turn the knob.
--   V  a variable-waveform virtual-analogue voice. one oscillator morphing
--      continuously from sine to saw, a noise source blended alongside it, a
--      resonant low-pass, and a Buchla-style wavefolder after the filter --
--      which is what stops it being a subtractive synth with the corners
--      already taken off. fold a sine and you get harmonics that no filter
--      can put back.
--
-- both are struck like a voice and both have an envelope of their own
-- (Attack and Decay per cell), which is what makes them play from the panel's
-- own pulse families rather than droning like a gust. their pitch runs
-- through the same route a modal voice's does -- a field or a register cabled
-- in tunes them, the global Pitch transposes them, and the global Scale has
-- the last word -- so a TM cabled to one plays it in the same key as
-- everything else on the panel.
--
-- `index` is 1-based per KIND, not across the four: the engine keeps two
-- arrays of two, and a cell's index is its slot in its own.
local FM_CELLS = {
  {id = "fm.1", name = "FM 1", index = 1, root = 110.0, decay = 0.9, x = 13, y = 2},
  {id = "fm.2", name = "FM 2", index = 2, root = 220.0, decay = 0.5, x = 14, y = 2},
}

for _, f in ipairs(FM_CELLS) do
  reg("FM", f.id, f.name, {{f.x, f.y}}, {
    letter = "X", index = f.index, root = f.root, decay = f.decay,
  })
end

local VA_CELLS = {
  {id = "va.1", name = "VA 1", index = 1, root = 82.41, decay = 1.1, x = 15, y = 2},
  {id = "va.2", name = "VA 2", index = 2, root = 164.81, decay = 0.6, x = 16, y = 2},
}

for _, v in ipairs(VA_CELLS) do
  reg("VA", v.id, v.name, {{v.x, v.y}}, {
    letter = "V", index = v.index, root = v.root, decay = v.decay,
  })
end

-- 2.4 exciter cells -- E (6, internally type "E", was "S") ------------------
-- trimmed from 20 to 6 -- a spread of textures (rustle, spiky resonance,
-- crackle, grain bursts, pitched chirp, slow walk).

local E_CELLS = {
  {id = "bracken",  x = 1, y = 6, source = "rustle"},
  {id = "gorse",    x = 1, y = 7, source = "spiky"},
  {id = "ember",    x = 2, y = 7, source = "crackle"},
  {id = "windfall", x = 1, y = 8, source = "grain"},
  {id = "mistle",   x = 2, y = 8, source = "chirp"},
  {id = "wisp",     x = 3, y = 8, source = "walk"},
}

for i, e in ipairs(E_CELLS) do
  local id = "e." .. e.id
  local name = e.id:sub(1, 1):upper() .. e.id:sub(2)
  reg("E", id, name, {{e.x, e.y}}, {source = e.source, index = i - 1})
end

-- 2.11 the gusts -- G (12, internally type "GUST") --------------------------
-- twelve small drone synths, one per cell, in the two rows the Q4/Q6 step
-- sequencer lanes used to fill. the lanes are gone: what the panel wanted
-- there was not another way to make a pulse (it already has T, C, R, TM and
-- the heartwood) but something to *play*.
--
-- a gust is loosely a Ciat-Lonbarde Deerhorn voice: a triangle core with a
-- slow swell and a slow decay, raw at the edges, and cross-modulated by
-- whatever is patched into it. it is not a clone -- there is no antenna
-- here, so the grid key is what an approaching hand was: press a cell and
-- that gust sounds its note.
--
-- two things make this family unlike every other sound on the panel:
--
--   * it is heard without being cabled. every other source is silent until
--     it reaches an Output cell; a gust is routed to the main mix
--     automatically, panned by where it physically sits (`pan` below).
--   * its pitch is not its own. each cell has a `root`, but what actually
--     sounds is that root pulled onto the global Scale (§4.1), so twelve
--     cells pressed at random are twelve notes of one scale. see lib/gust.lua.
--
-- pan comes from the column and nothing else, spread across the family's own
-- six-column span rather than the whole panel -- these cells only occupy
-- columns 6..11, and mapping them over all sixteen would leave twelve voices
-- huddled in the middle third of the stereo field. GUST_PAN_MAX keeps the
-- outermost pair short of hard left/right so the image still has somewhere
-- to go.
local GUST_X_MIN, GUST_X_MAX = 6, 11
local GUST_PAN_MAX = 0.8

-- roots are equal-tempered intervals above lib/gust.lua's 55 Hz reference,
-- laid out low-to-high left-to-right so the two rows read like a keyboard:
-- the bottom row is a bed (A2 up to A3), the top row sits roughly an octave
-- above it. the exact Hz matter -- gust.lua converts them back to
-- semitones to quantise them -- so they are written out rather than rounded.
--
-- `attack`/`decay` are this cell's own envelope times in seconds, the centre
-- of the two knobs on its page: the low, wide voices swell and fade slowest.
local GUST_CELLS = {
  -- the top row (6) -- higher, quicker to speak. gale and zephyr are the
  -- two added to bring this row level with the bed below it -- gale low and
  -- broad at the left edge, zephyr the highest and quickest at the right.
  {id = "gale",    x = 6,  y = 7, root = 220.00, attack = 0.50, decay = 2.4},
  {id = "sough",   x = 7,  y = 7, root = 261.63, attack = 0.55, decay = 2.6},
  {id = "eddy",    x = 8,  y = 7, root = 293.66, attack = 0.40, decay = 2.2},
  {id = "whorl",   x = 9,  y = 7, root = 329.63, attack = 0.70, decay = 3.0},
  {id = "flaw",    x = 10, y = 7, root = 392.00, attack = 0.30, decay = 1.8},
  {id = "zephyr",  x = 11, y = 7, root = 440.00, attack = 0.35, decay = 1.6},
  -- the bottom row (6) -- the bed
  {id = "squall",  x = 6,  y = 8, root = 110.00, attack = 1.40, decay = 6.0},
  {id = "flurry",  x = 7,  y = 8, root = 130.81, attack = 0.90, decay = 4.5},
  {id = "snell",   x = 8,  y = 8, root = 146.83, attack = 1.10, decay = 5.0},
  {id = "bluster", x = 9,  y = 8, root = 164.81, attack = 0.75, decay = 4.0},
  {id = "buffet",  x = 10, y = 8, root = 196.00, attack = 1.00, decay = 4.8},
  {id = "haar",    x = 11, y = 8, root = 220.00, attack = 1.60, decay = 6.5},
}

-- numbered rather than named, for the same reason the clocks are: twelve
-- cells of one mechanic that differ only in seat and envelope are twelve of
-- one thing, and reading "Gust 7" off the panel tells you which of the twelve
-- you are holding where "Skriker"-style folk names never did. the ids keep
-- their old spellings so saved patches still load. they are numbered in
-- registration order, which is the top row left-to-right (1-6) and then the
-- bottom row left-to-right (7-12).
for i, gu in ipairs(GUST_CELLS) do
  local id = "gu." .. gu.id
  local name = "Gust " .. i
  local span = (gu.x - GUST_X_MIN) / (GUST_X_MAX - GUST_X_MIN)
  reg("GUST", id, name, {{gu.x, gu.y}}, {
    letter = "G",
    index = i,
    root = gu.root,
    attack = gu.attack,
    decay = gu.decay,
    pan = (span * 2 - 1) * GUST_PAN_MAX,
  })
end

-- 2.12 the LFOs -- L (4, internally type "LFO") -----------------------------
-- four free-running modulators, sitting on the row right above the gusts.
-- each is a plain continuous point, patched like anything else -- what a
-- cable out of one bends is decided entirely by the cell at its other end
-- (dispatch.lua), same as an E cell's stream; the cable's own gain decides
-- how much. the cell's own page carries eight shapes (including a
-- sample-and-hold and an envelope follower on the Output row) and four
-- destination slots, each with its own Target, Param and Depth. see
-- lib/lfo.lua.
local LFO_CELLS = {
  {id = "flood",  x = 7,  y = 6},
  {id = "ebb",    x = 8,  y = 6},
  {id = "neap",   x = 9,  y = 6},
  {id = "spring", x = 10, y = 6},
}

for i, l in ipairs(LFO_CELLS) do
  local id = "lfo." .. l.id
  local name = l.id:sub(1, 1):upper() .. l.id:sub(2)
  reg("LFO", id, name, {{l.x, l.y}}, {index = i - 1})
end

-- what kind of thing this is, in a word ---------------------------------
-- the screen used to print a cell's one-letter panel code in front of its
-- name -- "M Oak", "T Hob", "R Tangle". the letter is the panel's own
-- shorthand and it is silk-screened nowhere: on a monome there is no legend
-- to look it up in, so it was a code you had to have memorised to read the
-- header at all. these are the same information as a word.
--
-- kept short on purpose. the header shares one 128px line with the transport,
-- the page dots and the tempo, so "Trigger Processor" would push the name
-- itself off the end -- these are the longest forms that still leave room for
-- the name beside them.
local FAMILY = {
  voice  = "Voice",
  FM     = "FM",
  VA     = "VA",
  D      = "Trigger",
  R      = "Process",   -- a trigger processor: the weave's rules
  TM     = "Register",
  C      = "Clock",
  E      = "Exciter",
  SMP    = "Sample",
  GUST   = "Gust",
  LFO    = "LFO",
  O      = "Output",
}

-- the percussion cells are two families sharing one mechanic, and the panel
-- already draws them as two ("F" and "N"); say which out loud rather than
-- calling both of them one word.
local GVOICE_FAMILY = {ping = "Drum", noise = "Noise"}

function topology.family(cell)
  if not cell then return "" end
  if cell.type == "GVOICE" then
    return GVOICE_FAMILY[cell.kind] or "Drum"
  end
  return FAMILY[cell.type] or cell.type
end

-- "Voice: Oak", "Trigger: Hob", "Exciter: Ember" -- what a cell is, then
-- which one. a cell already named for its family ("Gust 7", "Clock 2") is
-- left alone: prefixing it would only read "Gust: Gust 7".
function topology.label(id_or_cell)
  local cell = type(id_or_cell) == "string" and topology.get(id_or_cell) or id_or_cell
  if not cell then return "" end
  local fam = topology.family(cell)
  if fam == "" or cell.name:sub(1, #fam) == fam then return cell.name end
  return fam .. ": " .. cell.name
end

-- lookups -------------------------------------------------------------

-- cell id at a grid coordinate, or nil if the bezel is unlit there.
function topology.at(x, y)
  local col = topology.coord[x]
  return col and col[y] or nil
end

function topology.get(id)
  return topology.cells[id]
end

-- iterate all cell ids in stable registration order
function topology.each()
  local i = 0
  return function()
    i = i + 1
    local id = topology.order[i]
    if id then return id, topology.cells[id] end
  end
end

-- the types that carry a pulse of their own -- a phase (D), a rule (R) or a
-- register (TM). traffic between two of them is deferred a scheduler tick so
-- a cycle in the patch cannot recurse, which rambler.lua and heartwood.lua
-- both need to know about. a CLOCK cell is deliberately not a member: it is
-- a pure source, never a pulse target, the same shape climate used to be.
-- neither is a GUST cell: it answers a pulse with a sound, exactly the way a
-- voice or a GVOICE cell does, so it is dispatch's business and not the
-- scheduler's.
topology.PULSE_TYPES = {D = true, R = true, TM = true}

function topology.is_pulse_cell(cell)
  return (cell and topology.PULSE_TYPES[cell.type]) and true or false
end

topology.GRID_W = 16
topology.GRID_H = 8

return topology
