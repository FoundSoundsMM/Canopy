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
 3    ·   O   ·   F   H   ·   ·  TM  TM   ·   ·   H   F   ·   O   ·
 4    C   ·   C   F   H   ·   D   D   D   D   ·   H   F   C   ·   C
 5    C   ·   C   F   H   ·   D   D   D   D   ·   H   F   C   ·   C
 6    ·   T   ·   F   H   ·   ·  TM  TM   ·   ·   H   F   ·   T   ·
 7    P   V   M   R   R   G   G   G   G   G   G   R   R   P   V   M
 8    ·   O   ·   S   S   S   S   S   S   S   S   S   S   ·   O   ·

 V = voice        T = trigger in   P = pitch in   M = mod in   O = out
 D = pulse cell   R = weave cell   G = percussion  S = exciter
 H = heartwood    F = pitch field  C = climate     TM = Turing Machine
 · = unregistered coordinate, dark and inert
```

The panel was close to 180-degree rotationally symmetric about the centre
before the re-cut's re-cut (§2.7/§2.7b); the six G cells in the middle of the
bottom weave row broke that, on purpose — nothing reads the `counterpart`
field programmatically, it was always documentation rather than a constraint,
and a symmetric panel was never the point, a legible one was.

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

**Cell counts.** 4 voices + 16 sockets + 8 D + 4 TM + 14 R + 6 G + 20 S + 8 H
+ 8 F + 8 C = 96 live cells; 32 dark.

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
gain pushes toward anti-phase. `K` scales with the global **Scatter** macro.
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

### 2.3b Turing Machine cells — TM (4)

Four independent 8-bit shift-register sequencers, akin to the Music Thing
Modular Turing Machine with its Pulses and Voltages expanders each collapsed
onto one cell. They sit inside the sealed D-core box, on the four coordinates
the original map left dark: directly above Hob and Grim, directly below
Spriggan and Gabriel.

| Cell   | Name       | Counterpart |
|--------|------------|-------------|
| (8,3)  | Padfoot    | Tatterfoal  |
| (9,3)  | Barghest   | Puck        |
| (8,6)  | Puck       | Barghest    |
| (9,6)  | Tatterfoal | Padfoot     |

**Unlike a D cell, a TM cell has no phase and no gait of its own.** It never
runs on its own clock — the only thing that ever moves its register is a
pulse cabled into it. That is the point: it is meant to be clocked, the way
the hardware it is named after always is, and it is why the four of them sit
inside the same box the free-running gaits do without being gaits themselves.
A TM cell is a pulse cell in the same sense an R cell is (§7.2's "one door
for every pulse", and the one-tick deferral on pulse-cell-to-pulse-cell
traffic that makes a cycle through it safe by construction).

**Each incoming pulse is one clock edge**, and does three things:

1. **Shifts the register.** The bit about to fall off the far end is either
   kept — with its own small chance of flipping anyway (**Drift**, the "the
   knob past noon still surprises you" character the real module is known
   for) — or thrown away for a fresh, **Bias**-skewed coin flip. **Prob**
   decides which: 0 is fully random every step, 1 never lets go of the loop
   it started with.
2. **Updates its pitch.** Some number of the register's bits (**Bits**) are
   summed, binary-weighted, into an offset the same shape as a grove.lua
   field's degree (§2.6) — scaled by **Range** and snapped to the same minor
   pentatonic — and pushed to any voice cabled to this cell's P socket, summed
   in on top of whatever fields are also cabled there rather than blended into
   their own average: a shift register and a wandering field are different
   enough instruments to want kept separate, and the P socket's own depth
   knob scales both alike.
3. **Answers, maybe.** If the register's **Tap** bit (one of the eight,
   picked by the knob — the Pulses expander's eight gate outputs collapsed
   onto the one you choose) reads high, the cell answers with a pulse of its
   own, weighted by **Level**, exactly the way a G cell or an R cell answers
   (§2.7b, §2.7) — excluding the cable the triggering pulse arrived on, the
   same rule every transform on the panel follows.

**Eight parameters, one sound page** (same shape as a voice's or a G cell's,
§5.5/§2.7b — tap the cell to open it, hold it to peek):

| Row | What it is | Range |
|-----|-----------|-------|
| Length | steps in the register's loop | 2 .. 16 |
| Prob | chance a step keeps the loop rather than drawing fresh | 0 (random) .. 1 (locked) |
| Drift | chance a kept bit flips anyway | 0 .. 1 |
| Bias | skews a fresh bit toward 0 or 1 | −1 .. +1 |
| Range | how far the pitch output roams | 25 cents .. 2 octaves |
| Bits | how many register bits are summed into the pitch | 1 .. 8 |
| Tap | which bit gates the outgoing pulse | 1 .. 8 |
| Level | the outgoing pulse's own weight | 0 .. 1 |

Length, Prob, Drift, Bias and Tap only take effect on the register's next
step; Range and Bits push the cabled voice's pitch immediately, the same live
feel Range already has on an F cell (§2.6).

A TM cell has no sound of its own — E3-with-nothing-focused is inert on one,
same as a D, R, H, F or C cell — and no single E2 character either: like a
voice or a G cell, its eight parameters live on the sound page instead, so a
plain hold-and-turn on the grid has nothing to move but a cable's own gain.

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
wood and starts sounding out of tune. There is a separate per-strike detune in
`grove.on_strike`, scaled by the global **Drops** macro (§4.1) rather than by
this drift.

### 2.7 The weave — R (14)

A D cell decides *when* something happens. An R cell decides **what happens to
a pulse on its way somewhere**. This is the half of a drum machine that is not
the drums, and before the re-cut the panel had almost none of it: three
reactive gaits buried among ten pulse-makers.

Fourteen cells now, not twenty — the re-cut's re-cut (build phase 6c, §2.7b)
gave six of the bottom row's coordinates to a new cell type, and reshuffled
which rules keep a top-row seat. Like a gait, each still has one knob (E2)
meaning whatever the rule says it means, and `K1 + E2` swaps the rule; unlike a
gait, an R cell has no phase — it is silent until something arrives. Every rule
below is still reachable by `K1 + E2` on any R cell regardless of which cell
defaults to it — dropping a cell's default did not drop the rule.

| Cell | Name | Default rule | | Cell | Name | Default rule |
|------|------|------|---|------|------|------|
| (4,2)  | Thicket | rest — now and then it swallows a run | | (4,7)  | Holt    | blur — a human amount of lateness |
| (5,2)  | Briar   | roll — an accelerating run out of one pulse | | (5,7)  | Coppice | latch — a gate that flips every N |
| (6,2)  | Snicket | delay — one copy, a musical interval late | | (12,7) | Osier   | mask — a euclidean stencil over what arrives |
| (7,2)  | Twitten | echo — a decaying tail of repeats | | (13,7) | Sedge   | shift — a skip pattern that rotates each cycle |
| (8,2)  | Tangle  | ghost — a quiet shadow behind it | | | | |
| (9,2)  | Drove   | accent — a cycling weight contour | | | | |
| (10,2) | Sneck   | sift — only pulses over a weight threshold | | | | |
| (11,2) | Lych    | meet — fires when two inputs land together | | | | |
| (12,2) | Stile   | hocket — each pulse down a different cable | | | | |
| (13,2) | Weir    | swing — holds every other arrival back | | | | |

Six cells (x=6..11 of row 7 — Trod, Ginnel, Bostal, Spinney, Bramble and Withy
in the pre-re-cut's-re-cut map) gave up their coordinates entirely: three to
Thicket/Briar/Tangle moving up to the top row, three to the new G cells
between Holt/Coppice and Osier/Sedge (§2.7b). The top row keeps the two rules
the panel's own history singles out below (Hocket, Meet) plus the two the prose
under this table already calls the most useful (Sift, and Accent alongside
it), and pulls up the three that read best against a kit: a rest, a roll, a
ghost.

Four of these deserve their reasons written down:

- **Hocket** is the one that turns four voices into a kit rather than four
  voices. One line in, N lines out, none of them playing the same beat.
- **Sift** placed after Accent or Swell pulls one line out of a busy patch:
  the loud hits go one way, everything goes the other.
- **Meet** is the only rule that needs two cables in. It is a genuine AND.
- **Ghost** and **Briar** are a shadow and a run out of one pulse — placed
  next to Hocket and Meet because they read as immediately different things
  on a kit, which is the same reason **Thicket**'s rest earned a seat: a hole
  in a part is as much a part of the part as a hit is.

**Delay is musical; blur is not.** Snicket and Weir measure themselves in
beats, so they stay in time when the tempo moves; Twitten, Holt, Tangle and
Briar measure themselves in milliseconds, because smearing across the grid is
the whole point of them.

**What the weave emits is not re-quantised.** Swing/Scatter (§4.1) place a *gait's*
emission on a grid line. A pulse coming out of an R cell is derived from one
that was already placed, and snapping a flam or a swung off-beat back onto the
grid would undo the only thing that cell does.

**A transform never sends its output back down its own input.** Cables are
undirected, so an R cell's fan-out includes the cable the pulse arrived on;
excluding it is the same rule the heartwood applies to its injection source,
and for the same reason — that is not coupling, it is doubling. A D cell passes
no such exclusion: a pulse-maker answering its neighbour *is* the coupling
(§2.3).

### 2.7b Percussion cells — G (6)

Build phase 6c — the re-cut's re-cut. The weave's bottom row gave up its
middle six coordinates (x=6..11 of row 7, between Holt/Coppice and
Osier/Sedge) to a small, plain kind of voice: not the six-mode resonator bank
the four corners run, just a single pinged resonant filter or a single
enveloped noise burst, struck directly and shaped by a six-parameter sound
page of its own (tap the cell to open it, same gesture as §5.5).

| Cell | Name | Kind | Character |
|------|------|------|-----------|
| (6,7)  | Yaffle  | ping  | mid, woody knock — a woodpecker's rap |
| (7,7)  | Knap    | ping  | dry, high crack — flint struck |
| (8,7)  | Clapper | ping  | low wooden knock — the kick end |
| (9,7)  | Scree   | noise | bright scatter — the hihat end |
| (10,7) | Chaff   | noise | dry mid rustle — snare-like |
| (11,7) | Rattle  | noise | low shake — clap/rim-like |

**A G cell is itself the cable endpoint.** There is no room on a single grid
row for a separate T/P/M/O cluster the way a corner voice gets, so the cell
does double duty: an incoming pulse strikes it directly (force = edge gain ×
weight, the same as a voice's T socket, and under the same 28 ms refractory),
and — mirroring the corner voices' O socket — it answers with a pulse of its
own a tick later, excluding the cable it arrived on, so it can still sit in a
chain the way the R cell it replaced did.

Six knobs, the same E1-pick/E2-E3-nudge sound page as a voice's, just smaller
— there is no separate socket for a field to reach, so nothing here parallels
Bend, Body, Damp, Bright or Strike position:

| Row | What it is | Range |
|-----|-----------|-------|
| Pitch | transposition off the cell's own root/cutoff | ±2 octaves |
| Decay | ring (ping) or envelope (noise) time | ×0.25 .. ×4 of the cell's default |
| Tone | ping: a detuned second partial mixed in; noise: brown ↔ white colour and bandwidth | 0..1 |
| Punch | attack/transient character — harder and shorter at 1 | 0..1 |
| Drive | saturation into the tanh | 0..1 |
| Level | the cell's own amplitude | 0..1 |

A G cell has no single character knob for E2-while-held or a climate cable to
walk (same as a voice cell); its Decay does answer the global Decay macro
(§4.1) alongside the four corner voices, and its output is mixed into the same
dry bus at the same master level.

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
| E1 | pick one of nine global params (§5.2) |
| E2 / E3 | nudge the picked param, coarse / fine |
| K1 + E3 | Master level |
| K2 | **Still** — freeze all pulse gaits; resonators ring out. Tap again to resume |
| K3 | close the sound page, if it is open (nothing else to cycle to) |
| K1 + K2 | **Regrow** — a seeded patch that already plays (hold to confirm) |
| K1 + K3 | **Clearing** — cut every cable (hold to confirm) |

**The nine global params** (`lib/gparam.lua`), in E1 order:

| Param | What it does | Range |
|-------|--------------|-------|
| BPM | transport tempo, writes `clock_tempo` | 20 .. 300 |
| Swing | grid warp: each pair of 8ths stretched then squeezed, so off-beats land late and beats never move | 0 (straight) .. 1 (full, ~3:1 long-short) |
| Scatter | trigger randomness: loosens the quantise snap and grows a random displacement in its place; also scales gait-rate drift and coupling, and pitch-field wander | 0 (locked to the grid) .. 1 (free-running) |
| Scale | quantises every voice's total pitch to a scale, unconditionally and after everything else has summed. pentatonic only, shorthand "Pent" | 0 (free/unquantised) .. N (Pent Maj, Pent Min, Equi Pent, Equi Pent2) |
| Drops | per-strike random pitch offset, on top of the ~0.02 st floor every strike has always had | 0 .. 1 (up to ±1.5 st) |
| Decay | multiplies every voice's resonator ring time at once | ×0.25 .. ×4 |
| Pitch | transposes every voice at once | ±24 semitones |
| Rain | the always-on `audio/Rain.wav` ambience: its own dry level in the mix. loops from init regardless of this knob; 0 says nothing | 0 (silent) .. 1 |
| Excite | how much that same rain audio continuously excites every voice's resonator, whether or not anything is patched | 0 (no-op) .. 1 |

There is no reverb and no output compressor anywhere in the signal path —
build phase 7 removed both. §8 has the reasoning and what replaced them.

Swing and Scatter decide *when* a pulse is allowed to land, not what it sounds
like; `lib/quantise.lua` owns that mapping and `lib/rambler.lua` routes every
emission through it. The grid is per cell, not global: each is quantised to
the coarsest of 8th / 16th / 32nd / 64th that still fits inside one cycle of
its own rate, so a Shuck lands on 8ths and a Gabriel on 64ths and both stay in
time with each other. A **burst** overrides that and is triggered on the beat,
with its ratchet laid out on a subdivision so the whole flam sits on grid
lines.

Snapping is *forward* to the next line, never back to the nearest — a wrap is
only known about once it has happened. The cost is up to one grid interval of
latency, and since the grid is never coarser than the cell's own cycle, it never
costs the cell a pulse.

Swing/Scatter place a **gait's** emission. What the weave (§2.7) and a voice's O
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
| Voice | — the voice has nine parameters, not one; see the sound page (§5.5) | — |
| G cell | — same idea, six parameters; see its sound page (§2.7b) | — |
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
| G cell | ring (ping) or envelope (noise) time | ×0.25 .. ×4 of the cell's default |
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
| G | 2 unpatched, 4 patched | 10 while its sound page is open, same idea as a voice's; flash on being struck, decay ~120 ms, weighted by force — its own strike and its sound-page indicator share the one cell (§2.7b) |
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

### 5.2 Screen — Global param page (nothing held)

What used to be here — the full 16x8 map drawn as a lit grid with dotted
cable "wires" between cell centres, and a travelling dot per pulse — is gone.
It was a nice picture, but it left the nine global macros with nowhere of
their own to live: Canopy (now gone entirely, §8) and the old Weather knob
were plain encoder turns with no readout, and everything this page now
exposes (Scale, Drops, global Decay, global Pitch, Rain, Excite) had no home
at all.

In its place: the same two-column, nine-row list §5.5 already gave the voice
sound page, for `lib/gparam.lua`'s nine params (§4.1) instead of one voice's
nine. `E1` walks the list, `E2` moves the picked param coarsely and `E3`
finely. There is no tap/hold gesture to reach it and no page to leave — it is
simply what the screen shows whenever nothing is held and no sound page is
open, the same way the network view always was.

```
 Canopy                      severed Oak (2)
 ─────────────────────────────────────
 BPM         120    Decay      x1.00
 ▐▓▓▓▓▓▓▓░░░░       ▐▓▓▓▓▓▓░░░░░░
 Swing      0.80    Pitch     +0.0 st
 ▐▓▓▓▓▓▓▓▓░░░       ▐▓▓▓▓▓▓░░░░░░
 Scatter    0.00    Rain        0.00
 ▐░░░░░░░░░░░       ▐░░░░░░░░░░░░
 Scale      free    Excite      0.00
 ▐░░░░░░░░░░░       ▐░░░░░░░░░░░░
 Drops      0.00
 ▐░░░░░░░░░░░
 E1 pick  E2/E3 coarse/fine
