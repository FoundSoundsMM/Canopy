-- topology.lua
-- the map: cell records, coords, types, adjacency.
-- ids are stable strings (never coordinates) so layout can change without
-- breaking saved patches. see docs/woodland-spec.md §2, §7.5.
--
-- build phase 6 re-cuts the whole map. the panel is now four voice clusters
-- in the four corners, a sealed box of pulse-makers dead centre, and four
-- banks between them. a large number of coordinates are deliberately *not*
-- registered: an unregistered coordinate is dark and inert, and the shape of
-- what is left is what makes the panel readable at a glance.
--
--       1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
--  1    .   T   .   S   S   S   S   S   S   S   S   S   S   .   T   .
--  2    P   V   M   R   R   R   R   R   R   R   R   R   R   P   V   M
--  3    .   O   .   F   H   .   .   .   .   .   .   H   F   .   O   .
--  4    C   .   C   F   H   .   D   D   D   D   .   H   F   C   .   C
--  5    C   .   C   F   H   .   D   D   D   D   .   H   F   C   .   C
--  6    .   T   .   F   H   .   .   .   .   .   .   H   F   .   T   .
--  7    P   V   M   R   R   R   R   R   R   R   R   R   R   P   V   M
--  8    .   O   .   S   S   S   S   S   S   S   S   S   S   .   O   .
--
--   V  the voice itself -- not a socket. tap it to edit its sound (§5.5).
--   T  trigger in       a pulse strikes the resonator
--   P  pitch in         a field cabled here tunes it
--   M  mod in           a stream bends it; a pulse chokes it
--   O  out              its audio tap, and a pulse every time it is struck
--   D  pulse-makers (8) free-running gaits (§2.3)
--   R  the weave (20)   pulse transforms -- what happens *between* cells
--   S  exciters (20)    the noise sources (§2.4)
--   F  fields (8)       wandering pitch (§2.6, was "P" before the re-cut)
--   H  heartwood (8)    the diffusion lattice (§2.5)
--   C  climate (8)      slow modulators -- the long game

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

-- 2.1 voices ------------------------------------------------------------

-- `root` is the voice's fundamental in Hz and `decay` its default ring time
-- in seconds -- columns 2 and 6 of Engine_Woodland.sc's `voiceDefs` table,
-- duplicated here because both are needed on the Lua side: grove.lua computes
-- an absolute Hz from a semitone offset, and voice.lua maps the sound
-- editor's 0..1 knobs to real units around each voice's own defaults. the two
-- lists must stay in step, exactly like the S index list below.
--
-- four voices, one per corner, chosen to cover a kit: a trunk you can tune
-- down to a kick, a dry clack, a wet mid tom and a bright bell.
-- `struct` and `damp` are the same voice's structureBase and dampBase in the
-- SC table; the sound editor's Body and Damp knobs sweep around them rather
-- than replacing them, so a voice keeps its own character at any setting.
local VOICES = {
  {id = "oak",   name = "Oak",   index = 1, root = 55,  decay = 1.2,  struct = 0.55, damp = 1.1, x = 2,  y = 2},
  {id = "hazel", name = "Hazel", index = 2, root = 220, decay = 0.28, struct = 0.95, damp = 1.3, x = 15, y = 2},
  {id = "alder", name = "Alder", index = 3, root = 98,  decay = 1.6,  struct = 0.50, damp = 0.8, x = 2,  y = 7},
  {id = "rowan", name = "Rowan", index = 4, root = 330, decay = 1.8,  struct = 0.75, damp = 0.6, x = 15, y = 7},
}

-- 2.2 voice sockets (16) --------------------------------------------------
-- role in {"trig","pitch","mod","out"}, laid out around the voice cell:
-- trigger above, pitch left, mod right, out below. the four diagonals of the
-- 3x3 cluster are left unregistered, so a cluster reads as a plus sign.

local ROLE_NAME = {trig = "Trig", pitch = "Pitch", mod = "Mod", out = "Out"}
local ROLE_ORDER = {"trig", "pitch", "mod", "out"}
local ROLE_OFFSET = {trig = {0, -1}, pitch = {-1, 0}, mod = {1, 0}, out = {0, 1}}

