-- build phase 6, re-cut for the socket collapse: the voices as one point
-- each now. that the four old sockets are genuinely gone (no .trig/.pitch/
-- .mod/.out ids resolve at all), the twelve-parameter sound page (§5.5,
-- three rows moved onto it from the sockets that used to carry them), and
-- that every pulse landing on a voice strikes it and the voice answers back
-- out of the same single point -- which is still how voice<->voice feedback
-- closes, just without a dedicated O socket to carry it.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local OAK, ROWAN = "oak", "rowan"
local KNOCKER, GABRIEL = "d.hob", "d.gabriel"
-- weave trimmed to 6 cells; any two distinct survivors work here since every
-- test below sets its rule explicitly rather than relying on a default.
local TROD, GINNEL = "r.thicket", "r.tangle"
local BRACKEN = "e.bracken"

local function last(list, pred)
  local out
  for _, c in ipairs(list) do if (not pred) or pred(c) then out = c end end
  return out
end

local function driver(M, id, char)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = char or 0.5
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

print("\n-- the socket collapse: one point, and the old sockets are just gone --")
do
  local M = fresh(1)
  check("no .trig/.pitch/.mod/.out ids resolve any more",
        M.topology.get("oak.trig") == nil and M.topology.get("oak.pitch") == nil
        and M.topology.get("oak.mod") == nil and M.topology.get("oak.out") == nil)
  check("the voice cell itself is the only endpoint, and it is type voice",
        M.topology.get(OAK).type == "voice")
  check("it sits at its own single coordinate",
        M.topology.at(2, 2) == OAK, tostring(M.topology.at(2, 2)))
  check("all four voices exist, one point each", M.topology.get("hazel").type == "voice"
        and M.topology.get("alder").type == "voice" and M.topology.get(ROWAN).type == "voice")
end

