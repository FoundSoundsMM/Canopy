-- build phase 5b: the §2.6 pitch fields. that a cabled field actually
-- retunes a voice before it is struck, that Range bounds how far, that snap
-- lands on the scale and free does not, that a pulse steps a field on its own
-- clock, that P<->P cables pull two fields together, and that a voice with no
-- field cabled to it still never plays the same note twice.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local OAK_ROOT = 65
local CUCKOO, MERLIN, PLOVER, RAVEN = "p.cuckoo", "p.merlin", "p.plover", "p.raven"
local BITTERN, NIGHTJAR = "p.bittern", "p.nightjar"

-- semitones between an emitted Hz and a voice's own fundamental
local function st(hz, root)
  return 12 * math.log(hz / (root or OAK_ROOT)) / math.log(2)
end

local function pitches_for(voice)
  local out = {}
  for _, c in ipairs(CALLS.voice_pitch) do
    if c.voice == voice then table.insert(out, c) end
  end
  return out
end

-- one D cell striking Oak, as fast as the metric gait will go, so a test can
-- get plenty of strikes out of a short virtual run.
local function knock_oak(M)
  M.patch.add("d.knocker", "oak.knock", 1.0)
  M.state.character["d.knocker"] = 1.0  -- 4 x beat
end

print("\n-- a cabled field retunes the voice, and does it before the strike --")
do
  local M = fresh(1)
  knock_oak(M)
  M.patch.add(MERLIN, "oak.sway", 1.0)   -- scatter: a new degree every step
  M.state.character[MERLIN] = 1.0        -- widest range
  run(M, 4)

  local p = pitches_for(0)
  check("pitch reaches the engine", #p > 4, "#" .. #p)
  check("and the voice is actually struck", #CALLS.strike > 4, "#" .. #CALLS.strike)

  -- every strike must be preceded by the pitch it is meant to land on
  local ok = true
  for _, s in ipairs(CALLS.strike) do
    local last
    for _, c in ipairs(p) do
      if c.t <= s.t then last = c else break end
    end
    if not last then ok = false break end
  end
  check("every strike has a pitch sent ahead of it", ok)
  -- one per strike, not one per field plus one for the strike. the +1 is the
  -- push that goes out when the cable itself is made, before any of this ran.
  check("and exactly one per strike, not one per field as well",
        #p <= #CALLS.strike + 1,
        #p .. " pitches for " .. #CALLS.strike .. " strikes")

  local lo, hi = math.huge, -math.huge
  for _, c in ipairs(p) do
    local s = st(c.hz)
    lo, hi = math.min(lo, s), math.max(hi, s)
  end
  check("and the line actually moves", (hi - lo) > 3,
        string.format("%.2f .. %.2f st", lo, hi))
end

print("\n-- Range (E2) is what bounds how far the field roams --")
do
  local function spread(range)
    local M = fresh(3)
    knock_oak(M)
    M.patch.add(MERLIN, "oak.sway", 1.0)
    M.state.character[MERLIN] = range
    M.state.notify_character_change(MERLIN)
    run(M, 6)
    local lo, hi = math.huge, -math.huge
    for _, c in ipairs(pitches_for(0)) do
      local s = st(c.hz)
      lo, hi = math.min(lo, s), math.max(hi, s)
    end
    return hi - lo, hi
  end

  local narrow = spread(0)
  local wide, wide_hi = spread(1)
  check("at Range 0 it is a detuner, not a melody", narrow < 1.0,
        string.format("%.3f st", narrow))
  check("at Range 1 it plays across octaves", wide > 12,
        string.format("%.2f st", wide))
  check("and never leaves the two octaves it is given", wide_hi <= 24.5,
        string.format("%.2f st", wide_hi))
end

print("\n-- snap puts the field on the scale; K1+tap sets it free --")
do
  local function on_scale(hz)
    local x = st(hz)
    local rem = x - math.floor(x / 12) * 12
    for _, s in ipairs(wl("grove").SCALE) do
      if math.abs(rem - s) < 0.02 or math.abs(rem - 12) < 0.02 then return true end
    end
    return false
  end

  local M = fresh(5)
  M.patch.add(MERLIN, "oak.sway", 1.0)
  M.state.character[MERLIN] = 1.0
  M.state.notify_character_change(MERLIN)
  -- step the field directly: a strike would add its own few cents of detune,
  -- which is exactly the thing that would blur a snap test.
  for _ = 1, 40 do M.grove.step(MERLIN, 1) end
  local snapped, total = 0, 0
  for _, c in ipairs(pitches_for(0)) do
    total = total + 1
    if on_scale(c.hz) then snapped = snapped + 1 end
  end
  check("every degree lands on a scale tone", total > 10 and snapped == total,
        snapped .. "/" .. total)

  M.grove.toggle_snap(MERLIN)
  CALLS.voice_pitch = {}
  for _, id in ipairs({}) do end
  for _ = 1, 40 do M.grove.step(MERLIN, 1) end
  local off = 0
  for _, c in ipairs(pitches_for(0)) do
    if not on_scale(c.hz) then off = off + 1 end
  end
  check("a freed field sits between the notes", off > 0, "off-scale: " .. off)
end

print("\n-- a narrow field ignores snap, because a scale needs room --")
do
  local M = fresh(41)
  M.patch.add(MERLIN, "oak.sway", 1.0)
  M.state.character[MERLIN] = 0.2       -- well under the smallest interval
  M.state.notify_character_change(MERLIN)
  check("it reads as free even with snap set", M.grove.info(MERLIN).snap == false)
  local moved = false
  for _ = 1, 30 do
    M.grove.step(MERLIN, 1)
    if math.abs(M.grove.offset("oak")) > 1e-6 then moved = true end
  end
  check("and it still detunes rather than collapsing onto the root", moved)
end

print("\n-- a P->S cable makes the exciter's colour ride the line --")
do
  local M = fresh(43)
  M.patch.add("s.mistle", "oak.sap", 0.8)  -- cable it so the exciter is live
  M.patch.add(MERLIN, "s.mistle", 1.0)
  M.state.character[MERLIN] = 1.0
  M.state.notify_character_change(MERLIN)
  local before = #CALLS.exciter_colour
  local seen, in_range = {}, true
  for _ = 1, 30 do M.grove.step(MERLIN, 1) end
  for i = before + 1, #CALLS.exciter_colour do
    local c = CALLS.exciter_colour[i]
    seen[c.v] = true
    if c.v < 0 or c.v > 1 then in_range = false end
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  check("colour moves with the field", n > 3, "distinct colours: " .. n)
  check("and stays inside 0..1", in_range)

  -- and the offset must not survive the cable that created it
  local base = M.state.get_character("s.mistle", M.topology.get("s.mistle"), 0, 1)
  M.patch.remove(MERLIN, "s.mistle")
  local last = CALLS.exciter_colour[#CALLS.exciter_colour]
  check("pulling the cable hands the exciter its own colour back",
        last and math.abs(last.v - base) < 1e-9,
        last and string.format("%.3f vs %.3f", last.v, base) or "no colour sent")
end

print("\n-- octave mode transposes; it never plays a line --")
do
  local M = fresh(7)
  M.patch.add(BITTERN, "oak.sway", 1.0)
  M.state.character[BITTERN] = 1.0
  M.state.notify_character_change(BITTERN)
  for _ = 1, 60 do M.grove.step(BITTERN, 1) end
  local ok, seen = true, {}
  for _, c in ipairs(pitches_for(0)) do
    local s = st(c.hz)
    if math.abs(s - math.floor(s / 12 + 0.5) * 12) > 0.02 then ok = false end
    seen[math.floor(s / 12 + 0.5)] = true
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  check("every pitch is a whole number of octaves off the root", ok)
  check("and it uses more than one of them", n > 1, "octaves seen: " .. n)
end

print("\n-- a pulse steps the field on its own clock --")
do
  local M = fresh(11)
  -- no strike path at all: Shuck only feeds the field, nothing knocks Oak.
  M.patch.add(CUCKOO, "oak.sway", 1.0)
  M.patch.add("d.shuck", CUCKOO, 1.0)
  M.state.character["d.shuck"] = 1.0   -- 0.5 Hz
  M.state.character[CUCKOO] = 0.8
  M.state.notify_character_change(CUCKOO)
  run(M, 12)
  check("no strikes -- nothing is cabled to Knock", #CALLS.strike == 0,
        "#" .. #CALLS.strike)
  check("but the field moved the voice anyway", #pitches_for(0) > 3,
        "#" .. #pitches_for(0))
end

print("\n-- a P<->P cable pulls two fields together --")
do
  local function converge(gain)
    local M = fresh(13)
    M.patch.add(PLOVER, RAVEN, gain)
    local a, b = M.grove.get(PLOVER), M.grove.get(RAVEN)
    a.pos, b.pos = -0.9, 0.9
    local before = math.abs(a.pos - b.pos)
    run(M, 6)
    return before, math.abs(a.pos - b.pos)
  end

  local before, after = converge(1.0)
  check("positive gain closes the gap", after < before * 0.5,
        string.format("%.2f -> %.2f", before, after))

  local rbefore, rafter = converge(-1.0)
  check("negative gain does not", rafter >= rbefore * 0.9,
        string.format("%.2f -> %.2f", rbefore, rafter))
end

print("\n-- a voice with no field still never plays the same note twice --")
do
  local M = fresh(17)
  knock_oak(M)
  run(M, 4)
  local p = pitches_for(0)
  -- not exactly one per strike: the odd draw lands within a third of a cent
  -- of the last one and push_voice drops it as inaudible.
  check("a bare voice is retuned on all but the odd strike",
        #p >= #CALLS.strike * 0.7,
        #p .. " pitches for " .. #CALLS.strike .. " strikes")

  local same, lo, hi = 0, math.huge, -math.huge
  for i = 2, #p do
    if p[i].hz == p[i - 1].hz then same = same + 1 end
  end
  for _, c in ipairs(p) do
    local s = st(c.hz)
    lo, hi = math.min(lo, s), math.max(hi, s)
  end
  check("no two strikes land on the same pitch", same == 0, "repeats: " .. same)
  check("but it is a detune, not a transposition", math.max(-lo, hi) < 0.2,
        string.format("%.3f st", math.max(-lo, hi)))
end

print("\n-- the SC-side drift is on for every voice, and deepens under a field --")
do
  local M = fresh(19)
  M.grove.init()
  local depth = {}
  for _, c in ipairs(CALLS.voice_drift) do depth[c.voice] = c.depth end
  local n = 0
  for _ in pairs(depth) do n = n + 1 end
  check("all six voices get a drift depth at init", n == 6, "#" .. n)
  check("and it is small enough to read as wood, not as out of tune",
        (depth[0] or 0) > 0 and (depth[0] or 1) < 0.1,
        string.format("%.3f st", depth[0] or -1))

  local base = depth[0]
  M.state.character[NIGHTJAR] = 1.0    -- a two-octave field
  M.patch.add(NIGHTJAR, "oak.sway", 1.0)
  local now = base
  for _, c in ipairs(CALLS.voice_drift) do if c.voice == 0 then now = c.depth end end
  check("cabling a wide field in makes the voice breathe harder", now > base,
        string.format("%.3f -> %.3f st", base, now))
  check("and still nowhere near out of tune", now <= 0.35 + 1e-9,
        string.format("%.3f st", now))
end

print("\n-- Still freezes the fields with everything else --")
do
  local M = fresh(23)
  M.patch.add(PLOVER, "oak.sway", 1.0)  -- wander: moves on the tick, unprompted
  M.state.character[PLOVER] = 1.0
  M.state.notify_character_change(PLOVER)
  run(M, 2)
  local before = #pitches_for(0)
  check("a continuous field moves on its own", before > 5, "#" .. before)

  M.state.global.still = true
  run(M, 4)
  check("and stops dead under Still", #pitches_for(0) == before,
        before .. " -> " .. #pitches_for(0))

  M.state.global.still = false
  run(M, 2)
  check("and picks up again after it", #pitches_for(0) > before)
end

print("\n-- pulling the cable hands the voice back its own root --")
do
  local M = fresh(29)
  local edge = M.patch.add(MERLIN, "oak.sway", 1.0)
  M.state.character[MERLIN] = 1.0
  M.state.notify_character_change(MERLIN)
  for _ = 1, 20 do M.grove.step(MERLIN, 1) end
  check("the field has the voice somewhere else", math.abs(M.grove.offset("oak")) > 0,
        string.format("%.2f st", M.grove.offset("oak")))

  M.patch.remove_edge(edge.id)
  check("and severing it returns the voice to its fundamental",
        M.grove.offset("oak") == 0 and math.abs(M.grove.hz("oak") - OAK_ROOT) < 1e-9,
        string.format("%.3f Hz", M.grove.hz("oak")))
end

print("\n-- mode swap and the field's own readout --")
do
  local M = fresh(31)
  local first = M.grove.info(CUCKOO).mode
  check("a P cell starts on its topology default", first == "call", first)
  local key = M.grove.cycle_mode(CUCKOO, 1)
  check("cycle_mode advances it", key ~= first and M.grove.info(CUCKOO).mode == key, key)
  check("info reads out the range in musical units",
        M.grove.info(CUCKOO).param:find("cents") or M.grove.info(CUCKOO).param:find("st"),
        M.grove.info(CUCKOO).param)
  check("snap toggles", M.grove.toggle_snap(CUCKOO) == false
        and M.grove.toggle_snap(CUCKOO) == true)
end

report()