```

The title line's right side carries the same transient event feedback the old
network view printed along its bottom edge — a sever, a gait swap, Regrow or
Clearing's result — so that feedback still has somewhere to be read after a
tap-and-release gesture completes.

### 5.3 Screen — Cell view (a cell held)

```
 KNOCKER                            D
 ─────────────────────────────────────
 metric gait -- locks to the norns...
 metric     ▐▓▓▓▓▓▓▓░░░░░    1 x beat
 rooted · 1/8              coupling 0.42
 ─────────────────────────────────────
 3 cables   ▸ Trod              +0.80
 ─────────────────────────────────────
 K2+K3 sever   K1+E2 gait
```

Under the title is a one-line, plain-English gloss of what the cell actually
does (lexicon.lua's `describe`) — word-wrapped and cut to whatever fits one
line, since the screen has no room for the full sentence on every type. It is
there so the numbers underneath it mean something the first time you hold a
cell you have not held before.

The row below that is whatever the cell type has to say about itself: a D
cell's rooted/wild and the grid Scatter is holding it to; an R cell's cables
in and out and whether its gate is open; an H cell's hop, links and loss; an F
cell's current degree in semitones; a C cell's reach and current value; and
for anything with a sound of its own, the decay row.

The cable list is a one-row window onto `patch.edges_at`, following E1's
focus rather than showing a fixed slice — the description line above took the
screen space a second row used to have.

Two cells held → an edge view: both names, one bipolar gain bar, and a short
description of what actually flows across that edge given the two types.

### 5.4 Screen — Meters view (removed)

Was a placeholder per-cell activity view, cycled in with K3 alongside the
network view. It went with the network view in build phase 6b (§5.2) — a
metering back-channel (§7.4) still doesn't exist, and there is no longer a
screen mode reserved for it. If per-cell metering lands, it belongs on the
cell view (§5.3), read live under whichever cell is held, rather than as its
own idle-screen mode.

### 5.5 Screen — the voice sound page

Tapping a voice cell replaces the screen with that voice's nine parameters;
tapping it again puts the screen back where it was. `E1` picks one, `E2` moves
it coarsely and `E3` finely — nine knobs on two encoders would otherwise mean
either a slow encoder or an imprecise one, and a resonator's decay wants to be
swept across two octaves to find the sound and then moved a hair to make it
sit. `K3` also closes the page, so you never have to remember which cell you
tapped. *Holding* a voice cell shows the same page for as long as you hold it,
without taking the encoders off the patch.

```
 OAK                             sound
 ─────────────────────────────────────
 Tune     +0.0 st    Damp        1.10
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓▓▓▓░░░░░░
 Bend        0.00    Bright      0.50
 ▐░░░░░░░░░░░░       ▐▓▓▓▓▓▓░░░░░░
 Decay     1.20 s    Drive       0.25
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓░░░░░░░░░
 Body        0.55    Strike      0.16
 ▐▓▓▓▓▓▓░░░░░░       ▐▓▓▓▓░░░░░░░░
                     Level       0.98
                     ▐▓▓▓▓▓▓▓▓░░░░
 E1 pick  E2/E3 coarse/fine
