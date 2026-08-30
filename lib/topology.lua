-- topology.lua
-- the map: cell records, coords, types, adjacency.
-- ids are stable strings (never coordinates) so layout can change without
-- breaking saved patches. see docs/woodland-spec.md §2, §7.5.

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

local VOICES = {
  {id = "oak",   name = "Oak",   index = 1, coords = {{2, 2}}},
  {id = "rowan", name = "Rowan", index = 2, coords = {{2, 7}}},
  {id = "ash",   name = "Ash",   index = 3, coords = {{15, 2}}},
  {id = "hazel", name = "Hazel", index = 4, coords = {{15, 7}}},
  {id = "yew",   name = "Yew",   index = 5, coords = {{8, 2}, {9, 2}}},
  {id = "alder", name = "Alder", index = 6, coords = {{8, 7}, {9, 7}}},
}

for _, v in ipairs(VOICES) do
  reg("voice", v.id, v.name, v.coords, {index = v.index})
end

-- 2.2 voice nodes (24) ----------------------------------------------------
-- role in {"knock","sway","sap","moss"}

local NODES = {
  {voice = "oak",   knock = {2, 1},  sway = {3, 2},   sap = {2, 3},  moss = {1, 2}},
  {voice = "rowan", knock = {2, 8},  sway = {3, 7},   sap = {2, 6},  moss = {1, 7}},
  {voice = "ash",   knock = {15, 1}, sway = {14, 2},  sap = {15, 3}, moss = {16, 2}},
  {voice = "hazel", knock = {15, 8}, sway = {14, 7},  sap = {15, 6}, moss = {16, 7}},
  {voice = "yew",   knock = {8, 1},  moss = {9, 1},   sap = {8, 3},  sway = {9, 3}},
  {voice = "alder", knock = {9, 8},  moss = {8, 8},   sap = {9, 6},  sway = {8, 6}},
}

local ROLE_NAME = {knock = "Knock", sway = "Sway", sap = "Sap", moss = "Moss"}
local ROLE_ORDER = {"knock", "sway", "sap", "moss"}

for _, n in ipairs(NODES) do
  local vname = topology.cells[n.voice].name
  for _, role in ipairs(ROLE_ORDER) do
    local xy = n[role]
    local id = n.voice .. "." .. role
    local name = vname .. "\xC2\xB7" .. ROLE_NAME[role] -- middle dot, e.g. Oak·Knock
    reg("node", id, name, {xy}, {voice = n.voice, role = role})
  end
end

-- 2.3 pulse cells -- D (10) -----------------------------------------------
-- gait keys match rambler.lua

local D_CELLS = {
  {id = "knocker",  x = 5,  y = 3, gait = "metric",      counterpart = "hunt"},
  {id = "hob",      x = 6,  y = 3, gait = "euclidean",   counterpart = "puck"},
  {id = "grim",     x = 7,  y = 3, gait = "divider",     counterpart = "barguest"},
  {id = "shuck",    x = 5,  y = 4, gait = "slow",        counterpart = "gabriel"},
  {id = "boggart",  x = 6,  y = 4, gait = "burst",       counterpart = "spriggan"},
  {id = "spriggan", x = 11, y = 5, gait = "coincidence", counterpart = "boggart"},
  {id = "gabriel",  x = 12, y = 5, gait = "drifter",     counterpart = "shuck"},
  {id = "barguest", x = 10, y = 6, gait = "echo",        counterpart = "grim"},
  {id = "puck",     x = 11, y = 6, gait = "stochastic",  counterpart = "hob"},
  {id = "hunt",     x = 12, y = 6, gait = "accelerando", counterpart = "knocker"},
}

for _, d in ipairs(D_CELLS) do
  local id = "d." .. d.id
  local name = d.id:sub(1, 1):upper() .. d.id:sub(2)
  reg("D", id, name, {{d.x, d.y}}, {
    gait = d.gait,
    counterpart = "d." .. d.counterpart,
    rooted = (d.gait == "metric" or d.gait == "euclidean"),
  })
end

-- 2.4 exciter cells -- S (10) ----------------------------------------------
-- source keys match exciter.lua

local S_CELLS = {
  {id = "bracken",  x = 12, y = 3, source = "rustle",  counterpart = "beck"},
  {id = "gorse",    x = 11, y = 3, source = "spiky",   counterpart = "loam"},
  {id = "ember",    x = 10, y = 3, source = "crackle", counterpart = "drizzle"},
  {id = "windfall", x = 12, y = 4, source = "grain",   counterpart = "hollow"},
  {id = "mistle",   x = 11, y = 4, source = "chirp",   counterpart = "wisp"},
  {id = "wisp",     x = 6,  y = 5, source = "walk",    counterpart = "mistle"},
  {id = "hollow",   x = 5,  y = 5, source = "comb",    counterpart = "windfall"},
  {id = "drizzle",  x = 7,  y = 6, source = "droplet", counterpart = "ember"},
  {id = "loam",     x = 6,  y = 6, source = "brown",   counterpart = "gorse"},
  {id = "beck",     x = 5,  y = 6, source = "burble",  counterpart = "bracken"},
}

for i, s in ipairs(S_CELLS) do
  local id = "s." .. s.id
  local name = s.id:sub(1, 1):upper() .. s.id:sub(2)
  -- index is this cell's channel in the engine's exciter bus block AND its
  -- position in Engine_Woodland.sc's `excDefs` array -- the two lists must
  -- stay in the same order (they do: both follow the §2.4 table).
  reg("S", id, name, {{s.x, s.y}}, {
    source = s.source,
    counterpart = "s." .. s.counterpart,
    index = i - 1,
  })
end

-- 2.5 heartwood -- H (8) ---------------------------------------------------
-- ring of 8 (perimeter: top row L->R, down the right rung, bottom row R->L,
-- up the left/"wrap" rung) plus two interior chord rungs (mycel<->warren,
-- wyrd<->holloway). see docs/woodland-spec.md §2.5 diagram.

local H_CELLS = {
  {id = "taproot",  x = 7,  y = 4},
  {id = "mycel",    x = 8,  y = 4},
  {id = "wyrd",     x = 9,  y = 4},
  {id = "ley",      x = 10, y = 4},
  {id = "hearth",   x = 10, y = 5},
  {id = "holloway", x = 9,  y = 5},
  {id = "warren",   x = 8,  y = 5},
  {id = "barrow",   x = 7,  y = 5},
}

for i, h in ipairs(H_CELLS) do
  -- index is this node's slot in the engine's heartwood buses AND its row in
  -- Engine_Woodland.sc's `hNbr` adjacency table -- the two lists must stay in
  -- the same order (they do: both follow the perimeter order below).
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

topology.GRID_W = 16
topology.GRID_H = 8

return topology
