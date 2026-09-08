-- §2.3b lib/fill.lua: the four unpatched performance buttons where the TM
-- cells used to sit. covers: the four seats and their fixed flavours; that
-- FILL carries no cable and no settings page; that holding one changes every
-- primary pulse crossing rambler.emit_from while it is held and nothing once
-- it is released; and that an echo is never itself echoed, so two flavours
-- held together stay bounded rather than compounding.
local SP = os.getenv("SP")
local ROOT = os.getenv("ROOT")
arg = {ROOT}
dofile(SP .. "/harness.lua")

local RATCHET, HAUNT, VOLLEY, LULL =
  "fill.ratchet", "fill.haunt", "fill.volley", "fill.lull"
local KNOCKER = "d.hob"
local BECK = "e.bracken"

local function gates()
  return #CALLS.exciter_gate
end

-- a rooted metric D at one cycle per beat: 2 Hz at 120bpm, so `seconds`
-- seconds is exactly 2 x seconds pulses, with no dice anywhere in it -- the
-- same rig test/weave.lua's own rule tests use.
local function driver(M, id)
  M.rambler.set_gait(id, "metric")
  M.state.character[id] = 0.5
  M.state.rooted[id] = true
  M.rambler.get(id).rooted = true
end

local function rig(seed)
  local M = fresh(seed)
  M.state.global.swing = 0
  M.state.global.scatter = 0
  driver(M, KNOCKER)
  M.patch.add(KNOCKER, BECK, 1.0)
  return M
end

print("\n-- four fill cells, where the TM cells used to sit --")
do
  local M = fresh(1)
  local ids, flavors = {}, {}
  for id, cell in M.topology.each() do
    if cell.type == "FILL" then
      table.insert(ids, id)
      flavors[cell.flavor] = true
    end
  end
  check("four of them", #ids == 4, "#" .. #ids)
  local at = {}
  for _, id in ipairs(ids) do
    local c = M.topology.get(id)
    at[c.coords[1][1] .. "," .. c.coords[1][2]] = id
  end
  check("at the same four seats -- (4,4)/(5,4)/(12,4)/(13,4)",
        at["4,4"] and at["5,4"] and at["12,4"] and at["13,4"],
        table.concat(ids, ","))
  check("four different flavours", flavors.roll and flavors.ghost
        and flavors.double and flavors.skip)
  check("a FILL cell is not a pulse cell",
        M.topology.PULSE_TYPES.FILL == nil)
  check("and has no settings page", M.cellparam.page(RATCHET) == nil)
end

print("\n-- idle, a Fill cell changes nothing --")
do
  local M = rig(2)
  run(M, 10) -- 20 pulses in
  check("plain 2 Hz reaches the exciter unchanged", math.abs(gates() - 20) <= 1,
        "got " .. gates())
end

print("\n-- Ratchet (roll): every pulse also fires a fast, decaying burst --")
do
  local M = rig(3)
  M.fill.engage(RATCHET)
  run(M, 10) -- 20 primary pulses, each with 3 extra taps behind it
  check("more than the plain 20 pulses reach the exciter", gates() > 40,
        "got " .. gates())
  M.fill.release(RATCHET)
  local before = gates()
  run(M, 5) -- 10 more primary pulses once released
  -- a ratchet already in flight the instant of release still finishes (the
  -- same way letting go of a physical drum roll does not cut it off
  -- mid-stroke) -- so the budget here is the 10 plain pulses plus at most
  -- one trailing ratchet's worth of taps, not a hard one-for-one.
  check("released, it goes back to one hit per pulse",
        gates() - before <= 10 + 3 + 2, "added " .. (gates() - before))
end

print("\n-- Haunt (ghost): one quiet echo behind every pulse --")
do
  local M = rig(4)
  M.fill.engage(HAUNT)
  run(M, 10) -- 20 primary pulses, one echo each -> ~40
  check("roughly double the plain count", gates() >= 35 and gates() <= 45,
        "got " .. gates())
  local quiet, loud = false, false
  for _, c in ipairs(CALLS.exciter_gate) do
    if c.amp < 0.5 then quiet = true else loud = true end
  end
  check("the echoes are quieter than the pulses that made them",
        quiet and loud)
end

print("\n-- Volley (double): one full-weight copy right behind every pulse --")
do
  local M = rig(5)
  M.fill.engage(VOLLEY)
  run(M, 10)
  check("roughly double the plain count", gates() >= 35 and gates() <= 45,
        "got " .. gates())
  local near_full = 0
  for _, c in ipairs(CALLS.exciter_gate) do
    if c.amp > 0.8 then near_full = near_full + 1 end
  end
  check("most of them arrive at close to full weight, unlike Haunt's",
        near_full >= gates() - 4, tostring(near_full) .. "/" .. gates())
end

print("\n-- Lull (skip): thins the panel out instead of adding to it --")
do
  local M = rig(6)
  M.fill.engage(LULL)
  run(M, 20) -- 40 primary pulses, roughly 55% dropped
  check("well under the plain 40", gates() < 30, "got " .. gates())
  check("but not silence -- some still get through", gates() > 5,
        "got " .. gates())
end

print("\n-- two flavours held together layer, but an echo is never re-filled --")
do
  -- the regression this whole split-sender design exists for: if an echo
  -- went back through rambler.emit_from rather than emit_from_raw, holding
  -- Ratchet would roll its own rolls and this would run away well past
  -- MAX_EMITS_PER_TICK inside a few seconds.
  local M = rig(7)
  M.fill.engage(RATCHET)
  M.fill.engage(VOLLEY)
  local t0 = os.clock()
  run(M, 10) -- 20 primary pulses, each with (3 ratchet taps + 1 volley) = 4 extras
  local wall = os.clock() - t0
  check("bounded: nowhere near a geometric blow-up",
        gates() < 20 * 8, "got " .. gates())
  check("and it ran in reasonable time", wall < 15, string.format("%.2fs", wall))
end

print("\n-- an external transport Start drops every echo in flight --")
do
  local M = rig(8)
  M.fill.engage(RATCHET)
  M.rambler.emit_from(KNOCKER, 1.0) -- one primary pulse, echoes now pending
  check("something is pending", M.fill.pending_count() > 0,
        tostring(M.fill.pending_count()))
  M.rambler.resync()
  check("resync clears it", M.fill.pending_count() == 0)
end

report()
