# WOODLAND — design & implementation spec

A monome norns script for grid (128). Four modal/pinged-filter voices in the
corners, each with four named sockets, patched by hand into a sealed core of
pulse-makers and four banks of things to do to a pulse on its way between them.
Inspired by the Ciat-Lonbarde Plumbutter; dressed in British woodland folklore.

The panel was re-cut at build phase 6 around what the instrument turned out to
be for -- a generative, organic drum machine. §2 describes the map as re-cut;
where a decision changed, the reason is given rather than the history erased.

Target: norns (CM3-class), grid 128 (16x8) **required**. SuperCollider engine +
Lua patching/sequencing layer.

---

## 1. Core principles

1. **Every socket is androgynous.** A cell is simultaneously an input and an
   output. A cable is an undirected *coupling*, not a routing arrow. What
   actually flows is determined by what is at each end (see the interaction
   matrix, §6).
2. **You patch by hand, one cable at a time.** Hold a cell, tap another. That is
   the entire wiring grammar.
3. **The grid is the display.** Brightness is not decoration — it is the meter.
   The screen is secondary, for detail and naming.
4. **Everything is named.** Every one of the 92 live cells has a name from
   woodland or British folklore. Names are the interface's memory.
   Coordinates that are *not* cells are left unregistered, dark and inert --
   the shape of the gaps is as much of the layout as the cells are.
5. **Coupling, not sequencing.** Pulse cells do not "send to" each other, they
   *entrain* to each other. Rhythms emerge from phase-pulling, not step data.
6. **Feedback is a feature.** Voice audio can be patched into another voice's
   mod input, and a voice emits a pulse the instant it is struck, so a drum can
   trigger a drum. Both must self-limit musically rather than be prevented: a
   DC-blocked, soft-saturating, limited voice bus for the audio, and a 28 ms
   per-voice refractory for the pulses.

---

## 2. Grid topology (16 x 8)

Coordinates are `(x, y)`, x = column 1..16, y = row 1..8, matching `g.key(x,y,z)`.

```
      1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
 1    ·   T   ·   S   S   S   S   S   S   S   S   S   S   ·   T   ·
 2    P   V   M   R   R   R   R   R   R   R   R   R   R   P   V   M
 3    ·   O   ·   F   H   ·   ·   ·   ·   ·   ·   H   F   ·   O   ·
 4    C   ·   C   F   H   ·   D   D   D   D   ·   H   F   C   ·   C
 5    C   ·   C   F   H   ·   D   D   D   D   ·   H   F   C   ·   C
 6    ·   T   ·   F   H   ·   ·   ·   ·   ·   ·   H   F   ·   T   ·
 7    P   V   M   R   R   R   R   R   R   R   R   R   R   P   V   M
 8    ·   O   ·   S   S   S   S   S   S   S   S   S   S   ·   O   ·

 V = voice        T = trigger in   P = pitch in   M = mod in   O = out
 D = pulse cell   R = weave cell   S = exciter    H = heartwood
 F = pitch field  C = climate      · = unregistered coordinate, dark and inert
```

The whole figure is 180-degree rotationally symmetric about the centre: every
cell has a counterpart at `(17-x, 9-y)`.

**The gaps are load-bearing.** A `·` is not a dim cell or a shift layer — the
coordinate is not registered at all, so `topology.at()` returns nil and the key
does nothing. Three of them do real work:

- the four diagonals of each voice cluster, so a cluster reads as a plus sign
  with the voice in the middle and one socket on each arm;
- the sealed box of dark cells around the D core, so the pulse-makers are
  reachable only by cable and read as a thing apart;
- the two dark cells directly above and below each voice column, so the left
  and right edges break into a voice cluster, two climate cells and a voice
  cluster rather than one continuous column.

**Cell counts.** 4 voices + 16 sockets + 8 D + 20 R + 20 S + 8 H + 8 F + 8 C
= 92 live cells; 36 dark.

### 2.1 Voices (4)

| # | Name  | Cell   | Root | Character |
|---|-------|--------|------|-----------|
| 1 | Oak   | (2,2)  | 55 Hz | low, heavy, long — the trunk. tune it down and it is the kick |
| 2 | Hazel | (15,2) | 220 Hz | dry, clacky, short, very inharmonic — the crack |
| 3 | Alder | (2,7)  | 98 Hz | hollow, odd-harmonic — a struck tube. the tom |
| 4 | Rowan | (15,7) | 330 Hz | bright, bell-adjacent, protective — the metal |

Four, not six, and one per corner. Six voices with six sockets each filled the
panel with sockets and left nowhere to put anything that *shapes* a rhythm;
four voices covering a kit, with the space that buys spent on the weave and the
climate, is the trade the re-cut makes.

A **voice cell is not a socket.** It is not a cable endpoint at all. Tapping it
opens that voice's sound page (§5.5); holding it shows the same page read-only.

### 2.2 Voice sockets (16)

Four per voice, laid out around the voice cell — trigger above, pitch left, mod
right, out below — with a compound name: `Oak·Trig`, `Rowan·Mod`.

| Role | Position | In | Out |
|------|----------|----|-----|
| **T** trigger | above | a pulse strikes the resonator (force = edge gain × weight) | — |
| **P** pitch | left | a field cabled here tunes the voice; a pulse re-rolls it | — |
| **M** mod | right | a stream bends the body or is injected into it, per its own balance knob; a pulse chokes | — |
| **O** out | below | — | the voice's audio tap, **and** a pulse every time the voice is struck |

The previous four (Knock, Sway, Sap, Moss) were three stream inputs that all
ended up on the same resonator plus one pulse input, and a set of *outputs* that
never got built because each needed an analyser tap. This set is the same idea
with the redundancy collapsed and the one output that matters actually present:

- Sap and Sway and Moss became one **M** socket with a balance knob. At 0 the
  stream is excitation into the resonator (Sap); at 1 it is a control signal on
  the body — damping, brightness, a little structure (Moss, and half of Sway);
  between, a mix. One bus per voice instead of three.
- **P** is a socket of its own because a pitch field is not a stream and never
  was: its output is a number of semitones, and giving it a named landing place
  is what makes "the field belongs on P" a rule rather than a convention. Its
  knob is a **depth** multiplier (0..2) on everything the fields do to that
  voice — the per-voice answer to "that is too much melody".
- **O** is the socket the instrument was missing. Continuously it is the
  voice's own audio on a bus, scaled by the socket's knob, so O→M is one voice
  ringing another and O→S is a voice colouring an exciter. Discretely it emits
  a pulse the instant the voice is struck — which costs nothing, because Lua is
  the thing doing the striking and already knows. That is why voice↔voice
  feedback landed without the §7.4 metering back-channel it was waiting on.

**Refractory.** A voice cannot be re-struck within 28 ms. It is a sound-design
detail (a drum head cannot be either) and it is the safety rail on every loop
the O socket makes possible: a voice cabled out of O and back into its own T is
a legal, interesting patch, and this is what stops it being a 500 Hz machine
gun. A bare O→T self-loop is in fact silent — the answering pulse arrives one
2 ms tick later, well inside the refractory — so a feedback path only speaks
once something in it takes time. That is deliberate.

