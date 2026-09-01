-- cellparam.lua
-- a settings page for every cell type that did not already have one.
--
-- voice/GVOICE/TM cells each kept their own PARAMS list (voice.lua,
-- gvoice.lua, tm.lua) because each is a real instrument with its own units.
-- everything else on the panel -- T, R, F, E, H, C, Out -- used to
-- have its settings scattered across gestures instead: E2 for "the one knob",
-- K1+E2 to cycle a bank, K1+tap to flip a boolean, E3-with-nothing-focused
-- for decay. that meant the same physical gesture did a different thing (or
-- nothing at all) depending on which cell you were holding, which is exactly
-- the inconsistency this file removes.
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
local function character_row(label, text_fn)
  return {
    key = "character", label = label,
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
local function bank_row(label, order_fn, current_fn, apply_fn)
  return {
    key = label:lower(), label = label,
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
    key = label:lower(), label = label, steps = 2,
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
    key = "decay", label = "Decay",
    get = function(id) return state.get_decay(id) end,
    set = function(id, v) state.decay[id] = util.clamp(v, 0, 1) end,
    text = text_fn,
    push = function(id) state.notify_decay_change(id) end,
  }
end

-- the pages, one per type ----------------------------------------------------

local PAGES = {}

-- T cells (internally "D"): rate, which gait runs, and whether it is held to
-- the transport. `Couple` is the Kuramoto energy the cell is currently
-- sitting in -- a readout, not a setting, so it has no set of its own.
PAGES.D = {
  character_row("Rate", function(id)
    local info = wl("rambler").info(id)
    return info and info.param or "-"
  end),
  bank_row("Gait",
           function() return wl("rambler").GAIT_ORDER end,
           function(id) local r = wl("rambler").get(id); return r and r.gait end,
           function(id, key) wl("rambler").set_gait(id, key) end),
  flag_row("Clock", "rooted", "wild",
           function(id)
             local info = wl("rambler").info(id)
             if not info or not info.rooted_ok then return nil end
             return info.rooted
           end,
           function(id, on) wl("rambler").set_rooted(id, on) end),
  {
    key = "grid", label = "Grid",
    get = function(id)
      local info = wl("rambler").info(id)
      return info and util.clamp(info.phase or 0, 0, 1) or 0
    end,
    set = function() end,
    text = function(id)
      local info = wl("rambler").info(id)
      return info and (info.grid or "free") or "-"
    end,
    push = function() end,
  },
}

-- R cells: the transform's own amount, and which transform.
PAGES.R = {
  character_row("Amount", function(id)
    local info = wl("weave").info(id)
    return info and info.param or "-"
  end),
  bank_row("Rule",
           function() return wl("weave").RULE_ORDER end,
           function(id) local r = wl("weave").get(id); return r and r.rule end,
           function(id, key) wl("weave").set_rule(id, key) end),
  {
    key = "gate", label = "Gate",
    get = function(id)
      local info = wl("weave").info(id)
      return (info and info.open) and 1 or 0
    end,
    set = function() end,
    text = function(id)
      local info = wl("weave").info(id)
      if not info then return "-" end
      return (info.open and "open" or "shut")
             .. " " .. info.ins .. "/" .. info.outs
    end,
    push = function() end,
  },
}

-- F cells (the grove's pitch fields): how far it roams, which shape it roams
-- in, and whether it lands on the scale or between the notes.
PAGES.F = {
  character_row("Range", function(id)
    local info = wl("grove").info(id)
    return info and info.param or "-"
  end),
  bank_row("Mode",
           function() return wl("grove").MODE_ORDER end,
           function(id) local f = wl("grove").get(id); return f and f.mode end,
           function(id, key) wl("grove").set_mode(id, key) end),
  flag_row("Snap", "snapped", "free",
           function(id) local f = wl("grove").get(id); return f and f.snap or false end,
           function(id, on)
             local f = wl("grove").get(id)
             if f and (f.snap and true or false) ~= on then wl("grove").toggle_snap(id) end
           end),
  {
    key = "degree", label = "Now",
    get = function(id)
      local info = wl("grove").info(id)
      return info and util.clamp((info.pos + 1) / 2, 0, 1) or 0.5
    end,
    set = function() end,
    text = function(id)
      local info = wl("grove").info(id)
      return info and string.format("%+.2f st", info.degree) or "-"
    end,
    push = function() end,
  },
}

-- E cells: the source's colour, and the ratio its envelopes run at.
PAGES.E = {
  character_row("Colour", function(id)
    local ch = wl("lexicon").character(id)
    local lo, hi = (ch and ch.lo) or 0, (ch and ch.hi) or 1
    return string.format("%.2f", state.base_character(id, lo, hi))
  end),
  decay_row(function(id)
    return string.format("x%.2f", wl("exciter").decay_scale(id))
  end),
}

-- H cells: one knob standing for two quantities (§2.5), so the rows under it
-- read both back plus what is actually still moving around the lattice.
PAGES.H = {
  character_row("Conduct", function(id)
    local info = wl("heartwood").info(id)
    return info and string.format("%.2f", info.conductance) or "-"
  end),
  {
    key = "hop", label = "Hop",
    get = function(id)
      local info = wl("heartwood").info(id)
      return info and util.clamp(1 - info.hop / 0.4, 0, 1) or 0
    end,
    set = function() end,
    text = function(id)
      local info = wl("heartwood").info(id)
      return info and string.format("%.0f ms", info.hop * 1000) or "-"
    end,
    push = function() end,
  },
  {
    key = "loss", label = "Loss",
    get = function(id)
      local info = wl("heartwood").info(id)
      return info and util.clamp(1 - info.loss, 0, 1) or 0
    end,
    set = function() end,
    text = function(id)
      local info = wl("heartwood").info(id)
      return info and string.format("%.2f", 1 - info.loss) or "-"
    end,
    push = function() end,
  },
  {
    key = "charge", label = "Charge",
    get = function(id)
      local info = wl("heartwood").info(id)
      return info and util.clamp(info.charge, 0, 1) or 0
    end,
    set = function() end,
    text = function(id)
      local info = wl("heartwood").info(id)
      return info and string.format("%.2f", info.charge) or "-"
    end,
    push = function() end,
  },
}

-- C cells: a pure flasher, so its whole page is the one ratio.
PAGES.C = {
  character_row("Ratio", function(id)
    local info = wl("clockcell").info(id)
    return info and info.param or "-"
  end),
}

-- Out cells: nothing to set -- position along the row *is* the pan -- so the
-- page is two readouts. it still exists, and still opens on a tap, because
-- "some cells have a page and some don't" is the inconsistency this file is
-- here to remove.
PAGES.O = {
  {
    key = "pan", label = "Pan",
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
    key = "feeds", label = "Sources",
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

-- the one entry point. voice/GVOICE/TM/GUST keep their own modules;
-- everything else lands here. returns nil only for a type with nothing at
-- all to show, which no registered type currently is.
function cellparam.page(id)
  local cell = topology.get(id)
  if not cell then return nil end
  if cell.type == "voice" then return wl("voice") end
  if cell.type == "GVOICE" then return wl("gvoice") end
  if cell.type == "GUST" then return wl("gust") end
  if cell.type == "LFO" then return wl("lfo") end
  if cell.type == "TM" then return wl("tm") end
  local p = pages[cell.type]
  if p == nil then
    p = build(cell.type) or false
    pages[cell.type] = p
  end
  return p or nil
end

return cellparam
