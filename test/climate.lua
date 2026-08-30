-- build phase 6: the §2.8 climate. that a cabled C cell walks the far cell's
-- knob without ever overwriting it, that pulling the cable puts it back
-- exactly, that two climates on one cell average rather than race, and that a
-- pulse restarts the cycle.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local MOON, HOAR, DUSK = "c.moon", "c.hoar", "c.dusk"
local KNOCKER, GABRIEL = "d.knocker", "d.gabriel"
local BECK = "s.beck"

-- the fastest the knob goes: PERIOD_MIN is 6 seconds, so a minute of virtual
-- time is ten full turns of a tide.
local function fast(M, id)
  M.state.character[id] = 0
end

local function span_of(M, id)
  local lo, hi = math.huge, -math.huge
  for _ = 1, 60 do
    run(M, 1)
    local v = M.state.get_character(id, M.topology.get(id), 0, 1)
    lo, hi = math.min(lo, v), math.max(hi, v)
  end
  return lo, hi
end

print("\n-- a cabled climate moves the far cell's knob --")
do
  local M = fresh(1)
  fast(M, MOON)
  M.state.character[GABRIEL] = 0.5
  M.patch.add(MOON, GABRIEL, 1.0)
  local lo, hi = span_of(M, GABRIEL)
  check("it goes somewhere", hi - lo > 0.4, string.format("%.3f..%.3f", lo, hi))
  check("and stays inside the knob's own range", lo >= 0 and hi <= 1,
        string.format("%.3f..%.3f", lo, hi))
  check("the player's setting is untouched", M.state.character[GABRIEL] == 0.5,
        tostring(M.state.character[GABRIEL]))
  check("the base reads back clean", M.state.base_character(GABRIEL, 0, 1) == 0.5)
end

print("\n-- pulling the cable puts it back exactly --")
do
  local M = fresh(3)
  fast(M, MOON)
  M.state.character[BECK] = 0.42
  local edge = M.patch.add(MOON, BECK, 1.0)
  run(M, 4)
  check("it has drifted off the setting",
        M.state.get_character(BECK, M.topology.get(BECK), 0, 1) ~= 0.42)
  M.patch.remove_edge(edge.id)
  check("severing clears the offset", M.state.character_mod[BECK] == nil,
        tostring(M.state.character_mod[BECK]))
  check("and the cell is back where it was",
        M.state.get_character(BECK, M.topology.get(BECK), 0, 1) == 0.42)
end

print("\n-- E2 still works underneath it --")
do
  local M = fresh(5)
  fast(M, MOON)
  M.state.character[GABRIEL] = 0.5
  M.patch.add(MOON, GABRIEL, 1.0)
  run(M, 3)
  local mod = M.state.character_mod[GABRIEL]
  M.state.character[GABRIEL] = 0.2
  check("the weather rides on the new setting, not the old one",
        math.abs(M.state.get_character(GABRIEL, M.topology.get(GABRIEL), 0, 1)
                 - (0.2 + mod)) < 1e-9)
end

print("\n-- two climates on one cell average --")
do
  local M = fresh(7)
  fast(M, MOON)
  fast(M, HOAR)
  M.state.character[GABRIEL] = 0.5
  -- equal and opposite gains: whatever each of them is doing, the pair of
  -- them must stay inside the range one of them alone would reach.
  M.patch.add(MOON, GABRIEL, 1.0)
  M.patch.add(HOAR, GABRIEL, 1.0)
  local lo, hi = span_of(M, GABRIEL)
  check("still bounded", lo >= 0 and hi <= 1, string.format("%.3f..%.3f", lo, hi))
  check("and there is exactly one offset, not two",
        type(M.state.character_mod[GABRIEL]) == "number")
end

print("\n-- gain sets how far, and its sign which way --")
do
  local function excursion(gain)
    local M = fresh(11)
    fast(M, MOON)
    M.state.character[GABRIEL] = 0.5
    M.patch.add(MOON, GABRIEL, gain)
    local lo, hi = span_of(M, GABRIEL)
    return hi - lo
  end
  local wide, narrow = excursion(1.0), excursion(0.25)
  check("a weaker cable moves it less", narrow < wide * 0.5,
        string.format("%.3f vs %.3f", narrow, wide))
  check("a negative cable still moves it", excursion(-1.0) > 0.4)
