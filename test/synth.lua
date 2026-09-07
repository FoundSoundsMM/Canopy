-- §2.13 / lib/synth.lua: the two FM cells and the two VA cells at the right
-- of the instrument row.
--
-- covers: (1) where they sit and how row 2 is grouped now; (2) both pages
-- are the page object every other family exposes, with an envelope of their
-- own on them; (3) a pulse plays a note and the note reaches the engine at
-- the pitch grove says it is on; (4) they are pitched the same way a modal
-- voice is -- a field or a register cabled in tunes them, the global Scale
-- has the last word -- which is the whole reason they go through grove;
-- (5) the cable matrix: heard through an Output cell, cross-modulating with
-- each other and with a gust, and holdable by a High clock.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

print("== synth ==")

local FM1, FM2 = "fm.1", "fm.2"
local VA1, VA2 = "va.1", "va.2"

local function last(list)
  return list[#list]
end

local function driver(M, id, char)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = char or 1.0
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

print("\n-- four cells, two of each kind, at the right of the instrument row --")
do
  local M = fresh(1)
  local at = {}
  for x = 1, 16 do
    local id = M.topology.at(x, 2)
    at[x] = id and M.topology.get(id).type or "."
  end
  -- modal voices 1..4, a gap, six drums, a gap, the four new synths.
  check("the four modal voices run 1..4", at[1] == "voice" and at[2] == "voice"
        and at[3] == "voice" and at[4] == "voice",
        table.concat({at[1], at[2], at[3], at[4]}, " "))
  check("with a gap at 5", at[5] == ".", at[5])
  check("the six drums run 6..11", (function()
    for x = 6, 11 do if at[x] ~= "GVOICE" then return false end end
    return true
  end)())
  check("with a gap at 12", at[12] == ".", at[12])
  check("the two FM cells sit at 13 and 14",
        at[13] == "FM" and at[14] == "FM", at[13] .. " " .. at[14])
  check("and the two VA cells at 15 and 16",
        at[15] == "VA" and at[16] == "VA", at[15] .. " " .. at[16])

  -- each family numbers its own cells from 1, because the engine keeps two
  -- arrays of two.
  check("FM indices are 1 and 2",
        M.topology.get(FM1).index == 1 and M.topology.get(FM2).index == 2)
  check("VA indices are 1 and 2",
        M.topology.get(VA1).index == 1 and M.topology.get(VA2).index == 2)
  check("and the panel letters are X and V",
        M.topology.get(FM1).letter == "X" and M.topology.get(VA1).letter == "V")
end

print("\n-- two pages, both the object every other family exposes --")
do
  local M = fresh(2)
  local fm = M.cellparam.page(FM1)
  local va = M.cellparam.page(VA1)
  check("cellparam hands out the FM page", fm == M.synth.page("FM"))
  check("and a different one for VA", va == M.synth.page("VA") and va ~= fm)

  local function keys(page)
    local out = {}
    for _, p in ipairs(page.PARAMS) do table.insert(out, p.key) end
    return table.concat(out, ",")
  end
  check("the FM page is Pitch/Ratio/Index/Fbk/Attack/Decay/Cross/Level/Send",
        keys(fm) == "pitch,ratio,index,fbk,attack,decay,cross,level,send",
        keys(fm))
  check("and the VA page adds Shape, Noise, Fold, Cutoff, Res and Env",
        keys(va) == "pitch,shape,noise,fold,cutoff,res,envamt,attack,decay,cross,level,send",
        keys(va))

  -- both have an envelope of their own, which is what makes them struck
  -- voices rather than drones.
  for _, id in ipairs({FM1, VA1}) do
    check(id .. " has an attack in seconds",
          M.synth.attack_seconds(id) > 0
          and M.synth.attack_seconds(id) <= M.synth.ATTACK_MAX,
          tostring(M.synth.attack_seconds(id)))
    check(id .. " has a decay in seconds",
          M.synth.decay_seconds(id) >= M.synth.DECAY_MIN
          and M.synth.decay_seconds(id) <= M.synth.DECAY_MAX,
          tostring(M.synth.decay_seconds(id)))
  end

  -- and every row reads 0..1, prints, and pushes without erroring.
  for _, pair in ipairs({{FM1, fm}, {VA1, va}}) do
    local id, page = pair[1], pair[2]
    for i = 1, page.PARAM_COUNT do
      local p = page.param(i)
      local v = p.get(id)
      check(id .. " row " .. i .. " (" .. p.label .. ") reads 0..1 and prints",
            type(v) == "number" and v >= 0 and v <= 1
            and type(p.text(id)) == "string")
    end
  end
end

print("\n-- init pushes every knob of every cell --")
do
  local M = fresh(3)
  M.synth.init()
  -- one fm_set per non-pitch, non-send row of the FM page, per cell. Pitch
  -- goes through grove and Send through the patch matrix, so neither lands
  -- in fm_set/va_set.
  check("the FM cells were pushed", #CALLS.fm_set >= 12, tostring(#CALLS.fm_set))
  check("and the VA cells", #CALLS.va_set >= 18, tostring(#CALLS.va_set))
  local seen = {}
  for _, c in ipairs(CALLS.fm_set) do seen[c.key] = true end
  check("Ratio went out as a real ratio, not a knob position",
        seen.ratio == true)
end

print("\n-- Ratio is a ladder of exact ratios, derived from a plain knob --")
do
  local M = fresh(4)
  check("sixteen of them", #M.synth.RATIOS == 16, tostring(#M.synth.RATIOS))
  for i = 1, #M.synth.RATIOS do
    M.state.set_vparam(FM1, "ratio", (i - 0.5) / #M.synth.RATIOS)
    check("position " .. i .. " reads back as " .. M.synth.RATIOS[i],
          M.synth.ratio_index(FM1) == i
          and M.synth.ratio(FM1) == M.synth.RATIOS[i],
          tostring(M.synth.ratio(FM1)))
  end
  -- the default lands on 2:1, which is the plainest useful FM ratio.
  local M2 = fresh(5)
  check("and it starts on 2:1", M2.synth.ratio(FM1) == 2,
        tostring(M2.synth.ratio(FM1)))
end

print("\n-- a pulse plays a note, at the pitch grove says it is on --")
do
  local M = fresh(6)
  M.patch.add("d.hob", FM1, 1.0)
  M.dispatch.on_pulse("d.hob", FM1,
                      {id = -1, a = "d.hob", b = FM1, gain = 1.0}, 1.0)
  check("one note went out", #CALLS.fm_note == 1, tostring(#CALLS.fm_note))
  local c = last(CALLS.fm_note)
  check("at this cell's index", c.index == 0, tostring(c.index))
  check("and at grove's pitch for it",
        math.abs(c.hz - M.grove.hz(FM1)) < 1e-6,
        c.hz .. " vs " .. tostring(M.grove.hz(FM1)))

  -- the refractory, same as a drum head's: a cable looped back round into one
  -- of these is a legal patch and must not machine-gun.
  M.dispatch.on_pulse("d.hob", FM1,
                      {id = -1, a = "d.hob", b = FM1, gain = 1.0}, 1.0)
  check("a second pulse in the same instant is swallowed",
        #CALLS.fm_note == 1, tostring(#CALLS.fm_note))
  T = T + 0.05
  M.dispatch.on_pulse("d.hob", FM1,
                      {id = -1, a = "d.hob", b = FM1, gain = 1.0}, 1.0)
  check("and one past the refractory is not", #CALLS.fm_note == 2,
        tostring(#CALLS.fm_note))

  -- a VA cell answers the same way, on its own command.
  M.patch.add("d.grim", VA2, 1.0)
  M.dispatch.on_pulse("d.grim", VA2,
                      {id = -1, a = "d.grim", b = VA2, gain = 1.0}, 1.0)
  check("a VA cell plays on its own command", #CALLS.va_note == 1,
        tostring(#CALLS.va_note))
  check("at its own index", last(CALLS.va_note).index == 1,
        tostring(last(CALLS.va_note).index))
end

print("\n-- pitched the same way a modal voice is --")
do
  -- a register cabled in tunes it, exactly as it would a voice -- which is
  -- the pairing the Marbles rework was for, and the only pitch source there
  -- is now that the fields are gone (§2.6).
  local M2 = fresh(8)
  M2.state.global.scale_i = 0
  M2.state.set_vparam("tm.padfoot", "steps", 0)
  M2.patch.add("tm.padfoot", VA1, 1.0)
  local seen = {}
  for i = 1, 10 do
    M2.tm.pulse_in("tm.padfoot", 1, nil, 0)
    seen[i] = last(CALLS.va_pitch) and last(CALLS.va_pitch).hz
  end
  local moved = false
  for i = 2, 10 do if seen[i] ~= seen[1] then moved = true end end
  check("a register cabled in plays a line on it", moved,
        tostring(seen[1]) .. " .. " .. tostring(seen[10]))

  -- the global Scale has the last word, same as everywhere else.
  local M3 = fresh(9)
  M3.state.global.scale_i = 0
  M3.state.set_vparam(FM1, "pitch", 0.53)
  local free = M3.grove.hz(FM1)
  M3.state.global.scale_i = 1
  check("with a Scale on, the note is quantised",
        M3.grove.hz(FM1) ~= free,
        tostring(free) .. " -> " .. tostring(M3.grove.hz(FM1)))

  -- and neither family gets glide or drift: they are oscillators, not a bank
  -- of ringing resonators whose pitch has to move under a note.
  local M4 = fresh(10)
  M4.synth.init()
  M4.grove.init()
  local touched = false
  for _, c in ipairs(CALLS.voice_drift) do
    if c.voice > 3 then touched = true end
  end
  check("no drift is sent for them", not touched)
end

print("\n-- the cable matrix --")
do
  local M = fresh(11)
  -- an Output cable is the only way either family is ever heard.
  M.patch.add(FM1, "o.4", 0.8)
  local found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M.bridge.bus("fm_out", 0)
       and c.dst == M.bridge.bus("out", M.topology.get("o.4").index) then
      found = c
    end
  end
  check("cabled to an Output cell it is heard there", found ~= nil)

  -- two of them cross-modulate, the way two gusts do.
  local M2 = fresh(12)
  M2.patch.add(FM1, VA1, 0.7)
  local a, b = false, false
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M2.bridge.bus("fm_out", 0)
       and c.dst == M2.bridge.bus("va_mod", 0) then a = true end
    if c.src == M2.bridge.bus("va_out", 0)
       and c.dst == M2.bridge.bus("fm_mod", 0) then b = true end
  end
  check("an FM and a VA cell modulate each other", a and b,
        tostring(a) .. " " .. tostring(b))

  -- and one of them with a gust, which is the same rule over the same table.
  local M3 = fresh(13)
  M3.patch.add(VA2, "gu.gale", 0.5)
  local c1, c2 = false, false
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M3.bridge.bus("va_out", 1)
       and c.dst == M3.bridge.bus("gust_mod", 0) then c1 = true end
    if c.src == M3.bridge.bus("gust_out", 0)
       and c.dst == M3.bridge.bus("va_mod", 1) then c2 = true end
  end
  check("a VA cell and a gust modulate each other", c1 and c2,
        tostring(c1) .. " " .. tostring(c2))

  -- an LFO on "signal" lands on the cross-mod input, like a second synth.
  local M4 = fresh(14)
  M4.patch.add("lfo.flood", FM2, 0.6)
  local lfo_found
  for _, c in ipairs(CALLS.patch_add) do
    if c.src == M4.bridge.bus("lfo_out", 0)
       and c.dst == M4.bridge.bus("fm_mod", 1) then lfo_found = c end
  end
  check("an LFO lands on the cross-mod input", lfo_found ~= nil)
end

print("\n-- a High clock holds the note open --")
do
  local M = fresh(15)
  M.patch.add("clk.toll", FM1, 1.0)
  M.clockcell.set_high("clk.toll", true)
  check("the FM cell was held", #CALLS.fm_hold > 0 and last(CALLS.fm_hold).on == 1,
        tostring(#CALLS.fm_hold))
  M.clockcell.set_high("clk.toll", false)
  check("and let go again", last(CALLS.fm_hold).on == 0,
        tostring(last(CALLS.fm_hold).on))
end

print("\n-- the global Decay macro reaches them --")
do
  local M = fresh(16)
  local before = M.synth.decay_seconds(VA1)
  M.state.global.decay_mult = 1.0
  check("turning the macro up lengthens them",
        M.synth.decay_seconds(VA1) > before,
        before .. " -> " .. M.synth.decay_seconds(VA1))

  -- and the macro's own row PUSHES to them, which is what was missing: the
  -- multiplier had been folded into synth.decay_seconds since the day it was
  -- written and this file's listener was registered, but gparam's list of who
  -- to notify stopped at the four voices, the drums, the gusts and the
  -- samples -- so an FM cell picked the change up on the next touch of its
  -- own Decay row and not before.
  local M2 = fresh(26)
  local i
  for k = 1, M2.gparam.PARAM_COUNT do
    if M2.gparam.param(k).key == "decay" then i = k end
  end
  local fm_n, va_n = #CALLS.fm_set, #CALLS.va_set
  M2.gparam.nudge(i, 40, true)
  check("moving the macro pushes both synth families",
        #CALLS.fm_set > fm_n and #CALLS.va_set > va_n,
        (#CALLS.fm_set - fm_n) .. " / " .. (#CALLS.va_set - va_n))
  check("and it is their decay it moved",
        last(CALLS.fm_set).key == "dcy" and last(CALLS.va_set).key == "dcy",
        last(CALLS.fm_set).key .. " / " .. last(CALLS.va_set).key)
  -- and the per-cell Decay row pushes on the way through, via state's own
  -- decay listener rather than by anyone calling the engine directly.
  local n = #CALLS.va_set
  M.state.decay[VA1] = 0.8
  M.state.notify_decay_change(VA1)
  check("a decay change reaches the engine", #CALLS.va_set > n)
  check("as the dcy argument", last(CALLS.va_set).key == "dcy",
        last(CALLS.va_set).key)
end

print("\n-- §2.13 the envelope reaches a swell, not just a strike --")
do
  local M = fresh(27)
  local cell = M.topology.get(FM1)

  -- 0.5 is the family's own base, the same contract every other envelope on
  -- the panel has.
  M.state.set_vparam(FM1, "attack", 0.5)
  check("attack at centre is the family's base",
        math.abs(M.synth.attack_seconds(FM1) - M.synth.ATTACK_BASE) < 1e-9,
        tostring(M.synth.attack_seconds(FM1)))
  M.state.decay[FM1] = 0.5
  check("decay at centre is the cell's own",
        math.abs(M.synth.decay_seconds(FM1) - cell.decay) < 1e-9,
        tostring(M.synth.decay_seconds(FM1)))

  -- the two halves of each knob are not the same width: down is what it
  -- always was, up reaches a pad. a symmetric widening would have spent the
  -- bottom third of the Attack row clamped against a floor.
  M.state.set_vparam(FM1, "attack", 0)
  check("all the way down is where it always was",
        math.abs(M.synth.attack_seconds(FM1)
                 - M.synth.ATTACK_BASE / (2 ^ M.synth.ATTACK_OCTAVES_DOWN)) < 1e-9,
        tostring(M.synth.attack_seconds(FM1)))
  M.state.set_vparam(FM1, "attack", 1)
  check("and all the way up is seconds, not milliseconds",
        M.synth.attack_seconds(FM1) > 4,
        string.format("%.3f s", M.synth.attack_seconds(FM1)))
  check("still inside the family's own ceiling",
        M.synth.attack_seconds(FM1) <= M.synth.ATTACK_MAX,
        tostring(M.synth.attack_seconds(FM1)))

  M.state.decay[FM1] = 1
  check("and the fall reaches a gust's kind of length",
        M.synth.decay_seconds(FM1) > 10
        and M.synth.decay_seconds(FM1) <= M.synth.DECAY_MAX,
        string.format("%.3f s", M.synth.decay_seconds(FM1)))
  M.state.decay[FM1] = 0
  check("while the short end is where it always was",
        math.abs(M.synth.decay_seconds(FM1)
                 - cell.decay / (2 ^ M.synth.DECAY_OCTAVES_DOWN)) < 1e-9,
        tostring(M.synth.decay_seconds(FM1)))

  -- every cell of both families stays inside the engine's own clips at both
  -- ends of both knobs, which is what keeps the last of the travel from
  -- doing nothing.
  check("every cell's whole travel is inside the engine's clips", (function()
    local M2 = fresh(28)
    for _, id in ipairs(M2.synth.each()) do
      for _, v in ipairs({0, 0.5, 1}) do
        M2.state.set_vparam(id, "attack", v)
        M2.state.decay[id] = v
        local a, d = M2.synth.attack_seconds(id), M2.synth.decay_seconds(id)
        if a < M2.synth.ATTACK_MIN or a > M2.synth.ATTACK_MAX then return false end
        if d < M2.synth.DECAY_MIN or d > M2.synth.DECAY_MAX then return false end
      end
    end
    return true
  end)())
end

print("\n-- §4.1c Plonks lands on them too --")
do
  -- the detune grove pushes on a strike lands on `freq`, and then the note
  -- command writes `freq` again -- so before synth.play asked for one itself,
  -- the offset was being sent and overwritten a moment later and the macro
  -- did nothing at all here.
  local M = fresh(29)
  M.state.global.scale_i = 0
  M.state.global.drops = 1

  local seen = {}
  for i = 1, 12 do
    T = T + M.synth.REFRACTORY * 2
    M.synth.play(FM1, 1)
    seen[i] = last(CALLS.fm_note).hz
  end
  local moved, spread = false, 0
  for i = 2, 12 do
    if seen[i] ~= seen[1] then moved = true end
    spread = math.max(spread, math.abs(12 * math.log(seen[i] / seen[1]) / math.log(2)))
  end
  check("no two strikes land on the same note", moved,
        tostring(seen[1]) .. " .. " .. tostring(seen[12]))
  check("and it is a detune, inside the macro's own range",
        spread > 0 and spread <= 2 * (0.02 + M.gparam.DROPS_MAX_ST),
        string.format("%.3f st", spread))

  -- at Plonks 0 what is left is the same floor a modal voice has always had,
  -- which is what stops a bare patch sounding like a sample retriggered.
  local M2 = fresh(30)
  M2.state.global.scale_i = 0
  M2.state.global.drops = 0
  local narrow = 0
  local first
  for i = 1, 12 do
    T = T + M2.synth.REFRACTORY * 2
    M2.synth.play(FM1, 1)
    first = first or last(CALLS.fm_note).hz
    narrow = math.max(narrow,
      math.abs(12 * math.log(last(CALLS.fm_note).hz / first) / math.log(2)))
  end
  check("at Plonks 0 it is only the floor", narrow > 0 and narrow <= 0.05,
        string.format("%.4f st", narrow))
  M2.state.global.drops = 0
end

report()