print("\n-- the sound page pushes all twelve at init --")
do
  local M = fresh(3)
  M.voice.init()
  -- the socket collapse folded three more rows onto this page (the old T
  -- socket's hardness, the P socket's depth, the M socket's balance), so
  -- nine grew to twelve.
  check("twelve parameters", M.voice.PARAM_COUNT == 12, "#" .. M.voice.PARAM_COUNT)
  check("decay went out", last(CALLS.voice_decay, function(c) return c.voice == 0 end))
  check("structure went out", last(CALLS.voice_structure, function(c) return c.voice == 0 end))
  check("pitch went out", last(CALLS.voice_pitch, function(c) return c.voice == 0 end))
  check("and Balance -- the old M socket's continuous knob -- did too",
        last(CALLS.voice_mod, function(c) return c.voice == 0 end))
end

print("\n-- Tune is a transposition, in semitones --")
do
  local M = fresh(5)
  M.voice.init()
  local root = M.topology.get(OAK).root
  check("centre is the voice's own root",
        math.abs(M.grove.hz(OAK) - root) < 1e-9, string.format("%.3f", M.grove.hz(OAK)))
  M.state.set_vparam(OAK, "tune", 0.75)
  check("halfway up is a whole octave", math.abs(M.voice.tune_semitones(OAK) - 12) < 1e-9,
        string.format("%.2f st", M.voice.tune_semitones(OAK)))
  check("and the Hz doubles", math.abs(M.grove.hz(OAK) - root * 2) < 1e-6,
        string.format("%.3f Hz", M.grove.hz(OAK)))
  M.state.set_vparam(OAK, "tune", 0)
  check("all the way down is three octaves", math.abs(M.grove.hz(OAK) - root / 8) < 1e-6,
        string.format("%.3f Hz", M.grove.hz(OAK)))
end

print("\n-- Bend is a no-op at 0, and reaches the engine when turned up --")
do
  local M = fresh(6)
  M.voice.init()
  check("Bend defaults to 0", M.state.get_vparam(OAK, "bend", 0) == 0)
  M.state.set_vparam(OAK, "bend", 0.6)
  M.voice.nudge(OAK, 2, 0) -- push without moving it, same as an E2/E3 nudge would
  local c = last(CALLS.voice_bend, function(x) return x.voice == 0 end)
  check("bend amount forwarded", c and math.abs(c.v - 0.6) < 1e-9, c and c.v)
end

print("\n-- Body and Damp sweep around each voice's own baseline --")
do
  local M = fresh(7)
  for _, id in ipairs({OAK, ROWAN}) do
    local cell = M.topology.get(id)
    M.state.set_vparam(id, "body", 0.5)
    M.state.set_vparam(id, "damp", 0.5)
    check(cell.name .. " centres on its own structure",
          math.abs(M.voice.structure(id) - cell.struct) < 1e-9)
    check(cell.name .. " centres on its own damping",
          math.abs(M.voice.damp(id) - cell.damp) < 1e-9)
  end
  M.state.set_vparam(OAK, "body", 1.0)
  check("and the knob moves it either way",
        M.voice.structure(OAK) > M.topology.get(OAK).struct)
end

print("\n-- the sound page's Depth knob scales what the fields do --")
do
  -- the old P socket's own knob moved onto the sound page (voice.lua's
  -- `depth` row, index 11) when the socket it lived on collapsed into the
  -- voice's single point -- same 0..2 range, same "0 flattens the melody to
  -- nothing, 2 doubles it" shape, just reached through state.vparam now
  -- instead of a per-socket state.character entry.
  local M = fresh(11)
  local CUCKOO = "f.cuckoo"
  M.patch.add(CUCKOO, OAK, 1.0)
  M.state.character[CUCKOO] = 1.0
  M.state.notify_character_change(CUCKOO)
  for _ = 1, 20 do M.grove.step(CUCKOO, 1) end
  local full = math.abs(M.grove.offset(OAK))
  check("at depth 1 (the 0.5 default) the field moves the voice", full > 0,
        string.format("%.2f st", full))

  M.state.set_vparam(OAK, "depth", 0)
  check("at depth 0 it does not", M.grove.offset(OAK) == 0)
  M.state.set_vparam(OAK, "depth", 1.0)
  check("and at depth 2 it moves twice as far",
        math.abs(math.abs(M.grove.offset(OAK)) - full * 2) < 1e-6,
        string.format("%.2f vs %.2f", math.abs(M.grove.offset(OAK)), full * 2))
end