for _, v in ipairs(VOICES) do
  reg("voice", v.id, v.name, {{v.x, v.y}},
      {index = v.index, root = v.root, decay = v.decay,
       struct = v.struct, damp = v.damp})
  for _, role in ipairs(ROLE_ORDER) do
    local off = ROLE_OFFSET[role]
    local id = v.id .. "." .. role
    -- middle dot, e.g. Oak·Trig
    local name = v.name .. "\xC2\xB7" .. ROLE_NAME[role]
    reg("node", id, name, {{v.x + off[1], v.y + off[2]}}, {voice = v.id, role = role})
  end
end

-- 2.3 pulse cells -- D (8) -------------------------------------------------
-- gait keys match rambler.lua. every gait in here free-runs on a phase of its
-- own; the ones that only react to an incoming pulse moved out to the weave
-- (§2.7) when the panel was re-cut, which is where they always belonged.
-- counterparts are the 180-degree rotation of the panel (x -> 17-x, y -> 9-y).

local D_CELLS = {
  {id = "knocker",  x = 7,  y = 4, gait = "metric",      counterpart = "hunt"},
  {id = "hob",      x = 8,  y = 4, gait = "euclidean",   counterpart = "gabriel"},
  {id = "grim",     x = 9,  y = 4, gait = "figure",      counterpart = "spriggan"},
  {id = "shuck",    x = 10, y = 4, gait = "slow",        counterpart = "boggart"},
  {id = "boggart",  x = 7,  y = 5, gait = "burst",       counterpart = "shuck"},
  {id = "spriggan", x = 8,  y = 5, gait = "stochastic",  counterpart = "grim"},
  {id = "gabriel",  x = 9,  y = 5, gait = "drifter",     counterpart = "hob"},
  {id = "hunt",     x = 10, y = 5, gait = "accelerando", counterpart = "knocker"},
}

for _, d in ipairs(D_CELLS) do
  local id = "d." .. d.id
  local name = d.id:sub(1, 1):upper() .. d.id:sub(2)
  reg("D", id, name, {{d.x, d.y}}, {
    gait = d.gait,
    counterpart = "d." .. d.counterpart,
    rooted = (d.gait == "metric" or d.gait == "euclidean" or d.gait == "figure"),
  })
end

-- 2.7 the weave -- R (20) --------------------------------------------------
-- rule keys match weave.lua. a D cell decides *when* something happens; an R
-- cell decides what happens to a pulse on its way somewhere -- divided,
-- delayed, doubled, accented, dropped, swung, thinned. two rows of ten, one
-- either side of the core, so nothing is more than a couple of cables from a
-- transform.

local R_CELLS = {
  {id = "trod",    x = 4,  y = 2, rule = "divide"},
  {id = "ginnel",  x = 5,  y = 2, rule = "mult"},
  {id = "snicket", x = 6,  y = 2, rule = "delay"},
  {id = "twitten", x = 7,  y = 2, rule = "echo"},
  {id = "bostal",  x = 8,  y = 2, rule = "chance"},
  {id = "drove",   x = 9,  y = 2, rule = "accent"},
  {id = "sneck",   x = 10, y = 2, rule = "sift"},
  {id = "lych",    x = 11, y = 2, rule = "meet"},
  {id = "stile",   x = 12, y = 2, rule = "hocket"},
  {id = "weir",    x = 13, y = 2, rule = "swing"},
  {id = "holt",    x = 4,  y = 7, rule = "blur"},
  {id = "coppice", x = 5,  y = 7, rule = "latch"},
  {id = "spinney", x = 6,  y = 7, rule = "fill"},
  {id = "thicket", x = 7,  y = 7, rule = "rest"},
  {id = "bramble", x = 8,  y = 7, rule = "flam"},
  {id = "tangle",  x = 9,  y = 7, rule = "ghost"},
  {id = "briar",   x = 10, y = 7, rule = "roll"},
  {id = "withy",   x = 11, y = 7, rule = "swell"},
  {id = "osier",   x = 12, y = 7, rule = "mask"},
  {id = "sedge",   x = 13, y = 7, rule = "shift"},
}

for _, r in ipairs(R_CELLS) do
  local id = "r." .. r.id
  local name = r.id:sub(1, 1):upper() .. r.id:sub(2)
  reg("R", id, name, {{r.x, r.y}}, {
    rule = r.rule,
    counterpart = "r." .. (function()
      for _, o in ipairs(R_CELLS) do
        if o.x == 17 - r.x and o.y == 9 - r.y then return o.id end
      end
      return r.id
    end)(),
  })
