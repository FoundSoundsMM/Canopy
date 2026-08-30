-- lexicon.lua
-- names, descriptions, per-cell defaults. this is the on-device manual
-- (§5.4 lexicon view reads straight from here).

local topology = include("Woodland/lib/topology")

local lexicon = {}

-- one-line descriptions, keyed by cell id -----------------------------

local DESC = {
  -- voices (§2.1)
  oak   = "low, heavy, long — the trunk.",
  rowan = "bright, bell-adjacent, protective.",
  ash   = "hollow tube, odd-harmonic, spear-straight.",
  hazel = "dry, clacky, short, very inharmonic.",
  yew   = "darkest, longest decay, churchyard drone.",
  alder = "wet, comb-shifted, drifting — the water tree.",

  -- pulse cells / D (§2.3)
  ["d.knocker"]  = "metric gait — locks to the norns clock, integer division.",
  ["d.hob"]      = "euclidean gait — k pulses spread across n.",
  ["d.grim"]     = "divider gait — passes every Nth incoming pulse.",
  ["d.shuck"]    = "slow and heavy gait — very low rate, high weight.",
  ["d.boggart"]  = "burst gait — one wrap fires a ratchet of 2-7.",
  ["d.gabriel"]  = "drifter gait — fast, free, strongest coupling constant.",
  ["d.spriggan"] = "coincidence gait — fires when two inputs arrive inside a window.",
  ["d.barguest"] = "echo gait — re-emits incoming pulses, tapped, with decay.",
  ["d.puck"]     = "stochastic gait — a Bernoulli gate at the wrap.",
  ["d.hunt"]     = "accelerando gait — rate ramps across a cycle then resets.",

  -- exciter cells / S (§2.4)
  ["s.bracken"]  = "dry rustle — bandpassed white noise and crackle.",
  ["s.gorse"]    = "prickly high band, resonant, spiky.",
  ["s.ember"]    = "crackle and pop — exponential impulse noise.",
  ["s.windfall"] = "grain bursts — short enveloped clusters.",
  ["s.mistle"]   = "pitched chirps — formant/bird-shaped.",
  ["s.wisp"]     = "slow wandering random walk, control-rate.",
  ["s.hollow"]   = "wind in a trunk — pink noise through a long comb.",
  ["s.drizzle"]  = "sparse droplets — dust with a decaying tail.",
  ["s.loam"]     = "dark brown noise, heavily lowpassed.",
  ["s.beck"]     = "burbling filtered noise, self-moving cutoff.",

  -- heartwood / H (§2.5)
  ["h.taproot"]  = "heartwood node — anchors the ring, deep and slow.",
  ["h.mycel"]    = "heartwood node — a chord across the lattice.",
  ["h.wyrd"]     = "heartwood node — a chord across the lattice.",
  ["h.ley"]      = "heartwood node — carries energy toward the hearth.",
  ["h.hearth"]   = "heartwood node — the warm corner of the ring.",
  ["h.holloway"] = "heartwood node — a chord across the lattice.",
  ["h.warren"]   = "heartwood node — a chord across the lattice.",
  ["h.barrow"]   = "heartwood node — closes the ring back to the taproot.",
}

local ROLE_DESC = {
  knock = "in: pulses strike the resonator (force = edge gain). out: a pulse each time the voice is struck.",
  sway  = "in: bends pitch and structure (bipolar). out: the voice's amplitude envelope as a stream.",
  sap   = "in: stream injected audio-rate into the resonator. out: the voice's audio output tap.",
  moss  = "in: sets damping and brightness; a pulse chokes it. out: the voice's spectral centroid as a stream.",
}

function lexicon.describe(id)
  local cell = topology.get(id)
  if not cell then return nil end
  if cell.type == "node" then
    return ROLE_DESC[cell.role]
  end
  return DESC[id] or "(no description)"
end

-- §4.2 "the one thing that matters about that cell" --------------------

local CHARACTER = {
  voice = {label = "Grain",       lo = 0,  hi = 1, note = "soft/hollow -> hard/dry"},
  node = {
    knock = {label = "hardness",  lo = 0,  hi = 1, note = "mallet strike hardness"},
    sway  = {label = "bend",      lo = -1, hi = 1, note = "pitch <-> structure balance"},
    sap   = {label = "injection", lo = 0,  hi = 1, note = "how much stream reaches the resonator"},
    moss  = {label = "damping",   lo = 0,  hi = 1, note = "even vs frequency-weighted"},
  },
  D = {label = "rate",       lo = 0, hi = 1, note = "rate / clock relation (gait-dependent)"},
  S = {label = "Colour",     lo = 0, hi = 1, note = "the source's filter/character"},
  H = {label = "Conductance",lo = 0, hi = 1, note = "hop delay and loss"},
}

function lexicon.character(id)
  local cell = topology.get(id)
  if not cell then return nil end
  if cell.type == "node" then
    return CHARACTER.node[cell.role]
  end
  return CHARACTER[cell.type]
end

-- flat, sorted listing for the lexicon screen (§5.4) --------------------

local TYPE_ORDER = {voice = 1, node = 2, D = 3, S = 4, H = 5}

function lexicon.listing()
  local out = {}
  for id, cell in topology.each() do
    table.insert(out, {
      id = id,
      name = cell.name,
      type = cell.type,
      coords = cell.coords,
      desc = lexicon.describe(id),
    })
  end
  table.sort(out, function(a, b)
    if TYPE_ORDER[a.type] ~= TYPE_ORDER[b.type] then
      return TYPE_ORDER[a.type] < TYPE_ORDER[b.type]
    end
    return a.id < b.id
  end)
  return out
end

return lexicon
