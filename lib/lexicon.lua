-- lexicon.lua
-- names, descriptions and the one-knob definition for every cell type.
-- the standalone lexicon *pages* are gone -- they were a manual you had to
-- leave the patch to read. what survives is the part the running UI actually
-- uses: the label and range of each cell's character knob (§4.2), which the
-- cell view prints while you are holding the cell, and a one-line description
-- for the same line.

local topology = wl("topology")

local lexicon = {}

-- one-line descriptions, keyed by cell id -----------------------------

local DESC = {
  -- voices (§2.1)
  oak   = "low, heavy, long -- the trunk. tune it down and it is the kick.",
  hazel = "dry, clacky, short, very inharmonic -- the crack.",
  alder = "hollow, odd-harmonic -- a struck tube. the tom.",
  rowan = "bright, bell-adjacent, protective -- the metal.",

  -- pulse cells / D (§2.3)
  ["d.knocker"]  = "metric gait -- locks to the norns clock, integer division.",
  ["d.hob"]      = "euclidean gait -- k pulses spread across n.",
  ["d.grim"]     = "figure gait -- a bank of sixteen-step patterns, on the clock.",
  ["d.shuck"]    = "slow and heavy gait -- very low rate, high weight.",
  ["d.boggart"]  = "burst gait -- one wrap fires a ratchet of 2-7.",
  ["d.spriggan"] = "stochastic gait -- a Bernoulli gate at the wrap.",
  ["d.gabriel"]  = "drifter gait -- fast, free, strongest coupling constant.",
  ["d.hunt"]     = "accelerando gait -- rate ramps across a cycle then resets.",

  -- Turing Machine cells / TM (§2.3b)
  ["tm.padfoot"]    = "8-bit shift register -- triggered only. tap it: full sound page.",
  ["tm.barghest"]   = "8-bit shift register -- triggered only. tap it: full sound page.",
  ["tm.puck"]       = "8-bit shift register -- triggered only. tap it: full sound page.",
  ["tm.tatterfoal"] = "8-bit shift register -- triggered only. tap it: full sound page.",

  -- the weave / R (§2.7)
  ["r.trod"]    = "divide -- lets every Nth pulse through.",
  ["r.ginnel"]  = "mult -- one pulse in, a ratchet of N out.",
  ["r.snicket"] = "delay -- one copy, late by a musical interval.",
  ["r.twitten"] = "echo -- a decaying tail of repeats.",
  ["r.bostal"]  = "chance -- a coin, weighted by the knob.",
  ["r.drove"]   = "accent -- reshapes weight on a cycling contour.",
  ["r.sneck"]   = "sift -- only pulses over the threshold get through.",
  ["r.lych"]    = "meet -- fires when two different inputs land together.",
  ["r.stile"]   = "hocket -- sends each pulse down a different cable.",
  ["r.weir"]    = "swing -- holds every other pulse back.",
  ["r.holt"]    = "blur -- scatters arrival times by a human amount.",
  ["r.coppice"] = "latch -- alternate pulses open and close the gate.",
  ["r.spinney"] = "fill -- every Nth cycle it answers with a flurry.",
  ["r.thicket"] = "rest -- now and then it swallows a whole run.",
  ["r.bramble"] = "flam -- a grace note just ahead of the beat.",
  ["r.tangle"]  = "ghost -- a quiet shadow just behind it.",
  ["r.briar"]   = "roll -- an accelerating run out of one pulse.",
  ["r.withy"]   = "swell -- weight climbs across successive hits, then resets.",
  ["r.osier"]   = "mask -- a euclidean stencil laid over what arrives.",
  ["r.sedge"]   = "shift -- a skip pattern that rotates every cycle.",

  -- percussion cells / G (§2.7b)
  ["g.yaffle"]  = "ping -- a mid, woody knock. tap it: full sound page.",
  ["g.knap"]    = "ping -- a dry, high crack, flint struck. tap it: full sound page.",
  ["g.clapper"] = "ping -- a low wooden knock, the kick end. tap it: full sound page.",
  ["g.scree"]   = "noise -- a bright scatter, the hihat end. tap it: full sound page.",
  ["g.chaff"]   = "noise -- a dry mid rustle, snare-like. tap it: full sound page.",
  ["g.rattle"]  = "noise -- a low shake, clap/rim-like. tap it: full sound page.",

  -- exciter cells / S (§2.4)
  ["s.bracken"]  = "dry rustle -- bandpassed white noise and crackle.",
  ["s.gorse"]    = "prickly high band, resonant, spiky.",
  ["s.ember"]    = "crackle and pop -- exponential impulse noise.",
  ["s.windfall"] = "grain bursts -- short enveloped clusters.",
  ["s.mistle"]   = "pitched chirps -- formant/bird-shaped.",
  ["s.wisp"]     = "slow wandering random walk, control-rate.",
  ["s.hollow"]   = "wind in a trunk -- pink noise through a long comb.",
  ["s.drizzle"]  = "sparse droplets -- dust with a decaying tail.",
  ["s.loam"]     = "dark brown noise, heavily lowpassed.",
  ["s.beck"]     = "burbling filtered noise, self-moving cutoff.",
  ["s.skein"]    = "metal shimmer -- a detuned band of high partials.",
  ["s.flint"]    = "one hard click -- the shortest thing here.",
  ["s.husk"]     = "dry scrape -- noise dragged through a moving notch.",
  ["s.tinder"]   = "fizz -- fast dense sparks, close to a hiss.",
  ["s.mire"]     = "sub thud -- lowpassed noise with body, no top at all.",
  ["s.glim"]     = "ping -- a struck sine with a noise edge.",
  ["s.rasp"]     = "buzz -- comb-filtered saw, a stick on a fence.",
  ["s.cicada"]   = "chirr -- an amplitude-shivered band, insect-like.",
  ["s.hail"]     = "impacts -- a dense scatter of tiny hard hits.",
  ["s.reed"]     = "breath -- filtered air with a formant in it.",

  -- heartwood / H (§2.5)
  ["h.taproot"]  = "heartwood node -- anchors the ring, deep and slow.",
  ["h.mycel"]    = "heartwood node -- a chord across the lattice.",
  ["h.wyrd"]     = "heartwood node -- a chord across the lattice.",
  ["h.ley"]      = "heartwood node -- carries energy toward the hearth.",
  ["h.hearth"]   = "heartwood node -- the warm corner of the ring.",
  ["h.holloway"] = "heartwood node -- a chord across the lattice.",
  ["h.warren"]   = "heartwood node -- a chord across the lattice.",
  ["h.barrow"]   = "heartwood node -- closes the ring back to the taproot.",

  -- the grove / F (§2.6)
  ["f.cuckoo"]   = "call mode -- two notes back and forth, never quite the same twice.",
  ["f.nightjar"] = "drone mode -- stays on the root; only the last few cents move.",
  ["f.curlew"]   = "cascade mode -- a descending run, then a leap back to the top.",
  ["f.bittern"]  = "octave mode -- register jumps only; ignores the scale.",
  ["f.wren"]     = "flutter mode -- fast small steps around a wandering centre.",
  ["f.merlin"]   = "scatter mode -- a new degree anywhere in the field, each step.",
  ["f.plover"]   = "wander mode -- no degrees at all; glides continuously.",
  ["f.raven"]    = "gravity mode -- pulled toward the fields it is cabled to.",

  -- climate / C (§2.8)
  ["c.moon"]  = "tide -- one long slow swell, minutes end to end.",
  ["c.hoar"]  = "creep -- a drunk walk that never comes back the same way.",
  ["c.thaw"]  = "season -- a straight ramp up and a straight ramp down.",
  ["c.gale"]  = "gust -- mostly still, then it throws everything at once.",
  ["c.hush"]  = "breath -- a long draw in and a short push out.",
  ["c.ebb"]   = "wane -- falls away over a long time, then starts over.",
  ["c.bloom"] = "flourish -- climbs slowly, drops all at once.",
  ["c.dusk"]  = "shiver -- small and quick; a tremor rather than a tide.",
}