```

| Row | What it is | Range |
|-----|-----------|-------|
| Tune | transposition off the voice's own root | +24 / −36 semitones |
| Bend | a pitch drop fired at the strike, decaying to Tune's pitch over ~60 ms | 0..1 (0 is a no-op) |
| Decay | resonator ring time | ×0.25 .. ×4 of the voice's default |
| Body | structure: harmonic ↔ free-free bar | ±0.4 around the voice's own |
| Damp | frequency-dependent damping exponent | ±0.5 around the voice's own |
| Bright | the post-resonator lowpass | 0..1 |
| Drive | saturation into the tanh | 0..1 |
| Strike | mallet position, comb-notching modes with a node there | 0.02 .. 0.5 |
| Level | the voice's own amplitude | 0 .. 1.4 |

Tune's range is asymmetric on purpose: up still tops out at two octaves, but
down now reaches three, so Oak's 55 Hz root can fall well under 10 Hz — deep
enough to sit under a kick rather than just below a bass note. Turn Bend up
on a voice tuned that low and the strike starts a couple of octaves sharp and
glides down to it, which is the other half of the 808 kick: the low root
alone is just a sub tone, the pitch drop on top of it is the "thunk".

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
| **G** cell | strike the drum directly (same shape as T, above), subject to the same 28 ms refractory — see §2.7b |
| **TM** cell | clocks the shift register one step; it answers with a pulse of its own if the Tap bit reads high afterward — see §2.3b |

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
| **TM → P socket** | the register's own pitch tunes that voice, summed alongside whatever fields are also cabled there — see §2.3b |
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
- **A TM cell cabled straight to a P socket carries both halves of §2.3b at
  once**, and neither shadows the other: the pulse half (this table, above)
  fires whenever the TM cell's own answering pulse happens to be routed
  there, flashing the socket and stepping any *fields* also cabled to it,
  exactly as any other pulse source would; the number half (the row above)
  is a live, always-on contribution to that voice's tuning, read fresh every
  time the voice retunes for any reason at all, not only when the TM cell's
  own pulse lands. One cable, both meanings — the same androgynous-socket
  idea §1 opens with, just with two different things arriving down it.
- **D↔D at negative gain** produces anti-phase locking — the most reliable way
  to get a stable interlocking two-part rhythm.
- **R↔R** is transforms in series, and the chain *is* the pattern. It is
  bounded by the same one-tick deferral D↔D is, plus a weight floor every
  decaying rule terminates on.
- **F is a source only.** A field never emits a pulse and never writes a
  stream, so its whole column is one-way and nothing in it can feed back.
- **C is a source only**, for the reason in §2.8, which makes the same true of
  the climate.
- **G behaves as its own pulse source**, the same as an R cell — anything
  cabled to a G cell's answering pulse sees exactly what an R cell's output
  would give it (§2.7b), because there is no T/O split to route through.
  Climate cannot reach it (no single knob), and a G cell is not a target for
  a field either (no P socket) — both cables are legal to draw and mean
  nothing, the same as `node|F`, above.

---

## 7. Software architecture

### 7.1 File layout

```
Canopy/
  Canopy.lua                -- entry: init, grid/key/enc handlers, Regrow
  lib/
    topology.lua            -- the map: cell records, coords, types, adjacency
    lexicon.lua             -- names, descriptions, each cell type's one knob
    patch.lua               -- graph: add/remove/trim edges, serialisation
    dispatch.lua            -- the §6 type-interaction matrix
    rambler.lua             -- D-cell gaits, the phase-coupling scheduler, and
                               the shared pulse bus everything emits through
    weave.lua               -- the fourteen R-cell pulse transforms
    tm.lua                  -- the four TM-cell shift-register sequencers +
                               their eight-parameter page (§2.3b)
    climate.lua             -- the eight C-cell slow modulators
    quantise.lua            -- the groove: Swing/Scatter place a gait's emission
    exciter.lua             -- S-cell control layer (audio side lives in SC)
    heartwood.lua           -- diffusion lattice
    grove.lua               -- pitch fields: modes, coupling, voice retuning
    voice.lua               -- voice sockets + the nine-parameter sound page
    gvoice.lua              -- the six G-cell drums + their six-parameter page
    gparam.lua              -- the nine-parameter global page (§4.1, §5.2)
    gridui.lua              -- grid render + hold/tap state machine
    screenui.lua            -- global param / cell / edge / voice views
    bridge.lua              -- engine command wrapper, throttling, meter cache
  lib/Engine_Canopy.sc      -- SC: modal voices, G-cell drums, exciters, patch
                               matrix, heartwood, the always-on rain ambience
  audio/Rain.wav            -- the rain ambience's source loop
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
`Canopy.lua`. `topology`, `patch` and `state` are shared mutable singletons
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