end

-- cables are undirected, so the ordinary C->D cable also points that D cell's
-- output back at the climate. nothing on the C side may act on it: a gait at
-- a few Hz must not be able to disturb a six-second shape, let alone a
-- ten-minute one. (see the C handler in dispatch.lua.)
print("\n-- a pulse landing on a climate does nothing to it --")
do
  local M = fresh(13)
  fast(M, MOON)
  M.rambler.set_gait(GABRIEL, "drifter")
  M.state.character[GABRIEL] = 1.0     -- 8 Hz, pointed straight back at Moon
  M.patch.add(MOON, GABRIEL, 1.0)
  local f = M.climate.get(MOON)
  local start = f.phase
  run(M, 3)
  -- 3 seconds of a 6-second period is half a turn, whatever the pulses did
  local moved = (f.phase - start) % 1
  check("the cycle keeps its own time under a hail of pulses",
        math.abs(moved - 0.5) < 0.05, string.format("%.3f of a turn", moved))
end

print("\n-- shapes and the readout --")
do
  local M = fresh(17)
  check("a C cell starts on its topology default",
        M.climate.info(MOON).shape == "tide", M.climate.info(MOON).shape)
  local key = M.climate.cycle_shape(MOON, 1)
  check("cycle_shape advances", key == "creep" and M.climate.info(MOON).shape == key, key)

  for _, shape in ipairs(M.climate.SHAPE_ORDER) do
    local N = fresh(19)
    N.climate.set_shape(MOON, shape)
    fast(N, MOON)
    N.state.character[GABRIEL] = 0.5
    N.patch.add(MOON, GABRIEL, 1.0)
    local lo, hi = math.huge, -math.huge
    for _ = 1, 120 do
      run(N, 1)
      local v = N.climate.value(MOON)
      lo, hi = math.min(lo, v), math.max(hi, v)
    end
    check(shape .. " moves, and stays in range",
          hi - lo > 0.15 and lo >= -1.001 and hi <= 1.001,
          string.format("%.3f..%.3f", lo, hi))
  end

  -- the period readout is in the units a human would use for it
  -- Dusk is the shiver, which runs twenty times faster than the rest of the
  -- row, so the minutes readout is checked on a tide at the top of the knob.
  M.state.character[MOON] = 1.0
  M.climate.set_shape(MOON, "tide")
  check("a slow one reads out in minutes",
        M.climate.info(MOON).param:find("min") ~= nil, M.climate.info(MOON).param)
  check("and a fast one in seconds",
        M.climate.info(DUSK).param:find(" s") ~= nil, M.climate.info(DUSK).param)
end

print("\n-- the weather reaches the engine --")
do
  local M = fresh(23)
  M.exciter.resync()
  fast(M, MOON)
  M.patch.add(BECK, "oak.mod", 0.8)   -- turn the exciter on
  M.patch.add(MOON, BECK, 1.0)
  local before = #CALLS.exciter_colour
  run(M, 10)
  check("colour keeps being pushed as the weather turns",
        #CALLS.exciter_colour > before + 10,
        "#" .. (#CALLS.exciter_colour - before))
  local lo, hi = 1, 0
  for i = before + 1, #CALLS.exciter_colour do
    lo = math.min(lo, CALLS.exciter_colour[i].v)
    hi = math.max(hi, CALLS.exciter_colour[i].v)
  end
  check("and it is a sweep, not a jitter", hi - lo > 0.3,
        string.format("%.3f..%.3f", lo, hi))
end

print("\n-- Still freezes the weather with everything else --")
do
  local M = fresh(29)
  fast(M, MOON)
  M.state.character[GABRIEL] = 0.5
  M.patch.add(MOON, GABRIEL, 1.0)
  run(M, 2)
  M.state.global.still = true
  local frozen = M.state.character_mod[GABRIEL]
  run(M, 3)
  check("nothing moves while Still", M.state.character_mod[GABRIEL] == frozen)
  M.state.global.still = false
  run(M, 2)
  check("and it picks up again", M.state.character_mod[GABRIEL] ~= frozen)
end

report()
