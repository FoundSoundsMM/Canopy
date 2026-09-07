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
  local M = fresh(7)
  -- a field cabled in tunes it, exactly as it would a voice. the Scale is off
  -- and the field is wide, so its steps land on different notes rather than
  -- being rounded back onto the same one -- which is a real thing the Scale
  -- does and not what this test is about.
  M.state.global.scale_i = 0
  M.state.character["f.cuckoo"] = 0.8
  M.patch.add("f.cuckoo", FM1, 1.0)
  local before = #CALLS.fm_pitch
  for _ = 1, 6 do M.grove.step("f.cuckoo", 1.0, nil) end
  check("a field cabled in retunes it", #CALLS.fm_pitch > before,
        before .. " -> " .. #CALLS.fm_pitch)

  -- and a register, which is the pairing the Marbles rework was for.
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
  -- and the per-cell Decay row pushes on the way through, via state's own
  -- decay listener rather than by anyone calling the engine directly.
  local n = #CALLS.va_set
  M.state.decay[VA1] = 0.8
  M.state.notify_decay_change(VA1)
  check("a decay change reaches the engine", #CALLS.va_set > n)
  check("as the dcy argument", last(CALLS.va_set).key == "dcy",
        last(CALLS.va_set).key)
end

report()
