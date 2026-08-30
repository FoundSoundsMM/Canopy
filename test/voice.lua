-- build phase 6: the voices as the re-cut left them. the four sockets, the
-- eight-parameter sound page (§5.5), and the O socket -- which is both an
-- audio tap and a pulse, and is what finally closes voice<->voice feedback.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local OAK, ROWAN = "oak", "rowan"
local KNOCKER, GABRIEL = "d.knocker", "d.gabriel"
local GINNEL = "r.ginnel"
local BECK = "s.beck"

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

print("\n-- four sockets, and each of them means one thing --")
do
  local M = fresh(1)
  local roles = {}
  for id, cell in M.topology.each() do
    if cell.type == "node" and cell.voice == OAK then roles[cell.role] = id end
  end
  check("trig, pitch, mod and out, and nothing else",
        roles.trig and roles.pitch and roles.mod and roles.out)
  check("they are laid out around the voice cell",
        M.topology.at(2, 1) == "oak.trig" and M.topology.at(1, 2) == "oak.pitch"
        and M.topology.at(3, 2) == "oak.mod" and M.topology.at(2, 3) == "oak.out")
  check("the corners of the cluster are dark",
        M.topology.at(1, 1) == nil and M.topology.at(3, 1) == nil
        and M.topology.at(1, 3) == nil and M.topology.at(3, 3) == nil)
  check("and the voice cell itself is not a socket",
        M.topology.get(OAK).type == "voice")
end

print("\n-- the sound page pushes all eight at init --")
do
  local M = fresh(3)
  M.voice.init()
  check("eight parameters", M.voice.PARAM_COUNT == 8, "#" .. M.voice.PARAM_COUNT)
  check("decay went out", last(CALLS.voice_decay, function(c) return c.voice == 0 end))
  check("structure went out", last(CALLS.voice_structure, function(c) return c.voice == 0 end))
  check("pitch went out", last(CALLS.voice_pitch, function(c) return c.voice == 0 end))
  check("and the sockets with a continuous meaning did too",
        last(CALLS.voice_mod, function(c) return c.voice == 0 end)
        and last(CALLS.voice_tap, function(c) return c.voice == 0 end))
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
  check("all the way down is two octaves", math.abs(M.grove.hz(OAK) - root / 4) < 1e-6,
        string.format("%.3f Hz", M.grove.hz(OAK)))
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

print("\n-- the P socket's depth scales what the fields do --")
do
  local M = fresh(11)
  M.patch.add("f.merlin", "oak.pitch", 1.0)
  M.state.character["f.merlin"] = 1.0
  M.state.notify_character_change("f.merlin")
  for _ = 1, 20 do M.grove.step("f.merlin", 1) end
  local full = math.abs(M.grove.offset(OAK))
  check("at depth 1 the field moves the voice", full > 0, string.format("%.2f st", full))

  M.state.character["oak.pitch"] = 0
  check("at depth 0 it does not", M.grove.offset(OAK) == 0)
  M.state.character["oak.pitch"] = 2
  check("and at depth 2 it moves twice as far",
        math.abs(math.abs(M.grove.offset(OAK)) - full * 2) < 1e-6,
        string.format("%.2f vs %.2f", math.abs(M.grove.offset(OAK)), full * 2))
end

