-- lexicon.lua
-- names, descriptions and the one-knob definition for every cell type.
-- what survives here is what the running UI actually uses: the label and
-- range of each cell's character knob (§4.2), which the cell view prints
-- while you are holding the cell, and a one-line description for the same
-- line.

local topology = wl("topology")

local lexicon = {}

-- one-line descriptions, keyed by cell id -----------------------------

local DESC = {
  -- voices (§2.1) -- one point now, cable endpoint and sound page both.
  oak   = "low, heavy, long -- the trunk. tune it down and it is the kick.",
  hazel = "dry, clacky, short, very inharmonic -- the crack.",
  alder = "hollow, odd-harmonic -- a struck tube. the tom.",
  rowan = "bright, bell-adjacent, protective -- the metal.",

  -- trigger sources / T, internally D (§2.3)
  ["d.hob"]      = "euclidean gait -- k pulses spread across n.",
  ["d.grim"]     = "figure gait -- a bank of sixteen-step patterns, on the clock.",
  ["d.shuck"]    = "slow and heavy gait -- very low rate, high weight.",
  ["d.boggart"]  = "burst gait -- one wrap fires a ratchet of 2-7.",
  ["d.spriggan"] = "stochastic gait -- a Bernoulli gate at the wrap.",
  ["d.gabriel"]  = "drifter gait -- fast, free, strongest coupling constant.",
  ["d.hunt"]     = "accelerando gait -- rate ramps across a cycle then resets.",
  ["d.skriker"]  = "swarm gait -- a short, unpredictable cluster of 2-4 hits.",

  -- Turing Machine cells / TM (§2.3b)
  ["tm.padfoot"]    = "8-bit shift register -- triggered only. tap it: full sound page.",
  ["tm.barghest"]   = "8-bit shift register -- triggered only. tap it: full sound page.",
  ["tm.puck"]       = "8-bit shift register -- triggered only. tap it: full sound page.",
  ["tm.tatterfoal"] = "8-bit shift register -- triggered only. tap it: full sound page.",

  -- clock cells / C (new)
  ["clk.toll"]  = "flashes with the master clock, at this cell's own ratio.",
  ["clk.knell"] = "flashes with the master clock, at this cell's own ratio.",
  ["clk.chime"] = "flashes with the master clock, at this cell's own ratio.",
  ["clk.peal"]  = "flashes with the master clock, at this cell's own ratio.",

  -- the weave / R (§2.7)
  ["r.thicket"] = "rest -- now and then it swallows a whole run.",
  ["r.tangle"]  = "ghost -- a quiet shadow just behind it.",
  ["r.stile"]   = "hocket -- sends each pulse down a different cable.",
  ["r.sneck"]   = "sift -- only pulses over the threshold get through.",
  ["r.lych"]    = "meet -- fires when two different inputs land together.",
  ["r.drove"]   = "accent -- reshapes weight on a cycling contour.",

  -- percussion cells / F(ping), N(noise), internally GVOICE (§2.7b)
  ["gv.yaffle"]  = "ping -- a mid, woody knock. tap it: full sound page.",
  ["gv.knap"]    = "ping -- a dry, high crack, flint struck. tap it: full sound page.",
  ["gv.clapper"] = "ping -- a low wooden knock, the kick end. tap it: full sound page.",
  ["gv.scree"]   = "noise -- a bright scatter, the hihat end. tap it: full sound page.",
  ["gv.chaff"]   = "noise -- a dry mid rustle, snare-like. tap it: full sound page.",
  ["gv.rattle"]  = "noise -- a low shake, clap/rim-like. tap it: full sound page.",

  -- exciter cells / E, was S (§2.4)
  ["e.bracken"]  = "dry rustle -- bandpassed white noise and crackle.",
  ["e.ember"]    = "crackle and pop -- exponential impulse noise.",
  ["e.gorse"]    = "prickly high band, resonant, spiky.",
  ["e.windfall"] = "grain bursts -- short enveloped clusters.",
  ["e.mistle"]   = "pitched chirps -- formant/bird-shaped.",
  ["e.wisp"]     = "slow wandering random walk, control-rate.",

  -- heartwood / H (§2.5)
  ["h.taproot"] = "heartwood node -- anchors the chain, deep and slow.",
  ["h.mycel"]   = "heartwood node -- passes energy along the chain.",
  ["h.wyrd"]    = "heartwood node -- passes energy along the chain.",
  ["h.ley"]     = "heartwood node -- the far end of the chain.",

  -- the gusts / G (§2.11)
  ["gu.gale"]    = "gust -- the top row's low edge, broad and unhurried.",
  ["gu.sough"]   = "gust -- a high, breathy swell. press it: it sounds.",
  ["gu.eddy"]    = "gust -- quick to speak, turns over on itself.",
  ["gu.whorl"]   = "gust -- the slowest of the top row, wide and open.",
  ["gu.flaw"]    = "gust -- the sharpest: fast swell, short fall.",
  ["gu.zephyr"]  = "gust -- the top row's high edge, quickest of the twelve.",
  ["gu.squall"]  = "gust -- lowest and furthest left, a very long swell.",
  ["gu.flurry"]  = "gust -- low and quick, the bed's moving part.",
  ["gu.snell"]   = "gust -- cold and thin for its register.",
  ["gu.bluster"] = "gust -- the bed's most forward voice.",
  ["gu.buffet"]  = "gust -- broad and slow, sits under the others.",
  ["gu.haar"]    = "gust -- lowest right, the slowest to arrive of all twelve.",

  -- the LFOs / L (§2.12) -- one sine each, sitting right above the gusts.
  ["lfo.flood"]  = "sine LFO -- cable it anywhere and turn up Speed.",
  ["lfo.ebb"]    = "sine LFO -- cable it anywhere and turn up Speed.",
  ["lfo.neap"]   = "sine LFO -- cable it anywhere and turn up Speed.",
  ["lfo.spring"] = "sine LFO -- cable it anywhere and turn up Speed.",

  -- the grove / F (§2.6)
  ["f.cuckoo"]   = "call mode -- two notes back and forth, never quite the same twice.",
  ["f.nightjar"] = "drone mode -- stays on the root; only the last few cents move.",
  ["f.curlew"]   = "cascade mode -- a descending run, then a leap back to the top.",
  ["f.bittern"]  = "octave mode -- register jumps only; ignores the scale.",
}

function lexicon.describe(id)
  local cell = topology.get(id)
  if not cell then return nil end
  return DESC[id] or "(no description)"
end

-- §4.2 "the one thing that matters about that cell" --------------------
-- a voice has no single one: it has the sound editor instead (§5.5), which
-- is why there is no `voice` row here. GVOICE, TM and GUST are the same way.

local CHARACTER = {
  D = {label = "rate",  lo = 0, hi = 1, note = "rate / clock relation (gait-dependent)"},
  R = {label = "rule",  lo = 0, hi = 1, note = "the transform's own amount (rule-dependent)"},
  E = {label = "Colour", lo = 0, hi = 1, note = "the source's filter/character"},
  H = {label = "Conductance", lo = 0, hi = 1, note = "hop delay and loss"},
  F = {label = "Range", lo = 0, hi = 1, note = "how far the field roams"},
  C = {label = "Ratio", lo = 0, hi = 1, note = "multiple/division of the master clock"},
}

function lexicon.character(id)
  local cell = topology.get(id)
  if not cell then return nil end
  return CHARACTER[cell.type]
end

return lexicon