### 2.3 Pulse cells — D (8)

Eight cells in a 4×2 block at the centre, sealed behind a ring of dark
coordinates. All eight share one core object: a **rambler**, a free-running
phase oscillator that emits a pulse on wrap. What differs is its *gait* — the
rule that shapes when the phase advances and how a pulse is weighted. Gaits are
per-cell defaults, swappable with `K1 + E2` while holding the cell.

| Cell   | Name     | Default gait | Counterpart |
|--------|----------|--------------|-------------|
| (7,4)  | Knocker  | metric — locks to norns clock, integer division | Hunt |
| (8,4)  | Hob      | euclidean — k pulses in n | Gabriel |
| (9,4)  | Grim     | figure — a bank of sixteen-step patterns, on the clock | Spriggan |
| (10,4) | Shuck    | slow and heavy — very low rate, high weight | Boggart |
| (7,5)  | Boggart  | burst — one wrap fires a ratchet of 2-7 | Shuck |
| (8,5)  | Spriggan | stochastic — Bernoulli gate at the wrap | Grim |
| (9,5)  | Gabriel  | drifter — fast, free, strongest coupling constant | Hob |
| (10,5) | Hunt     | accelerando — rate ramps across a cycle then resets | Knocker |

**Every gait here free-runs.** The three reactive ones (divider, echo,
coincidence) moved to the weave (§2.7), which is what they always were:
transforms of somebody else's pulse rather than gaits of their own. What
replaces them is **figure** — a bank of sixteen-step patterns (four, backbeat,
offbeat, tresillo, son, rumba, bossa, shiko) rooted to the clock. Euclidean
gives an even spread of k in n and nothing else; the crooked, asymmetric
figures are most of what a drum machine is actually made of, and they had
nowhere to live.

**Coupling.** When two D cells are cabled, they phase-pull each other
(Kuramoto):

```
dphi_i  =  rate_i * dt  +  K * sum_j ( g_ij * sin(2*pi*(phi_j - phi_i)) )
```

`g_ij` is the edge gain (bipolar). Positive gain pulls toward sync; negative
gain pushes toward anti-phase. `K` scales with the global **Weather** macro.
This is the whole rhythm engine — no step sequencer anywhere.

Metric, euclidean and figure are *rooted* to the norns clock by default; the
rest are *wild*. `K1 + tap` a D cell toggles rooted/wild.

**Organic rhythm.** The phase/coupling math above stays exact — it is
calibrated for Kuramoto stability, and for the gait-rate counts the test
suite checks; nudging it risks the whole rhythm engine. What's humanized
instead is every pulse's *audible result*: dispatch gives each triggered
strike/choke/grain a small parameter wobble (force, hardness, strike
position, choke depth/time, grain amp/dur each move a few percent per hit)
on top of the edge-gain/weight shaping already there, so no two hits sound
quite the same the way a real mallet never repeats itself either. Timing
itself is untouched — the wobble is on *what* a pulse sounds like, not
*when* it lands. Timing that is deliberately humanized lives in the weave
(Blur, Flam, Ghost, Swing) where it is a patchable choice.

### 2.4 Exciter cells — S (20)

Continuous stream sources — noise colours, textures, and slow modulators. They
are what the resonators eat. Each runs as a SynthDef on its own audio bus, and
is only instantiated when it has at least one cable (lazy allocation), which at
twenty of them is load-bearing rather than tidy.

Row 1 (`y=1`, x = 4..13) is the original ten: weather and undergrowth.

| Cell | Name | Source |
|------|------|--------|
| (4,1)  | Bracken  | dry rustle — bandpassed white + crackle |
| (5,1)  | Gorse    | prickly high band, resonant, spiky |
| (6,1)  | Ember    | crackle/pop — exponential impulse noise |
| (7,1)  | Windfall | grain bursts — short enveloped clusters |
| (8,1)  | Mistle   | pitched chirps — formant/bird-shaped |
| (9,1)  | Wisp     | slow wandering random walk (control-rate) |
| (10,1) | Hollow   | wind in a trunk — pink noise through a long comb |
| (11,1) | Drizzle  | sparse droplets — dust with a decaying tail |
| (12,1) | Loam     | dark brown noise, heavily lowpassed |
| (13,1) | Beck     | burbling filtered noise, self-moving cutoff |

Row 8 (`y=8`, x = 4..13) is the second ten, aimed squarely at a kit.

| Cell | Name | Source |
|------|------|--------|
| (4,8)  | Skein  | metal shimmer — four inharmonic partials rung by pink noise |
| (5,8)  | Flint  | one hard click — four milliseconds of highpassed noise |
| (6,8)  | Husk   | dry scrape — noise dragged through a wandering notch |
| (7,8)  | Tinder | fizz — fast dense sparks, close to a hiss |
| (8,8)  | Mire   | sub thud — resonant lowpassed brown noise, no top at all |
| (9,8)  | Glim   | ping — a struck sine with a noise edge |
| (10,8) | Rasp   | buzz — comb-filtered saw, a stick on a fence |
| (11,8) | Cicada | chirr — an amplitude-shivered high band |
| (12,8) | Hail   | impacts — a dense scatter of tiny hard hits |
| (13,8) | Reed   | breath — filtered air with a formant in it |

**Key behaviour:** an S cell is continuous *until a pulse is cabled into it*.
A cable from a D or R cell turns the exciter into an enveloped grain, fired by
that pulse. This is the central "man with red steam" move — pulses make sources
into gestures. S↔S cables cross-modulate each other's colour.

Gating is D and R cables only, deliberately. The heartwood can deliver a pulse
too, and so can a voice's O socket, but an S↔H cable's *usual* meaning is the
stream diffusing through the lattice and an O→S cable's is the voice colouring
the exciter — gating on either would silence an exciter the player cabled in
expecting to hear it.

### 2.5 Heartwood — H (8)

Not a bus. A **diffusion lattice**. Signals injected at one heartwood node
spread outward through the lattice with a per-hop delay and loss, emerging from
the other nodes at different times and amplitudes. Both pulses and streams
diffuse. Topology: a ring of 8 with two horizontal chord rungs.

```
(5,3) Taproot                                    (12,3) Barrow
   |                                                 |
(5,4) Mycel    ----------- chord -----------  (12,4) Warren
   |                                                 |
(5,5) Wyrd     ----------- chord -----------  (12,5) Holloway
   |                                                 |
(5,6) Ley      ------------ ring ------------ (12,6) Hearth
   |_________________________________________________|   (wrap, via the top)
```

The two seams flank the D core, so a pulse entering the lattice is visibly
walking around the pulse-makers, and the chords cross the panel horizontally.

Per-node **conductance** (E2 while holding) sets local hop delay and loss.
Low conductance = a signal dies within one hop. High conductance = energy
circulates the ring for a long time, producing self-sustaining rhythmic
patterns and long spectral smears. The heartwood is the closest thing the
instrument has to a memory.

