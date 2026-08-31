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
-- their mechanics with a smaller, curated set of default seats; and two new
-- step-sequencer lanes (Q4, Q6) join the panel. `cell.letter` is a *display*
-- override only -- code that needs the mechanic still reads `cell.type`.
--
--       1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
--  1    O   O   O   O   O   O   O   O   O   O   O   O   O   O   O   O
--  2    .   M   .   M   .   F   F   F   N   N   N   .   M   .   M   .
--  3    .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .
--  4    F   .   .  TM  TM   C   T   T   T   T   C  TM  TM   .   .   H
--  5    .   F   .   .   .   C   T   T   T   T   C   .   .   .   H   .
--  6    E   .   F   .   .   .   .   .   .   .   .   .   .   H   .   R
--  7    E   E   .   F   .   .  Q4  Q4  Q4  Q4   .   .   H   .   R   R
--  8    E   E   E   .   .   Q6  Q6  Q6  Q6  Q6  Q6   .   .   R   R   R
--
--   O  output (16)     M  voice (4)        F  grove field / percussion-ping
--   N  percussion-noise TM Turing Machine  C  clock (4)
--   T  trigger source (8, was D)          H  heartwood (4)
--   E  exciter (6, was S)                  R  weave (6)
--   Q4/Q6 step sequencers                  .  unregistered, dark and inert

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

for _, c in ipairs(CLOCK_CELLS) do
  local id = "clk." .. c.id
  local name = c.id:sub(1, 1):upper() .. c.id:sub(2)
  reg("C", id, name, {{c.x, c.y}}, {counterpart = "clk." .. c.counterpart})
end

-- 2.5 heartwood -- H (4) -----------------------------------------------------
-- trimmed from a ring of 8 to a simple chain of 4 (fewer cells, "choose the
-- best ones") -- each node still only neighbours the next/previous one, so
-- energy still visibly travels, just along a line rather than a ring.

local H_CELLS = {
  {id = "taproot", x = 16, y = 4},
  {id = "mycel",   x = 15, y = 5},
  {id = "wyrd",    x = 14, y = 6},
  {id = "ley",     x = 13, y = 7},
}

for i, h in ipairs(H_CELLS) do
  reg("H", "h." .. h.id, h.id:sub(1, 1):upper() .. h.id:sub(2), {{h.x, h.y}},
      {index = i - 1})
end

for i, h in ipairs(H_CELLS) do
  local id = "h." .. h.id
  local nxt = H_CELLS[i + 1] and ("h." .. H_CELLS[i + 1].id) or nil
  local prv = H_CELLS[i - 1] and ("h." .. H_CELLS[i - 1].id) or nil
  local nbrs = {}
  if nxt then table.insert(nbrs, nxt) end
  if prv then table.insert(nbrs, prv) end
  topology.cells[id].neighbors = nbrs
end

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

-- 2.10 step sequencers -- Q4 / Q6 (10, internally type "SEQ") ---------------
-- no phase of their own, like a TM cell -- only a pulse cabled in moves them.
-- one lane is four physical cells, the other six; each is its own cable
-- endpoint and its own tap-toggle step, and the *last* cell of a lane is the
-- "driver": a pulse there advances the shared playhead, a pulse on any other
-- cell in the lane fires that one step directly, independent of the
-- playhead. see the new lib/sequencer.lua.

-- both lanes are centred on the 16-column panel: a 4-cell lane starts at
-- column 7, a 6-cell lane at column 6, so Q4 sits symmetrically inside Q6.
local SEQ_LANES = {
  {group = "q4", coords = {{7, 7}, {8, 7}, {9, 7}, {10, 7}}},
  {group = "q6", coords = {{6, 8}, {7, 8}, {8, 8}, {9, 8}, {10, 8}, {11, 8}}},
}

for _, lane in ipairs(SEQ_LANES) do
  local len = #lane.coords
  for step, xy in ipairs(lane.coords) do
    local id = lane.group .. "." .. step
    local name = lane.group:upper() .. " " .. step
    reg("SEQ", id, name, {xy}, {
      letter = "Q" .. len,
      group = lane.group,
      len = len,
      step = step,
      driver = (step == len),
    })
  end
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

-- the types that carry a pulse of their own -- a phase (D), a rule (R), a
-- register (TM) or a sequencer step (SEQ). traffic between two of them is
-- deferred a scheduler tick so a cycle in the patch cannot recurse, which
-- rambler.lua and heartwood.lua both need to know about. a CLOCK cell is
-- deliberately not a member: it is a pure source, never a pulse target, the
-- same shape climate used to be.
topology.PULSE_TYPES = {D = true, R = true, TM = true, SEQ = true}

function topology.is_pulse_cell(cell)
  return (cell and topology.PULSE_TYPES[cell.type]) and true or false
end

topology.GRID_W = 16
topology.GRID_H = 8

return topology
