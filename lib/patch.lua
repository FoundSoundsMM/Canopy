-- patch.lua
-- the cable graph: add/remove/trim edges, serialisation. (§3, §7.5)
--
-- cables are undirected by default (oneway=false); a oneway cable still
-- occupies a single undirected slot between a and b (no duplicate/reverse
-- edges), it's just interpreted/drawn differently downstream.
--
-- one exception to "a cell can be cabled to anything, any number of times":
-- the Output row. a source reaches the speakers at exactly one pan position,
-- so cabling it to a second Out cell MOVES it rather than adding a second
-- cable -- see `displace_output` below.

local topology = wl("topology")

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

local function is_output(id)
  local cell = topology.get(id)
  return (cell and cell.type == "O") and true or false
end

-- which end of a source<->Out pair is which, or nil,nil when the pair is not
-- one of those (Out<->Out, and everything that touches no Out cell at all).
local function source_and_output(a, b)
  if is_output(b) and not is_output(a) then return a, b end
  if is_output(a) and not is_output(b) then return b, a end
  return nil, nil
end

-- §2.1: position along the Output row IS pan, so one source in two slots is
-- one source at two pan positions at once -- which reads on the panel as a
-- patching mistake and sounds like a widened, phase-smeared copy of itself
-- nobody asked for. tapping a second Out cell is therefore a *move*: the
-- cable that was there is pulled first, at the same gain, so the gesture
-- reads as dragging the source along the row rather than as adding to it.
--
-- returns the Out cell the source just left, or nil if it was not already
-- on the row. only fires when exactly one end is an Out cell: an Out<->Out
-- cable has no source to move and is left alone.
local function displace_output(a, b)
  local src, out = source_and_output(a, b)
  if not src then return nil end

  local set = patch.by_cell[src]
  if not set then return nil end
  for edge_id in pairs(set) do
    local edge = patch.edges[edge_id]
    local other = patch.other(edge, src)
    if other ~= out and is_output(other) then
      local gain = edge.gain
      patch.remove_edge(edge_id)
      return other, gain
    end
  end
  return nil
end

-- the other half of the same rule, and the newer one: an Output cell carries
-- exactly ONE source. it used to sum -- several cables could land on one Out
-- and be heard together at that pan position -- and that made an Output cell
-- an anonymous bus rather than a channel. one source per slot is what lets
-- the mixer page (lib/mixer.lua) call a channel by the name of the instrument
-- on it instead of by the number of the seat it is sitting in, which is the
-- whole reason the exclusivity runs both ways now.
--
-- so a source landing on an occupied Out evicts whatever was there, the same
-- way landing on a second Out moves the source itself. returns the source
-- cell that was evicted, or nil.
local function displace_source(a, b)
  local src, out = source_and_output(a, b)
  if not src then return nil end

  local set = patch.by_cell[out]
  if not set then return nil end
  for edge_id in pairs(set) do
    local edge = patch.edges[edge_id]
    local other = patch.other(edge, out)
    if other ~= src and not is_output(other) then
      patch.remove_edge(edge_id)
      return other
    end
  end
  return nil
end

-- returns edge, err, moved_from, replaced -- `moved_from` being the Out cell
-- this source was pulled off to make the new cable, and `replaced` the source
-- evicted from the Out cell it landed on. both nil in every other case.
function patch.add(a, b, gain, oneway)
  gain = gain or 0.6
  if a == b then return nil, "self" end
  if patch.has(a, b) then return nil, "duplicate" end

  -- before the cap check, not after: a move must never fail for want of a
  -- cable slot, since it is about to free the one it is using.
  local moved_from, old_gain = displace_output(a, b)
  if moved_from then gain = old_gain end
  local replaced = displace_source(a, b)

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
  return edge, nil, moved_from, replaced
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
-- returns "added"|"moved"|"removed"|"error", edge_or_err, replaced.
-- "moved" is an "added" that pulled the source off another Output cell on
-- its way in (see displace_output) -- the caller reports it differently, but
-- the resulting cable is an ordinary one. `replaced` is the source this one
-- evicted from the Out cell it landed on (displace_source), which is a
-- separate thing and can happen alongside either verb.
function patch.toggle(a, b, oneway, default_gain)
  if patch.has(a, b) then
    patch.remove(a, b)
    return "removed"
  end
  local edge, err, moved_from, replaced = patch.add(a, b, default_gain, oneway)
  if edge then return moved_from and "moved" or "added", edge, replaced end
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
