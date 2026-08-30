-- patch.lua
-- the cable graph: add/remove/trim edges, serialisation. (§3, §7.5)
--
-- cables are undirected by default (oneway=false); a oneway cable still
-- occupies a single undirected slot between a and b (no duplicate/reverse
-- edges), it's just interpreted/drawn differently downstream.

local patch = {}

patch.MAX_CABLES = 64

patch.edges = {}       -- edge_id -> {id, a, b, gain, oneway}
patch.pair_index = {}  -- "a\0b" (sorted) -> edge_id
patch.by_cell = {}     -- cell_id -> {edge_id = true, ...}
patch.next_id = 1
patch._listeners = {}

local function key(a, b)
  if a > b then a, b = b, a end
  return a .. "\0" .. b
end

function patch.on_change(fn)
  table.insert(patch._listeners, fn)
end

function patch._notify()
  for _, fn in ipairs(patch._listeners) do fn() end
end

function patch.count()
  local n = 0
  for _ in pairs(patch.edges) do n = n + 1 end
  return n
end

-- edge_id if a<->b already cabled, else nil
function patch.has(a, b)
  return patch.pair_index[key(a, b)]
end

function patch.get(edge_id)
  return patch.edges[edge_id]
end

function patch.add(a, b, gain, oneway)
  gain = gain or 0.6
  if a == b then return nil, "self" end
  if patch.has(a, b) then return nil, "duplicate" end
  if patch.count() >= patch.MAX_CABLES then return nil, "cap" end

  local id = patch.next_id
  patch.next_id = id + 1
  local edge = {id = id, a = a, b = b, gain = gain, oneway = oneway or false}
  patch.edges[id] = edge
  patch.pair_index[key(a, b)] = id
  patch.by_cell[a] = patch.by_cell[a] or {}
  patch.by_cell[a][id] = true
  patch.by_cell[b] = patch.by_cell[b] or {}
  patch.by_cell[b][id] = true

  patch._notify()
  return edge
end

function patch.remove_edge(edge_id)
  local edge = patch.edges[edge_id]
  if not edge then return false end
  patch.pair_index[key(edge.a, edge.b)] = nil
  if patch.by_cell[edge.a] then patch.by_cell[edge.a][edge_id] = nil end
  if patch.by_cell[edge.b] then patch.by_cell[edge.b][edge_id] = nil end
  patch.edges[edge_id] = nil
  patch._notify()
  return true
end

function patch.remove(a, b)
  local id = patch.has(a, b)
  if id then return patch.remove_edge(id) end
  return false
end

-- hold A, tap B: toggle the cable between them.
-- returns "added"|"removed"|"error", edge_or_err
function patch.toggle(a, b, oneway, default_gain)
  if patch.has(a, b) then
    patch.remove(a, b)
    return "removed"
  end
  local edge, err = patch.add(a, b, default_gain, oneway)
  if edge then return "added", edge end
  return "error", err
end

function patch.edges_at(id)
  local out = {}
  local set = patch.by_cell[id]
  if set then
    for edge_id in pairs(set) do
      table.insert(out, patch.edges[edge_id])
    end
  end
  table.sort(out, function(x, y) return x.id < y.id end)
  return out
end

function patch.degree(id)
  local set = patch.by_cell[id]
  if not set then return 0 end
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

function patch.sever_all(id)
  local set = patch.by_cell[id]
  if not set then return 0 end
  local ids = {}
  for edge_id in pairs(set) do table.insert(ids, edge_id) end
  for _, edge_id in ipairs(ids) do patch.remove_edge(edge_id) end
  return #ids
end

-- the far end of an edge, from id's point of view
function patch.other(edge, id)
  if edge.a == id then return edge.b else return edge.a end
end

function patch.set_gain(edge_id, gain)
  local edge = patch.edges[edge_id]
  if not edge then return end
  if gain > 1.0 then gain = 1.0 end
  if gain < -1.0 then gain = -1.0 end
  edge.gain = gain
  patch._notify()
end

function patch.clear()
  patch.edges = {}
  patch.pair_index = {}
  patch.by_cell = {}
  patch.next_id = 1
  patch._notify()
end

-- §7.5 persistence: a flat list of {a_id, b_id, gain, oneway}

function patch.to_table()
  local out = {}
  for _, edge in pairs(patch.edges) do
    table.insert(out, {a = edge.a, b = edge.b, gain = edge.gain, oneway = edge.oneway})
  end
  return out
end

function patch.from_table(list)
  patch.clear()
  for _, e in ipairs(list) do
    patch.add(e.a, e.b, e.gain, e.oneway)
  end
end

return patch