local ROLE_DESC = {
  trig  = "in: a pulse strikes the resonator (force = edge gain x weight).",
  pitch = "in: a field cabled here tunes the voice; a pulse re-rolls it.",
  mod   = "in: a stream bends the body; a pulse chokes it.",
  out   = "out: the voice's audio tap, and a pulse every time it is struck.",
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
-- a voice has no single one: it has the eight-parameter sound editor
-- instead (§5.5), which is why there is no `voice` row here.

local CHARACTER = {
  node = {
    trig  = {label = "hardness", lo = 0, hi = 1, note = "mallet strike hardness"},
    pitch = {label = "depth",    lo = 0, hi = 2, note = "how far a field moves this voice"},
    mod   = {label = "balance",  lo = 0, hi = 1, note = "inject <-> damp/bend"},
    out   = {label = "tap",      lo = 0, hi = 1, note = "level of the audio tap"},
  },
  D = {label = "rate",        lo = 0, hi = 1, note = "rate / clock relation (gait-dependent)"},
  R = {label = "rule",        lo = 0, hi = 1, note = "the transform's own amount (rule-dependent)"},
  S = {label = "Colour",      lo = 0, hi = 1, note = "the source's filter/character"},
  H = {label = "Conductance", lo = 0, hi = 1, note = "hop delay and loss"},
  F = {label = "Range",       lo = 0, hi = 1, note = "how far the field roams"},
  C = {label = "Period",      lo = 0, hi = 1, note = "how long one turn of the weather takes"},
}

function lexicon.character(id)
  local cell = topology.get(id)
  if not cell then return nil end
  if cell.type == "node" then
    return CHARACTER.node[cell.role]
  end
  return CHARACTER[cell.type]
end

return lexicon
