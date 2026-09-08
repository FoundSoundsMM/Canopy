-- cellparam.lua
-- a settings page for every cell type that did not already have one.
--
-- voice/GVOICE cells each kept their own PARAMS list (voice.lua, gvoice.lua)
-- because each is a real instrument with its own units. everything else on
-- the panel -- T, R, E, C, Out -- used to have its settings scattered across
-- gestures instead: E2 for "the one knob", K1+E2 to cycle a bank, K1+tap to
-- flip a boolean, E3-with-nothing-focused for decay. that meant the same
-- physical gesture did a different thing (or nothing at all) depending on
-- which cell you were holding, which is exactly the inconsistency this file
-- removes.
--
-- a FILL cell (§2.3b) has no page at all -- cellparam.page returns nil for
-- one, the same nil it would for any type with nothing registered -- because
-- it has nothing to set: four fixed flavours, no knob, no cable.
--
-- now every cell type answers `page(id)`, and every page is the same object:
-- a PARAMS list, E1 to pick a row, E2/E3 to move it coarse/fine. what used to
-- be a hidden modifier gesture is a visible, named row.
--
-- the contract matches voice.PARAMS exactly, so screenui/Canopy.lua can drive
-- any of the four modules through one code path:
--   key, label, get(id) -> 0..1, set(id, v), text(id) -> string, push(id)
-- plus one addition of our own, `steps`: the number of discrete positions a
-- row has (a bank of gaits, an on/off flag). a stepped row scales the
-- encoder so one option takes about three detents rather than a tenth of the
-- knob's travel.

local topology  = wl("topology")
local state     = wl("state")
local patch     = wl("patch")

local cellparam = {}

-- E2's own step is 1/80 of the knob (Canopy.lua's VP_COARSE), so a row with
-- `steps` positions wants this much extra gain to move one position per
-- DETENTS_PER_STEP of encoder travel.
local DETENTS_PER_STEP = 3

local function step_scale(n)
  if not n or n < 2 then return 1 end
  return 80 / ((n - 1) * DETENTS_PER_STEP)
end

-- §4.2b a row's label is not always a constant any more. on a T or R cell the
-- two knobs are the *gait's* or the *rule's* two knobs, so what E2 is called
-- changes as E1 scrolls: "Steps" under euclidean, "Chance" under stochastic,
-- "Rate" under four others. every caller that prints a label goes through
-- here so none of them has to know that.
function cellparam.label_of(p, id)
  if p and p.label_fn then return p.label_fn(id) or p.label end
  return p and p.label
end

