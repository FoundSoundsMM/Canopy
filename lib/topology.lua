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
-- Turing Machines are unchanged; the weave/heartwood/exciter families keep
-- their mechanics with a smaller, curated set of default seats; and the two
-- bottom rows carry ten Gust cells -- small drone synths, one per cell (the
-- Q4/Q6 step-sequencer lanes that were briefly there are gone; see §2.11).
-- `cell.letter` is a *display* override only -- code that needs the mechanic
-- still reads `cell.type`.
--
--       1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
--  1    O   O   O   O   O   O   O   O   O   O   O   O   O   O   O   O
--  2    .   M   .   M   .   F   F   F   N   N   N   .   M   .   M   .
--  3    .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .
--  4    F   .   .  TM  TM   C   T   T   T   T   C  TM  TM   .   .   S
--  5    .   F   .   .   .   C   T   T   T   T   C   .   .   .   S   .
--  6    E   .   F   .   .   .   L   L   L   L   .   .   .   S   .   R
--  7    E   E   .   F   .   G   G   G   G   G   G   .   S   .   R   R
--  8    E   E   E   .   .   G   G   G   G   G   G   .   .   R   R   R
--
--   O  output (16)     M  voice (4)        F  grove field / percussion-ping
--   N  percussion-noise TM Turing Machine  C  clock (4)
--   T  trigger source (8, was D)           S  sample player (4)
--   E  exciter (6, was S)                  R  weave (6)
--   G  gust (12, drone synths)             L  LFO (4, sine modulators)
--   .  unregistered, dark and inert

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

-- all four sit together on row 2 now, two either side of the six percussion
-- cells, rather than two up top and two buried among the E/R families in row
-- 7 -- where the panel read as having two voices, not four.
local VOICES = {
  {id = "oak",   name = "Oak",   index = 1, root = 55,  decay = 1.2,  struct = 0.55, damp = 1.1, x = 2,  y = 2},
  {id = "hazel", name = "Hazel", index = 2, root = 220, decay = 0.28, struct = 0.95, damp = 1.3, x = 4,  y = 2},
  {id = "alder", name = "Alder", index = 3, root = 98,  decay = 1.6,  struct = 0.50, damp = 0.8, x = 13, y = 2},
  {id = "rowan", name = "Rowan", index = 4, root = 330, decay = 1.8,  struct = 0.75, damp = 0.6, x = 15, y = 2},
}

for _, v in ipairs(VOICES) do
  reg("voice", v.id, v.name, {{v.x, v.y}},
      {index = v.index, root = v.root, decay = v.decay,
       struct = v.struct, damp = v.damp})
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
-- unchanged: independent 8-bit shift-register sequencers, no phase of their
-- own, moved only by an incoming pulse. see lib/tm.lua.

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

-- 2.5 sample players -- S (4, internally type "SMP") ------------------------
-- what used to be the heartwood diffusion lattice. that family was four cells
-- of one shared mechanic nobody could hear the shape of -- a pulse went in,
-- something came out somewhere else later, and the only knob was a single
-- "conductance" number standing in for two quantities at once. it is gone.
--
-- in its place, four sample players, one per field recording under audio/.
-- a pulse (or K1+tap) plays that sample under an envelope with a slow attack
-- and a slow fall the player sets per cell, so the same four soundscapes that
-- used to sit under the patch as always-on loops are now something the patch
-- can actually play. it is cabled to an Output cell like every other source
-- -- these four used to be the exception, panned by their own seat and mixed
-- in automatically, and are not any more. see lib/sample.lua.
--
-- `file` is a name under audio/ and `index` is the engine's own sample slot
-- (0-based), which is also the buffer amb_load fills.
local SMP_CELLS = {
  {id = "rain",    name = "Rain",    file = "Rain.wav",    x = 16, y = 4, attack = 1.2, decay = 6.0},
  {id = "cicada",  name = "Cicada",  file = "Cicada.wav",  x = 15, y = 5, attack = 2.0, decay = 8.0},
  {id = "thunder", name = "Thunder", file = "Thunder.wav", x = 14, y = 6, attack = 0.8, decay = 10.0},
  {id = "sea",     name = "Sea",     file = "Sea.wav",     x = 13, y = 7, attack = 2.5, decay = 9.0},
}

-- these four sit on a diagonal from the right edge inward. they used to
-- carry a `pan` of their own, taken from the column the way a gust's is,
-- because they mixed themselves; the Out cell each is cabled to decides that
-- now, so there is nothing left here but the recording and its envelope.
for i, sm in ipairs(SMP_CELLS) do
  reg("SMP", "smp." .. sm.id, sm.name, {{sm.x, sm.y}}, {
    letter = "S",
    index = i - 1,
    file = sm.file,
    attack = sm.attack,
    decay = sm.decay,
  })
end

topology.SAMPLES = SMP_CELLS

-- 2.6 the grove -- F (4) -----------------------------------------------------
-- the pitch fields, mechanic unchanged (mode keys match grove.lua). trimmed
-- from 8 to 4 -- one representative of each of the most distinct shapes
-- (call/drone/cascade/octave) rather than paired seams; every mode not given
-- a seat here is still reachable by K1+E2 cycling on any F cell.

local F_CELLS = {
  {id = "cuckoo",   x = 1, y = 4, mode = "call"},
  {id = "nightjar", x = 2, y = 5, mode = "drone"},
  {id = "curlew",   x = 3, y = 6, mode = "cascade"},
  {id = "bittern",  x = 4, y = 7, mode = "octave"},
}

for _, f in ipairs(F_CELLS) do
  local id = "f." .. f.id
  local name = f.id:sub(1, 1):upper() .. f.id:sub(2)
  reg("F", id, name, {{f.x, f.y}}, {
    mode = f.mode,
    snap = true,
  })
end

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
-- "N"; a `letter` field carries the display override since the true grove
-- pitch fields already own the bare type string "F".

local GVOICE_CELLS = {
  {id = "yaffle",  x = 6,  y = 2, kind = "ping",  letter = "F", root = 180,  decay = 0.28},
  {id = "knap",    x = 7,  y = 2, kind = "ping",  letter = "F", root = 620,  decay = 0.09},
  {id = "clapper", x = 8,  y = 2, kind = "ping",  letter = "F", root = 95,   decay = 0.40},
  {id = "scree",   x = 9,  y = 2, kind = "noise", letter = "N", root = 4200, decay = 0.06},
  {id = "chaff",   x = 10, y = 2, kind = "noise", letter = "N", root = 1500, decay = 0.16},
  {id = "rattle",  x = 11, y = 2, kind = "noise", letter = "N", root = 750,  decay = 0.22},
}

for i, gc in ipairs(GVOICE_CELLS) do
  local id = "gv." .. gc.id
  local name = gc.id:sub(1, 1):upper() .. gc.id:sub(2)
  reg("GVOICE", id, name, {{gc.x, gc.y}}, {
    letter = gc.letter, kind = gc.kind, index = i, root = gc.root, decay = gc.decay,
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
-- four free-running sine sources, sitting on the row right above the gusts.
-- each is a plain continuous point, patched like anything else -- what a
-- cable out of one bends is decided entirely by the cell at its other end
-- (dispatch.lua), same as an E or H cell's stream; the cable's own gain
-- decides how much. the cell's own page has exactly one row, Speed, so
-- "select a destination" is just the ordinary hold/tap cable gesture and
-- there is nothing else here to set. see lib/lfo.lua.
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
  D      = "Trigger",
  R      = "Process",   -- a trigger processor: the weave's rules
  TM     = "Register",
  C      = "Clock",
  E      = "Exciter",
  F      = "Field",
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