### 2.6 The grove — F (8)

Four fixed-pitch resonators is one chord, however alive the rhythm on top of
it is. The grove is the answer: eight **pitch fields**, two vertical seams at
`x=4` and `x=13` just outside the heartwood seams, paired across the same 180°
symmetry as everything else. (These were the "P" cells before the re-cut; **P**
is a voice's pitch socket now, and the type letter moved to **F**.)

| Cell | Name | Default mode | Counterpart |
|--------|----------|--------------|-------------|
| (4,3)  | Cuckoo   | call — two notes back and forth, never quite the same twice | Raven |
| (4,4)  | Nightjar | drone — stays on the root; only the last few cents move | Plover |
| (4,5)  | Curlew   | cascade — a descending run, then a leap back to the top | Merlin |
| (4,6)  | Bittern  | octave — register jumps only; ignores the scale | Wren |
| (13,3) | Wren     | flutter — fast small steps around a wandering centre | Bittern |
| (13,4) | Merlin   | scatter — a new degree anywhere in the field, each step | Curlew |
| (13,5) | Plover   | wander — no degrees at all; glides continuously | Nightjar |
| (13,6) | Raven    | gravity — pulled toward the fields it is cabled to | Cuckoo |

A field is to pitch what a rambler is to rhythm, and the parallel is
deliberate: the **mode** is the F cell's gait (swappable with `K1 + E2`), and
a mode only decides the *shape* of the line. How far it travels is E2's
**Range**, logarithmic from a 25-cent shimmer to two octaves, so Range means
the same thing in every mode.

**Three clocks move a field**, and they are different on purpose:

1. **A strike.** Every voice a field tunes re-tunes immediately before it is
   struck. This is the important one: *one cable* turns an existing rhythm
   into a melody, with no sequencer and nothing else patched.
2. **A pulse.** A cable from anything that emits one steps the field on its own
   clock, so the line need not be locked to the rhythm playing it. A pulse
   landing on a voice's **P** socket does the same thing from the other end:
   every field tuning that voice steps, and the voice is retuned, without
   anything being struck.
3. **Time.** The continuous modes (wander, gravity) and the F↔F pull run on
   the 2 ms scheduler, decimated to every 8th tick, and freeze under Still
   with everything else.

**Snap.** By default a field quantises to a minor pentatonic — with mode banks
this inharmonic, anything denser stops reading as a scale and starts reading
as an out-of-tune one. `K1 + tap` an F cell sets it free to sit between the
notes. A field narrower than the smallest interval in the scale ignores snap
either way: at small Range this is a microtonal detuner, at large Range it is
a melody, and quantising the small end would just pin it to the root.

**F↔F** is the pitch counterpart of D↔D's Kuramoto term, on position rather
than phase: positive gain pulls two fields toward each other (converging on a
consonance), negative pushes them apart into contrary motion.

**An F cell never emits a pulse.** Its whole output is a number of semitones.
That is what makes an F cell unable to sit in any feedback path, and it is why
F contributes nothing to the continuous patch matrix — there is no stream to
route, only `voice_pitch`/`exciter_colour` calls out of `grove.lua`.

**A field only reaches a voice through its P socket.** Cabling one to T, M or O
is a legal patch that simply means nothing on that side; letting it retune the
voice anyway would make the four sockets interchangeable, which is the one
thing they must not be.

**Detune drift.** Separately from all of the above, every voice carries a
continuous few-cents wander generated in SC (`driftDepth`/`driftRate`, three
incommensurate slow shapes summed, per-voice phase offsets). It is on by
default at ~6 cents whether or not anything is cabled — it is why an untouched
patch no longer repeats one identical note — and cabling a wide field into a
voice deepens it, to a ceiling of 35 cents. Above that it stops sounding like
wood and starts sounding out of tune. There is a per-strike detune of the same
order in `grove.on_strike`, scaled by Weather: the pitch half of §2.3's
organic-rhythm wobble.

### 2.7 The weave — R (20)

A D cell decides *when* something happens. An R cell decides **what happens to
a pulse on its way somewhere**. This is the half of a drum machine that is not
the drums, and before the re-cut the panel had almost none of it: three
reactive gaits buried among ten pulse-makers.

Twenty cells, two rows of ten, one either side of the core, so nothing is more
than a couple of cables from a transform. Like a gait, each has one knob (E2)
meaning whatever the rule says it means, and `K1 + E2` swaps the rule. Unlike a
gait, an R cell has no phase — it is silent until something arrives.

| Cell | Name | Default rule | | Cell | Name | Default rule |
|------|------|------|---|------|------|------|
| (4,2)  | Trod    | divide — every Nth pulse passes | | (4,7)  | Holt    | blur — a human amount of lateness |
| (5,2)  | Ginnel  | mult — one in, a ratchet out | | (5,7)  | Coppice | latch — a gate that flips every N |
| (6,2)  | Snicket | delay — one copy, a musical interval late | | (6,7)  | Spinney | fill — every Nth arrival answers with a flurry |
| (7,2)  | Twitten | echo — a decaying tail of repeats | | (7,7)  | Thicket | rest — now and then it swallows a run |
| (8,2)  | Bostal  | chance — a coin at the gate | | (8,7)  | Bramble | flam — a grace note ahead of the beat |
| (9,2)  | Drove   | accent — a cycling weight contour | | (9,7)  | Tangle  | ghost — a quiet shadow behind it |
| (10,2) | Sneck   | sift — only pulses over a weight threshold | | (10,7) | Briar   | roll — an accelerating run out of one pulse |
| (11,2) | Lych    | meet — fires when two inputs land together | | (11,7) | Withy   | swell — weight climbs across hits, then resets |
| (12,2) | Stile   | hocket — each pulse down a different cable | | (12,7) | Osier   | mask — a euclidean stencil over what arrives |
| (13,2) | Weir    | swing — holds every other arrival back | | (13,7) | Sedge   | shift — a skip pattern that rotates each cycle |

Three of these deserve their reasons written down:

- **Hocket** is the one that turns four voices into a kit rather than four
  voices. One line in, N lines out, none of them playing the same beat.
- **Sift** placed after Accent or Swell pulls one line out of a busy patch:
  the loud hits go one way, everything goes the other.
- **Meet** is the only rule that needs two cables in. It is a genuine AND.

**Delay is musical; blur is not.** Snicket, Weir and Spinney measure themselves
in beats, so they stay in time when the tempo moves; Twitten, Holt, Bramble,
Tangle and Briar measure themselves in milliseconds, because smearing across
the grid is the whole point of them.

**What the weave emits is not re-quantised.** Weather (§4.1) places a *gait's*
emission on a grid line. A pulse coming out of an R cell is derived from one
that was already placed, and snapping a flam or a swung off-beat back onto the
grid would undo the only thing that cell does.

**A transform never sends its output back down its own input.** Cables are
undirected, so an R cell's fan-out includes the cable the pulse arrived on;
excluding it is the same rule the heartwood applies to its injection source,
and for the same reason — that is not coupling, it is doubling. A D cell passes
no such exclusion: a pulse-maker answering its neighbour *is* the coupling
(§2.3).

### 2.8 Climate — C (8)

Everything else on this panel works on the scale of a bar. These eight work on
the scale of a piece. They sit in the outer corners, where nothing else
reaches, and cable one to any cell and that cell's own knob is walked around
over tens of seconds to tens of minutes.

| Cell | Name | Shape | Counterpart |
|------|------|-------|-------------|
| (1,4)  | Moon  | tide — one long slow swell | Dusk |
| (1,5)  | Hoar  | creep — a bounded drunk walk | Bloom |
| (3,4)  | Thaw  | season — a straight ramp up and a straight ramp down | Ebb |
| (3,5)  | Gale  | gust — mostly still, then everything at once | Hush |
| (14,4) | Hush  | breath — a long draw in and a short push out | Gale |
| (14,5) | Ebb   | wane — falls away over a long time, then starts over | Thaw |
| (16,4) | Bloom | flourish — climbs slowly, drops all at once | Hoar |
| (16,5) | Dusk  | shiver — small and quick; a tremor rather than a tide | Moon |

E2 is the **period**, logarithmic from six seconds to ten minutes; `K1 + E2`
swaps the shape; the cable gain is how far it reaches and which way round.

**The knob is never overwritten.** A climate writes into a separate per-cell
offset which `state.get_character` adds on read, so the setting the player left
is still the setting they left, pulling the cable puts the cell back exactly
where it was, and turning E2 underneath a live climate moves the centre the
weather is riding on. Two climates on one cell sum into a single offset rather
than racing each other for the last write.

**A pulse landing on a climate does nothing to it,** and that is a decision
rather than an omission. An earlier version restarted the cycle, so a slow gait
cabled to one would begin its long shape on a downbeat. It does not survive
contact with the panel: cables are undirected, so the *ordinary* use — cable a
climate to a pulse-maker so the weather walks that cell's rate — also points
that pulse-maker's output back at the climate, and a gait running at a few Hz
then resets a six-second shape thirty times a second. The feature was worth one
bar of novelty; the trap was worth an unusable cell.

**A C cell cabled to another C cell** modulates *its* period, and needs no
special case at all: a climate reads its own period through the same accessor
as everything else.

---

## 3. Patching grammar

| Gesture | Result |
|---------|--------|
| Hold cell A, tap unconnected cell B | make cable A↔B at default gain (+0.6) |
| Hold cell A, tap connected cell B | remove cable A↔B |
| Hold A, hold B (both down) | screen focuses that edge; E3 sets its gain directly |
| Hold cell A + `K2` and `K3` together | sever every cable at A |
| Hold A, `K1` + tap B | make a **one-way** cable A→B (advanced; drawn differently) |
| Tap a **voice** cell (nothing else held) | open its sound page (§5.5); tap again to close |
| `K1` + tap a **D** cell | root it to the clock, or set it wild |
| `K1` + tap an **F** cell | snap its field to the scale, or set it free |

Cables are undirected and bipolar. Gain range `-1.0 .. +1.0` through zero.
Negative gain inverts: streams are phase-inverted, pulse coupling becomes
repulsion, damping modulation reverses. Attenuversion is the main expressive
control after the patch itself.

Constraints: no self-cables; no duplicate edges; a soft cap of 64 cables. A
**voice cell** is not a cable endpoint — only its four sockets are — so a tap on
one is unambiguously the sound-page gesture.

---

## 4. Norns controls

### 4.1 Nothing held on the grid

| Control | Function |
|---------|----------|
| E1 | **Canopy** — global space/reverb amount |
| E2 | **Weather** — the groove knob (see below) |
| E3 | **Tempo** — transport BPM, 1 per detent (writes `clock_tempo`) |
| K1 + E3 | Master level |
| K2 | **Still** — freeze all pulse gaits; resonators ring out. Tap again to resume |
| K3 | cycle screen view: Network → Meters — or close the sound page if it is open |
| K1 + K2 | **Regrow** — a seeded patch that already plays (hold to confirm) |
| K1 + K3 | **Clearing** — cut every cable (hold to confirm) |

**Weather (E2) is one sweep through three regimes.** It decides *when* a pulse
is allowed to land, not what it sounds like; `lib/quantise.lua` owns the whole
mapping and `lib/rambler.lua` routes every emission through it.

| Weather | What the patch does |
|---------|---------------------|
| 0 | **Locked.** Every emission snaps forward onto a grid line, whatever rate the cell free-runs at, so unrelated gaits cohere into one groove |
| 0 → 0.5 | **Swing.** The grid itself is warped: each pair of 8ths is stretched then squeezed, so off-beats land late and beats never move. Full swing is a 3:1 long-short; the triplet 2:1 feel sits two thirds up |
| 0.5 → 1 | **Chaos.** The snap loosens toward the time the cell actually wanted, and a widening random displacement grows in its place. Rate drift comes back here too |
| 1 | **Rain.** Nothing is held at all — the free-running behaviour the gaits had before any of this |

The grid is per cell, not global: each is quantised to the coarsest of
8th / 16th / 32nd / 64th that still fits inside one cycle of its own rate, so a
Shuck lands on 8ths and a Gabriel on 64ths and both stay in time with each
other. A **burst** overrides that and is triggered on the beat, with its ratchet
laid out on a subdivision so the whole flam sits on grid lines.

Snapping is *forward* to the next line, never back to the nearest — a wrap is
only known about once it has happened. The cost is up to one grid interval of
latency, and since the grid is never coarser than the cell's own cycle, it never
costs the cell a pulse.

Weather places a **gait's** emission. What the weave (§2.7) and a voice's O
socket (§2.2) emit is deliberately not re-quantised: those pulses are derived
from one that was already placed, and holding them to the grid a second time
would undo the transform. Timing you want humanized is a patchable choice on
the weave, not a global setting.

**Regrow** seeds cell settings as well as cables. It has to: half the weave
blocks a pulse at its default knob (Sift's threshold sits above most weights,
Meet wants two sources it has not got), so a Regrow that only drew cables drew
silent ones about half the time. It picks a gait and a knob for each
pulse-maker it uses, a rule and a knob for each transform, a modest Range for a
field and a middling period for a climate — then lets the dice decide the rest.
Every Regrow plays.

### 4.2 Holding a grid cell

| Control | Function |
|---------|----------|
| E1 | select which cable at this cell is focused (ALL → 1..n) |
| E2 | the cell's **character** parameter (see below) |
| E3 | attenuvert — focused cable's gain, or that sound's **decay** when ALL is selected |
| K1 + E2 | swap the rule this cell runs on (D: gait, R: rule, F: mode, C: shape) |
| K2 + K3 | sever all cables at this cell |

**E2 per cell type — the one thing that matters about that cell:**

| Cell type | E2 = | Range |
|-----------|------|-------|
| Voice | — the voice has eight parameters, not one; see the sound page (§5.5) | — |
| T socket | strike hardness (mallet) | 0..1 |
| P socket | **depth** — how far the cabled fields move this voice | 0..2 |
| M socket | **balance** — inject into the resonator ↔ bend the body | 0..1 |
| O socket | **tap** — level of the audio this socket puts on the bus | 0..1 |
| D cell | rate / clock relation | gait-dependent |
| R cell | the transform's own amount | rule-dependent |
| S cell | **Colour** — the source's filter/character | 0..1 |
| H cell | **Conductance** — hop delay and loss | 0..1 |
| F cell | **Range** — how far the field roams (25 cents .. 2 octaves) | 0..1 |
| C cell | **Period** — how long one turn of the weather takes (6 s .. 10 min) | 0..1 |

E2 moves the player's **base** value. A cabled climate cell (§2.8) adds an
offset on top of it that E2 never touches, and the cell view draws both: the
bar is the setting, and a single bright pixel is where the weather currently
has it.

**E3 with no cable focused — decay.** 0.5 is whatever that sound's own default
is; the knob is symmetrical around it.

| Cell type | E3 = | Range |
|-----------|------|-------|
| Voice | resonator ring time, in seconds | ×0.25 .. ×4 of the voice's default |
| Voice socket | its voice's ring time — a socket is part of the voice, not a sound of its own | as above |
| S cell | a ratio on the exciter's grain envelope and on whatever tail its recipe has | ×0.35 .. ×2.8 |
| D / R / H / F / C | nothing — these have no sound of their own, and their row already carries their gait / rule / conductance / field / weather readout | — |

Decay is one number wherever it is reached from: the gesture above and the
Decay row on the sound page (§5.5) move the same store.

---

## 5. Displays

### 5.1 Grid brightness (0-15)

| Cell | Idle | Live |
|------|------|------|
| Voice | 5 | 12 while its sound page is open — the one open page is worth seeing from across the room. Its amplitude envelope still needs the metering back-channel (§7.4) |
| Voice socket | 2 unpatched, 6 patched | flash on a Lua-known pulse arriving (a strike, a choke, a pitch re-roll, the O socket answering), decay ~120 ms, weighted by force/depth |
| D | 3 | flash 15 on pulse, decay ~120 ms; base rises with coupling strength |
| R | 2 | base rises with how much is cabled through it; flashes on the way *out*, not the way in — what you want to see is what it decided. A dimmer second flash on arrival, so a cell swallowing everything still shows something reaching it |
| S | 3 unpatched, 5 patched | flash on a grain firing, decay ~120 ms, weighted by amp; continuous stream-amplitude shimmer still needs the metering back-channel (§7.4) |
| H | 2 | local lattice energy — signals are visibly seen spreading |
| F | 2 | where the field currently sits, so a rising line climbs the cell; flash on each step |
| C | 1 | *is* its value — no flash, because nothing here happens at an instant. The outer corners read as four pairs of very slow meters, which is exactly what they are |
| unregistered | 0 | — |

**Patch reveal** — while a cell is held: held cell solid 15; every cell cabled to
it blinks at 13 in sync; every other cell that is a valid patch target is
floored to a minimum readable brightness so it doesn't vanish; voice cells
(never cable endpoints themselves) scale ×0.4 toward black. This is how you
read a patch — and see what's still available to patch into — on the grid.

### 5.2 Screen — Network view (nothing held)

The full 16x8 map drawn at 7px pitch (112x56, centred), with cables drawn
between cell centres as **dim dotted runs**. At full brightness and solid, a
patch of twenty cables is a ball of wool: the lines are the least important
thing on this screen and they were shouting over the cells, the travelling
pulse dots and each other. Brightness still tracks |gain|, but over a much
shorter range; an inverting cable is drawn with the dots twice as far apart, so
it reads as a thinner connection rather than as a different kind of drawing;
and a one-way cable gets one brighter dot three quarters of the way along
rather than an arrowhead made of five pixels. The endpoints are left alone —
the cell's own dot should be the brightest thing at that coordinate.

Pulses render as a bright dot travelling the line. Now that the cables are dim,
those dots are what the view is *for*. Bottom line: the most recent event, with
the tempo and the Weather tag in the corner.

**Everything on this view is bucketed by brightness and painted once per
level.** Drawn a dot at a time — level, shape, fill, level, shape, fill — the
map plus its cables is around six hundred screen commands a frame, a couple of
hundred of them cairo *paint* calls. At 15 fps that fills matron's screen queue
faster than it drains, and a full queue blocks the Lua thread: the screen stops
updating and the front panel stops responding, while the grid — its own
callback, its own metro — carries on, so the script looks alive and the norns
looks broken. Bucketed, the same picture costs about sixteen paint calls. The
number of cable dots is budgeted too (they are shared out across however many
cables exist, evenly spaced within each), so the frame cost is bounded by the
patch cap rather than by the patch. `test/soak.lua` asserts both numbers.

```
    ▪ ▪▪▪▪▪▪▪▪▪▪ ▪
  ▪[O]▪ ··········  ▪[H]▪
    ▪  ▪ ▪ · · · · ▪ ▪  ▪
  ·  · ▪ ▪ ░░░░ ▪ ▪ ·  ·
  ·  · ▪ ▪ ░░░░ ▪ ▪ ·  ·
    ▪  ▪ ▪ · · · · ▪ ▪  ▪
  ▪[A]▪ ▪▪▪▪▪▪▪▪▪▪  ▪[R]▪
    ▪ ▪▪▪▪▪▪▪▪▪▪ ▪
 Knocker -> Trod        120 lock
```

### 5.3 Screen — Cell view (a cell held)

```
 KNOCKER                            D
 ─────────────────────────────────────
 metric     ▐▓▓▓▓▓▓▓░░░░░    1 x beat
 rooted · 1/8              coupling 0.42
 ─────────────────────────────────────
 3 cables   ▸ Trod              +0.80
             Oak·Trig           -0.40
 ─────────────────────────────────────
 K2+K3 sever   K1+E2 gait
```

The second row is whatever that cell type has to say about itself: a D cell's
rooted/wild and the grid Weather is holding it to; an R cell's cables in and
out and whether its gate is open; an H cell's hop, links and loss; an F cell's
current degree in semitones; a C cell's reach and current value; and for
anything with a sound of its own, the decay row.

Two cells held → an edge view: both names, one bipolar gain bar, and a short
description of what actually flows across that edge given the two types.

### 5.4 Screen — Meters view

Per-cell activity, once the metering back-channel (§7.4) exists. Until then it
draws idle brightness as small bars and says so.

### 5.5 Screen — the voice sound page

Tapping a voice cell replaces the screen with that voice's eight parameters;
tapping it again puts the screen back where it was. `E1` picks one, `E2` moves
it coarsely and `E3` finely — eight knobs on two encoders would otherwise mean
either a slow encoder or an imprecise one, and a resonator's decay wants to be
swept across two octaves to find the sound and then moved a hair to make it
sit. `K3` also closes the page, so you never have to remember which cell you
tapped. *Holding* a voice cell shows the same page for as long as you hold it,
without taking the encoders off the patch.

```
 OAK                             sound
 ─────────────────────────────────────
 Tune     +0.0 st    Bright      0.50
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓▓▓▓░░░░░░
 Decay     1.20 s    Drive       0.25
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓░░░░░░░░░
 Body        0.55    Strike      0.16
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓▓░░░░░░░░
 Damp        1.10    Level       0.98
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓▓▓▓▓▓░░░░
 E1 pick  E2/E3 coarse/fine
```

| Row | What it is | Range |
|-----|-----------|-------|
| Tune | transposition off the voice's own root | ±24 semitones |
| Decay | resonator ring time | ×0.25 .. ×4 of the voice's default |
| Body | structure: harmonic ↔ free-free bar | ±0.4 around the voice's own |
| Damp | frequency-dependent damping exponent | ±0.5 around the voice's own |
| Bright | the post-resonator lowpass | 0..1 |
| Drive | saturation into the tanh | 0..1 |
| Strike | mallet position, comb-notching modes with a node there | 0.02 .. 0.5 |
| Level | the voice's own amplitude | 0 .. 1.4 |

Body and Damp sweep *around* each voice's baked-in baseline rather than
replacing it, so a voice keeps its own character at any setting.

**The Grain macro is gone.** It morphed structure, damping, brightness and
drive together behind one knob because there was nowhere to put four knobs.
This page is that somewhere, and a drum you can only shape through a macro is a
drum you cannot tune.

---

## 6. Type interaction matrix

What a cable *means* is derived from the pair of endpoint types. This table is
the authority; implement it as a dispatch table, not as branching.

The socket column is split, because the whole point of the re-cut is that the
four sockets are *not* interchangeable.

**Pulses in** (what happens when a pulse-carrying cell speaks down a cable):

| Target | Meaning |
|--------|---------|
| **T** socket | strike the resonator; force = edge gain × pulse weight, subject to the 28 ms refractory |
| **P** socket | re-roll the pitch: every field tuning that voice steps, and the voice is retuned, without being struck |
| **M** socket | choke: a momentary duck, depth from gain × weight, length from the socket's own knob |
| **O** socket | nothing — it is a source |
| **D** cell | mutual phase coupling (Kuramoto) plus a small trigger nudge |
| **R** cell | the transform's input |
| **S** cell | fire one grain (and a D or R cable is what puts the cell into grain mode at all) |
| **F** cell | step the field to a new degree |
| **H** cell | enter the lattice and diffuse |
| **C** cell | nothing, deliberately — see §2.8 |

**Streams** (live SC synths for as long as the cable exists):

|            | M socket | S (exciter) | H (heartwood) |
|------------|----------|-------------|---------------|
| **O socket** | one voice ringing another | the voice's amplitude colours the exciter | the voice pours into the wood |
| **S** | the stream drives the body or excites it, per M's balance | cross-modulation: each modulates the other's colour | the stream diffuses through the lattice, and what the lattice makes of it comes back as colour |
| **H** | the lattice returns into the voice | — | direct link — short-circuits two lattice points, adds a shortcut path |

**Neither** — the two families that carry a number rather than a pulse or a
stream:

| Pair | Meaning |
|------|---------|
| **F → P socket** | the field tunes that voice; P's knob is the depth, and negative gain inverts the contour |
| **F → S** | the exciter's Colour rides the field's line |
| **F ↔ F** | the two fields pull together (apart, at negative gain) |
| **C → anything with a knob** | the weather walks that cell's own knob, bipolar around whatever the player set |
| **C ↔ C** | one weather sets how fast the other turns |

Notes on the awkward pairs:

- **Voice↔Voice** is now two cables' worth of meaning on one socket. `O→M` is
  one resonator exciting another — a feedback path by definition, and every
  voice bus gets a DC blocker, soft saturation and a limiter so a loop howls
  musically instead of clipping. `O→T` (or `O→R→T`) is one drum triggering
  another, bounded by the refractory instead. Do not prevent either loop.
- **Two O sockets cabled together** is a patch with no meaning; nothing gives
  it one.
- **D↔D at negative gain** produces anti-phase locking — the most reliable way
  to get a stable interlocking two-part rhythm.
- **R↔R** is transforms in series, and the chain *is* the pattern. It is
  bounded by the same one-tick deferral D↔D is, plus a weight floor every
  decaying rule terminates on.
- **F is a source only.** A field never emits a pulse and never writes a
  stream, so its whole column is one-way and nothing in it can feed back.
- **C is a source only**, for the reason in §2.8, which makes the same true of
  the climate.

---

## 7. Software architecture

### 7.1 File layout

```
Woodland/
  Woodland.lua              -- entry: init, grid/key/enc handlers, Regrow
  lib/
    topology.lua            -- the map: cell records, coords, types, adjacency
    lexicon.lua             -- names, descriptions, each cell type's one knob
    patch.lua               -- graph: add/remove/trim edges, serialisation
    dispatch.lua            -- the §6 type-interaction matrix
    rambler.lua             -- D-cell gaits, the phase-coupling scheduler, and
                               the shared pulse bus everything emits through
    weave.lua               -- the twenty R-cell pulse transforms
    climate.lua             -- the eight C-cell slow modulators
    quantise.lua            -- the Weather groove: quantise -> swing -> chaos
    exciter.lua             -- S-cell control layer (audio side lives in SC)
    heartwood.lua           -- diffusion lattice
    grove.lua               -- pitch fields: modes, coupling, voice retuning
    voice.lua               -- voice sockets + the eight-parameter sound page
    gridui.lua              -- grid render + hold/tap state machine
    screenui.lua            -- network / meters / cell / edge / voice views
    bridge.lua              -- engine command wrapper, throttling, meter cache
  lib/Engine_Woodland.sc    -- SC: modal voices, exciters, patch matrix, canopy
  README.md
```

**One door for every pulse.** Three different things emit one — a D cell
wrapping, an R cell passing something on, a voice answering out of its O socket
— and all three go out through `rambler.emit_from`, so trails, the fan-out cap
and the one-tick deferral that makes cycles safe are written exactly once.
Pulse-cell-to-pulse-cell traffic (D or R at the far end) is always deferred a
tick, which makes runaway impossible by construction rather than by a depth
counter; 2 ms per hop is inaudible.

**Module loading.** norns' `include()` is `dofile`-based and returns a new table
each call, so every module here is loaded through a memo (`wl()`) defined in
`Woodland.lua`. `topology`, `patch` and `state` are shared mutable singletons
and plain `include()`s would give three separate patch graphs.

### 7.2 Lua / SC split

**Lua owns:** the patch graph, all pulse generation, coupling and transformation,
the heartwood lattice's discrete-event side, the grove's pitch fields, the
climate, all UI. **SC owns:** every sample of audio, the audio-rate patch
matrix, and continuous modulation — including the per-voice detune drift
(§2.6), which is a few cents moving continuously and so far too fine-grained to
push over OSC without either flooding it or stepping audibly.

Pulses are generated in Lua because they must be visualised, coupled, and
rewired live — all of which are painful in SC. The cost is timing jitter; see
§8.

**Scheduler.** One metro at a 2 ms tick advances all rambler phases and applies
coupling, then drives the lattice, the fields, the weather and the weave's own
scheduled taps. (A metro rather than `clock.run`: `clock.sleep` is
tempo-relative in norns, and D-cell rates are genuine Hz. Rooted gaits get their
tempo relation back by reading `clock.get_beats()` directly, which locks them to
the transport exactly rather than approximately.)

### 7.3 SC bus topology

```
groups:  gSrc -> gPatch -> gVoice -> gTap -> gFx

voiceBus        4  voice outputs (summed by the Canopy reverb)

patchBus       20  exciter outputs        (excBase        0)
               20  per-S colour-mod sums  (colourModBase 20)
                4  per-voice M socket in  (modInBase     40)
                4  per-voice O socket tap (voiceOutBase  44)
                8  heartwood injection    (heartInBase   48)
                8  heartwood emergence    (heartOutBase  56)
               --
               64  total
```

These are **audio** buses throughout, including the modulation ones. The spec
originally called them control buses; `Out.kr` *overwrites* a bus each block
while `Out.ar` *adds*, and several cables landing on one voice's M socket have
to sum rather than fight. Keep the six offsets identical to `bridge.BUS` on the
Lua side.

Patch synths, instantiated per cable, live in `gPatch`:

- `\wl_patch_aa` — `Out.ar(dst, InFeedback.ar(src) * gain)`
- `\wl_patch_ak` — `Out.ar(dst, LPF(Amplitude(InFeedback.ar(src)),20) * gain)`

`InFeedback`, not `In`. `gPatch` runs before `gVoice`, so a cable whose source
is a voice's own output tap — which is now the most interesting cable on the
panel — would read silence with plain `In.ar`. One block of latency on every
cable (about 1.5 ms at norns' block size) buys a matrix that is
order-independent by construction, rather than a node-ordering rule nobody can
see from the Lua side. Removing a cable frees its synth. ~64 patch synths worst
case.

### 7.4 Metering back-channel

Still unbuilt, and the shape has changed since it was specified. One `\watcher`
synth in `gFx` reading a bank of meter buses and sending an OSC message at
30 Hz:

```supercollider
SendReply.kr(Impulse.kr(30), '/wl_meters', In.kr(meterBus, n));
```

forwarded to `NetAddr("127.0.0.1", 10111)` — norns' OSC in port — and picked up
by `osc.event(path, args)`. Lua caches the array and *decays it locally* between
messages so the grid stays smooth if a packet is dropped. (Verify the port and
the SendReply→NetAddr forwarding pattern against the norns version in use;
`addPoll` is scalar-only and will not carry an n-element array.)

What it is still needed for is narrower than it was: voice amplitude envelopes,
the continuous shimmer of an S cell under no gate, and a socket's response to a
steady stream. The one thing it was originally *blocking* — voice↔voice
feedback — no longer needs it at all, because the O socket's pulse half is
generated in Lua, which already knows when it struck the voice.

### 7.5 Persistence

The patch graph is saved alongside the PSET:

```lua
params.action_write = function(filename, name, number)
  write_graph(norns.state.data .. number .. ".woodland")
end
params.action_read = function(filename, silent, number)
  read_graph(norns.state.data .. number .. ".woodland")
end
```

Graph format: a flat list of `{a_id, b_id, gain, oneway}` plus per-cell
character values, per-cell rule choices (gait / rule / mode / shape, and the
rooted and snap flags), and the eight sound-page parameters per voice. Cell ids
are stable strings (`"oak.trig"`, `"d.knocker"`, `"r.sedge"`, `"h.warren"`,
`"f.cuckoo"`, `"c.moon"`) — never coordinates — which is what let the whole
panel be re-cut at phase 6 without the format changing. The climate's own
offsets are *not* saved: they are where the weather happened to be, not
something the player set.

---

## 8. Sound engine — making it woody

Modal synthesis (`DynKlank`-style, hand-built), excited by short filtered
noise bursts through a plain, tuneable, pinged bank of resonant filters — no
body-cavity diffuser any more (see the FM/noise addendum below for why). Eight
recipe parameters per voice, each on its own row of the sound page (§5.5); the
Grain macro that used to morph four of them together is gone with the page that
replaced it.

**The five things that actually make it sound like wood:**

1. **Inharmonic mode ratios.** Morph the ratio set with `structure`:
   harmonic `(1, 2, 3, 4, 5, 6)` → free-free bar `(1, 2.756, 5.404, 8.933,
   13.34, 18.64)` → stretched. Wood sits between harmonic and bar.
2. **Frequency-dependent damping.** `decay_n = decay * ratio_n ^ -damp_exp`,
   with `damp_exp ≈ 0.7..1.2`. High modes *must* die fast. This is the single
   biggest woodiness factor after the exciter.
3. **A noise-burst exciter, never a raw impulse.** 2-8 ms of *pink* noise
   through a bandpass whose centre = mallet hardness, further offset by an
   independently tuneable octave (`voice_noise_tune`) and resonance
   (`voice_noise_q`). Hard mallet = brighter, shorter; pink rather than white
   keeps the burst warmer, less hiss-forward.
4. **Strike position.** Multiply mode `n`'s amplitude by `sin(pi * position * n)`
   — comb-notching that removes modes with a node at the strike point. Cheap,
   and it is what makes a struck object sound *struck somewhere*.
5. **Gentle nonlinearity.** `tanh` on the resonator sum (dialled back — see
   below), plus a small amplitude-dependent pitch drop (`freq * (1 - amp *
   0.02)`) — the "thunk" of real wood under a hard hit.

One shared plate/hall — **Canopy** — across the whole instrument. There is
deliberately no per-voice body-cavity diffuser: the original design cascaded
two `AllpassC` stages (~20 ms / ~31 ms) after the mode bank, and in practice
that read as a slapback/flutter echo through a resonant filter bank, not as
diffusion — the "odd reverb-like/slappy" artifact. It's gone; the tanh stage
is still there (a much gentler `x0.8` drive instead of the original `x3`) but
purely as the DC-blocked, soft-saturating, limited safety net §6 wants once
voice↔voice feedback lands, not as a tone-shaping effect in its own right.

**FM and tuneable-noise addendum.** Every voice, and every S-cell exciter, now
also takes an `fmRatio`/`fmDepth` pair: an internal sine modulator (ratio =
multiple of that voice/exciter's own natural frequency) FM's the voice's mode
bank or the exciter's own frequency-determining parameter (a BPF/RLPF/LPF
centre, a Dust rate, a comb delay time, or — Mistle — a genuine SinOsc
carrier). `fmDepth=0` is a no-op, so nothing about the existing sound changes
until it's turned up. This is engine-level only for now — reachable via
`voice_fm`/`exciter_fm` (and PARAMS, once PARAMS exist), not yet a patchable
grid cable; making FM a first-class §6 cable type is future work, not
included here.

**Per-voice defaults.** These are the numbers the sound page's Tune, Decay,
Body and Damp knobs sweep *around*, so they have to be identical on both sides
of the bridge (`topology.lua`'s VOICES table and the engine's `voiceDefs`).

| Voice | Fundamental | Structure | Damp exp | Decay | Notes |
|-------|-------------|-----------|----------|-------|-------|
| Oak   | 55 Hz  | 0.55 bar  | 1.1 | 1.2 s  | heavy, dark — the kick end |
| Hazel | 220 Hz | 0.95 bar  | 1.3 | 0.28 s | dry clack |
| Alder | 98 Hz  | odd-only  | 0.8 | 1.6 s  | hollow tube — the tom |
| Rowan | 330 Hz | 0.75 bar  | 0.6 | 1.8 s  | bright, bell-adjacent |

Four voices with ±2 octaves of Tune each covers more ground than six fixed
ones did, and the two that were cut (Ash's hollow tube and Yew's drone) are
reachable from what is left: Alder took the odd-only ratio set, and Oak at the
bottom of Tune with Decay at the top is the churchyard.

**Engine commands:**

```
strike(voice, force, hardness, position)
voice_pitch(voice, hz)          voice_glide(voice, seconds)
voice_drift(voice, depth, rate, seed)
voice_decay(voice, seconds)     voice_structure(voice, v)
voice_damp(voice, v)            voice_bright(voice, v)
voice_pos(voice, v)             voice_drive(voice, v)
voice_amp(voice, v)             voice_modes(voice, n)
voice_choke(voice, depth, time)
voice_mod(voice, balance)       voice_tap(voice, level)
voice_fm(voice, ratio, depth)
voice_noise_tune(voice, v)      voice_noise_q(voice, v)
exciter_on(i)                   exciter_off(i)
exciter_colour(i, v)            exciter_decay(i, scale)
exciter_gated(i, flag)          exciter_gate(i, dur, amp)
exciter_fm(i, ratio, depth)
patch_add(id, kind, src, dst, gain)
patch_gain(id, gain)            patch_free(id)
heart_conductance(i, v)
canopy(size, damp, mix)         master_level(v)
```

`voice_grain` is gone; `voice_sap`/`voice_sway`/`voice_moss` collapsed into
`voice_mod`; `voice_structure` and `voice_tap` are new.

**CPU budget.** 4 voices x 6 modes = 24 resonators, plus up to 20 exciters
(lazily allocated, so in practice a handful), ~64 patch synths, the eight-node
heartwood delay network, and one reverb. Fewer voices than before pays for the
larger exciter bank. Mitigations: the mode-count knob (`voice_modes`), lazy
exciter allocation, and the fact that an unpatched cell costs nothing at all.

**Lua-side budget.** The 2 ms tick, measured offline: idle 0.4% of one core,
a modest patch 0.4%, the full heartwood 0.6%, all eight fields cabled 0.7%, the
D core fully ringed 0.5%, all eight climates at full rate 0.5%, and a
deliberately pathological chain of ten multiplying weave rules 1.3%. A dev
machine is not a CM3, so re-check there if the UI ever stutters.

---

## 9. Build order

Each phase ends in something testable on the device.

1. **The light show.** topology + lexicon + grid render + hold/tap patching +
   network and cell screens. No audio at all. The instrument is fully playable
   as a light show and every UI decision is verifiable before any DSP exists.
2. **First sound.** SC engine with the modal voices and `strike`. One D cell
   (Knocker) driving them from Lua. Prove the woodiness recipe here — it is the
   hardest thing to get right and everything else depends on it.
3. **Rhythm.** The gaits + D↔D phase coupling + the 2 ms scheduler.
4. **Exciters.** S cells, the audio-rate patch matrix, D→S gating.
5. **Heartwood.** The diffusion lattice, both discrete and continuous paths.
5b. **Grove.** The pitch fields, their modes and coupling, `glide` and the
   per-voice detune drift in SC. Out of build order deliberately: fixed-pitch
   voices made every patch one chord, and that was audible long before feedback
   or metering were.
5c. **Weather as a groove knob.** `quantise.lua` between every gait and its
   output, E3 as the transport, and the whole quantise → swing → chaos sweep.
6. **The re-cut.** The panel rebuilt around what the instrument turned out to
   be: four voices with named T/P/M/O sockets, the O socket closing voice↔voice
   feedback (both the audio path and the pulse path, so this phase absorbed the
   old phase 6), the weave, the climate, twenty exciters, the `figure` gait, the
   per-voice sound page, and the lexicon pages dropped. See the §2 header.
7. **Life.** Metering back-channel → grid and screen animation. Narrower than
   it was: see §7.4.
8. **Persistence and polish.** PARAMS, PSET + graph save/load, clock sync,
   README.

---

## 10. Risks and open decisions

**Risks**

| Risk | Mitigation |
|------|------------|
| Lua pulse jitter (~1-2 ms) | fractional-overshoot latency offset to SC; keep the audible strike scheduled in SC, not the Lua tick |
| CPU ceiling on CM3 | the mode-count knob, lazy exciters, and the fact that an unpatched cell costs nothing |
| Feedback instability on voice↔voice audio | per-voice DC block + tanh + limiter; conservative default gain on O→M edges |
| Runaway on voice↔voice *pulses* | the 28 ms per-voice refractory (§2.2), the per-tick emit cap, and the one-tick deferral on every pulse-cell hop |
| A weave chain that multiplies faster than it decays | a weight floor every decaying rule terminates on, a capped pending queue, and the refractory at the end of it |
| OSC metering flooding | 30 Hz cap, local decay in Lua, drop-tolerant |
| Patch becomes unreadable at 30+ cables | patch reveal on hold is the primary reader; the network view's cables are dim and dotted so the cells and the travelling pulses stay legible over them |
| 92 cells is a lot of panel to learn | the dark coordinates are doing this job: four corner clusters, a sealed core and four banks read as six things, not ninety-two |

**Decisions for you**

1. **Grid 64.** The layout needs 16x8, and the re-cut needs it more than the
   original did. 128 only.
2. **Arc.** An arc would be a natural fit for the four attenuverters of a
   focused cell, or for the eight rows of the sound page. Out of scope for v1?
3. **Regrow** — seeded patching. It now seeds cell settings as well as cables
   (§4.1), which makes it closer to a "surprise me" button than to a randomiser.
   Cut it if you would rather the patch always be hand-made.
4. **One-way cables** (K1 + tap) slightly break the androgynous premise. Kept as
   an advanced escape hatch, and they earn their keep now that the O socket
   makes real feedback loops easy to draw by accident.
5. **The two voices that were cut.** Ash and Yew are reachable from the four
   that are left (§8), but they are not *there*. If four corners is one too few,
   the shape that would take six is two more clusters on the middle columns —
   at the cost of the weave rows, which is the trade the re-cut says no to.