voiceBus        4  voice outputs (panned, summed, and mixed with rainBus in gFx)
gBus            6  G-cell drum outputs (§2.7b), panned and summed into gFx the
                   same way voiceBus is -- its own allocation since 6 != 4,
                   not a sub-range of anything above
rainBus         2  the always-on rain ambience (§4.1 Rain/Excite), written once
                   in gSrc by \wl_rain -- silent until rain_load's buffer is
                   ready. read directly (plain In.ar, not InFeedback) by every
                   voice's excitation and by gFx's dry level, since both live
                   in groups after gSrc.

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
  write_graph(norns.state.data .. number .. ".canopy")
end
params.action_read = function(filename, silent, number)
  read_graph(norns.state.data .. number .. ".canopy")
end
```

Graph format: a flat list of `{a_id, b_id, gain, oneway}` plus per-cell
character values, per-cell rule choices (gait / rule / mode / shape, and the
rooted and snap flags), and the sound-page parameters per voice, G cell and TM
cell (nine, six and eight respectively — `state.vparam` already stores all
three the same way, so this is one save loop, not three). Cell ids
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

**No reverb, anywhere.** There never was a per-voice body-cavity diffuser --
the original design cascaded two `AllpassC` stages (~20 ms / ~31 ms) after the
mode bank, and in practice that read as a slapback/flutter echo through a
resonant filter bank, not as diffusion, so it never shipped. What did ship for
a while was a single shared plate/hall across the whole instrument (**Canopy**,
`FreeVerb`) plus an output glue **Compressor**; build phase 7 removed both --
the mix is dry, four voices panned and summed, nothing else. The tanh stage is
still there (a much gentler `x0.8` drive instead of the original `x3`) but
purely as the DC-blocked, soft-saturating, limited safety net §6 wants once
voice↔voice feedback lands, not as a tone-shaping effect in its own right.

**The always-on rain ambience.** What replaced Canopy on the global page is
literal rather than an effect: `\wl_rain` (`Engine_Canopy.sc`) loops
`audio/Rain.wav` continuously from init, on its own stereo bus (`rainBus`,
§7.3), loaded async by `rain_load` once Lua knows the sample's path. Two
knobs read that same bus two different ways: **Rain** (`rain_volume`) is its
plain dry level in the mix, mixed in alongside the four panned voices in
`\woodland_fx`; **Excite** (`rain_excite`) feeds a mono sum of it into every
voice's own resonator as continuous excitation -- the same signal path a
strike's noise burst uses, `totalExc` in `\woodland_voice` -- at whatever
depth the knob asks for, whether or not anything is patched. Both default to
0, so an untouched patch is exactly as quiet as it always was; turning Rain
up is weather in the room, turning Excite up is the wood being rained on.

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

**G-cell defaults.** Same idea, one number smaller: `topology.lua`'s G_CELLS
table carries `root` (Hz, or a noise cell's cutoff) and `decay`, which
`gvoice.lua`'s Pitch/Decay knobs sweep around, same as the voice table above.
The engine side only needs to know each index's *kind* (`gDefs`, matching
G_CELLS' order) — the real numbers are pushed once at init by `gvoice.init()`
rather than duplicated into the SC source.

| Cell | Kind | Root/cutoff | Decay |
|------|------|--------------|-------|
| Yaffle  | ping  | 180 Hz  | 0.28 s |
| Knap    | ping  | 620 Hz  | 0.09 s |
| Clapper | ping  | 95 Hz   | 0.40 s |
| Scree   | noise | 4200 Hz | 0.06 s |
| Chaff   | noise | 1500 Hz | 0.16 s |
| Rattle  | noise | 750 Hz  | 0.22 s |

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
g_strike(i, force)              g_pitch(i, hz)
g_decay(i, seconds)             g_tone(i, v)
g_punch(i, v)                   g_drive(i, v)
g_amp(i, v)
exciter_on(i)                   exciter_off(i)
exciter_colour(i, v)            exciter_decay(i, scale)
exciter_gated(i, flag)          exciter_gate(i, dur, amp)
exciter_fm(i, ratio, depth)
patch_add(id, kind, src, dst, gain)
patch_gain(id, gain)            patch_free(id)
heart_conductance(i, v)
master_level(v)
rain_load(path)                 rain_volume(v)
rain_excite(v)
```

