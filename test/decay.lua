-- build phase 5c: E3 with no cable focused is the held sound's decay (§4.2).
-- that every voice starts on its own ring time, that the knob moves it in
-- seconds, that a voice's sockets hand the gesture to the voice they belong
-- to, and that an S cell's exciter gets the same knob as a ratio.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local OAK, ROWAN, HAZEL = "oak", "rowan", "hazel"
local BRACKEN = "e.bracken"

local function last_decay_for(v)
  local out
  for _, c in ipairs(CALLS.voice_decay) do if c.voice == v then out = c.secs end end
  return out
end

local function last_exciter_decay(i)
  local out
  for _, c in ipairs(CALLS.exciter_decay) do if c.index == i then out = c.scale end end
  return out
end

-- decay is a named row on the cell's settings page now, not "E3 with no cable
-- focused" -- the same row whether the page is open or you are just holding
-- the cell. this drives it the way the grid does: hold the cell, put E1 on
-- the Decay row, turn E2.
local function row_of(id, key)
  local page = wl("cellparam").page(id)
  if not page then return nil end
  for i, p in ipairs(page.PARAMS) do
    if p.key == key then return i end
  end
  return nil
end

local function turn_decay(M, id, detents)
  local gridui = wl("gridui")
  M.state.held = {id}
  M.state.held_t[id] = T
  M.state.vparam_focus = row_of(id, "decay") or 1
  gridui.on_norns_enc(2, detents, {k1 = false, k2 = false, k3 = false})
  M.state.held = {}
end

print("\n-- every voice starts on its own ring time --")
do
  local M = fresh(1)
  M.voice.init()
  local seen = 0
  for id, cell in M.topology.each() do
    if cell.type == "voice" then
      seen = seen + 1
      local sent = last_decay_for(cell.index - 1)
      check(cell.name .. " opens on its default",
            sent and math.abs(sent - cell.decay) < 1e-9,
            string.format("%s vs %.2f s", tostring(sent), cell.decay))
    end
  end
  check("all four of them", seen == 4, "#" .. seen)
  check("and the defaults are the ones the engine's own table has",
        M.topology.get(ROWAN).decay == 1.8 and M.topology.get(HAZEL).decay == 0.28)
end

print("\n-- the knob moves it, in seconds either way --")
do
  local M = fresh(3)
  M.voice.init()
  local base = M.topology.get(OAK).decay

  check("0.5 is the voice's own default",
        math.abs(M.voice.decay_seconds(OAK) - base) < 1e-9)

  M.state.decay[OAK] = 1.0
  check("all the way up is four times as long",
        math.abs(M.voice.decay_seconds(OAK) - base * 4) < 1e-6,
        string.format("%.3f s", M.voice.decay_seconds(OAK)))

  M.state.decay[OAK] = 0.0
  check("all the way down is a quarter of it",
        math.abs(M.voice.decay_seconds(OAK) - base / 4) < 1e-6,
        string.format("%.3f s", M.voice.decay_seconds(OAK)))

  -- Hazel is already the short one; shortening it further must reach a knock
  M.state.decay[HAZEL] = 0.0
  check("the shortest voice can be cut down to a knock",
        M.voice.decay_seconds(HAZEL) < 0.1,
        string.format("%.3f s", M.voice.decay_seconds(HAZEL)))
  -- Rowan's 1.8s default x4 is the longest ring the sound page can ask for
  -- anywhere, and it has to stay under the mode bank's own ceiling (Ringz,
  -- clipped at 30s in Engine_Canopy.sc) or the page would read out a decay
  -- you cannot hear.
  M.state.decay[ROWAN] = 1.0
  check("and the longest is a real bell",
        M.voice.decay_seconds(ROWAN) > 6 and M.voice.decay_seconds(ROWAN) <= 30,
        string.format("%.2f s", M.voice.decay_seconds(ROWAN)))
end

print("\n-- E3 on the grid reaches the engine --")
do
  local M = fresh(5)
  M.voice.init()
  local before = last_decay_for(0)
  turn_decay(M, OAK, 20)
  local after = last_decay_for(0)
  check("turning it up lengthens the ring", after > before,
        string.format("%.3f -> %.3f s", before, after))
  turn_decay(M, OAK, -60)
  check("and turning it down shortens it", last_decay_for(0) < before,
        string.format("%.3f s", last_decay_for(0)))

  -- and it stops at the ends rather than running away
  turn_decay(M, OAK, -10000)
  local floor_s = last_decay_for(0)
  turn_decay(M, OAK, 20000)
  local ceil_s = last_decay_for(0)
  local base = M.topology.get(OAK).decay
  check("the knob is bounded at both ends",
        math.abs(floor_s - base / 4) < 1e-6 and math.abs(ceil_s - base * 4) < 1e-6,
        string.format("%.3f .. %.3f s", floor_s, ceil_s))
end