print("\n-- the voice answers with a pulse every time it is struck --")
do
  -- there is no dedicated O socket left to carry this -- a struck voice
  -- answers out of its own single point into whatever else it's cabled to,
  -- the instant patch.degree(voice_id) > 1 (dispatch.lua's strike_voice).
  local M = fresh(13)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER)                       -- 2 Hz
  M.patch.add(KNOCKER, OAK, 1.0)
  M.patch.add(OAK, BRACKEN, 1.0)
  run(M, 20)
  check("the voice was struck", #CALLS.strike > 30, "#" .. #CALLS.strike)
  check("and it answered into the exciter each time",
        math.abs(#CALLS.exciter_gate - #CALLS.strike) <= 1,
        #CALLS.exciter_gate .. " vs " .. #CALLS.strike)
end

print("\n-- and with an audio tap on the same point --")
do
  local M = fresh(17)
  -- oneway, so this is exactly the one continuous synth the old O->M cable
  -- made -- a symmetric voice<->voice cable makes two (see dispatch.lua's
  -- voice_to_voice_specs), which is a different, already-covered shape.
  local edge = M.patch.add(OAK, ROWAN, 0.7, true)
  local add = last(CALLS.patch_add)
  check("one patch synth", add ~= nil)
  check("aa kind", add and add.kind == "aa", add and add.kind)
  check("from Oak's own audio tap",
        add and add.src == M.bridge.bus("voice_out", 0), add and add.src)
  check("into Rowan's mod-in bus",
        add and add.dst == M.bridge.bus("mod_in", 3), add and add.dst)
  M.patch.remove_edge(edge.id)
  check("freed on remove", #CALLS.patch_free == 1)
end

print("\n-- a voice cabled through one transform back to itself can't close a loop --")
do
  -- straight back into itself directly is not just inaudible now, it is
  -- unrepresentable: the socket collapse means trig/out are the same point,
  -- so there is only one cable between a voice and a single transform, and
  -- an R cell's own `except` rule (weave.lua) forbids it from ever answering
  -- back down the cable a pulse arrived on. so a voice's own answer reaches
  -- the transform (it is not swallowed at the door) but the transform's
  -- reply has nowhere left to go -- structurally bounded, not just
  -- refractory-bounded the way the old direct trig<-out loop was.
  local M = fresh(19)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER)
  M.patch.add(KNOCKER, OAK, 1.0)
  M.weave.set_rule(TROD, "accent")   -- passes almost everything through
  M.patch.add(OAK, TROD, 1.0)        -- Oak's only other cable
  run(M, 10)
  check("Oak strikes at exactly Knocker's own rate, no faster",
        math.abs(#CALLS.strike / 10 - 2) < 0.2,
        string.format("%.1f/s", #CALLS.strike / 10))
  check("the transform did receive Oak's self-answer", M.weave.get(TROD).count > 0,
        tostring(M.weave.get(TROD).count))
  check("but has nowhere left to send it back out",
        M.rambler.out_degree(TROD, OAK) == 0,
        tostring(M.rambler.out_degree(TROD, OAK)))

  -- through *two* transforms it is a real, distinct edge back to Oak, and
  -- the loop closes and rings, same as the old multi-hop case always did.
  local N = fresh(19)
  N.state.global.swing = 0
  N.state.global.scatter = 0
  driver(N, KNOCKER)
  N.weave.set_rule(TROD, "accent")
  N.weave.set_rule(GINNEL, "echo")
  N.patch.add(KNOCKER, OAK, 1.0)
  N.patch.add(OAK, TROD, 1.0)
  N.patch.add(TROD, GINNEL, 1.0)
  N.patch.add(GINNEL, OAK, 1.0)     -- a different edge than Oak's cable to Trod
  run(N, 20)
  local rate = #CALLS.strike / 20
  check("with a real second edge back, the voice answers itself", rate > 3,
        string.format("%.1f/s", rate))
  -- the refractory in dispatch.lua is 28ms, so nothing can exceed ~36/s
  check("and it rings rather than screams", rate <= 36, string.format("%.1f/s", rate))
end

print("\n-- the refractory is what bounds it, not luck --")
do
  local M = fresh(23)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER, 1.0)                  -- 4 x beat = 8 Hz
  M.weave.set_rule(GINNEL, "mult")
  M.state.character[GINNEL] = 1.0          -- x7
  M.patch.add(KNOCKER, GINNEL, 1.0)
  M.patch.add(GINNEL, OAK, 1.0)
  M.patch.add(GINNEL, BRACKEN, 1.0)        -- an exciter has no refractory
  run(M, 20)
  check("the exciter takes every tap", #CALLS.exciter_gate > 800,
        "#" .. #CALLS.exciter_gate)
  check("the voice takes fewer", #CALLS.strike < #CALLS.exciter_gate,
        #CALLS.strike .. " vs " .. #CALLS.exciter_gate)
  check("and never more than the refractory allows", #CALLS.strike / 20 <= 36,
        string.format("%.1f/s", #CALLS.strike / 20))
end

print("\n-- the sound page's Balance knob reaches the engine --")
do
  -- the old M socket's balance knob moved onto the sound page (index 12) the
  -- same way Depth did -- there is no socket-level state.character to drive
  -- it live any more, only the ordinary nudge/push path every other row uses.
  local M = fresh(29)
  M.voice.init()
  M.state.set_vparam(OAK, "balance", 0.9)
  M.voice.nudge(OAK, 12, 0) -- push without moving it, same as an E2/E3 nudge would
  local c = last(CALLS.voice_mod, function(x) return x.voice == 0 end)
  check("balance forwarded", c and math.abs(c.v - 0.9) < 1e-9, c and c.v)
end

report()