`voice_grain` is gone; `voice_sap`/`voice_sway`/`voice_moss` collapsed into
`voice_mod`; `voice_structure` and `voice_tap` are new. `canopy`/`compressor`
are gone with build phase 7; `rain_load`/`rain_volume`/`rain_excite` are new.
`g_*` is build phase 6c's re-cut of the re-cut (§2.7b) — six knobs, no
glide/drift/choke/mod/tap/FM, because a G cell has no sockets for any of
those to mean something on.

**CPU budget.** 4 voices x 6 modes = 24 resonators, plus 6 always-on G cells
(one Ringz-pair or one BPF each, far cheaper than a voice) and up to 20
exciters (lazily allocated, so in practice a handful), ~64 patch synths, the
eight-node heartwood delay network, and one stereo sample loop (`\wl_rain` --
no reverb any more). Fewer voices than before pays for the larger exciter
bank.
Mitigations: the mode-count knob (`voice_modes`), lazy exciter allocation, and
the fact that an unpatched cell costs nothing at all.

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
6b. **The global param page.** The network view (and the meters view
   cycled alongside it) is gone, replaced by §5.2's nine-parameter list —
   `gparam.lua`. Weather is gone with it, split into independent Swing and
   Rain (renamed Scatter in 7); Scale, Drops, global Decay, global Pitch and
   an output Compressor are new. Out of build order for the same reason
   5b/5c were: this is a control-surface rework, not something that needed
   the phases between it and phase 6 to exist first.