end

-- 2.4 exciter cells -- S (20) ----------------------------------------------
-- source keys match Engine_Woodland.sc's `excDefs` array, in this order.
-- the top row is the original ten; the bottom row is the ten that came with
-- the re-cut, aimed squarely at a kit -- clicks, metals, scrapes, impacts.

local S_CELLS = {
  {id = "bracken",  x = 4,  y = 1, source = "rustle"},
  {id = "gorse",    x = 5,  y = 1, source = "spiky"},
  {id = "ember",    x = 6,  y = 1, source = "crackle"},
  {id = "windfall", x = 7,  y = 1, source = "grain"},
  {id = "mistle",   x = 8,  y = 1, source = "chirp"},
  {id = "wisp",     x = 9,  y = 1, source = "walk"},
  {id = "hollow",   x = 10, y = 1, source = "comb"},
  {id = "drizzle",  x = 11, y = 1, source = "droplet"},
  {id = "loam",     x = 12, y = 1, source = "brown"},
  {id = "beck",     x = 13, y = 1, source = "burble"},
  {id = "skein",    x = 4,  y = 8, source = "shimmer"},
  {id = "flint",    x = 5,  y = 8, source = "click"},
  {id = "husk",     x = 6,  y = 8, source = "scrape"},
  {id = "tinder",   x = 7,  y = 8, source = "fizz"},
  {id = "mire",     x = 8,  y = 8, source = "sub"},
  {id = "glim",     x = 9,  y = 8, source = "ping"},
  {id = "rasp",     x = 10, y = 8, source = "buzz"},
  {id = "cicada",   x = 11, y = 8, source = "chirr"},
  {id = "hail",     x = 12, y = 8, source = "impacts"},
  {id = "reed",     x = 13, y = 8, source = "breath"},
}

for i, s in ipairs(S_CELLS) do
  local id = "s." .. s.id
  local name = s.id:sub(1, 1):upper() .. s.id:sub(2)
  -- index is this cell's channel in the engine's exciter bus block AND its
  -- position in Engine_Woodland.sc's `excDefs` array -- the two lists must
  -- stay in the same order (they do: both follow this table).
  local cp
  for _, o in ipairs(S_CELLS) do
    if o.x == 17 - s.x and o.y == 9 - s.y then cp = o.id end
  end
  reg("S", id, name, {{s.x, s.y}}, {
    source = s.source,
    counterpart = "s." .. (cp or s.id),
    index = i - 1,
  })
end

-- 2.5 heartwood -- H (8) ---------------------------------------------------
-- ring of 8 (down the left seam, across the bottom, up the right seam, across
-- the top) plus two interior chord rungs that cross the panel horizontally
-- (mycel<->warren, wyrd<->holloway). the two seams flank the D core, so a
-- pulse entering the lattice visibly walks around the pulse-makers.

local H_CELLS = {
  {id = "taproot",  x = 5,  y = 3},
  {id = "mycel",    x = 5,  y = 4},
  {id = "wyrd",     x = 5,  y = 5},
  {id = "ley",      x = 5,  y = 6},
  {id = "hearth",   x = 12, y = 6},
  {id = "holloway", x = 12, y = 5},
  {id = "warren",   x = 12, y = 4},
  {id = "barrow",   x = 12, y = 3},
}

for i, h in ipairs(H_CELLS) do
  -- index is this node's slot in the engine's heartwood buses AND its row in
  -- Engine_Woodland.sc's `hNbr` adjacency table -- the two lists must stay in
  -- the same order (they do: both follow the ring order below).
  reg("H", "h." .. h.id, h.id:sub(1, 1):upper() .. h.id:sub(2), {{h.x, h.y}},
      {index = i - 1})
end

local RING = {"taproot", "mycel", "wyrd", "ley", "hearth", "holloway", "warren", "barrow"}
local CHORDS = {{"mycel", "warren"}, {"wyrd", "holloway"}}