-- how far `delta` (already in knob units) should actually move this row.
-- `steps_fn` exists for banks whose size is only known once the module that
-- owns them has loaded (rambler's gaits, weave's rules, grove's modes).
function cellparam.scale(p, delta)
  local n = p.steps
  if p.steps_fn then n = p.steps_fn() end
  return delta * step_scale(n)
end

-- shared row builders --------------------------------------------------------

-- "the one thing that matters about that cell" (§4.2) -- the knob E2 used to
-- be when nothing else was going on. lexicon.lua still owns its label and
-- range; this only turns it into a row.
local function character_row(label, text_fn, glyph)
  return {
    key = "character", label = label, glyph = glyph or "fader",
    get = function(id)
      local ch = wl("lexicon").character(id)
      local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
      local v = state.base_character(id, lo, hi)
      return (hi > lo) and ((v - lo) / (hi - lo)) or 0
    end,
    set = function(id, frac)
      local ch = wl("lexicon").character(id)
      local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
      state.character[id] = util.clamp(lo + frac * (hi - lo), lo, hi)
    end,
    text = text_fn,
    push = function(id) state.notify_character_change(id) end,
  }
end

-- a bank of named options (gaits, rules, modes) as one row. `order` is the
-- module's own ORDER table, `current`/`apply` its getter/setter -- this file
-- never learns what any of the keys mean.
-- a bank always draws as `word` -- a pointer angle says nothing about
-- "euclidean" -- and glyph_data gives the box the one thing the old one could
-- not show: that there are nine gaits and this is the second.
local function bank_row(label, order_fn, current_fn, apply_fn)
  return {
    key = label:lower(), label = label, glyph = "word",
    glyph_data = function(id)
      local order = order_fn()
      local cur = current_fn(id)
      for i, key in ipairs(order) do
        if key == cur then return {idx = i - 1, total = #order} end
      end
      return {idx = 0, total = #order}
    end,
    steps_fn = function() return #order_fn() end,
    get = function(id)
      local order = order_fn()
      local cur = current_fn(id)
      for i, key in ipairs(order) do
        if key == cur then return (i - 1) / math.max(1, #order - 1) end
      end
      return 0
    end,
    set = function(id, frac)
      local order = order_fn()
      local i = util.clamp(math.floor(frac * (#order - 1) + 0.5), 0, #order - 1) + 1
      apply_fn(id, order[i])
    end,
    text = function(id) return current_fn(id) or "-" end,
    push = function() end,
  }
end

-- an on/off row. `read` returns a boolean or nil ("this cell cannot"), and
-- `write` takes the new boolean.
local function flag_row(label, on_text, off_text, read_fn, write_fn)
  return {
    key = label:lower(), label = label, glyph = "flag", steps = 2,
    get = function(id) return read_fn(id) and 1 or 0 end,
    set = function(id, frac) write_fn(id, frac >= 0.5) end,
    text = function(id)
      local v = read_fn(id)
      if v == nil then return "n/a" end
      return v and on_text or off_text
    end,
    push = function() end,
  }
end

-- §4.2's E3-with-nothing-focused, as a row. state.lua still decides which
-- cells have a decay at all.
local function decay_row(text_fn)
  return {
    key = "decay", label = "Decay", glyph = "ramp",
    get = function(id) return state.get_decay(id) end,
    set = function(id, v) state.decay[id] = util.clamp(v, 0, 1) end,
    text = text_fn,
    push = function(id) state.notify_decay_change(id) end,
  }
end

-- §4.2b the two knobs a T or R cell's page is made of ------------------------
--
-- these two rows replaced four (Rate / Gait / Clock / Grid) and three
-- (Amount / Rule / Gate). the list they used to hold -- which gait, which
-- rule -- is E1 now rather than a row, because it is the one choice on the
-- page that changes what the other two mean; and Grid and Gate were readouts,
-- which is what the scope underneath is for (§5.2c). Clock went with the
-- gait: `metric` is the rooted one, and rootedness on the other eight was a
-- switch that read `n/a` on six of them.
--
-- both rows are plain 0..1 knobs. `info_fn` is the owning module's info()
-- and carries the label and the reading for whichever entry E1 has landed on.
local function knob_row(key, glyph, fallback, info_fn, second)
  return {
    key = key, label = fallback, glyph = glyph,
    label_fn = function(id)
      local i = info_fn(id)
      if not i then return fallback end
      return (second and i.label2 or i.label) or fallback
    end,
    get = function(id)
      if second then return state.base_character_b(id, 0.5) end
      return state.base_character(id, 0, 1)
    end,
    set = function(id, v)
      if second then state.character_b[id] = util.clamp(v, 0, 1)
      else state.character[id] = util.clamp(v, 0, 1) end
    end,
    text = function(id)
      local i = info_fn(id)
      if not i then return "-" end
      return (second and i.param2 or i.param) or "-"
    end,
    push = function(id) state.notify_character_change(id) end,
  }
end

-- what E1 scrolls on a page that has a list rather than a cursor. one entry
-- per type that has one; `build` turns it into page.cycle().
local CYCLES = {
  D = {
    label = "Gait",
    order   = function() return wl("rambler").GAIT_ORDER end,
    current = function(id) local r = wl("rambler").get(id); return r and r.gait end,
    apply   = function(id, key) wl("rambler").set_gait(id, key) end,
  },
  R = {
    label = "Rule",
    order   = function() return wl("weave").RULE_ORDER end,
    current = function(id) local r = wl("weave").get(id); return r and r.rule end,
    apply   = function(id, key) wl("weave").set_rule(id, key) end,
  },
}

-- the pages, one per type ----------------------------------------------------

local PAGES = {}

-- T cells (internally "D"): rate, which gait runs, and whether it is held to
-- the transport. `Couple` is the Kuramoto energy the cell is currently
-- sitting in -- a readout, not a setting, so it has no set of its own.
PAGES.D = {
  knob_row("character",   "fader", "Rate",
           function(id) return wl("rambler").info(id) end, false),
  knob_row("character_b", "tilt",  "Shape",
           function(id) return wl("rambler").info(id) end, true),
}

-- R cells: the same two knobs, belonging to whichever rule E1 is on.
PAGES.R = {
  knob_row("character",   "fader", "Amount",
           function(id) return wl("weave").info(id) end, false),
  knob_row("character_b", "tilt",  "Shape",
           function(id) return wl("weave").info(id) end, true),
}

-- E cells: the source's colour, and the ratio its envelopes run at.
PAGES.E = {
  character_row("Colour", function(id)
    local ch = wl("lexicon").character(id)
    local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
    return string.format("%.2f", state.base_character(id, lo, hi))
  end, "tilt"),
  decay_row(function(id)
    return string.format("x%.2f", wl("exciter").decay_scale(id))
  end),
}

-- C cells: the ratio, and §2.9b the one switch that decides whether the
-- ratio means anything. Mode: Clock is what this family has always been, a
-- pulse on a division of the transport; High is a trigger that is simply
-- always up, holding whatever it is cabled to open rather than striking it.
-- Ratio stays on the page in High -- it is where the cell will be when it
-- comes back, and blanking a knob you are about to want again is worse than
-- leaving it showing a number nothing is currently reading.
PAGES.C = {
  character_row("Ratio", function(id)
    local info = wl("clockcell").info(id)
    return info and info.param or "-"
  end, "word"),
  flag_row("Mode", "high", "clock",
    function(id) return wl("clockcell").is_high(id) end,
    function(id, on) wl("clockcell").set_high(id, on) end),
}

-- Out cells: nothing to set -- position along the row *is* the pan -- so the
-- page is two readouts. it still exists, and still opens on a tap, because
-- "some cells have a page and some don't" is the inconsistency this file is
-- here to remove.
PAGES.O = {
  {
    key = "pan", label = "Pan", glyph = "marker",
    get = function(id)
      local cell = topology.get(id)
      return cell and ((cell.pan + 1) / 2) or 0.5
    end,
    set = function() end,
    text = function(id)
      local cell = topology.get(id)
      local p = cell and cell.pan or 0
      if math.abs(p) < 0.01 then return "centre" end
      return string.format("%s %.0f", p < 0 and "L" or "R", math.abs(p) * 100)
    end,
    push = function() end,
  },
  {
    key = "feeds", label = "Sources", glyph = "steps",
    glyph_data = function(id) return {n = 8, lit = patch.degree(id)} end,
    get = function(id) return util.clamp(patch.degree(id) / 8, 0, 1) end,
    set = function() end,
    text = function(id) return tostring(patch.degree(id)) end,
    push = function() end,
  },
}

-- one page object per type, built once and shared. the same shape voice.lua
-- and friends expose, so screenui and Canopy.lua can hold any of them.
local pages = {}

local function build(kind)
  local params = PAGES[kind]
  if not params then return nil end
  local page = {PARAMS = params, PARAM_COUNT = #params}

  -- §4.2b a page with a CYCLE is driven differently: E1 walks the list, and
  -- E2/E3 are rows one and two rather than coarse and fine on one row. there
  -- is no cursor on such a page, so nothing to focus and nothing to scroll --
  -- which is exactly what makes it one page.
  local cyc = CYCLES[kind]
  if cyc then
    page.CYCLE = cyc.label

    function page.cycle_pos(id)
      local order = cyc.order()
      local cur = cyc.current(id)
      for i, key in ipairs(order) do
        if key == cur then return i, #order, key end
      end
      return 1, #order, order[1]
    end

    function page.cycle(id, d)
      local order = cyc.order()
      local at = page.cycle_pos(id)
      local nxt = ((at - 1 + d) % #order) + 1
      cyc.apply(id, order[nxt])
      return order[nxt]
    end
  end

  function page.param(i)
    return params[util.clamp(i, 1, #params)]
  end

  -- a stepped row cannot round-trip through its own getter: `Gait` reads back
  -- as one of eight fixed positions, so adding a third of a step and reading
  -- it again lands on the position you started from and the row never moves,
  -- however long you turn. so the encoder's position is kept here, unrounded,
  -- and only re-seeded from the getter when something else has moved the row
  -- (Regrow, a patch load, the other half of a counterpart pair).
  local acc = {}   -- id\0key -> {raw = unrounded knob, seen = what we last read}

  function page.nudge(id, i, delta)
    local p = page.param(i)
    local k = id .. "\0" .. tostring(p.key or i)
    local cur = p.get(id)
    local a = acc[k]
    if not a or a.seen ~= cur then
      a = {raw = cur, seen = cur}
      acc[k] = a
    end
    a.raw = util.clamp(a.raw + cellparam.scale(p, delta), 0, 1)
    p.set(id, a.raw)
    p.push(id)
    a.seen = p.get(id)
    return p
  end
  return page
end

-- the one entry point. voice/GVOICE/GUST/LFO/SMP/FM/VA keep their own
-- modules; everything else lands here. returns nil for a type with nothing
-- at all to show -- currently only FILL (§2.3b).
function cellparam.page(id)
  local cell = topology.get(id)
  if not cell then return nil end
  if cell.type == "voice" then return wl("voice") end
  if cell.type == "GVOICE" then return wl("gvoice") end
  if cell.type == "GUST" then return wl("gust") end
  -- §2.13 one module, two pages: the FM and VA families differ only in what
  -- makes the tone, so lib/synth.lua owns both and picks by type.
  if cell.type == "FM" or cell.type == "VA" then
    return wl("synth").page(cell.type)
  end
  if cell.type == "LFO" then return wl("lfo") end
  if cell.type == "SMP" then return wl("sample") end
  local p = pages[cell.type]
  if p == nil then
    p = build(cell.type) or false
    pages[cell.type] = p
  end
  return p or nil
end

return cellparam