print("\n-- the O socket answers with a pulse every time it is struck --")
do
  local M = fresh(13)
  M.state.global.weather = 0
  driver(M, KNOCKER)                       -- 2 Hz
  M.patch.add(KNOCKER, "oak.trig", 1.0)
  M.patch.add("oak.out", BECK, 1.0)
  run(M, 20)
  check("the voice was struck", #CALLS.strike > 30, "#" .. #CALLS.strike)
  check("and its out socket fired a grain each time",
        math.abs(#CALLS.exciter_gate - #CALLS.strike) <= 1,
        #CALLS.exciter_gate .. " vs " .. #CALLS.strike)
end

print("\n-- and with an audio tap on the same socket --")
do
  local M = fresh(17)
  local edge = M.patch.add("oak.out", "rowan.mod", 0.7)
  local add = last(CALLS.patch_add)
  check("one patch synth", add ~= nil)
  check("aa kind", add and add.kind == "aa", add and add.kind)
  check("from Oak's tap bus",
        add and add.src == M.bridge.bus("voice_out", 0), add and add.src)
  check("into Rowan's mod-in bus",
        add and add.dst == M.bridge.bus("mod_in", 3), add and add.dst)
  M.patch.remove_edge(edge.id)
  check("freed on remove", #CALLS.patch_free == 1)
end

print("\n-- a voice cabled back into its own trigger cannot run away --")
do
  -- straight back into itself is inaudible on purpose: the answering pulse
  -- arrives one 2ms tick later, well inside the refractory, so the voice
  -- ignores it. that is the design working, not the loop failing -- a
  -- feedback path only says anything once something in it takes time.
  local M = fresh(19)
  M.state.global.weather = 0
  driver(M, KNOCKER)
  M.patch.add(KNOCKER, "oak.trig", 1.0)
  M.patch.add("oak.out", "oak.trig", 1.0)
  run(M, 20)
  check("a bare self-loop is swallowed by the refractory",
        math.abs(#CALLS.strike / 20 - 2) < 0.2,
        string.format("%.1f/s", #CALLS.strike / 20))

  -- through a transform that does take time, the same loop is a real one.
  local N = fresh(19)
  N.state.global.weather = 0
  driver(N, KNOCKER)
  N.weave.set_rule("r.twitten", "echo")
  N.patch.add(KNOCKER, "oak.trig", 1.0)
  N.patch.add("oak.out", "r.twitten", 1.0)
  N.patch.add("r.twitten", "oak.trig", 1.0)
  run(N, 20)
  local rate = #CALLS.strike / 20
  check("with a delay in it, the voice answers itself", rate > 3,
        string.format("%.1f/s", rate))
  -- the refractory in dispatch.lua is 28ms, so nothing can exceed ~36/s
  check("and it rings rather than screams", rate <= 36, string.format("%.1f/s", rate))
end

print("\n-- the refractory is what bounds it, not luck --")
do
  local M = fresh(23)
  M.state.global.weather = 0
  driver(M, KNOCKER, 1.0)                  -- 4 x beat = 8 Hz
  M.weave.set_rule(GINNEL, "mult")
  M.state.character[GINNEL] = 1.0          -- x7
  M.patch.add(KNOCKER, GINNEL, 1.0)
  M.patch.add(GINNEL, "oak.trig", 1.0)
  M.patch.add(GINNEL, BECK, 1.0)           -- an exciter has no refractory
  run(M, 20)
  check("the exciter takes every tap", #CALLS.exciter_gate > 800,
        "#" .. #CALLS.exciter_gate)
  check("the voice takes fewer", #CALLS.strike < #CALLS.exciter_gate,
        #CALLS.strike .. " vs " .. #CALLS.exciter_gate)
  check("and never more than the refractory allows", #CALLS.strike / 20 <= 36,
        string.format("%.1f/s", #CALLS.strike / 20))
end

print("\n-- the M socket's balance and the O socket's tap reach the engine --")
do
  local M = fresh(29)
  M.voice.init()
  M.state.character["oak.mod"] = 0.9
  M.state.notify_character_change("oak.mod")
  local c = last(CALLS.voice_mod, function(x) return x.voice == 0 end)
  check("balance forwarded", c and math.abs(c.v - 0.9) < 1e-9, c and c.v)
  M.state.character["oak.out"] = 0.2
  M.state.notify_character_change("oak.out")
  local t = last(CALLS.voice_tap, function(x) return x.voice == 0 end)
  check("tap level forwarded", t and math.abs(t.v - 0.2) < 1e-9, t and t.v)
end

report()