for i, name in ipairs(RING) do
  local id = "h." .. name
  local nxt = "h." .. RING[(i % #RING) + 1]
  local prv = "h." .. RING[((i - 2) % #RING) + 1]
  topology.cells[id].neighbors = {nxt, prv}
end
for _, pair in ipairs(CHORDS) do
  local a, b = "h." .. pair[1], "h." .. pair[2]
  table.insert(topology.cells[a].neighbors, b)
  table.insert(topology.cells[b].neighbors, a)
end

-- 2.6 the grove -- F (8) ---------------------------------------------------
-- the pitch fields. mode keys match grove.lua. two vertical seams at x=4 and
-- x=13, just outside the heartwood seams, paired across the same 180-degree
-- symmetry everything else uses. (these were the "P" cells before the re-cut;
-- P is a voice's pitch socket now, and the type letter moved to F.)

local F_CELLS = {
  {id = "cuckoo",   x = 4,  y = 3, mode = "call",    counterpart = "raven"},
  {id = "nightjar", x = 4,  y = 4, mode = "drone",   counterpart = "plover"},
  {id = "curlew",   x = 4,  y = 5, mode = "cascade", counterpart = "merlin"},
  {id = "bittern",  x = 4,  y = 6, mode = "octave",  counterpart = "wren"},
  {id = "wren",     x = 13, y = 3, mode = "flutter", counterpart = "bittern"},
  {id = "merlin",   x = 13, y = 4, mode = "scatter", counterpart = "curlew"},
  {id = "plover",   x = 13, y = 5, mode = "wander",  counterpart = "nightjar"},
  {id = "raven",    x = 13, y = 6, mode = "gravity", counterpart = "cuckoo"},
}

for _, p in ipairs(F_CELLS) do
  local id = "f." .. p.id
  local name = p.id:sub(1, 1):upper() .. p.id:sub(2)
  reg("F", id, name, {{p.x, p.y}}, {
    mode = p.mode,
    counterpart = "f." .. p.counterpart,
    -- snapped to the scale by default; K1 + tap sets a field free (§2.6).
    snap = true,
  })
end

-- 2.8 climate -- C (8) -----------------------------------------------------
-- shape keys match climate.lua. eight very slow modulators tucked into the
-- outer corners, where nothing else reaches. cable one to any cell and that
-- cell's own knob is walked around over tens of seconds to minutes: this is
-- the difference between a patch that loops and a patch that goes somewhere.

local C_CELLS = {
  {id = "moon",  x = 1,  y = 4, shape = "tide",     counterpart = "dusk"},
  {id = "hoar",  x = 1,  y = 5, shape = "creep",    counterpart = "bloom"},
  {id = "thaw",  x = 3,  y = 4, shape = "season",   counterpart = "ebb"},
  {id = "gale",  x = 3,  y = 5, shape = "gust",     counterpart = "hush"},
  {id = "hush",  x = 14, y = 4, shape = "breath",   counterpart = "gale"},
  {id = "ebb",   x = 14, y = 5, shape = "wane",     counterpart = "thaw"},
  {id = "bloom", x = 16, y = 4, shape = "flourish", counterpart = "hoar"},
  {id = "dusk",  x = 16, y = 5, shape = "shiver",   counterpart = "moon"},
}

for _, c in ipairs(C_CELLS) do
  local id = "c." .. c.id
  local name = c.id:sub(1, 1):upper() .. c.id:sub(2)
  reg("C", id, name, {{c.x, c.y}}, {
    shape = c.shape,
    counterpart = "c." .. c.counterpart,
  })
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

function topology.node_ids_for_voice(voice_id)
  local out = {}
  for _, role in ipairs(ROLE_ORDER) do
    table.insert(out, voice_id .. "." .. role)
  end
  return out
end

-- the types that carry a pulse of their own -- a phase (D) or a rule (R).
-- traffic between two of them is deferred a scheduler tick so a cycle in the
-- patch cannot recurse, which rambler.lua and heartwood.lua both need to know
-- about. it lives here because it is a fact about the map, and putting it in
-- rambler would mean heartwood reaching into the scheduler mid-load.
topology.PULSE_TYPES = {D = true, R = true}

function topology.is_pulse_cell(cell)
  return (cell and topology.PULSE_TYPES[cell.type]) and true or false
end

topology.ROLE_ORDER = ROLE_ORDER
topology.GRID_W = 16
topology.GRID_H = 8

return topology
