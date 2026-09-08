-- lexicon.lua
-- names, descriptions and the one-knob definition for every cell type.
-- what survives here is what the running UI actually uses: the label and
-- range of each cell's character knob (§4.2), which the cell view prints
-- while you are holding the cell, and a one-line description for the same
-- line.
--
-- how these lines are written, since it took two passes to get right. they
-- are read on a 128px screen, wrapped to three lines of about thirty
-- characters, by someone holding the cell down and wondering what it is. so:
-- say what the cell DOES, in the first four words, in the plainest word
-- available. no dashes standing in for a clause, no folk-etymology, no
-- "the trunk" when "the lowest voice" is what is meant. a sentence you can
-- act on beats a sentence you can admire.

local topology = wl("topology")

local lexicon = {}

-- one-line descriptions, keyed by cell id -----------------------------

local DESC = {
  -- voices (§2.1). one cable endpoint each, and a full sound page on a tap.
  oak   = "Deep, heavy and long. Tuned down it is the kick drum.",
  hazel = "Dry and clacky, very short. A hard crack.",
  alder = "Hollow, like a struck tube. The tom.",
  rowan = "Bright and metallic, close to a bell.",

  -- trigger sources / T, internally D (§2.3)
  ["d.hob"]      = "Fires k evenly spread pulses out of every n. Rate sets n.",
  ["d.grim"]     = "Plays a 16 step pattern from a bank, in time with the clock.",
  ["d.shuck"]    = "Very slow and very heavy. One big hit at a time.",
  ["d.boggart"]  = "Every cycle it fires a fast roll of 2 to 7 hits.",
  ["d.spriggan"] = "Rolls a dice each cycle and only sometimes fires.",
  ["d.gabriel"]  = "Fast, free running, and pulled hardest by its neighbours.",
  ["d.hunt"]     = "Speeds up across a cycle, then drops back and starts again.",
  ["d.skriker"]  = "Fires an unpredictable cluster of 2 to 4 hits close together.",

  -- the fills / FILL (§2.3b). unpatched: hold one and it punches its own
  -- flavour into every pulse moving through the panel, for as long as it
  -- is held.
  ["fill.ratchet"] = "Hold: every pulse also fires a fast, decaying ratchet.",
  ["fill.haunt"]   = "Hold: every pulse also fires one quiet echo behind it.",
  ["fill.volley"]  = "Hold: every pulse immediately fires a second, full copy.",
  ["fill.lull"]    = "Hold: thins the panel out, dropping some pulses outright.",

  -- clock cells / C
  ["clk.toll"]  = "Pulses in time with the transport, at the ratio you set.",
  ["clk.knell"] = "Pulses in time with the transport, at the ratio you set.",
  ["clk.chime"] = "Pulses in time with the transport, at the ratio you set.",
  ["clk.peal"]  = "Pulses in time with the transport, at the ratio you set.",

  -- the weave / R (§2.7). every one of these takes a pulse in and sends a
  -- changed pulse out, so the line says what changes.
  ["r.thicket"] = "Drops pulses. Now and then it swallows a whole run of them.",
  ["r.tangle"]  = "Adds a quiet echo just behind every pulse.",
  ["r.stile"]   = "Sends each pulse out of a different cable, in turn.",
  ["r.sneck"]   = "Only lets the hardest pulses through. Amount sets the bar.",
  ["r.lych"]    = "Fires only when two different inputs arrive together.",
  ["r.drove"]   = "Makes some pulses louder than others, on a repeating shape.",

  -- percussion cells / F(ping), N(noise), internally GVOICE (§2.7b)
  ["gv.yaffle"]  = "A mid, woody knock. Tap it for a full sound page.",
  ["gv.knap"]    = "A dry, high crack, like flint. Tap it for a full sound page.",
  ["gv.clapper"] = "A low wooden knock, the kick end. Tap it for a sound page.",
  ["gv.scree"]   = "Bright noise, the hi hat end. Tap it for a full sound page.",
  ["gv.chaff"]   = "Dry mid noise, snare like. Tap it for a full sound page.",
  ["gv.rattle"]  = "A low shake, clap or rim like. Tap it for a sound page.",

  -- exciter cells / E (§2.4). continuous until a pulse is cabled in, then
  -- each pulse fires one short grain of it.
  ["e.bracken"]  = "A dry rustle. Filtered noise and crackle.",
  ["e.ember"]    = "Crackle and pop, like a fire.",
  ["e.gorse"]    = "A prickly, ringing high band.",
  ["e.windfall"] = "Short bursts of grains, in clusters.",
  ["e.mistle"]   = "Pitched chirps, shaped like a bird call.",
  ["e.wisp"]     = "A slow random wander. Too slow to hear, use it to modulate.",

  -- sample players / S, internally SMP (§2.5). eight seats, two mirrored
  -- diagonals of four, and none of them owns a recording any more -- the File
  -- row picks one out of the script's audio/ folder -- so what these say is
  -- what the SEAT is: how it swells, and where it lands in the image.
  ["smp.fen"]     = "Plays a sample. File picks it; Attack and Decay swell it.",
  ["smp.mire"]    = "Plays a sample, slower to arrive. Hard left of centre.",
  ["smp.carr"]    = "Plays a sample. The quickest swell of the eight.",
  ["smp.holt"]    = "Plays a sample. The slowest to arrive, left of centre.",
  ["smp.rain"]    = "Plays a sample. File picks it; Attack and Decay swell it.",
  ["smp.cicada"]  = "Plays a sample, slower to arrive. Right of centre.",
  ["smp.thunder"] = "Plays a sample. The quickest swell of the eight.",
  ["smp.sea"]     = "Plays a sample. The slowest to arrive, right of centre.",

  -- the gusts / G (§2.11). twelve of one instrument, so twelve of one line:
  -- what differs between them is the seat, and the panel already shows that.
  ["gu.gale"]    = "A drone. Press it to play its note. Low and broad.",
  ["gu.sough"]   = "A drone. Press it to play its note. High and breathy.",
  ["gu.eddy"]    = "A drone. Press it to play its note. Quick to speak.",
  ["gu.whorl"]   = "A drone. Press it to play its note. Wide and open.",
  ["gu.flaw"]    = "A drone. Press it to play its note. Fast swell, short fall.",
  ["gu.zephyr"]  = "A drone. Press it to play its note. The highest of the twelve.",
  ["gu.squall"]  = "A drone. Press it to play its note. Very long swell.",
  ["gu.flurry"]  = "A drone. Press it to play its note. Low and quick.",
  ["gu.snell"]   = "A drone. Press it to play its note. Cold and thin.",
  ["gu.bluster"] = "A drone. Press it to play its note. The most forward of them.",
  ["gu.buffet"]  = "A drone. Press it to play its note. Broad and slow.",
  ["gu.haar"]    = "A drone. Press it to play its note. The slowest of the twelve.",

  -- the LFOs / L (§2.12)
  ["lfo.flood"]  = "A sine that never stops. Cable it out, then pick what it moves.",
  ["lfo.ebb"]    = "A sine that never stops. Cable it out, then pick what it moves.",
  ["lfo.neap"]   = "A sine that never stops. Cable it out, then pick what it moves.",
  ["lfo.spring"] = "A sine that never stops. Cable it out, then pick what it moves.",

  -- the two new synth families / X and V (§2.13)
  ["fm.1"] = "Two operator FM. Ratio and Index make the tone. Strike it.",
  ["fm.2"] = "Two operator FM, an octave up. Ratio and Index make the tone.",
  ["va.1"] = "Sine to saw, plus noise, folded and filtered. Strike it.",
  ["va.2"] = "Sine to saw, plus noise, folded and filtered. An octave up.",
}

function lexicon.describe(id)
  local cell = topology.get(id)
  if not cell then return nil end
  return DESC[id] or "(no description)"
end

-- §4.2 "the one thing that matters about that cell" --------------------
-- a voice has no single one: it has the sound editor instead (§5.5), which
-- is why there is no `voice` row here. GVOICE, GUST, LFO, SMP, FM and VA are
-- the same way. so is FILL, for the opposite reason -- there is nothing to
-- turn, fixed or otherwise.

local CHARACTER = {
  D = {label = "Rate",  lo = 0, hi = 1, note = "how often it fires"},
  R = {label = "Amount", lo = 0, hi = 1, note = "how strongly the rule applies"},
  E = {label = "Colour", lo = 0, hi = 1, note = "the source's filter and character"},
  C = {label = "Ratio", lo = 0, hi = 1, note = "multiple or division of the clock"},
}

function lexicon.character(id)
  local cell = topology.get(id)
  if not cell then return nil end
  return CHARACTER[cell.type]
end

return lexicon
