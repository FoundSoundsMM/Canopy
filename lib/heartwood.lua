-- heartwood.lua
-- the §2.5 diffusion lattice. "not a bus. a diffusion lattice. signals
-- injected at one heartwood node spread outward through the lattice with a
-- per-hop delay and loss, emerging from the other nodes at different times
-- and amplitudes."
--
-- this file is the *discrete* half -- pulses, per §7.2's "Lua owns ... the
-- heartwood lattice's discrete-event side". the continuous half (streams
-- diffusing through the same eight nodes) is \wl_heartwood in the engine,
-- addressed from here only by forwarding conductance; dispatch.lua routes
-- the cables that feed and tap it.
--
-- topology.lua owns the adjacency (a ring of 8 with two chord rungs). a
-- H<->H *cable* adds a shortcut edge on top of that (§6: "direct link --
-- short-circuits two lattice points, adds a shortcut path"), so the lattice
-- a pulse walks is topology's ring plus whatever the player has patched.
--
-- dependency note: dispatch.lua requires this file at load, so this one must
-- not require dispatch (or rambler, which requires dispatch) at load -- both
-- are fetched lazily inside `arrive`, by which time wl() has them memoised.

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local bridge   = wl("bridge")

local heartwood = {}

-- a pulse stops when it has taken this many hops, or when its share of the
-- original energy falls under the floor. a lattice with cycles in it needs
-- both: the floor alone can't bound the *number* of live events once a wave
-- starts splitting at the chord nodes, and the hop count alone can't stop a
-- high-conductance ring from ringing forever.
heartwood.MAX_HOPS = 16
heartwood.FLOOR = 0.03
heartwood.MAX_PENDING = 96
heartwood.FLASH_DECAY = 0.18   -- §5.1, a touch slower than a D cell's flash
heartwood.CHARGE_TAU = 0.9     -- how fast the screen's energy readout falls

-- §2.5 conductance (E2 while holding) "sets local hop delay and loss". the
-- spec doesn't fix which way round, so: high conductance is a *better*
-- conductor -- shorter hop, less lost per hop, hence "energy circulates the
-- ring for a long time". low conductance is one slow, lossy thud that "dies
-- within one hop". keep these two ranges in step with the same mapping in
-- Engine_Canopy.sc's \wl_heartwood, or the pulse and stream halves of one
-- node will disagree about what its knob does.
local HOP_MIN, HOP_MAX = 0.05, 0.35
local LOSS_MIN, LOSS_MAX = 0.10, 0.90

local nodes = {}    -- h_id -> node record
local order = {}    -- h_ids, stable iteration order
local pending = {}  -- {t=, id=, w=, hops=, from=} arrivals still in flight

for id, cell in topology.each() do
  if cell.type == "H" then
    nodes[id] = {
      id = id,
      cell = cell,
      flash = -1,      -- util.time() of the last arrival
      last_w = 0,      -- its weight, for the flash depth
      charge = 0,      -- decaying "how busy is this node" readout
      charge_t = 0,
      out_links = {},  -- cables to non-H cells: where a pulse emerges
      lattice = {},    -- {id=, gain=} ring/chord neighbours + patched shortcuts
    }
    table.insert(order, id)
  end
end

function heartwood.conductance(id)
  local n = nodes[id]
  if not n then return 0.5 end
  return state.get_character(id, n.cell, 0, 1)
end

function heartwood.hop_delay(id)
  return HOP_MAX - heartwood.conductance(id) * (HOP_MAX - HOP_MIN)
end

function heartwood.loss(id)
  return LOSS_MIN + heartwood.conductance(id) * (LOSS_MAX - LOSS_MIN)
end

-- link caching -------------------------------------------------------------
-- same reasoning as rambler.lua's: edges_at() allocates, and `arrive` runs on
-- the 2 ms tick, so the per-node lists are rebuilt only when the graph moves.

local function rebuild_links()
  for _, n in pairs(nodes) do
    n.out_links = {}
    n.lattice = {}

    -- topology's ring + chords. always both ways, always unity gain: these
    -- are the wood itself, not something the player patched.
    for _, nbr in ipairs(n.cell.neighbors or {}) do
      table.insert(n.lattice, {id = nbr, gain = 1})
    end

    for _, edge in ipairs(patch.edges_at(n.id)) do
      local other = patch.other(edge, n.id)
      local ocell = topology.get(other)
      -- a one-way cable a->b only sends from a (§3), same rule rambler uses.
      local can_send = (not edge.oneway) or (edge.a == n.id)
      if ocell and can_send then
        if ocell.type == "H" then
          table.insert(n.lattice, {id = other, gain = math.abs(edge.gain)})
        else
          -- `pulse` means the far end has a phase or a rule of its own (a D
          -- or an R cell), so what emerges there has to go through rambler's
          -- inbox rather than straight down dispatch, or a D->H->D loop would
          -- recurse where a D->D one does not. asked of topology, not of
          -- rambler: this runs at load time, and rambler is mid-load when it
          -- does -- wl() memoises only on return, so reaching for it here
          -- would re-enter this file through a second copy of rambler.
          table.insert(n.out_links, {
            id = other, edge = edge, pulse = topology.is_pulse_cell(ocell),
          })
        end
      end
    end
  end
end

patch.on_change(rebuild_links)
rebuild_links()

-- diffusion ------------------------------------------------------------------

-- one pulse landing on one node: it emerges through that node's cables, then
-- passes on to its lattice neighbours after this node's hop delay.
--
-- `from` is the lattice neighbour it hopped from (nil at the injection
-- point); `src` is the cell whose cable put it in here, and only ever set on
-- that first arrival. they are separate because they exclude different
-- things: `from` keeps a wave travelling outward, `src` stops a pulse
-- bouncing straight back out of the cable it came in on before it has been
-- anywhere. a pulse that comes all the way back round the ring *does* go
-- back out to its source -- that is the lattice returning energy, and the
-- whole point of a high-conductance ring.
local function arrive(n, w, hops, from, now, src)
  local dispatch = wl("dispatch")
  local rambler = wl("rambler")

  n.flash = now
  n.last_w = w
  n.charge = math.min(1, heartwood.charge(n.id) + w)
  n.charge_t = now

  -- emerge: every cable out of this node delivers the pulse, exactly as if
  -- the node were a D cell that had just wrapped. dispatch applies the edge
  -- gain itself, so `w` goes through unscaled.
  for _, link in ipairs(n.out_links) do
    if link.id ~= src then
      if link.pulse then
        rambler.inject(link.id, w * math.abs(link.edge.gain), n.id,
                       link.edge.gain < 0 and -1 or 1)
      else
        dispatch.on_pulse(n.id, link.id, link.edge, w)
      end
    end
  end

  if hops >= heartwood.MAX_HOPS then return end

  -- pass on to every neighbour except the one it came from. that exclusion is
  -- what makes this diffusion rather than a swarm of ping-pong echoes: a wave
  -- keeps travelling outward, and two waves meeting head-on pass through each
  -- other instead of bouncing.
  local outs = {}
  for _, l in ipairs(n.lattice) do
    if l.id ~= from then table.insert(outs, l) end
  end
  if #outs == 0 then return end

  -- the energy leaving a node is split between its outward neighbours, so a
  -- chord node halves rather than doubles what it passes on. this is what
  -- bounds the whole thing: total energy in flight can only ever fall.
  local share = (w * heartwood.loss(n.id)) / #outs
  if share < heartwood.FLOOR then return end

  local delay = heartwood.hop_delay(n.id)
  for _, l in ipairs(outs) do
    local ww = share * l.gain
    if ww >= heartwood.FLOOR and #pending < heartwood.MAX_PENDING then
      table.insert(pending, {
        t = now + delay, id = l.id, w = ww, hops = hops + 1, from = n.id,
      })
    end
  end
end

-- a pulse enters the lattice at `h_id` (a D->H cable, or anything else §6
-- routes here). it emerges from that node immediately and spreads from there.
function heartwood.inject(h_id, w, src_id)
  local n = nodes[h_id]
  if not n then return end
  arrive(n, util.clamp(w or 1, 0, 1), 0, nil, util.time(), src_id)
end

-- §4.3 an external transport Start: drop every hop still in flight, for the
-- reason weave.resync spells out. the nodes' own charge is deliberately left
-- alone -- a lattice ringing out through a Stop and picking up where it left
-- off is exactly what Still promises.
function heartwood.resync()
  pending = {}
end

-- called from rambler.tick, on the far side of the Still check -- signals in
-- flight freeze with the gaits rather than flushing all at once on resume.
function heartwood.tick(now)
  if #pending == 0 then return end
  -- swap first: `arrive` appends this hop's onward traffic to `pending`, and
  -- rebuilding the list afterwards would throw all of it away.
  local due = pending
  pending = {}
  for _, ev in ipairs(due) do
    if ev.t <= now then
      local n = nodes[ev.id]
      if n then arrive(n, ev.w, ev.hops, ev.from, now) end
    else
      table.insert(pending, ev)
    end
  end
end

-- read/control surface --------------------------------------------------------

-- decayed on read rather than per tick: eight nodes at 500 Hz is real work to
-- do for something only the screen and the grid ever look at.
function heartwood.charge(id)
  local n = nodes[id]
  if not n or n.charge <= 0 then return 0 end
  local age = util.time() - n.charge_t
  if age <= 0 then return n.charge end
  return n.charge * math.exp(-age / heartwood.CHARGE_TAU)
end

-- §5.1: flash on arrival over a base that rises with how live the node is.
function heartwood.level(id, base)
  local n = nodes[id]
  if not n then return base end
  local lvl = base + math.floor(heartwood.charge(id) * 5)
  if patch.degree(id) > 0 then lvl = lvl + 2 end
  local age = util.time() - n.flash
  if age >= 0 and age < heartwood.FLASH_DECAY then
    local f = 1 - (age / heartwood.FLASH_DECAY)
    lvl = lvl + math.floor((15 - lvl) * f * n.last_w)
  end
  return util.clamp(math.floor(lvl), 0, 15)
end

function heartwood.info(id)
  local n = nodes[id]
  if not n then return nil end
  return {
    conductance = heartwood.conductance(id),
    hop = heartwood.hop_delay(id),
    loss = heartwood.loss(id),
    charge = heartwood.charge(id),
    -- ring/chord neighbours plus any patched shortcuts
    links = #n.lattice,
  }
end

function heartwood.pending_count()
  return #pending
end

-- push every node's conductance at the engine once, at init, the way
-- voice.init does for Grain -- a freshly booted \wl_heartwood is at its
-- SynthDef defaults and knows nothing about what the knobs were left at.
function heartwood.init()
  for _, id in ipairs(order) do
    bridge.heart_conductance(nodes[id].cell.index, heartwood.conductance(id))
  end
end

state.on_character_change(function(id)
  local n = nodes[id]
  if n then
    -- through heartwood.conductance, not state.character directly, so any
    -- future indirection on top of the player's own setting stays in step
    -- between the readout and the engine automatically.
    bridge.heart_conductance(n.cell.index, heartwood.conductance(id))
  end
end)

return heartwood