print("\n-- the socket collapse: a voice IS its own decay target, directly --")
do
  -- the four sockets are gone; a voice is one cable endpoint and its own
  -- sound page target both, so E3 on the voice cell itself is now the only
  -- gesture there is (already covered above). what is still worth checking
  -- is that decay_target's DECAY_TYPES set -- voice, GVOICE, E -- covers
  -- every kind of cell that actually has a sound to decay, each against its
  -- own id, with no forwarding indirection left to test.
  local M = fresh(7)
  M.voice.init()
  check("a voice decays against its own id",
        M.state.decay_target(M.topology.get(OAK)) == OAK)
  check("a GVOICE cell decays against its own id, same shape as a voice",
        M.state.decay_target(M.topology.get("gv.yaffle")) == "gv.yaffle")
  check("an E cell decays against its own id too",
        M.state.decay_target(M.topology.get(BRACKEN)) == BRACKEN)

  -- and a different voice must not have moved with Oak's own knob.
  local base = last_decay_for(0)
  turn_decay(M, OAK, 25)
  check("turning Oak's decay leaves Hazel untouched",
        last_decay_for(1) == nil
        or math.abs(last_decay_for(1) - M.topology.get(HAZEL).decay) < 1e-9)
  check("but did move Oak's own", last_decay_for(0) ~= base)
end

print("\n-- an E cell gets the same knob, as a ratio --")
do
  local M = fresh(11)
  check("0.5 leaves the recipe's own envelopes alone",
        math.abs(M.exciter.decay_scale(BRACKEN) - 1.0) < 1e-9)
  M.state.decay[BRACKEN] = 1.0
  check("up is nearly three times as long",
        math.abs(M.exciter.decay_scale(BRACKEN) - 2 ^ 1.5) < 1e-9,
        string.format("x%.3f", M.exciter.decay_scale(BRACKEN)))
  M.state.decay[BRACKEN] = 0.0
  check("down is a third of it",
        math.abs(M.exciter.decay_scale(BRACKEN) - 2 ^ -1.5) < 1e-9,
        string.format("x%.3f", M.exciter.decay_scale(BRACKEN)))

  -- nothing is sent while the exciter is unpatched (§2.4 lazy alloc)
  M.state.decay[BRACKEN] = 0.7
  M.state.notify_decay_change(BRACKEN)
  check("an unpatched exciter is not talked to", #CALLS.exciter_decay == 0,
        "#" .. #CALLS.exciter_decay)

  local index = M.topology.get(BRACKEN).index
  M.patch.add(BRACKEN, OAK, 0.8)
  check("cabling it pushes whatever decay it was already set to",
        last_exciter_decay(index)
        and math.abs(last_exciter_decay(index) - M.exciter.decay_scale(BRACKEN)) < 1e-9,
        tostring(last_exciter_decay(index)))

  turn_decay(M, BRACKEN, -30)
  check("and E3 forwards it live", last_exciter_decay(index) < 1.0,
        string.format("x%.3f", last_exciter_decay(index)))
end

print("\n-- cells with no sound of their own have no decay --")
do
  local M = fresh(17)
  for _, id in ipairs({"d.skriker", "h.wyrd", "f.cuckoo"}) do
    local cell = M.topology.get(id)
    check(cell.name .. " has no decay target",
          M.state.decay_target(cell) == nil, tostring(M.state.decay_target(cell)))
    turn_decay(M, id, 30)
    check("and E3 stores nothing against it", M.state.decay[id] == nil,
          tostring(M.state.decay[id]))
  end
  check("nothing reached the engine", #CALLS.voice_decay == 0
        and #CALLS.exciter_decay == 0)
end

print("\n-- a cell's own decay and a cable's gain are separate gestures now --")
do
  -- they used to share E3, split by whether a cable was "focused" -- a mode
  -- with no indicator you could see more than one row of. one cell held is
  -- that cell's page; two cells held is the cable between them.
  local M = fresh(13)
  M.voice.init()
  local gridui = wl("gridui")
  M.patch.add(BRACKEN, OAK, 0.5)
  local edge_id = M.patch.has(BRACKEN, OAK)

  local decay_before = M.state.get_decay(BRACKEN)
  turn_decay(M, BRACKEN, 10)
  check("one cell held, the Decay row moves the decay",
        M.state.get_decay(BRACKEN) > decay_before)
  check("and the cable is left alone",
        math.abs(M.patch.get(edge_id).gain - 0.5) < 1e-9)

  local decay_now = M.state.get_decay(BRACKEN)
  M.state.held = {BRACKEN, OAK}
  M.state.held_t[BRACKEN], M.state.held_t[OAK] = T, T
  gridui.on_norns_enc(3, 10, {})
  check("two cells held, E3 moves the cable between them",
        M.patch.get(edge_id).gain > 0.5,
        string.format("%.3f", M.patch.get(edge_id).gain))
  check("and the decay is left alone",
        math.abs(M.state.get_decay(BRACKEN) - decay_now) < 1e-9)
  M.state.held = {}
end

report()