7. **The re-name.** The script becomes Canopy (§1's file layout, engine.name,
   every in-code/doc title). Canopy the reverb and the output Compressor are
   both gone — the mix is dry (§8). The old Rain macro is renamed Scatter,
   freeing "Rain" for `audio/Rain.wav`: an always-on loop with its own dry
   level (Rain) and how much it excites every voice's resonator (Excite),
   both new global params replacing Compressor/Canopy in the same nine-slot
   list. Scale is narrowed to pentatonic only (§4.1). Like 6b, this is a
   control-surface and naming rework rather than a phase that depended on 7/8
   below existing first — renumbered ahead of them for that reason.
6c. **The re-cut's re-cut.** Six of the weave's twenty R cells become G
   cells (§2.7b) — small, plain drum voices, not the modal resonator bank
   the four corners run: three pinged resonant filters, three enveloped
   noise bursts, each with its own six-parameter sound page. The top weave
   row is reshuffled to keep the rules the panel's own history and this
   phase judge coolest (§2.7); the six that lost their default seat are
   still reachable by `K1 + E2`. Out of build order for the same reason as
   5b/5c/6b: a control-surface and instrument-shape change, not something
   that depended on 7/8/9 existing first.
6d. **The Turing Machines.** Four of the D core's dark coordinates — directly
   above Hob and Grim, directly below Spriggan and Gabriel — become TM cells
   (§2.3b): 8-bit shift-register sequencers, triggered only, each with its
   own eight-parameter sound page. Out of build order for the same reason as
   6c: an instrument-shape addition, not something that depended on 7/8/9
   existing first, and it lands after 6c because it follows the same
   "small cell, own sound page, own file" shape 6c's G cells set.
8. **Life.** Metering back-channel → grid and screen animation. Narrower than
   it was: see §7.4.
9. **Persistence and polish.** PARAMS, PSET + graph save/load, clock sync,
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
   focused cell, or for the nine rows of the sound page. Out of scope for v1?
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
