-- the re-cut's re-cut (docs/canopy-spec.md §2.7b): the six GVOICE percussion
-- cells (renamed from G). that they're registered right (three ping, three
-- noise, in row 2), that the sound page (lib/gvoice.lua) pushes and nudges
-- like the four corner voices' does, that a pulse strikes one the same way it
-- strikes a voice -- the socket collapse means there is no separate T socket
-- on either side any more -- and that a GVOICE cell answers with a pulse of
-- its own without sending it back down the cable it arrived on.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local KNOCKER = "d.hob"
local YAFFLE, KNAP, SCREE = "gv.yaffle", "gv.knap", "gv.scree"
local BRACKEN, WISP = "e.bracken", "e.wisp"

local function driver(M, id, char)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = char or 0.5
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

print("\n-- six GVOICE cells, three ping and three noise, in row 2 --")
do
  local M = fresh(1)
  local ids = {}
  for id, cell in M.topology.each() do
    if cell.type == "GVOICE" then table.insert(ids, id) end
  end
  check("six of them", #ids == 6, "#" .. #ids)
  local kinds, letters = {}, {}
  for _, id in ipairs(ids) do
    local c = M.topology.get(id)
    kinds[c.kind] = (kinds[c.kind] or 0) + 1
    letters[c.letter] = (letters[c.letter] or 0) + 1
    check(id .. " sits in row 2", c.coords[1][2] == 2, tostring(c.coords[1][2]))
  end
  check("three ping", kinds.ping == 3, tostring(kinds.ping))
  check("three noise", kinds.noise == 3, tostring(kinds.noise))
  check("the ping ones display as F, the noise ones as N",
        letters.F == 3 and letters.N == 3,
        string.format("F=%s N=%s", tostring(letters.F), tostring(letters.N)))
end

print("\n-- the sound page pushes all six at init --")
do
  local M = fresh(1)
  M.gvoice.init()
  check("six parameters", M.gvoice.PARAM_COUNT == 6, "#" .. M.gvoice.PARAM_COUNT)
  check("pitch went out", #CALLS.g_pitch >= 6, "#" .. #CALLS.g_pitch)
  check("decay went out", #CALLS.g_decay >= 6, "#" .. #CALLS.g_decay)
  check("tone went out", #CALLS.g_tone >= 6, "#" .. #CALLS.g_tone)
  check("punch went out", #CALLS.g_punch >= 6, "#" .. #CALLS.g_punch)
  check("drive went out", #CALLS.g_drive >= 6, "#" .. #CALLS.g_drive)
  check("level (amp) went out", #CALLS.g_amp >= 6, "#" .. #CALLS.g_amp)
end

print("\n-- Pitch is a transposition, in semitones, off the cell's own root --")
do
  local M = fresh(1)
  local cell = M.topology.get(YAFFLE)
  M.state.vparam[YAFFLE] = nil
  check("centre is the cell's own root", math.abs(M.gvoice.pitch_hz(YAFFLE) - cell.root) < 1e-6)
  M.state.set_vparam(YAFFLE, "pitch", 1.0)
  check("all the way up is two octaves", math.abs(M.gvoice.pitch_hz(YAFFLE) - cell.root * 4) < 1e-3,
        string.format("%.1f Hz", M.gvoice.pitch_hz(YAFFLE)))
  M.state.set_vparam(YAFFLE, "pitch", 0.0)
  check("all the way down is two octaves under", math.abs(M.gvoice.pitch_hz(YAFFLE) - cell.root / 4) < 1e-3,
        string.format("%.1f Hz", M.gvoice.pitch_hz(YAFFLE)))
end

print("\n-- Decay sweeps two octaves either side of the cell's own default --")
do
  local M = fresh(1)
  local cell = M.topology.get(KNAP)
  check("0.5 is the cell's own default", math.abs(M.gvoice.decay_seconds(KNAP) - cell.decay) < 1e-9)
  M.state.decay[KNAP] = 1.0
  check("all the way up is x4", math.abs(M.gvoice.decay_seconds(KNAP) - cell.decay * 4) < 1e-6)
  M.state.decay[KNAP] = 0.0
  check("all the way down is x0.25", math.abs(M.gvoice.decay_seconds(KNAP) - cell.decay / 4) < 1e-6)
end

print("\n-- a pulse strikes a G cell directly -- there is no separate T socket --")
do
  local M = fresh(3)
  M.dispatch.on_pulse(KNOCKER, YAFFLE, {gain = 0.8}, 1.0)
  local c = M.topology.get(YAFFLE)
  check("the drum was struck", #CALLS.g_strike == 1, "#" .. #CALLS.g_strike)
  check("at its own engine index", CALLS.g_strike[1].index == c.index - 1,
        tostring(CALLS.g_strike[1].index))
  check("force follows the edge gain", math.abs(CALLS.g_strike[1].force - 0.8) < 0.05,
        string.format("%.2f", CALLS.g_strike[1].force))
end

print("\n-- the refractory bounds it, same 28ms as a voice's T socket --")
do
  local M = fresh(3)
  M.dispatch.on_pulse(KNOCKER, KNAP, {gain = 1.0}, 1.0)
  M.dispatch.on_pulse(KNOCKER, KNAP, {gain = 1.0}, 1.0)
  check("a second strike inside the window is swallowed", #CALLS.g_strike == 1,
        "#" .. #CALLS.g_strike)
  T = T + 0.03
  M.dispatch.on_pulse(KNOCKER, KNAP, {gain = 1.0}, 1.0)
  check("and answers again once it's past", #CALLS.g_strike == 2, "#" .. #CALLS.g_strike)
end

print("\n-- a G cell answers with a pulse of its own, chained through the panel --")
do
  local M = fresh(5)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER)                      -- 2 Hz at 120bpm
  M.patch.add(KNOCKER, SCREE, 1.0)
  M.patch.add(SCREE, BRACKEN, 1.0)
  M.patch.add(SCREE, WISP, 1.0)
  run(M, 3)
  check("the drum was struck", #CALLS.g_strike > 0, "#" .. #CALLS.g_strike)
  check("and its answer gated both exciters",
        #CALLS.exciter_gate > 0, "#" .. #CALLS.exciter_gate)
  check("not back out of the cable the pulse arrived on",
        M.rambler.out_degree(SCREE, KNOCKER) == 2,
        tostring(M.rambler.out_degree(SCREE, KNOCKER)))
end

report()
