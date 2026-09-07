# WOODLAND — design & implementation spec

A monome norns script for grid (128). Four modal/pinged-filter voices, a
sealed core of pulse-makers and clocks, small percussion cells, weave
transforms, drone synths, sample players, pitch fields and sine modulators,
patched by hand, with an explicit Output row deciding what is ever heard at
all.
Inspired by the Ciat-Lonbarde Plumbutter; dressed in British woodland
folklore.

The panel was re-cut at build phase 6 around what the instrument turned out
to be for — a generative, organic drum machine — and re-cut again at the
**grid overhaul** (§9) around an explicit Output row and a single cable point
per voice. §2 describes the map as it stands now; where a decision changed,
the reason is given rather than the history erased.

Target: norns (CM3-class), grid 128 (16x8) **required**. SuperCollider engine +
Lua patching/sequencing layer.

---

## 1. Core principles

1. **Every cell is androgynous.** A cell is simultaneously an input and an
   output. A cable is an undirected *coupling*, not a routing arrow. What
   actually flows is determined by what is at each end (see the interaction
   matrix, §6). The grid overhaul took this further than the original design
   did: a voice used to be the one exception (not a cable endpoint at all,
   only its four sockets were) — now a voice is one point, and that point is
   just as androgynous as everything else on the panel.
2. **You patch by hand, one cable at a time.** Hold a cell, tap another. That is
   the entire wiring grammar.
3. **The grid is the display.** Brightness is not decoration — it is the meter.
   The screen is secondary, for detail and naming.
4. **Everything is named.** Every live cell has a name from woodland or
   British folklore. Names are the interface's memory. Coordinates that are
   *not* cells are left unregistered, dark and inert — the shape of the gaps
   is as much of the layout as the cells are.
5. **Coupling, not sequencing.** Pulse cells do not "send to" each other, they
   *entrain* to each other. Rhythms emerge from phase-pulling, not step data
   — except the TM cells (§2.3b), whose shift registers are the one place on
   the panel that carries anything step-shaped.
6. **Nothing is heard unless it is patched to an output.** The Output row
   (§2's `O` cells) is the only way audio reaches the speakers. A fresh
   patch is silent by design — panning is something the player places, not
   something the instrument assumes.

---

## 2. Grid topology (16 x 8)

Coordinates are `(x, y)`, x = column 1..16, y = row 1..8, matching `g.key(x,y,z)`.

```
      1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
 1    O   O   O   O   O   O   O   O   O   O   O   O   O   O   O   O
 2    M   M   M   M   ·   F   F   F   N   N   N   ·   X   X   V   V
 3    ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·
 4    F   ·   ·  TM  TM   C   T   T   T   T   C  TM  TM   ·   ·   S
 5    ·   F   ·   ·   ·   C   T   T   T   T   C   ·   ·   ·   S   ·
 6    E   ·   F   ·   ·   ·   L   L   L   L   ·   ·   ·   S   ·   R
 7    E   E   ·   F   ·   G   G   G   G   G   G   ·   S   ·   R   R
 8    E   E   E   ·   ·   G   G   G   G   G   G   ·   ·   R   R   R

 O = output (16)       M = modal voice (4)   F = grove field / percussion-ping
 N = percussion-noise  TM = Turing Machine   C = clock (4)
 T = trigger source (8) S = sample player (4) R = weave (6)
 G = gust (12)         L = LFO (4)           E = exciter (6)
 X = 2-op FM synth (2) V = wavefolding VA synth (2)
 · = unregistered coordinate, dark and inert
```

**Row 2 is the instrument row, grouped by family.** It reads left to right as
one sentence: the four modal voices, a gap, the six drums, a gap, the four new
synths (§2.13). It used to interleave them — two voices, the drums, two more
voices — which put the same family on both sides of the kit, read as two
families of two rather than one of four, and left no adjacent run anywhere for
a family that was not already on the panel. Grouped, every family is one run
and the two gaps are the only punctuation the row needs.

**The gaps are load-bearing.** A `·` is not a dim cell or a shift layer — the
coordinate is not registered at all, so `topology.at()` returns nil and the key
does nothing. Row 3 is entirely dark on purpose: it is what separates the
voice/percussion row from the trigger-and-clock core below it, the same way
the sealed box around the old D core once did.

**`F` is deliberately reused for two different cell types at different
coordinates** — the untouched pitch fields (§2.6) on the left seam, and the
three "ping" percussion cells (§2.7b) in row 2 — because both genuinely read
as "F" on the panel and neither collides with the other's `id` prefix
(`f.*` vs `gv.*`). Nothing reads the bare display letter programmatically; it
is documentation, the same as `counterpart` always was.

**Cell counts.** 16 O + 4 voice + 8 T(D) + 4 TM + 4 C(clock) + 4 S(sample)
+ 4 F(grove) + 6 R + 6 GVOICE(F/N) + 6 E + 12 G(gust) + 4 L(LFO)
+ 2 X(FM) + 2 V(VA) = 82 live cells; 46 dark.

### 2.1 The Output row — O (16)

By default **nothing is heard**. The top row is sixteen output cells; position
along it sets pan, hard left at column 1 to hard right at column 16. Cabling a
voice, a percussion (GVOICE) cell, an exciter or a sample player (§2.5) to
one of these is the only way its audio ever reaches the speakers — with one
deliberate exception, the gusts (§2.11), which pan themselves by where the
cell sits and mix themselves in. There is no other automatic mix left
anywhere in the engine (§7.3, §8).

**The row is exclusive, both ways round.**

*One source, one slot.* Position along the row *is* pan, so a source cabled
to two O cells is one source at two pan positions at once — which reads on
the panel as a patching mistake and sounds like a widened, phase-smeared copy
of itself nobody asked for. Cabling a source that is already on the row to a
second O cell therefore **moves** it: the cable it had is pulled first, at
the same gain, so the gesture reads as dragging the source along the row
rather than as adding to it. (`lib/patch.lua`'s `displace_output`;
`patch.toggle` returns `"moved"` rather than `"added"` so the panel can say
so.)

*One slot, one source.* An Output cell used to sum — several cables could
land on one and be heard together at that pan position — and that made it an
anonymous bus rather than a channel. It carries exactly one source now: a
source landing on an occupied Out cell **evicts** whatever was there, the
same way landing on a second Out moves the source itself
(`displace_source`; the panel names the cell that went dark). This is what
lets the mixer page call a channel by the name of the instrument on it rather
than by the number of the seat (§4.1b), which is most of the reason for the
rule.

Everything else about a source's patch is untouched — it may still fan out
to as many non-Output cells as it likes.

An O cell is a pure destination: a pulse landing on one means nothing (§6),
and it never speaks itself. Two O cells cabled together is not a cable at all
— there is no source to move, so nothing is displaced and nothing flows.

### 2.2 Voices (4)

Each voice is now **one cell** — the socket cluster (T/P/M/O) the panel used
to draw around a corner voice is gone. That one cell is simultaneously the
tap-to-open-sound-page target (§5.5) and the sole cable endpoint: what a
cable does when it lands there is decided entirely by what's at the other
end, the same "every socket is androgynous" principle §1 opens with, just
with one socket per voice instead of four.

| # | Name  | Cell   | Root | Character |
|---|-------|--------|------|-----------|
| 1 | Oak   | (2,2)  | 55 Hz | low, heavy, long — the trunk. tune it down and it is the kick |
| 2 | Hazel | (15,2) | 220 Hz | dry, clacky, short, very inharmonic — the crack |
| 3 | Alder | (2,7)  | 98 Hz | hollow, odd-harmonic — a struck tube. the tom |
| 4 | Rowan | (15,7) | 330 Hz | bright, bell-adjacent, protective — the metal |

Unchanged from before the overhaul: four voices, one per corner, chosen to
cover a kit.

**What lands on a voice's point:**

- A **pulse** (from a T cell, an R transform, a TM register, a Clock cell, a
  GVOICE or gust answer, or another voice) always **strikes** it, force
  = edge gain × pulse weight, subject to the 28 ms refractory. Discrete choke
  — the old M socket's "a pulse chokes it" — is gone: there is no socket left
  to carry the distinction between "this strikes" and "this ducks", and every
  pulse now does the one thing a strike always did. The continuous half of
  what choking used to mean (a stream bending the body rather than exciting
  it) still exists, immediately below.
- A **stream** (from an E cell or an H node) always drives the voice's **mod
  path**, unconditionally — there is no socket check left to gate it on. The
  sound page's **Balance** knob (§5.5) decides what that means: at 0 the
  stream is excitation into the resonator; at 1 it is a control signal on the
  body (damping, brightness, a little structure); between, a mix.
- A **field or a TM cell** cabled to a voice tunes it — the old P socket's
  job, now reached by cabling straight to the voice, scaled by the sound
  page's own **Depth** knob (§5.5).
- A cable to an **Output cell** is how the voice is heard at all (§2.1).
- A cable to **another voice** is fully symmetric: each voice's own audio
  feeds the other's mod path, and either answers a strike into the other —
  §1's "every socket is androgynous" taken at its word, now that there is
  only one socket per voice to be androgynous *about*.

**Refractory.** Unchanged: a voice cannot be re-struck within 28 ms — the
safety rail on every loop a cable can make, including a voice cabled straight
back into itself by way of another cell.

### 2.3 Trigger sources — T (8, internally type `D`)

Eight cells in a 4x2 block, sealed behind a ring of dark coordinates. All
eight share one core object: a **rambler**, a free-running phase oscillator
that emits a pulse on wrap. What differs is its *gait* — the rule that shapes
when the phase advances and how a pulse is weighted. Gaits are per-cell
defaults, swappable with `K1 + E2` while holding the cell. Mechanically
unchanged from before the overhaul — only the panel's display letter and
coordinates moved, and Knocker's old job changed hands.

| Cell   | Name     | Default gait | Counterpart |
|--------|----------|--------------|-------------|
| (7,4)  | Hob      | euclidean — k pulses in n | Gabriel |
| (8,4)  | Grim     | figure — a bank of sixteen-step patterns, on the clock | Spriggan |
| (9,4)  | Shuck    | slow and heavy — very low rate, high weight | Boggart |
| (10,4) | Boggart  | burst — one wrap fires a ratchet of 2-7 | Shuck |
| (7,5)  | Spriggan | stochastic — Bernoulli gate at the wrap | Grim |
| (8,5)  | Gabriel  | drifter — fast, free, strongest coupling constant | Hob |
| (9,5)  | Hunt     | accelerando — rate ramps across a cycle then resets | Skriker |
| (10,5) | Skriker  | swarm — a short, unpredictable cluster of 2-4 hits | Hunt |

**Every gait has two knobs** (§4.2b). E2 is the character it always had; E3 is
new, and is in every case the number the gait was previously hard-coding or
borrowing from a global macro:

| Gait | E2 | E3 | E3 was |
|------|----|----|--------|
| metric      | Div — 1/4 .. 4 × beat | **Phase** — ±50% of a cycle | nothing; the gait is rooted, so an offset holds |
| euclidean   | Steps — k:8 | **Rotate** — 0..7 | nothing; the spread had no start |
| figure      | Figure — eight patterns | **Rotate** — 0..15 | nothing |
| slow        | Rate — 0.03 .. 0.5 Hz | **Weight** — 0.3 .. 1.0 | fixed at 1.0 |
| burst       | Rate — 0.3 .. 3 Hz | **Count** — 2..7 | the *global* Scatter macro |
| stochastic  | Chance — p | **Rate** — 0.5 .. 6 Hz | the *global* Scatter macro |
| drifter     | Rate — 0.5 .. 8 Hz | **Couple** — ×0 .. ×2 | fixed at ×1 |
| accelerando | Rate — 0.5 .. 4 Hz | **Ramp** — ×1 .. ×5 | fixed at ×2.5 |
| swarm       | Rate — 0.4 .. 4 Hz | **Spread** — ×0.3 .. ×3 | fixed at ×1 |

Two of those were live bugs rather than missing knobs. **Burst's Count** and
**Stochastic's Rate** were read off the global Scatter, so the one number that
decides what a burst *is* could not be set on the cell doing the bursting —
and reaching for Scatter to loosen the timing of the whole panel also
silently lengthened every ratchet on it. Both are local now, and Scatter is
back to being only about the grid.

**Rootedness follows the gait.** The Clock row is gone with the rest of the T
page (§4.2b), and `metric` — whose whole definition is "locks to the norns
clock, integer division" — is the gait that is rooted. The other eight run
free and couple, which is what all eight of them were already doing: no cell
defaulted to rooted, so nothing that was playing changes. `rooted_ok` and
`rambler.set_rooted` survive in the module for the three gaits that could
take it, so re-exposing it later costs a row and no mechanism.

**Knocker is gone.** Its `metric` gait — locking to the norns clock, integer
division — is still in the gait bank (still reachable by `K1 + E2` on any T
cell), but no cell defaults to it any more: that job, "flash with the master
clock", now belongs to the new Clock cells (§2.9), which sit right next to
this block for exactly that reason. **Skriker** takes Knocker's old seat with
a new gait, **swarm**: a short, unpredictable cluster of 2-4 micro-pulses,
distinct from Boggart's fixed 2-7 ratchet on a quantised grid and from
Spriggan's single Bernoulli gate.

**Coupling.** Unchanged (§2.3's Kuramoto term, `lib/rambler.lua`):

```
dphi_i  =  rate_i * dt  +  K * sum_j ( g_ij * sin(2*pi*(phi_j - phi_i)) )
```

No cell starts **rooted** to the clock any more — that was Knocker's job by
default before, and rootedness is now the **Clock** row on a T cell's
settings page, available on any cell whose current gait supports it
(euclidean, figure, metric — still `rooted_ok` gaits, just nobody's default;
the row reads `n/a` on the others). It used to be a `K1 + tap` gesture that
existed on T and F cells and nowhere else, which is the kind of
per-type-only gesture the single vocabulary in §4.2 replaced.

**Organic rhythm.** Unchanged: the phase/coupling math is exact and
calibrated; every triggered strike gets a small parameter wobble on top of
the edge-gain/weight shaping so no two hits sound quite the same. Timing
itself is untouched by the wobble — timing that's deliberately humanized
lives in the weave.

### 2.4 Exciter cells — E (6, internally type `E`, was `S`)

Continuous stream sources — noise colours and textures. Trimmed from twenty
to six for the grid overhaul: a spread rather than a full kit, since the
panel has far less room for them now. Each runs as a SynthDef on its own
audio bus, lazily allocated only when it has at least one cable.

| Cell | Name | Source |
|------|------|--------|
| (1,6)  | Bracken  | dry rustle — bandpassed white noise and crackle |
| (2,6)  | Ember    | crackle/pop — exponential impulse noise |
| (1,7)  | Gorse    | prickly high band, resonant, spiky |
| (1,8)  | Windfall | grain bursts — short enveloped clusters |
| (2,8)  | Mistle   | pitched chirps — formant/bird-shaped |
| (3,8)  | Wisp     | slow wandering random walk (control-rate) |

**Key behaviour, unchanged:** an E cell is continuous *until a pulse is
cabled into it*. A cable from a T or R cell turns it into an enveloped grain,
fired by that pulse. E↔E cables cross-modulate each other's colour. Gating is
T/R cables only, deliberately — a voice or gust cable's usual meaning here is
colouring, not gating.

### 2.5 Sample players — S (4)

Four cells, one field recording each, on the diagonal in from the right edge.
A pulse plays that recording from the top, under an envelope with a slow
attack and a slow fall the player sets per cell.

```
(16,4) Rain -- (15,5) Cicada -- (14,6) Thunder -- (13,7) Sea
```

| Row | Range | Notes |
|--------|-------------|-------|
| Attack | 0.02 – 20 s | log-mapped around the cell's own default, ±3 octaves |
| Decay  | 0.1 – 40 s  | rides `state.decay`, so the global Decay macro reaches it |
| Speed  | ±1.5 oct    | playback rate, as a ratio of the recording's own |
| Level  | 0 – 1       | this cell's own level in the mix |

It is **routed like every other source**: cable it to an Output cell or it is
not heard, and the Out cell it lands on is what pans it. This is a change —
it used to be the second family (with the gusts, §2.11) that mixed itself,
panned by where the cell sits, and needed no cable at all. Routing it costs
one cable and buys three things: one rule about what is audible for every
family that makes a sound, a fader on the mixer page under the recording's
own name (§4.1b), and a K1+tap that warns when the cell cannot be heard
instead of staying quiet about it.

It keeps its own **Level** knob even so, the way a gust does: a field
recording's loudness is a property of the recording rather than of the cable
carrying it, and Thunder.wav and Sea.wav are nowhere near each other to
start with.

It emits no answering pulse: a swell measured in seconds is not an event
anything downstream could be timed against, and a family with no pulse out
cannot be half of a feedback loop.

An **LFO** cabled to one reaches all four of its rows, Level included — pick
which on the LFO's own Param row (§2.12). That is the ordinary
Target/Param machinery rather than anything special to this family; what
changed is only that these four now have knobs worth aiming it at.

A **Clock cell set to High** (§2.9b) holds the envelope open instead of
striking it, so the recording plays continuously for as long as the gate is
up — `smp_hold(i, 0|1)`, which crossfades `\wl_smp` between its perc envelope
and an asr off the same two knobs.

**What was here before.** These four seats were the **heartwood**, a
diffusion lattice: a pulse injected at one node spread outward with a per-hop
delay and loss and emerged from the others later and quieter, under a single
"conductance" knob standing in for both quantities at once. It was the
hardest family on the panel to hear the shape of and the hardest to aim, and
it is cut outright — `lib/heartwood.lua`, `\wl_heartwood`, the `heart_in` /
`heart_out` bus families and every H pair in the §6 matrix with it. The four
recordings these cells play are the same four the mixer used to run as an
always-on bed (§4.1b); they are played now rather than left running — and
back on the mixer page, but as channels of the patch under their own names
rather than as four fixed rows nothing could remove.

### 2.6 The grove — F (4)

The pitch fields. Trimmed from eight to four for the grid overhaul — one seam
instead of two, and one representative of each of the most distinct shapes
rather than all eight modes having a dedicated cell. Mechanically unchanged:
mode keys match `grove.lua`, and every mode not given a seat here is still
reachable by `K1 + E2` cycling on any F cell.

| Cell | Name | Default mode |
|--------|----------|--------------|
| (1,4)  | Cuckoo   | call — two notes back and forth, never quite the same twice |
| (2,5)  | Nightjar | drone — stays on the root; only the last few cents move |
| (3,6)  | Curlew   | cascade — a descending run, then a leap back to the top |
| (4,7)  | Bittern  | octave — register jumps only; ignores the scale |

**A field reaches a voice by cabling straight to it now** — the old P socket
is gone with the rest of the socket cluster, and there is no other meaning a
field's pulse-less "neither" family link to a voice could have (§2.2, §6).
The voice's own sound-page **Depth** knob (§5.5) is what used to be the P
socket's own depth knob: a multiplier on everything the fields (and TM
cells) do to that voice's pitch. Everything else about a field —
strike-driven stepping, pulse-driven stepping, the continuous modes, F↔F
coupling, snap — is unchanged from before the overhaul.

### 2.7 The weave — R (6)

A T cell decides *when* something happens. An R cell decides **what happens
to a pulse on its way somewhere**. Trimmed from fourteen to six for the grid
overhaul: the rules the panel's own history already singled out as the most
useful on a kit. Every rule not given a seat here is still reachable by
`K1 + E2` cycling on any R cell — dropping a cell's default never drops the
rule itself, the same pattern the panel used the first time it was trimmed.

| Cell | Name | Default rule |
|------|------|------|
| (16,6) | Thicket | rest — now and then it swallows a run |
| (14,7) | Tangle  | ghost — a quiet shadow behind it |
| (16,7) | Stile   | hocket — each pulse down a different cable |
| (14,8) | Sneck   | sift — only pulses over a weight threshold |
| (15,8) | Lych    | meet — fires when two inputs land together |
| (16,8) | Drove   | accent — a cycling weight contour |

**Every rule has two knobs** as well (§4.2b), and every one of the new ones
is a constant the rule used to hard-code — so a rule left alone behaves
exactly as it did before the knob existed:

| Rule | E2 | E3 | E3 was |
|------|----|----|--------|
| divide | Every 1..8 | **Offset** — which of the N | always the last |
| mult   | Count 2..7 | **Decay** 0.4..1.0 | 0.82 |
| delay  | Time — ten musical intervals | **Level** 0.2..1.0 | 1.0 |
| echo   | Time 40..500 ms | **Decay** 0.3..0.9 | 0.62 |
| chance | Chance p | **Hold** 1..4 in a row | 1 |
| accent | Depth | **Length** 2..8 steps | 8 |
| sift   | Above | **Boost** 0..100% | 0 |
| meet   | Window 10..250 ms | **Hold** 0..500 ms | the window itself |
| hocket | Step 1..4 | **Lanes** 2..6 | all of them |
| swing  | Amount | **Every** 2..4 | 2 |
| blur   | Late 0..60 ms | **Wobble** 0..60% | 0 |
| latch  | Length 1..8 | **Duty** 20..80% | 50% |
| fill   | Every 4..32 | **Hits** 1..6 | 3 |
| rest   | Chance | **Run** 1..8 | 1-5 |
| flam   | Gap 8..63 ms | **Grace** 0.1..0.9 | 0.4 |
| ghost  | Gap 20..220 ms | **Level** 0.1..0.6 | 0.32 |
| roll   | Time 80..780 ms | **Taps** 2..10 | 6 |
| swell  | Over 4..24 | **Floor** 0..0.8 | 0.3 |
| mask   | Steps k:16 | **Rotate** 0..15 | 0 |
| shift  | Steps k of 8 | **Turn** 1..4 steps a lap | 1 |

**Meet's Hold** is the one that was doing two jobs: the refractory period was
the coincidence window, so widening the window to catch a loose player also
slowed the whole rule down. They are two numbers now.

**Hocket** turns four voices into a kit rather than four voices; **Sift**
placed after **Accent** pulls one line out of a busy patch; **Meet** is the
only rule that needs two cables in; **Ghost** and **Thicket**'s rest are a
shadow and a hole, and a hole in a part is as much a part of the part as a
hit is. Every other rule (divide, mult, delay, echo, chance, swing, blur,
latch, fill, flam, roll, swell, mask, shift) is unchanged in `lib/weave.lua`
and reachable by cycling.

### 2.7b Percussion cells — F (ping) / N (noise) (6, internally type `GVOICE`)

Unchanged mechanic (the small drum voice §2.7b always described: not the
six-mode resonator bank the corner voices run, just a single pinged resonant
filter or a single enveloped noise burst, struck directly and shaped by its
own six-parameter sound page) — **renamed and repositioned** into row 2, next
to the voices, and split into two labelled groups on the panel: the three
"ping" cells read **F**, the three "noise" cells read **N**. The underlying
type is `GVOICE` and the `id` prefix is `gv.*`, so the display letter `F`
here never collides with the true pitch fields' own `f.*` ids (§2.6).

| Cell | Name | Kind | Character |
|------|------|------|-----------|
| (6,2)  | Yaffle  | ping  | mid, woody knock — a woodpecker's rap |
| (7,2)  | Knap    | ping  | dry, high crack — flint struck |
| (8,2)  | Clapper | ping  | low wooden knock — the kick end |
| (9,2)  | Scree   | noise | bright scatter — the hihat end |
| (10,2) | Chaff   | noise | dry mid rustle — snare-like |
| (11,2) | Rattle  | noise | low shake — clap/rim-like |

**A GVOICE cell is itself the cable endpoint**, same as always: an incoming
pulse strikes it directly, and it answers with a pulse of its own a tick
later, excluding the cable it arrived on. The one new thing since the
overhaul: it now needs an Output-row cable to be heard at all, same as a
voice — there is no automatic mix left to carry it for free.

### 2.8 Turing Machine cells — TM (4)

Four independent shift-register **voltage sources**, no phase or gait of their
own — the only thing that ever moves a register is a pulse cabled into it.

| Cell   | Name       | Counterpart |
|--------|------------|-------------|
| (4,4)  | Padfoot    | Tatterfoal  |
| (5,4)  | Barghest   | Puck        |
| (12,4) | Puck       | Barghest    |
| (13,4) | Tatterfoal | Padfoot     |

**The trigger half is gone.** These used to be a Music Thing Turing Machine
with its Pulses *and* Voltages expanders collapsed onto one cell: a TM chose a
pitch and also answered with a trigger of its own, gated by a Tap bit. That
made every register in a patch a sequencer nobody had asked for, in an
instrument that already has four families whose entire job is making and
shaping pulses (T, C, R, and the clock cells that feed them). So a TM cell is
now the **right-hand side of a Mutable Marbles** and nothing else: a clocked
random voltage with a loop. It is fed a pulse and it answers with a number.

| Row    | What it does |
|--------|--------------|
| Length | 2–16 steps of loop |
| Deja   | how often the bit falling off the end is kept rather than re-flipped |
| Drift  | the chance a kept bit flips anyway — the knob past noon still surprises you |
| Spread | how wide the distribution is, 25 cents to two octaves, log-mapped |
| Bias   | where the centre of that distribution sits, ±12 st |
| Steps  | the grid the readout snaps to: `free`, `semi`, `scale`, `fifth`, `oct`, `lock` |

Spread / Bias / Steps are Marbles' own three knobs and mean what they mean
there. Length and Deja are the loop, kept as two rows because a loop length
you can set exactly is worth more here than one folded into the same control
as the probability of looping at all.

**Bias moves the distribution rather than skewing the coin.** It used to skew
the fresh coin flip, which changed the *shape* of the distribution and only
moved its centre as a side effect, by an amount nobody could name. It is a
straight output offset now, so the register is a fair walk and every knob that
shapes the melody does so at the output, where the number it moves things by
can be printed on the screen.

**Steps is a ladder, not a blend.** One control walks all the way from "a
continuous voltage" to "one note" without ever being ambiguous about which of
those it is on, so it is six named grids and the row prints the name of the
one it is on. `scale` is the global Scale (§4.1), falling back to the minor
pentatonic when that is on `free` — so a TM lands in tune with the rest of the
panel by default. `lock` returns the root and nothing else: the register still
runs, and nothing it does reaches the pitch.

A TM cell is still a member of `topology.PULSE_TYPES`, and has to be: that is
what routes an arriving pulse through rambler's inbox rather than straight
into dispatch, which is what keeps a cycle in the patch from recursing. What
it no longer does is *answer*. K1+tap on one therefore clocks it (through
`HANDLERS["TM"]`) rather than firing a pulse out of it.

### 2.9 Clock cells — C (4, new)

Climate — the eight very-slow modulators the letter `C` used to mean — is
gone entirely from the panel (see the note at the end of this section). The
letter is reused for something unrelated: small cells that flash in sync
with the master (norns) clock, at a multiple or division the player sets,
feeding the trigger block they sit next to.

| Cell   | Name  |
|--------|-------|
| (6,4)  | Toll  |
| (11,4) | Knell |
| (6,5)  | Chime |
| (11,5) | Peal  |

A Clock cell has no phase of its own to couple and no gait bank — it is not
built on the T cells' rambler machinery at all (`lib/clockcell.lua`), so it
never inherits the 8-gait cycle or Kuramoto coupling. It just tracks
`clock.get_beats()` directly at its own **Ratio** (E2, the one knob: 1/8x up
to 8x the beat) and emits a pulse through the same shared door
(`rambler.emit_from`) every other pulse source on the panel uses on every
crossing. It is a **pure source** — a pulse landing on a Clock cell means
nothing, deliberately, for the same reason it always meant nothing on a
climate cell: cables are undirected, so the *ordinary* use (cable a Clock
cell to a T cell so the trigger locks to it) also points that T cell's
output back at the Clock cell, and a fast gait resetting a clock-locked
flasher thirty times a second was never worth having.

#### 2.9b Mode: Clock or High

A clock cell has a second thing it can be. **Mode** (the second row of its
page) switches it between **Clock** — everything above, a pulse on a division
of the transport — and **High**: not a clock at all, but a trigger that is
simply always up.

The reason it lives here rather than as a family of its own is that this is
what a clock cell already is with the division taken away. Everything on the
panel that makes a sound is *struck*: a pulse arrives, the sound swells and
falls, and holding a drone means striking it over and over, which is a rhythm
whether you wanted one or not. High is the missing half of that. Cable one
to a modal voice and the mode bank rings continuously; to a percussion cell
and it rings on; to a gust and the swell arrives under its own Attack and
stays; to a sample cell and the recording plays continuously instead of
swelling and going.

| At the other end | What High does |
|------------------|----------------|
| voice            | `voice_hold` — a continuous excitation into the mode bank, through the same noise band `hardness` shapes for a strike |
| percussion       | `g_hold` — the same click excitation, held low and never released |
| gust             | `gust_hold` — an asr off the same Attack/Decay, in place of the perc |
| sample cell      | `smp_hold` — the same, so the recording plays on |
| exciter          | nothing, and nothing is needed: an exciter free-runs unless a *trigger* cell gates it (§2.4), so a clock cell has always left it sounding |
| everything else  | nothing. A field takes a note and a register takes a trigger; neither has an envelope to hold |

A High cell **does not fire**. It emits no pulses at all — a gate that also
clocked would be two things, and the Ratio knob it would clock at is exactly
what High is for turning off. Ratio stays on the page regardless: it is where
the cell will be when it comes back, and blanking a knob you are about to
want again is worse than leaving it showing a number nothing is reading.

On the panel a Clock cell blinks and a High cell simply sits lit (§5.1) —
that is the whole reading. Two High cells on one target is one held target,
not two: letting go of one leaves the other's grip intact, and the gate is
only released when the last one lets go, the mode goes back to Clock, or the
cable is pulled.

**What happened to Climate.** The eight slow modulators (tide, creep,
season, gust, breath, wane, flourish, shiver — walking another cell's own
knob around, bipolar, over tens of seconds to tens of minutes, without ever
overwriting the player's own setting) are not relocated anywhere; the
feature is gone. The corner space it used to occupy went to more exciters
and a smaller footprint generally, in keeping with the rest of the grid
overhaul's trims. If a "the long game" modulator is wanted again later, it
would need its own letter and its own coordinates — `C` is spoken for now.

### 2.11 The gusts — G (12, internally type `GUST`)

Twelve small drone synths, filling the two bottom rows. **Step sequencers
were here.** Two lanes, Q4 and Q6, sat on these cells briefly and are cut:
what the panel wanted in its two largest free rows was not a fifth way to
make a pulse — it already has T, C, R and TM — but something to *play*.
§2.10 is retired with them; the numbering is left alone so the section
references scattered through the code still resolve.

A gust is loosely a Ciat-Lonbarde Deerhorn voice: a triangle core, folded at
its edges so it is raw rather than sterile, under an envelope with a slow
swell and a slow fall the player sets per cell. It is a reference, not a
schematic — there is no antenna, and the grid key is what an approaching
hand was there. Press a cell and it sounds; a pulse down a cable sounds it
too, and it answers with a pulse of its own a tick later like every other
struck cell.

| Row | What it does |
|--------|--------------|
| Pitch  | ±2 octaves from the cell's own seat, then quantised to the Scale |
| Attack | 0.01 – 12 s, log-mapped around the cell's own default |
| Decay  | 0.05 – 30 s; rides `state.decay`, so the global Decay macro reaches it — and there is deliberately no family Decay on §2.11b for that reason |
| Timbre | how hard the triangle is folded: flute at 0, horn at 1 |
| Cross  | how deeply whatever is cabled in modulates this gust |
| Level  | this cell's own level in the mix |

Two things a gust does that nothing else on the panel does. **It is heard
uncabled** — the engine pans it by the column it sits in and mixes it in,
through the shared send effect (§2.11c), which was this family's own delay
line until every other family got a Send knob into it.
It is now the only family that reaches the mix uncabled: the sample cells (§2.5)
did too and are routed like everything else. An Output cable is still allowed
and still means what it means; it just places a second copy. And **its pitch
is not its own**: the cell's seat plus its Pitch knob is pulled onto the global Scale
before it sounds, so twelve keys pressed at random are twelve notes of one
scale.

**Cross is the reason two gusts cable together.** A continuous cable into a
gust lands on its cross-modulation input, where Cross scales it into pitch
and fold at once — so a modulating gust is heard in this one's timbre as well
as in its tuning, and a pair cabled to each other genuinely FM each other
rather than merely summing. The depth is two octaves at full Cross, and the
mod input is scaled back up to near unity before its soft-limit, because a
gust's output tap is scaled for a mix (`env * amp * 0.3`) and feeding that
straight in bent the receiving gust by about a fifth of a semitone — which is
a waver, not modulation.

#### 2.11b The gusts page — K3, once

Twelve cells is enough of a family to want to move as one, and the twelve
cell pages are the wrong place to do it: setting the same knob twelve times
is not a gesture, and the delay line all twelve share is not a cell's
property at all. So the family gets a page, sitting between the main screen
and the mixer (`gust.MACROS` in `lib/gust.lua`).

| Row | What it does |
|--------|--------------|
| Pitch  | transposes all twelve, ±12 st, before the Scale quantises them |
| Timbre | offsets every cell's fold |
| Attack | offsets every cell's swell time |
| Cross  | offsets every cell's cross-modulation depth |
| Level  | offsets every cell's level |

The three delay rows that used to end this page — Space, Delay, Regen — are
gone from it. That line is a send every family can reach now (§2.11c) and its
rows are on a page of their own past the mixer; a knob that has stopped being
about one family has no business on that family's page.

**The five family knobs are offsets, not values.** Twelve cells you have
spent a while setting individually are the whole point of having twelve, and
a unified knob that wrote absolute values would erase that the first time you
touched it — worse, invisibly, since the twelve cell pages would go on
showing numbers nothing was reading. Each of these sits at a centre meaning
"leave them alone"; moving it slides all twelve together and keeps whatever
spread is between them, and turning it back to the middle puts them exactly
where they were. The sum is clamped **per cell**, so a macro runs out of
travel gracefully at the ends rather than wrapping or shoving cells past each
other. Pitch is in semitones because that is the unit every other pitch on
the panel is in; the other four ride the 0..1 knobs they offset.

**What a cell page reads is what that cell sounds.** The per-cell rows
(§2.11) report the *effective* value — knob plus macro — while `E2`/`E3` go on
moving the cell's own stored knob. That is the arrangement Pitch always had
there, where the reading has always been the note that will sound rather than
the offset that was dialled in, and it is what keeps a macro from being
invisible.

**There is no family Decay**, and that is a decision rather than an omission:
the global page's Decay macro already scales every gust's fall along with
every voice's and every drum's, and it is one `K2` away. Two knobs over one
number is two knobs neither of which can be read. Attack has no such macro
anywhere, so Attack stays. Dropping it also lands the page on exactly eight
rows, which is one screen of the widget grid — the whole family in one look,
no page dots, no seam.

**The delay's three rows have moved twice.** They were on the mixer while it
had a fixed eight-row list to fill; they went to the global page when the
mixer became one fader per active output (a room is not a channel); and they
are here now, on the page that is actually about the family that is heard
through them. What they do, how far they go and where their numbers live
(`state.global.gust_space`) is unchanged by any of it.

#### 2.11c The send effect — a page of its own, past the mixer

The twelve gust cells shared one delay line, and its three knobs sat on the
gusts page because that is whose delay it was. It was also the only effect on
the panel with any sense of a room in it, and every other family was dry: a
snare could be compressed, saturated, crushed and folded on the Colour page,
and could not be put in the same space as the drone underneath it.

So the line is a **send**. Every cell that makes a sound has a **Send** row at
the bottom of its own page saying how much of it goes there; the gusts still
arrive the way they always did, dry-plus-wet on their automatic route; and the
knobs moved onto a page one K3 past the mixer.

| Row | What it does |
|--------|--------------|
| Space  | how much of the delayed signal is heard |
| Delay  | the line's time, 20 ms – 2 s |
| Regen  | its feedback, up to 0.92 |
| Tone   | the damping in the feedback loop, 700 Hz – 12 kHz |

Tone is the one new knob. It was a fixed 3200 Hz, which is the right number
for twelve gusts and the wrong one for a snare; once every family can reach
the line, the colour of the tail is something the player has to be able to
set. The header counts how many cells are currently sending — that is the one
thing this page cannot show any other way, since how much of anything is going
there belongs to the cell, next to its Level, and a second list of send
amounts here would be a mixer nobody asked for.

**There is no `send` argument on any SynthDef.** The panel already has a
general way to route one cell's audio into something at a gain — the patch
matrix (`\wl_patch_aa`) — so a send is exactly that: one source's own tap bus
into one shared mono bus, at the gain that cell's Send knob is set to
(squared, like a fader). `lib/send.lua` builds them as ordinary patch synths,
which is why adding a Send row to a family that grows one later is a line in
its `SOURCES` table and nothing else. At zero the synth is freed outright
rather than left running at a gain of nothing, so a patch that never opens the
page costs four OSC messages and no synths at all. The ids they claim are one
flat block from `send.ID_BASE` (100000), far above anything `edge.id * 10 + i`
can reach with `patch.MAX_CABLES` of 64.

The send arrives **centred and wet only**. Centred, because what places a
source in the image on this panel is the Out cell it is cabled to, and a send
that arrived elsewhere in the stereo field would put the tail of a hard-left
instrument in the middle of the room — which is, as it happens, exactly what a
real send does, and is the one place the panel's "position is pan" rule does
not run. Wet only, because a source that sent its dry signal here as well
would be heard twice at two different levels and Send would be a second volume
control.

An exciter deliberately has no Send row: it is a texture that runs
continuously into whatever it is cabled to rather than a note, and a send on
one is a wash of delayed noise under the patch at all times. Cable it to a
voice and send the voice.

The state stays on `state.global.gust_space` under its old key. It is the same
numbers in the same place, and renaming it would silently discard them out of
every patch saved before the move.

### 2.12 The LFOs — L (4, internally type `LFO`)

Four free-running modulators on the row directly above the gusts. No sound of
their own; a cable out of one is the whole point.

| Row | What it does |
|--------|--------------|
| Speed  | 0.02 – 20 Hz, log-mapped. On `follow` it reads "follows" and is inert |
| Shape  | one of eight (below) |
| Slot   | which of this LFO's four destinations the three rows under it describe |
| Target | which of the cells this LFO is cabled to *this slot* is aimed at |
| Param  | which row of *that cell's* settings page this slot moves |
| Depth  | how far *this slot* swings that knob, either side of where you left it |

**Four destinations, not one.** One modulator moving one knob is a patch cable
with extra steps; what a modulator is *for* is moving several things at once,
at different depths — so that one knob opens a filter *and* lengthens a decay
*and* pulls a pitch. Each LFO carries four slots, each with its own Target,
Param and Depth, and the Slot row says which one the three rows under it are
describing. Slot 1 aims itself at the first cell the LFO is cabled to, so a
freshly patched LFO works without the page being opened at all; slots 2–4
start on `off` and cost nothing. Naming a target and then pulling that cable
leaves the slot idle rather than sliding it onto whatever else is patched —
silently re-aiming a modulator is worse than stopping.

**Eight shapes**, shared by all four of a cell's slots (an LFO is one
modulator with four wires out of it, not four modulators sharing a seat). The
list is `sine`, `tri`, `ramp`, `saw`, `square`, `s+h`, `rand`, `follow`, and
that order is the index sent over the wire — it must match `\wl_lfo`'s own
`Select.ar` array exactly. `s+h` is a sample-and-hold: one fresh random value
per cycle, held flat between them, which is the one shape a free-running
oscillator cannot make. `rand` is the same values joined by a raised cosine,
so it wanders rather than steps.

**`follow` is not an oscillator.** It is an envelope follower on the Output
row — the same sixteen channels `\woodland_fx` reads — so an LFO on that shape
moves with what the instrument is actually playing rather than against it.
Pointed at a filter it is a wah that opens on the loud parts; pointed at a
decay it is a patch that rings longer the harder it is hit. It has no rate,
so the Speed row says so and stores whatever it was left on for when an
oscillator shape comes back.

Both halves compute the shape: the engine, for a cable on `signal`, and Lua,
for a slot aimed at a knob. They have to agree — a cell switching between the
two must not change shape on the way — so `lfo.value` is the twin of that
`Select.ar` and not merely a resemblance of it.

**Param decides what kind of thing the cable is.** Its first entry is
`signal`, and on `signal` that slot moves nothing and the cable is an ordinary
audio-rate one:
`dispatch.lua` builds the same spec any other continuous source would get
(into a voice's mod path, an exciter's colour, a gust's cross-mod input, or
an Output cell, where a Speed up in the audio range is heard as a plain
tone). Pick any other entry and the cable stops being audio entirely: Lua
moves that named knob instead, and dispatch drops its own spec for the pair
so the cable is never heard twice — which it does if *any* of the four slots
is aimed at a knob on that cell.

**How the knob is moved.** Every settings page in the script is the same
object — a list of rows with `get` / `set` / `push` — so modulating one needs
no new machinery: read the base value, set the modulated one, push it, write
the base straight back (`lfo.apply`, on its own 40 Hz metro in `Canopy.lua`).
The stored number never moves, so the screen keeps showing where the player
left the knob and turning it still works while the LFO runs. It costs one OSC
message per *filled slot* per frame — what turning one encoder costs — and it
reaches every parameter on the panel rather than the four families that had a
bus. Changing a slot's Target or Param puts the knob it was holding back where
the player left it.

The shape is read **once per cell** rather than once per slot: four slots of
one LFO are four wires out of one modulator, so they have to be reading the
same number at the same instant — and with a sample-and-hold or a follower,
asking twice can genuinely give two answers. The slot resolution in
`lfo.apply` is likewise written against a destination set built once per cell
per pass rather than in terms of the page's own readers, which rebuild two
lists per call: right for an encoder turn, and sixteen times a frame the wrong
shape entirely.

### 2.13 The new synths — X (2, `FM`) and V (2, `VA`)

The right-hand end of the instrument row, and the first genuinely new
sound-making family since the gusts. Four cells, two of each kind.

| Cell    | Name | Kind | Root |
|---------|------|------|------|
| (13,2)  | FM 1 | 2-op FM | 110 Hz |
| (14,2)  | FM 2 | 2-op FM | 220 Hz |
| (15,2)  | VA 1 | wavefolding VA | 82.41 Hz |
| (16,2)  | VA 2 | wavefolding VA | 164.81 Hz |

**X — a two-operator FM voice.** One sine modulating the phase of another, at
a Ratio you set, by an Index you set, with the modulator able to feed back into
itself. No operator stack, no algorithm menu: two operators is the point at
which FM stops being a bank of presets and starts being something you can hear
the shape of while you turn the knob.

| Row | What it does |
|--------|--------------|
| Pitch  | ±2 octaves, shown as the note it will actually sound |
| Ratio  | a ladder of sixteen exact ratios, 0.5 to 16 |
| Index  | how deep the modulation is — the brightness knob |
| Fbk    | the modulator's own feedback: sine → saw-like → noise |
| Attack | 1 ms – 8 s, log-mapped around a 10 ms centre |
| Decay  | rides on `state.decay`, so the global Decay macro reaches it |
| Cross  | how deeply a cable into this cell modulates it |
| Level  | |
| Send   | how much of it goes to the shared send effect (§2.11c) |

*Phase* modulation rather than true FM, which is what every digital FM synth
since the DX7 has actually done: the carrier's average pitch does not drift as
Index comes up, where true FM detunes as it gets brighter and sounds like the
tuning slipping. Index is enveloped as well as knobbed, on a copy of the
amplitude envelope with a shorter fall — that single thing is what makes two
operators sound like an instrument rather than a test tone, since a struck
sound is brightest at the attack. Ratio is a ladder rather than a sweep
because in two-operator FM the ratio decides whether a note is a bell, a horn
or a clang, and the ones worth landing on are exact.

**V — a variable-waveform virtual-analogue voice** with a Buchla-style
wavefolder in it.

| Row | What it does |
|--------|--------------|
| Pitch  | as above |
| Shape  | sine → triangle → saw, continuously |
| Noise  | pink noise blended alongside the core |
| Fold   | the wavefolder |
| Cutoff | 40 Hz – 12 kHz, log-mapped |
| Res    | |
| Env    | how far the amplitude envelope opens the filter |
| Attack, Decay, Cross, Level, Send | as above |

The chain is oscillator → noise → **fold** → filter, and the order of the last
two is the whole character of the thing. A folder *after* a filter is a
distortion box on the end of a subtractive synth; a folder *before* it is a
Buchla timbre section, where folding generates the harmonics and the filter
then decides how many survive. Fold a sine and you get partials no filter
could have put back — which is why this is not a saw through a low-pass with
extra steps. `Env` is a knob and not a constant because a struck VA voice with
a static filter speaks the same on every note, and hiding that behind a fixed
amount would be a decision the player could hear and could not reach.

**What they share with a modal voice, and what they do not.**

* They are **struck**. A pulse cabled in plays a note, K1+tap plays a note,
  and a High clock (§2.9b) holds one open — exactly the vocabulary a voice or
  a drum has. They are not gusts: a gust is a key you press and a drone that
  routes itself, and these are neither.
* Their pitch runs through `grove.lua`, the **same route a modal voice's
  does**. A field or a register cabled in tunes them, the global Pitch
  transposes them, and the global Scale has the last word. That is the whole
  reason to put them through grove rather than give them a private note like a
  gust has: a TM cabled to one has to play it in the same key as everything
  else on the panel. `grove.PITCHED` is the one table that list lives in.
* They are heard **only through an Output cable**, like everything except a
  gust.
* They have **no glide and no drift**. A modal voice has both because it is a
  bank of ringing resonators whose pitch moves under a note that is already
  sounding; these two are oscillators, and a portamento on one is a knob
  nobody asked for.
* They have no **Depth** row, and sit at the ×1 that row's own centre detent
  means. There are already nine and twelve rows on these pages, and a second
  scaling knob under the one the field itself has is the first thing that
  would come off again.

Engine-side they are the same shape a gust is — one mono tap out per cell, one
summed mod input per cell that Cross scales — so every cable pair among
{FM, VA, GUST} is one rule in `dispatch.lua` over one `CROSS` table rather
than nine written out. Both families answer a single keyed setter (`fm_set` /
`va_set`), the same one-command-per-page arrangement the Colour chain uses and
for the same reason.

---

## 3. Patching grammar

| Gesture | Result |
|---------|--------|
| Hold cell A, tap unconnected cell B | make cable A↔B at default gain (+0.6) |
| Hold cell A, tap connected cell B | remove cable A↔B |
| Hold A, hold B (both down) | screen focuses that edge; E3 sets its gain directly |
| Hold cell A + `K2` and `K3` together | sever every cable at A |
| Hold A, `K1` + tap B | make a **one-way** cable A→B (advanced; drawn differently) |
| Tap a **voice**, **GVOICE** or **TM** cell (nothing else held) | open its sound page (§5.5); tap again to close |
| Tap a **GUST** cell (nothing else held) | it sounds on the way *down*; the release still opens its page |
| `K1` + tap a **T** cell | root it to the clock, or set it wild |
| `K1` + tap an **F** cell | snap its field to the scale, or set it free |

Cables are undirected and bipolar. Gain range `-1.0 .. +1.0` through zero.
Negative gain inverts: streams are phase-inverted, pulse coupling becomes
repulsion, damping modulation reverses. Attenuversion is the main expressive
control after the patch itself.

Constraints: no self-cables; no duplicate edges; a soft cap of 64 cables.
Every cell on the panel is a legal cable endpoint now — the voice exception
the original design carried (§1) is gone with the socket cluster.

---

## 4. Norns controls

### 4.1 Nothing held on the grid

| Control | Function |
|---------|----------|
| E1 | pick one of eight global params (§5.2) |
| E2 / E3 | nudge the picked param, coarse / fine |
| K1 + E3 | Master level |
| K3 | **forward one page** down the stack: main screen → gusts (§2.11b) → mixer (§4.1b) → colour (§4.4) → map (§4.1d). Works from an open cell page too, whose focus it drops on the way. It does not wrap: K3 on the map stays on the map |
| K2 | **back one page** up the same stack, or out of an open cell page; on the main screen, with nothing above it, **Still** |
| K1 + K2 | **Regrow** — a seeded patch that already plays (hold to confirm) |
| K1 + K3 | **Clearing** — cut every cable (hold to confirm) |

**The eight global params** (`lib/gparam.lua`), in E1 order: BPM, Swing,
Rain, Scale, Plonks, Decay, Pitch, Drums. It was nine, then seven when Rain
and Excite left for the mixer, then ten when the gusts' delay line came back
from it — and eight now that the delay has gone on to the gusts' own page
(§2.11b) and the seat it left is Drums (§4.1e). Eight is exactly one screen
of the widget grid (§5.2b), so this page has no page dots and no seam.

**Swing defaults to 0**, not to 0.8. This is an instrument whose gaits are
mostly euclidean, stochastic and drifting, and a hard shuffle is not the
neutral reading of any of them: a default of 0.8 meant every fresh patch
arrived already interpreted, and you had to find this row and turn it down
before you could hear what the gaits themselves were doing. Swing is a thing
you add.

Two of these are renamed and nothing else about them changed. **Rain** was
Scatter: it is the knob that makes everything land a little off the grid and
then a lot, which is what weather does to a rhythm, and "scatter" named the
mechanism rather than the sound. **Plonks** was Drops, for the same reason.
The state keys are unchanged (`scatter`, `drops`) — five other files read
them, and the rename is of the word on the panel, not of the mechanism.

Rain also draws the one shape on the panel that **moves on its own**
(§5.2c): rainfall, light at the bottom of the knob and heavy at the top —
more streaks, longer, falling faster and more slanted.

**Scale** starts on **P.Maj**, the major pentatonic, rather than on free.
Every pitched family here — voices, gusts, the fields that tune them — is
more listenable in tune than out of it, and free is the deliberate choice you
make after hearing what the panel does in a scale rather than the state you
have to find your way out of on first boot. The names are abbreviations
because the Scale row draws with `word`, whose box is five characters wide —
"Pent Maj" clipped to "Pent " there, which named the family and hid the only
part that differed between the four.

**Twelve scales, and eight of them are not 12-TET.** The first four are the
original pentatonics: P.Maj, P.Min, and E.Pn1/E.Pn2, the two distinct 12-TET
roundings of a true five-equal-step (slendro-style) octave that are not
already major or minor pentatonic under some rotation. Every one of them is a
five-note anhemitonic set, so nothing quantised to one can land a semitone
against itself.

The eight after them are neither pentatonic nor, in most cases, in 12-TET —
which is the point of adding them:

| Name  | What it is |
|-------|------------|
| Hijaz | the Arabic/Turkish jins with the augmented second (12-TET, because its second degree is a genuine semitone) |
| Rast  | the central Arabic maqam: neutral third and neutral seventh |
| Bayat | Bayati / Shur — neutral second, the commonest Persian colour |
| Sikah | built on the neutral third itself |
| Homay | Homayoun, the Persian dastgah: neutral second, major third |
| Slen  | slendro — five equal steps of 240 cents |
| Pelog | the Javanese set, in its common five-note selection |
| Anchi | Anchihoye, an Ethiopian qenet |

**No new machinery was needed for the microtonal ones.** A degree in
`grove.SCALES` is a number of *semitones*, not a MIDI note, and nothing
downstream ever rounded it — a `3.5` is three and a half semitones and always
was; the table simply never had a fractional entry in it before. That is what
lets the maqam and dastgah rows carry their real neutral seconds and thirds
(the koron / half-flat degrees, three quarter-tones off the natural) rather
than a 12-TET impression of them, and what lets Slen and Pelog be the actual
Javanese step sizes instead of the two roundings above them on the list.

The cost, stated plainly: a seven-note scale with a semitone in it *can* put
two voices a semitone apart, which the original four could not. That is a fair
trade for being able to play in Hijaz, and the four pentatonics are still
first in the list for anyone who wants the old guarantee.

**K2 and K3 are one linear stack**, not a different pair of jobs per page:

    main screen  →  gusts  →  mixer  →  send  →  colour  →  map

K3 walks it forward one page per press and K2 walks it back one page per
press. Neither end wraps: K3 on the map stays on the map, and K2 on the main
screen is Still, because the main screen is the one place with nothing to
come back from and freezing the patch is a fair reading of "there is nothing
above this". K3's old job — closing a cell page — is K2's too, along with
everything else that means "one step"; an open cell page is checked first, so
it closes before the page step happens.

**The order is the signal's own**, which is why it is worth remembering
rather than looking up. The gusts are the one family that routes itself, so
they come before anything about routing. The mixer balances what the cables
deliver. Colour is what the balanced mix is put through on its way out. The
map is the reference you check rather than a surface you play, so it is at
the far end. Walking right is walking downstream.

**Each page keeps its own E1 cursor** (`state.gparam_focus`,
`guparam_focus`, `mparam_focus`, `cparam_focus`), so stepping away from a
page and back lands on the row you left rather than on its first.

**Regrow** always wires exactly one Output cable per voice it uses — and, if
it seeds a sample cell, one for that too — or a freshly regrown patch would
strike voices nobody can hear, and the whole point of the gesture ("a patch
that already plays") depends on it. Exactly one, not one-or-two: the row is
exclusive (§2.1), so a second would only move the first.

### 4.1b The mixer page — K3

**One channel for every Output cell the patch is actually using**, named
after the instrument on it, with a live meter (`lib/mixer.lua`). The page has
no fixed contents at all: cable Thunder to Out 5 and a "Thunder" channel
appears; pull that cable and it goes. An unpatched patch is an empty page,
which is the honest picture of a patch that makes no sound; a fully patched
one is sixteen, which is the cap because the Output row is sixteen cells
long. `E1` picks a channel, `E2`/`E3` move it coarse/fine — the same page
shape as §5.2 and §5.5. A channel appears at unity, not at zero — a fader
that materialised silent would read as the cable not having worked.

**There is no master row.** A master is not a channel: it is one number over
the whole instrument, and a fader for it sitting first in a list made the
list read as five things of the same kind when it is one thing and four of
another. It is on `K1`+`E3` from every screen, this one included, which is
where it always was.

**The channel is named after the source, not the seat.** An Output cell
carries exactly one source (§2.1), which is what makes that possible and is
most of the reason for that rule: "Out 11" names a pan position, and by the
time six channels are open the position is the least useful thing about any
of them. "Thunder" is what the player reached for the fader to move.

**Every channel carries a meter** (§7.4). It is read *post-fader* engine side
— the level from `lvlBus` is applied exactly as `\woodland_fx` applies it —
which is the only reading that makes sense beside a fader: pull a channel
down and its meter falls with it. Without one, a fader at 0.8 on a silent
channel and one on a roaring channel are the same picture. The same reading
lights that cell on the grid (§5.1).

**A channel fader and a cable's gain are different things.** A cable's gain
says how much of that source arrives at that pan position, and it belongs to
the cable — you set it by holding both ends. The fader is the channel: the
level of that instrument in the mix, reachable in a list beside everything
else that is sounding. Engine side it is one channel of a control bus read by
`\woodland_fx` (`out_level(i, v)`), lagged and squared, so a fader can be
set one channel at a time.

**What used to be here.** Four always-on soundscape loops — Rain, Cicada,
Thunder, Sea — with a fader each, plus the master, plus the gusts' shared
delay line, which together came to exactly eight rows and one screen. The
loops are the four sample cells now (§2.5), played rather than left running,
and they are back here as ordinary channels because they are cabled to the
Output row like everything else; the delay line went to the global page,
where the rest of the patch-wide numbers already were; the master went to
`K1`+`E3` alone. What is left is the one thing a mixer is actually for.

The four recordings still load once each at init, at the same engine indices
— they belong to `sample.init` rather than to this page now. The old
**Excite** knob (the same rain audio fed continuously into every voice's
resonator) has no successor at all: the six E cells (§2.4) are the panel's
excitation sources, and `\woodland_voice` is excited only by its own strike
burst and by whatever a cable puts on its mod path.

Engine side: `smp_load(i, path)`, `smp_note(i, force)`, `smp_hold(i, 0|1)`
and the four knob setters, with one `\wl_smp` synth per cell writing a mono
tap into its own `patchBus` slot (`smpOutBase`) — the shared stereo `smpBus`
those four used to pan themselves into is gone with the self-mixing, and
there is no `smp_pan` any more either. Level is applied inside each
`\wl_smp`; the pan comes from the Out cell the cable lands on. Every knob is
held engine-side whether or not that cell's `Buffer.read` has completed, so
pushing a whole page at init — which `sample.init` does — loses nothing; a
missing file simply leaves that one cell silent and does not touch the other
three.

**Cost.** Thunder and Cicada are minutes long; between them the four buffers
hold roughly 130 MB of scsynth memory. If that ever becomes a problem, the
fix is `VDiskIn` streaming rather than `PlayBuf`, or shorter loops — nothing
above changes.

### 4.1c External clock and transport

norns' own clock owns the tempo source (`PARAMS > CLOCK > source`: internal,
MIDI, Link, crow) and calls `clock.transport.start` / `.stop` / `.reset` back
whichever source is running. So there is no MIDI parsing in the script and no
second clock: select MIDI and the whole patch is externally clocked. Rooted
gaits already read `clock.get_beats()` rather than integrating a rate of
their own (§2.3), so they follow it exactly; `gparam`'s BPM row becomes a
readout and says `ext`.

What the script decides is what Start and Stop *mean* here, and the answer is
the one the panel already has a word for:

| Event | Effect |
|-------|--------|
| Stop | **Still** — gaits freeze, resonators ring out, and everything in flight freezes with them rather than flushing on resume |
| Start | un-Still, and every queue the freeze caught mid-flight is dropped rather than flushed (`rambler.resync`, which also resyncs the weave and the clock cells) |
| Reset (song-position jump, no stop) | the queues only; nothing freezes |

Stop being Still — the *same flag* `K2` writes, not a parallel record of its
own — is what makes a remote stop and a local freeze the same state, which is
the only way the two can never disagree. `K2` resumes from an external stop
for the same reason. The one thing Start has to do beyond clearing the flag is drop the
scheduled/inbox/source queues (`rambler.resync`): `tick()` returns *before*
those drains while Still, so a stop leaves entries sitting there with
timestamps already in the past, and without clearing them the first tick
after a Start would fire the lot in one block.

### 4.1e Drums — the global macros and the percussion cells

The eighth row on the global page, and the one that is not a knob.

Three of the macros above — **Plonks**, **Decay** and **Pitch** — were
written for the four corner voices. Decay quietly grew to reach the drums,
the gusts and the sample cells, because a decay multiplier means the same
thing to all of them. Plonks and Pitch never did, for a good reason: a kit
that transposes with the tune and detunes on every hit is a particular
musical choice rather than the obvious one, and making it the default would
have taken the drums away from anyone using them as drums.

So it is a switch, on the seat the gusts' delay line left (§2.11b):

| Drums | The six `GVOICE` cells |
|-------|------------------------|
| off (default) | ignore Plonks, Pitch **and** Decay entirely. No per-strike traffic is sent at all |
| on | struck notes land a little off (Plonks), the whole kit transposes (Pitch), and the Decay multiplier rides on their envelopes |

**One switch over all three, not three switches.** "Make the kit part of the
instrument" is one idea, and picking it apart into three rows would have made
the common case three gestures instead of one.

**Decay is included, which is a behaviour change**, not just an addition: the
global Decay macro used to reach the drums unconditionally. At the default it
makes no audible difference — `decay_mult` sits at 0.5, which is ×1 — but at
any other setting, Drums off now genuinely detaches them. That is the honest
reading of a switch labelled "Drums: off"; leaving one of the three
permanently attached would be a row that does not do what it says.

**Plonks on a drum has no floor.** `grove.on_strike` gives a voice 0.02 st of
detune whatever Plonks is set to — that floor is the "breathing" an unpatched
voice has always had. A drum head that was dead still before this row existed
has to stay dead still with the row off, so `gvoice.strike_detune` falls all
the way to zero, and sends no `g_pitch` at all when there is nothing to say.

### 4.1d The map page — the end of the stack

`K3` from the Colour page goes on to the map, the last stop: every registered
cell in topology's own 16 x 8 layout (§2), drawn small under the header —
lit if something is cabled to it, dim if it isn't, gone entirely if the
coordinate was never a cell (the "." squares in §2's own sketch). No wires:
a cable's other end is one hold away on the real grid, so the map's job is
only "is this cell doing anything", not "to what".

Holding a cell here, or tapping one open, does exactly what it does on every
other screen: the screen goes to that cell's own settings page (§5.3/§5.5),
not a filtered version of the map. Letting go, or closing the page, comes
back to the map. Two cells held is unchanged either way — that's still the
edge view (§3's "hold A, hold B") and its gain.

`K3` here does nothing: the walk stops. There is nothing downstream of the
map to step on to, and wrapping back round to the main screen would make the
one key that means "forward" also mean "start again", which is the kind of
thing you have to learn rather than read. `K2` walks back the way it came,
one page per press.

### 4.2 Holding a grid cell

| Control | Function |
|---------|----------|
| E1 | select which cable at this cell is focused (ALL → 1..n) |
| E2 | the cell's **character** parameter (see below) |
| E3 | attenuvert — focused cable's gain, or that sound's **decay** when ALL is selected |
| K1 + E2 | swap the rule this cell runs on (T: gait, R: rule, F: mode) |
| K2 + K3 | sever all cables at this cell |

T and R cells are the exception, and §4.2b is the whole of it.

**E2 per cell type:**

| Cell type | E2 = | Range |
|-----------|------|-------|
| Voice | — the sound page has eleven parameters, not one; see §5.5 | — |
| GVOICE | — same idea, six parameters; see §2.7b | — |
| TM | — eight parameters; see §2.8 | — |
| GUST | — six parameters; see §2.11 | — |
| SMP | — four parameters; see §2.5 | — |
| LFO | — four parameters; see §2.12 | — |
| O | — a pure destination; nothing to turn | — |
| T cell | rate / clock relation | gait-dependent |
| R cell | the transform's own amount | rule-dependent |
| E cell | **Colour** — the source's filter/character | 0..1 |
| F cell | **Range** — how far the field roams (25 cents .. 2 octaves) | 0..1 |
| C cell | **Ratio** — multiple/division of the master clock | 1/128 .. 8x |

There is no longer a weather offset riding on top of E2 anywhere — Climate is
gone (§2.9), so the bar an E2-adjustable cell's cell view draws is simply the
player's own setting; nothing else moves it.

**E3 with no cable focused — decay.** 0.5 is whatever that sound's own
default is; the knob is symmetrical around it.

| Cell type | E3 = | Range |
|-----------|------|-------|
| Voice | resonator ring time, in seconds | ×0.25 .. ×4 of the voice's default |
| GVOICE | ring (ping) or envelope (noise) time | ×0.25 .. ×4 of the cell's default |
| E cell | a ratio on the exciter's grain envelope and on whatever tail its recipe has | ×0.35 .. ×2.8 |
| GUST | the fall half of its envelope | 0.05 .. 30 s |
| SMP | the fall half of its envelope | 0.1 .. 40 s |
| T / R / F / C / TM / LFO / O | nothing — no sound of their own | — |

### 4.2b One page, two knobs — T and R cells

A T cell's page used to be four rows (Rate, Gait, Clock, Grid) and an R
cell's three (Amount, Rule, Gate), driven the way every page on the panel is:
E1 walks a cursor down the list, E2 and E3 are coarse and fine on the row
under it. That is the right shape for a voice, which has eleven genuinely
independent numbers. It is the wrong shape here, for three reasons that only
became obvious once §5.2c gave the block underneath a drawing:

- **two of the seven rows were readouts.** `Grid` returned the cell's phase as
  its fraction and `Gate` returned open/shut — facts, not settings, and facts
  the scope now draws far better than a word can.
- **`Clock` read `n/a` on six of the nine gaits.** A row that is inapplicable
  two thirds of the time is a property of the gait wearing a row's clothes.
- **the one row that mattered most was the hardest to reach.** Gait and Rule
  are the choice the whole page hangs off — every other row means something
  different underneath each of them — and both sat *second*, behind a cursor.

So: **E1 is the list, E2 is the first knob, E3 is the second, and there is no
cursor and no second page.**

| Control | T cell | R cell |
|---------|--------|--------|
| E1 | which **gait** (nine, wrapping) | which **rule** (twenty, wrapping) |
| E2 | that gait's first knob | that rule's first knob |
| E3 | that gait's second knob | that rule's second knob |

Both knobs are re-labelled and re-read as E1 moves, and the scope underneath
redraws as whatever the new entry is — so scrolling the list is how you audit
the row, not a thing you do before you can start.

**Scrolling re-seeds both knobs.** The two knobs mean something different
under every entry: euclidean's Rotate is not burst's Count, and Ghost's Level
is not Mask's Rotate. Carrying the raw number across would land the new entry
on a setting nobody chose, so arriving on one puts both knobs at that entry's
own defaults — and every one of those defaults is what the entry did before it
had a second knob (§2.3, §2.7). Scrolling the list is therefore always
non-destructive to *how the thing sounds as itself*; it is destructive to the
two numbers you had set, which is the trade, and is why the list wraps rather
than paginating: nine and twenty are both short enough to walk.

**What this does not change.** Every other cell type keeps the cursor it
always had, unchanged — a voice's eleven rows, a Turing machine's eight, the
gusts' six. This is not a new vocabulary; it is the one page shape that a
two-knob-and-a-list cell wanted all along, and there are exactly two of them.

**The header carries the list.** With no cursor there are no page dots, so
that space is where in the list you are — a track with a block on it, which
reads the same for nine gaits and twenty rules where dots would only have fit
the nine. The cell's own name goes dim and the entry goes bright: you know
which cell you are on, because it is lit under your finger.

### 4.4 The Colour page — one K3 past the mixer

Eight processors across the master output (`lib/colour.lua`, the chain inside
`\woodland_fx`). Everything else on this panel is a thing you patch: a source,
a transform, a seat in the stereo field. These eight are none of those — they
are what the whole instrument sounds like coming out of it, and a cable that
had to be drawn to reach them would be a cable every patch drew identically.
So they live on a page, after the mixer, which is also where they are in the
signal: the faders decide the balance, this decides the surface.

| Row | What it does |
|--------|--------------|
| Tape   | saturation: a tanh curve, and the top end coming off as it is driven |
| Crush  | word length, sixteen bits down to about three |
| Alias  | sample rate, held down from 20 kHz to about 400 Hz, log-swept |
| Loss   | a low-bitrate codec: the band closing from the top, surviving partials warbling under slow noise, and a short smear ahead of every transient |
| Chorus | two modulated delay taps, summed in rather than crossfaded — depth |
| Swirl  | the same pair's rate, 0.05 – 3.5 Hz |
| Shape  | a bipolar transient designer: softer attacks below the middle, snappier above |
| Comp   | one knob doing threshold, ratio and makeup together |

**The chain order is fixed and is not the page order.** It runs

    transient → compressor → tape → chorus → crush → alias → loss

— shape the hits, level them, warm them, widen them, and only then take the
resolution away. The page reads in the order you reach for the knobs: the
four degradations first, because they are what this page is *for*, then the
two chorus rows, then the two dynamics rows. Degradation last in the chain is
what makes it sound like a bad copy of this instrument rather than like this
instrument playing a bad copy of itself — a chorus after a bit crusher smooths
the quantisation noise back out, and that noise is the whole point of Crush.

**Tape lost its wow, and had to.** It used to carry a third thing: a slow
±0.6 ms modulated delay on the wet path, at about 0.7 Hz. The wow itself was
not the problem — the *delay* was. The wet path was offset by a fixed 8 ms
before the modulation even started, and then crossfaded against the dry one; a
delayed copy summed with its original is a comb filter, so the whole knob swept
a phaser across the mix rather than driving it into tape, and the modulation on
top only made the phasing move. Turning Tape up sounded like a parallel effect
because it was one. The delay line is gone entirely and the saturation is
computed in place. A real transport's wow belongs on the signal going *onto*
the tape, not on a copy summed back against it, and there is nothing on this
chain to put it on — so rather than fake it in a way that combs, Tape is
saturation and bandwidth and says so.

**Every row is a genuine bypass at its default**, not a wet/dry mix at zero:
Compander at slope 1 is transparent, an `XFade2` at −1 passes the dry signal
untouched, the chorus taps are summed in scaled by their own knob, and the
transient shaper's exponent is 0 at the centre so its gain is exactly unity.
A patch that never opens this page therefore sounds exactly as it did before
the page existed, and costs the same handful of UGens it always would. There
is no bypass switch because there is nothing to switch off.

Defaults are all 0 except **Shape** (0.5, bipolar and neutral in the middle)
and **Swirl** (0.3 — a rate, inaudible until Chorus is up, and starting it at
zero would make the first thing anyone hears on turning Chorus up a static
comb filter rather than a chorus).

**Comp is percussion-focused**, which means three specific choices: a 4 ms
attack, slow enough that the click of a drum gets out before the gain comes
down — which is what keeps a compressed kit sounding *hit* rather than
sounding pushed; a 110 ms release, long enough not to pump on sixteenths and
short enough to breathe between phrases; and a threshold that comes down as
the ratio goes up, so one knob is always doing both.

All eight are lagged engine-side (80 ms). These are master-bus knobs on a
live instrument: an encoder step that steps the whole mix is a click on every
one of them.

The Lua side sends one command, `colour(key, value)`, rather than eight named
ones — these are eight positions on one chain inside one synth, so the key
*is* the argument name. The engine checks it against `colourKeys` first, so a
typo on the Lua side is a dropped message rather than a stray argument
silently set on the synth.

---

## 5. Displays

### 5.1 Grid brightness (0-15)

| Cell | Idle | Live |
|------|------|------|
| O | 1 unpatched, 4 patched | **its own live meter** (§7.4), post-fader, taking it from 4 up to 15 — the one row on the panel lit by audio rather than by events |
| Voice | 3 unpatched, 6 patched | 12 while its sound page is open |
| T | 3 | flash 15 on pulse, decay ~120 ms; base rises with coupling strength |
| R | 2 | base rises with how much is cabled through it; flashes on the way *out* |
| GVOICE | 2 unpatched, 4 patched | 10 while its sound page is open; flash on being struck |
| E | 3 unpatched, 5 patched | flash on a grain firing, decay ~120 ms |
| H | 2 | local lattice energy |
| F | 2 | where the field currently sits; flash on each step |
| C | 2 | flash on each clock crossing — a pure flasher, no idle "value" reading. **Set to High** (§2.9b) it sits lit at 12 and does not blink at all: a clock blinks, a gate is simply on |
| TM | 2 unpatched, 4 patched | 10 while its sound page is open; flash on each step |
| GUST | 2 unpatched, 5 patched | 10 while its sound page is open; flash on each note |
| SMP | 2 unpatched, 5 patched | 10 while its page is open; flash on each trigger |
| LFO | breathes through its own sine, in three non-overlapping bands (idle / cabled / open) |
| unregistered | 0 | — |

**Patch reveal** — while a cell is held: held cell solid 15; every cell cabled
to it blinks at 13 in sync; every other cell that is a valid patch target is
floored to a minimum readable brightness. Every cell fades toward this floor
the same way now — the old voice-only ×0.4 dim case is gone with the
socket-endpoint exception it existed for.

### 5.1b Inspect dimming — a settings page is open

With a cell's page open and nothing held, the panel dims to that one cell:

| | Level |
|-|-------|
| the cell whose page is open | 15 |
| every cell cabled to it | 7, steady (not blinking) |
| everything else | 1 |

The page you are reading is about ONE cell, and ninety cells all doing their
own thing behind it is ninety things competing with the four numbers you came
to look at. So the grid shows the same one thing the screen is showing. It is
deliberately dimmer and calmer than the held reveal above — a hold is a
momentary gesture and can afford to blink, a page is something you sit on for
a minute — and it is deliberately *flat*, not scaled from what each cell is
currently doing: a trigger's pulse flash is noise while you are reading a
page, and it must not punch back through.

Holding wins over inspecting when both apply: the hold reveal is the more
urgent question.

### 5.2 Screen — Global param page (nothing held)

`lib/gparam.lua`'s eight global rows, drawn as §5.2c's widget grid. `E1`
walks the list, `E2` moves the picked param coarsely and `E3` finely. Eight
is exactly one page.

### 5.2b Screen — the widget grid

Every full-screen page in the script — global (§5.2), gusts (§2.11b), mixer
(§4.1b), colour (§4.4), and every cell page (§5.3, §5.5) — is drawn by one
routine in `lib/screenui.lua`,
and it is not a list any more. The map page (§4.1d) shares the same header
but not the widget grid below it — there is no list to walk, just the
16 x 8 layout redrawn small.

It used to be: a two-column list of `label ....... value` rows with a
hairline bar under each. That was compact, and it read like a settings menu —
rows of small type you parse left to right, one at a time, while the thing
you are editing is making noise. So it became a fixed grid of widgets, each
showing its value as a shape and its name as a word underneath. §5.2c is what
that grid became once the shapes stopped all being the same shape.

### 5.2c Screen — one shape per parameter

The first cut of the grid was a Digitakt tribute: an 11px inverted title bar
and a 4 × 2 grid of identical 270° knob gauges, with a value line under each
label. On a Digitakt that is the right answer — it has eight physical knobs
whose meaning changes per page, so the screen's whole job is to *label* them,
and eight identical widgets is honest about the eight identical knobs under
your fingers. norns has no such row. Here the screen is not labelling
anything; it is the only thing there is.

Which made the grid a list wearing a costume. A circle with a pointer tells
you a quantity but never *which* quantity, so you read all eight words every
time — slower than the text rows it replaced, and with seven of the eight
values now hidden in the header.

So: **the drawing carries the meaning, and no two parameters may look
alike.** `lib/glyph.lua` holds the vocabulary — twenty-eight shapes, one named
by each row's own `glyph` field. A Decay draws a falling tail and the tail
gets longer; a Prob draws a field of dots and the field gets denser; a Length
draws a row of steps and more of them light; a Tap draws the eight bits of
the register and points at the one it reads.

Two of the twenty-eight are worth naming for what they break:

- **`rain`** (the global page's Rain row) is the only shape that **moves on
  its own**. Every other shape is a function of its parameter alone, because
  a widget that moves when the value has not is a widget that cannot be
  read; rainfall is the one case where standing still is the misreading —
  frozen streaks are hatching, not rain. Three quantities rise together with
  the knob so light and heavy read as one weather at two strengths rather
  than as two pictures: how many streaks (3 → 14), how long each is (2 → 7
  px), and how fast and how slanted they fall. Columns and per-streak head
  starts are hashed rather than random, so the shower has a fixed shape that
  scrolls rather than reshuffling itself each frame, and turning the knob up
  adds streaks *between* what is already falling.
- **`channel`** (the mixer page, and nowhere else) is a fader with a live
  meter down its right-hand side — the one place a knob on this panel has a
  signal behind it. The fader is outlined and reads as a control; the meter
  is solid and reads as a measurement. See §4.1b.

The Colour page (§4.4) is where this rule cost the most, and four of the
twenty-eight exist only because of it. Half that page is degradation, and
**Crush** and **Alias** in particular are close enough neighbours that
drawing them alike would have been exactly the failure this vocabulary is
here to prevent — so one quantises *vertically* (`crush`: a staircase across
the transfer line, its steps taller and fewer as bits are lost) and one
quantises *horizontally* (`alias`: sample-and-hold segments over the curve
they are sampling, wider and fewer as the rate comes down), which is the
actual difference between them. **`loss`** is a row of partials with the top
of the band cut and holes punched in what is left, the stumps of the dropped
ones still drawn, dim — "what was taken", not "a shorter row of bars".
**`squash`** is a run of peaks at their own heights behind and the same run
pulled toward one height in front; at zero the two coincide, which is what no
compression is. The page's other four rows borrow shapes that already said
the right thing: `knee` for tape saturation (the parameter is the shape of
the bend, not an amount), `span` for the chorus's detune spread, `fader` for
its rate, and `spike` for the transient shaper.

Three things went, and each paid for the same thing:

| gone | returns | spent on |
|-|-|-|
| the inverted 11px title slab | 3px, and the panel's brightest object | the shape |
| the value line under every label | 7px per row | the shape |
| the knob | a circle's worth of pixels | the shape |

**The header.** 8px, no fill, no chips, a 1px rule underneath. The same five
things, as plain text at three levels: transport (triangle running, square
frozen — Still and an external Stop are one state, §4.1c), the tag (a cell's
panel letter, `MIX`, `MAP`, `G` — the one thing the name cannot tell you,
since "Bittern" does not say whether it is a field or a drum), the name, page
dots, and the tempo. The value readout is gone: every widget draws its own.

**The block.** 128 × 64, header 8, two blocks of 27 — 62, with two spare. In
a block the shape occupied the first 19 rows and the label's baseline was at
26, so the ascenders started two pixels below where the shape stopped and the
bottom row's descenders landed on 63. Four columns of 32; the shape is 26
wide, inset 3 either side. (§5.2d re-cut the inside of the block to fit a
value line back in; the block, the columns and the header are unchanged.)

**Curves, but only cheap ones.** `test/soak.lua` caps `redraw()` at 200
screen commands a frame, because a queue matron cannot drain blocks the Lua
thread and takes the front panel down with the screen. That budget decides
how a curve is drawn, not taste: `screen.curve` is **one** command and draws
a real cubic, while the same curve sampled into a 26-point polyline is
twenty-seven — eight of those is the whole frame. So Decay, Attack, Body,
Bright, Drive and Timbre are genuine cubics, and everything discrete or
positional stays straight, because a curve would say nothing there. No
`screen.arc`: with a live current point — and there always is one, left by
the previous widget's label — `cairo_arc` drags a phantom segment in from
wherever the pen was, which is the bug the old `draw_knob` carried two extra
`move()`s to suppress. `curve_to` has no such behaviour.

Shapes that draw many cells (a dot field, a row of steps, a register) issue
their rects into one path and paint with a single `screen.fill()` — the rects
accumulate, the fill is what costs. The measured cost of a full page was 145
commands on the global page, 147 on a voice's, 142 on the mixer; §5.2d's
value line put those at 166, 174 and 161.

**What it cost, and what was done about it.** There was now nowhere on the
panel to read an exact number. You could set Tune by ear but not to
`+3.00 st`, and you could not match two cells by eye — the gusts' Delay row,
whose whole point is a millisecond figure you match to the tempo, is where
that bit hardest, and it was left consistent with everything else rather than
made an exception, because one row that prints a number is a row that looks
broken. That is the cost §5.2d went back and paid off, for every row at once
rather than one exception at a time.

**Four columns, not the Digitakt's five.** At five a column is 25px, and 25px
of this font is four or five characters — which would turn two adjacent
parameters with a shared prefix into the same four letters. 32px
fits the longest label the panel has. It also means eight to a page rather
than ten, which lands every page in the script except a voice's twelve on one
screen.

**The scopes.** A page of four rows or fewer leaves the whole second block
empty. That used to fill with three wrapped lines from the lexicon — a
sentence you read once on the first day and then never again, sitting in the
best display real estate on the panel while the thing you were listening to
went undrawn. It is now a live display per cell type, drawn from state that
already exists and is already read at frame rate for the grid LEDs:

- **LFO** — the sine, scrolling. The right edge is now, and the current value
  is carried out to the margin. `lfo.phase(id)` (§5.1).
- **D** — the gait itself, one drawing per gait (nine).
- **R** — the rule itself, one layout for all twenty.

A type with no scope keeps its sentence, which is what lets the rest land one
family at a time.

**The phase bar is gone.** The first D scope drew one number — how far through
its cycle the cell was — full width, at level 15, and drew it *identically for
all nine gaits*: a euclidean cell and a swarm cell were the same picture. It
was also the fourth widget on the page saying the same thing twice, because
the `Grid` row's fraction was the phase. A drawing that is the same under
every setting is a drawing of the frame, not of the thing.

**The T scope: mechanism, then history.** Two halves, in every one of the
nine:

- `x 2..48` — the thing that decides. A ring of eight steps with the hand on
  the one sounding (euclidean), a sixteen-step strip with the figure on it
  (figure), a comb of the ratchet (burst), a bar the dice is thrown against
  (stochastic), a ramp that climbs and resets (accelerando), a charge box
  that fills and empties (slow), a line with this cell's phase on it and its
  cabled neighbours' either side (drifter).
- `x 54..126` — what came out, newest at the right edge, bar height for
  weight, over faint ticks of the transport's beats. Same direction the LFO
  scope scrolls.

The drifter drawing is the one worth calling out: §2.3's Kuramoto coupling
has been in the maths since the first build and had never once been on the
screen. The dim dots are the cells this one is cabled to and the bright one
is this cell being pulled between them.

**The R scope: in above, out below.** An R cell had no scope at all — its page
fell through to the lexicon's sentence, which is the one page where a sentence
is least use, because "sends each pulse out of a different cable, in turn" is
a thing you have to imagine. One layout for all twenty:

- rows 0..7, what arrived;
- rows 9..13, the rule's own working where there is something to see — a
  counter, a coin, a square-wave gate, a euclidean stencil, a threshold bar;
- rows 15..25, what left.

The rule is the difference between the two rows. A pulse the rule **swallowed**
leaves a short stub on the bottom row rather than nothing at all: a hole in a
part is as much a part of the part as a hit is (§2.7), and the panel has never
been able to draw one. `weave` keeps three small fixed rings per cell — in,
out, dropped — written in place so a pulse costs no allocation.

**Two rules break the layout, and they are the right two.** `meet` draws two
input rows and `hocket` draws up to six output rows, because those are the two
rules that are not one-in-one-out. The break is the information. Hocket's
Lanes knob is capped at six for exactly this reason — the rows are the cables,
rather than the cables folded onto however many rows happened to fit — and
`weave.out` records which cable each pulse left by so the staircase is read
rather than guessed.

**Each rule carries its own time window.** The millisecond rules — flam at
8-63 ms, ghost, roll, blur — are simply invisible on a lane scaled to bars, so
the window is per rule (1.1 s for flam, 8 s for mask) rather than one constant
that suits neither end. This is a real decision, not a detail: a scope with
one time base would have been legible for about half the row.

**Cost.** `test/soak.lua` walks all nine gaits and all twenty rules and asserts
the worst of each stays under the 150-command cell budget — measured on a
saturated patch that has been *playing*, since a lane is one rect per pulse
still inside its window and an idle page proves nothing. Worst observed: 113
(figure) and 110 (sift).

`test/screen.lua` is the authority on the geometry: two words may never share
pixels; a word may sit inside a box but never inside a shape, and never
half-clipped by anything. It also asserts that every row names a shape, that
the shape exists, and that **no page shows the same shape twice** — the two
exceptions are named there, the mixer (five faders in a row is what a mixer
looks like; the repetition is the reading) and a D cell's Gait and Grid,
which are both words and have no other shape to be. (§4.2b retired that pair
along with the rest of the D page; a T or R page is a fader and a tilt.)

`test/render.lua` is the other half: it rasterises the real `screenui.lua`
into a PGM per view, so the drawing can be looked at without a norns on the
desk. It asserts nothing — geometry tests cannot tell you whether a Decay
looks like a decay.

### 5.2d Screen — the value line, back

§5.2c took every number off the panel and named the cost in its own last
paragraph. This is that paragraph being paid.

The claim was that a shape which fills, tilts, thickens or slides has already
said where the parameter is set. That is true of **where** and false of
**what**: a tail two thirds along says two thirds of *something*, and the
answer is 1.4 seconds, or 0.66, or +7 semitones, depending on which row you
are looking at. Which is precisely the thing you need when you are matching
one cell to another, writing a patch down, tuning to something outside the
box, or coming back to it tomorrow. The shape is the glance. The number is
the check. There was never a reason they could not both be there.

**So every widget prints its own reading**, in the unit the parameter is
actually in — `1.20 s`, `+3.5 st`, `220 Hz`, `2.4 st`, `x1.25`, `65% lock`,
`12 steps`, `on`. Each row's `text()` already produced exactly that string;
§5.2c simply stopped drawing it.

**What it costs, in the same currency §5.2c spent.** 7px a row, and it comes
straight back off the shape: **19px tall becomes 13**. Four of the
twenty-eight shapes could not survive that as drawn and were re-cut rather
than squashed:

| shape | was | is |
|-|-|-|
| `word` | a 13px box at `y+1` | a 10px box at the top, ticks under it |
| `dots` | 9 × 5 cells on a 4px pitch | 9 × 4 on a 3px pitch |
| `stack` | 8 rows, 1px bar every 2px (needs 16px) | 8 rows spread over 12, two pairs touching |
| `flag` | a 13px block | 11px, with air around it |

`stack` is the one place a shape stopped being exactly countable, and it is
also the row whose value line reads `5 bits` — which is the whole bargain in
one widget. It stays a vertical stack rather than becoming a row of eight,
which would fit easily, because Length and Tap are already rows of eight on
that same page and three of them would read as one repeated widget.

**The block, re-cut.** Rows 0–12 the shape, row 13 blank, the value's
baseline at 19, the label's at 26. Text at baseline *y* covers *y*−5 … *y*+1
in this font, so the two lines sit **seven** apart rather than six: a value
ending in a descender and a label starting with an ascender are then adjacent
rather than sharing a row. The bottom row's descenders still land on 63, and
the header, the columns and the two 27px blocks are all untouched.

**Shortening, not clipping.** A row's `text()` is written for a line with a
hundred pixels in it and a column has 28. A name that gives way at the end is
still the name; a number that does is a *different number*. So `screenui.
shorten` gives way in the order that costs the least meaning — the space in
front of a short unit (`1.20 s` → `1.20s`), then decimal places from the
right (`+12.0st` → `+12st`), then whole trailing words (`65% lock` → `65%`) —
and never the sign or the leading digits. It measures with
`screen.text_extents` rather than counting characters, so on hardware, where
the font is narrower than the test harness's pessimistic 5px-per-character
estimate, more of the string survives than the tests assume, never less.

**The one row with no value line** is `word` — a bank of names in a box. It
*is* its value spelled out, and printing `dorian` a second time six pixels
under the first is not a second fact (`glyph.reads_own_value`).

**The cable, too.** The edge view (two cells held) prints its gain under the
bipolar bar, right-aligned, for the same reason: the bar says which side of
centre and how far, and the number is what you need to give a second cable
the same gain.

**The frame budget** (`test/soak.lua`, 200 commands) is why the grid now
draws in *passes* — every shape, then every dim value, then every dim label,
then the focused widget's two lines — rather than finishing one widget before
starting the next. `screen.level` is a socket message like any other, and a
level per line per widget is sixteen of them where a level per band is three.
That, plus three shapes trimmed (`channel` draws its frame and its meter
floor at one level, `alias` holds nine samples rather than thirteen, `squash`
runs five peaks rather than seven), is what keeps the Colour page — the
tightest on the panel — at 187 of its 200 with the value line on it.

### 5.3 Screen — Cell view (a cell held or open)

The same widget grid as §5.2c, for whichever page that cell's type has
(`lib/cellparam.lua`, or `voice`/`gvoice`/`tm`'s own). The header's tag
carries the panel letter and its dots the page number. T and R cells are laid
out differently — two knobs side by side under a header carrying the gait or
rule and its position in the list, and no page dots because there is one page
(§4.2b). Holding is a glance —
the encoders are on the page for as long as you hold, and the patch gesture
is live underneath; tapping latches it open, and dims the panel to that cell
(§5.1b).

The old cell view's second line — a plain-English gloss from
`lexicon.describe`, or a list of what the cell is cabled to — is gone with
the list layout. The grid dimming shows the cables more directly, and the
edge view below still describes any one of them.

Two cells held → an edge view: the same header, both names, a bipolar gain
bar (when cabled), and a short description of what actually flows across that
edge given the two types (§6).

### 5.4 Screen — Meters view (removed)

Unchanged: still removed, still absorbed into the cell view if a metering
back-channel (§7.4) ever lands.

### 5.5 Screen — the voice sound page

Tapping a voice cell replaces the screen with its parameters; tapping again
(or `K2`) puts the screen back. `E1` picks one, `E2` moves it coarsely, `E3`
finely. *Holding* a voice cell shows the same page for as long as you hold
it, without taking the encoders off the patch — unchanged. Thirteen parameters
is one of exactly three lists in the script long enough to paginate on §5.2c's
eight-wide grid; the other two are the FM and VA pages (§2.13), which are the
other two full sound pages on the panel. Nothing else may join them without
someone deciding to let it — `test/screen.lua` names the three.

**Three new rows since the grid overhaul**, at the end of the list: the old
T/P/M sockets' own knobs, which moved here because there is no socket left to
carry them.

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
| **Hardness** | mallet strike hardness — the old T socket's knob, read live at strike time | 0..1 |
| **Depth** | how far a cabled field or TM cell moves this voice's pitch — the old P socket's knob | 0..2 |
| **Balance** | what a stream landing on this voice does — the old M socket's knob: 0 injects, 1 bends the body | 0..1 |
| **Send** | how much of this voice goes to the shared send effect (§2.11c) | 0..1, zero by default |

The old **Tap** knob (the O socket's own output-level control) is gone
outright, not moved — output level is now purely the gain on whichever
Output-row cable(s) the voice reaches (§2.1), and there is nothing left for a
separate per-voice level-before-the-cable knob to do.

Everything else about the page — Tune's asymmetric range, Bend's glide, Body/
Damp sweeping around each voice's own baseline, the Grain macro staying gone
— is unchanged.

---

## 6. Type interaction matrix

What a cable *means* is derived from the pair of endpoint types. This table is
the authority; implement it as a dispatch table, not as branching
(`lib/dispatch.lua`).

The socket column the original design needed is gone — a voice is one point
now, and what a cable does is decided by the type at the *other* end,
exactly the way every other cell on the panel already worked.

**Pulses in** (what happens when a pulse-carrying cell speaks down a cable):

| Target | Meaning |
|--------|---------|
| **Voice** | always strikes it, whatever the source type — force = edge gain × pulse weight, subject to the 28 ms refractory. Discrete choke is gone; there is no socket left to distinguish it from a strike |
| **T** cell | mutual phase coupling (Kuramoto) plus a small trigger nudge |
| **R** cell | the transform's input |
| **E** cell | fire one grain (a T or R cable is what puts the cell into grain mode at all) |
| **F** cell | step the field to a new degree |
| **H** cell | enter the lattice and diffuse |
| **C** cell | nothing, deliberately — it is a pure source (§2.9) |
| **O** cell | nothing — it is a pure destination |
| **GVOICE** cell | strike it directly (same shape as a voice), subject to the same 28 ms refractory — §2.7b |
| **TM** cell | clocks the shift register one step, and answers with a *number*, not a pulse — §2.8 |
| **GUST** cell | plays its note; answers with a pulse of its own a tick later — §2.11 |
| **FM** / **VA** cell | plays a note, at whatever pitch the fields and registers cabled to it have left it on; answers with a pulse a tick later, subject to the 28 ms refractory — §2.13 |
| **SMP** cell | plays its recording from the top; answers with nothing — §2.5 |
| **LFO** cell | nothing — it is a pure continuous source (§2.12) |

**Streams** (live SC synths for as long as the cable exists):

|            | Voice (mod path) | E (exciter) | GUST / FM / VA (cross-mod in) |
|------------|-------------------|-------------|----------------|
| **Voice**  | the other voice's own audio, unconditionally (§2.2) | the voice's audio colours the exciter | the voice bends the synth's core |
| **E**      | the stream drives the body or excites it, per Balance | cross-modulation: each modulates the other's colour | the exciter bends the synth's core |
| **GUST / FM / VA** | the synth drives the voice's mod path | the synth rides the exciter's colour | cross-modulation: each modulates the other (§2.11, §2.13) |
| **LFO**    | on `Param = "signal"` in every slot — otherwise it moves a named knob instead (§2.12) | as above | as above |

The last row of that table is one rule over one table (`CROSS` in
`dispatch.lua`) rather than nine pairs written out: a gust, an FM cell and a
VA cell are built the same way engine-side — one mono tap out, one summed mod
input the cell's own Cross knob scales — so every pair among the three, and
every pair of one of them with a voice, an exciter or an Output cell, is the
same four rules.

**To an Output cell** — a source's own audio, panned at that O cell's fixed
position (§2.1): a voice, a GVOICE cell, an E cell, a sample cell, a gust, an
FM or VA cell, or an LFO can all reach one. Nothing else can, and an O cell never talks back.
A gust already mixes itself, so a cable there is a second,
deliberately-placed copy; a sample cell has no other route to a speaker at
all. An Out cell carries one of these at a time — a second evicts the first
(§2.1).

**Gates** (a Clock cell set to High, §2.9b — a level rather than an event, so
it is neither a pulse nor a stream):

| Target | Meaning |
|--------|---------|
| **Voice** | held open, ringing continuously, never struck |
| **GVOICE** cell | the same |
| **GUST** cell | the swell arrives under its own Attack and stays |
| **FM** / **VA** cell | the note arrives under its own Attack and is held open (§2.13) |
| **SMP** cell | the recording plays continuously instead of swelling and going |
| **E** cell | nothing needed — an exciter free-runs unless a *trigger* cell gates it (§2.4) |
| everything else | nothing. No envelope to hold |

**Neither** — the families that carry a number rather than a pulse or a
stream:

| Pair | Meaning |
|------|---------|
| **F → voice / FM / VA** | the field tunes it; the receiving cell's Depth knob (§5.5, ×1 fixed on FM and VA) scales it, and negative gain inverts the contour |
| **F → E** | the exciter's Colour rides the field's line |
| **F ↔ F** | the two fields pull together (apart, at negative gain) |
| **TM → voice / FM / VA** | the register's own pitch tunes it, summed alongside whatever fields are also cabled there |

"a voice" in those last two means any **pitched** cell — the four modal voices
and the four new synths alike (§2.13). `grove.PITCHED` is the one table that
list lives in, and both `grove.lua` and `tm.lua` ask it rather than testing
for the type by hand.

Notes on the awkward pairs:

- **Voice↔Voice** is now two cables' worth of meaning on one point, same
  cable: each voice's own audio excites/bends the other (a feedback path by
  definition — DC blocker, soft saturation and a limiter on every voice bus
  so a loop howls musically instead of clipping), and either can strike the
  other on the pulse side, bounded by the refractory instead. Do not prevent
  either loop.
- **Two O cells cabled together** is a patch with no meaning; nothing gives
  it one (and it isn't a useful gesture either way — an O cell never has
  audio of its own to send).
- **A TM cell cabled straight to a pitched cell is a tuning, and only a
  tuning.** It used to be two things at once — the register's own answering
  pulse struck the voice as well as tuning it — and the trigger half is gone
  (§2.8). What is left is a live, always-on contribution to that cell's
  pitch, read fresh every time it retunes for any reason at all. What clocks
  the register is a separate cable, from whatever is keeping time.
- **T↔T at negative gain** produces anti-phase locking.
- **R↔R** is transforms in series, and the chain *is* the pattern.
- **F is a source only.** A field never emits a pulse and never writes a
  stream, so its whole column is one-way.
- **C is a source only** (§2.9) — the same "cables are undirected, so a
  reactive pulse-in would fire on the return leg of the ordinary use" reason
  climate always had, kept even though climate itself is gone. Set to High
  (§2.9b) it sends no pulses at all and holds instead, so every "the clock
  pulse ..." row above is simply not the sentence for it.
- **GVOICE behaves as its own pulse source**, the same as an R cell — a Clock
  cell cannot reach it with anything but a pulse (no single knob to walk, and
  there's no weather left to walk it with anyway), and a GVOICE cell is not a
  target for a field either (both cables are legal to draw and mean nothing).
- **Gusts, drums and the new synths chain freely** — each answers its own
  trigger with a pulse a tick later, so one can drive the next, and a cycle
  between two is safe by the same one-tick construction as a T↔T cable. A
  sample cell deliberately does not answer, so it can only ever be the end of
  such a chain — and neither does a register, now.

---

## 7. Software architecture

### 7.1 File layout

```
Canopy/
  Canopy.lua                -- entry: init, grid/key/enc handlers, Regrow
  lib/
    topology.lua            -- the map: cell records, coords, types, adjacency
    lexicon.lua              -- names, descriptions, each cell type's one knob
    patch.lua                -- graph: add/remove/trim edges, serialisation
    dispatch.lua              -- the §6 type-interaction matrix
    rambler.lua              -- T-cell gaits, the phase-coupling scheduler, and
                               the shared pulse bus everything emits through
    weave.lua                -- the six R-cell pulse transforms
    tm.lua                   -- the four TM-cell random voltage sources +
                               their six-parameter page (§2.8)
    clockcell.lua            -- the four C-cell clock flashers (§2.9)
    quantise.lua             -- the groove: Swing/Rain place a gait's emission
    exciter.lua              -- E-cell control layer (audio side lives in SC)
    sample.lua               -- the four S-cell sample players (§2.5)
    gust.lua                 -- the twelve G-cell drone synths (§2.11)
    synth.lua                -- the two FM and two VA cells + both their
                               pages (§2.13)
    send.lua                 -- the shared send effect, its page, and every
                               cell's Send row (§2.11c)
    lfo.lua                  -- the four L-cell modulators: eight shapes and
                               four destinations each (§2.12)
    grove.lua                -- pitch fields: modes, coupling, voice retuning
    voice.lua                -- the thirteen-parameter voice sound page (§5.5)
    gvoice.lua               -- the six GVOICE-cell drums + their sound page
    gparam.lua                -- the eight-parameter global page (§4.1, §5.2)
    mixer.lua                 -- master + one fader per live output (§4.1b)
    colour.lua                -- the master colour chain's page (§4.4)
    gridui.lua                -- grid render + hold/tap state machine
    screenui.lua              -- the widget grid (§5.2c/d): global / gusts /
                                 mixer / send / colour / cell / edge views,
                                 plus the map (§4.1d)
    glyph.lua                 -- the shape vocabulary (§5.2c): one drawn
                                 shape per parameter, named by its `glyph`,
                                 26 x 13 under §5.2d's value line
    bridge.lua                -- engine command wrapper
  lib/Engine_Canopy.sc      -- SC: modal voices, GVOICE drums, exciters, the
                               gusts, the FM and VA synths, the shared send
                               effect, the four sample players, the eight-shape
                               LFOs, the patch matrix, the Output row's
                               fixed-pan mix and the master colour chain
  audio/*.wav               -- Rain, Cicada, Thunder, Sea: one per S cell
  README.md
```

**One door for every pulse.** A T cell wrapping, an R cell passing something
on, a voice/GVOICE/GUST/FM/VA answering — all go out through
`rambler.emit_from`, so trails, the fan-out cap and the one-tick deferral
that makes cycles safe are written exactly once. A TM cell is no longer on
that list: it answers with a number rather than a pulse (§2.8).

**Module loading.** Unchanged — `wl()`, defined in `Canopy.lua`.

### 7.2 Lua / SC split

Unchanged. **Lua owns:** the patch graph, all pulse generation, coupling and
transformation, the grove's pitch fields, the clock cells, the LFOs'
knob-targeting half (§2.12) and their Lua-side twin of the shape bank, all UI.
**SC owns:**
every sample of audio, the audio-rate patch matrix, and continuous
modulation.

### 7.3 SC bus topology

```
groups:  gSrc -> gPatch -> gVoice -> gTap -> gFx

patchBus        6  exciter outputs        (excBase         0)
                6  per-E colour-mod sums  (colourModBase   6)
                4  per-voice mod path in  (modInBase      12)
                4  per-voice audio tap    (voiceOutBase   16)
                6  per-GVOICE audio tap   (gvoiceOutBase  20)
               16  Output row (§2.1)      (outBase        26)
               12  per-GUST audio tap     (gustOutBase    42)
               12  per-GUST cross-mod in  (gustModBase    54)
                4  per-LFO shape tap      (lfoOutBase     66)
                4  per-SMP audio tap      (smpOutBase     70)
                2  per-FM audio tap       (fmOutBase      74)
                2  per-FM cross-mod in    (fmModBase      76)
                2  per-VA audio tap       (vaOutBase      78)
                2  per-VA cross-mod in    (vaModBase      80)
                1  the shared send bus    (sendBase       82)
               --
               83  total

control buses:
outLevelBus    16  the mixer's channel faders, read by \woodland_fx
excMeterBus     6  per-exciter envelope follower (§7.4)
outMeterBus    16  per-Output-cell envelope follower, post-fader (§7.4)
```

**`smpBus` is gone too.** The four sample cells used to `Pan2` themselves by
their own seat into one shared stereo bus `\woodland_fx` read directly. They
are ordinary cabled sources now (§2.5), so each writes a mono tap into
`smpOutBase` and the Out cell it is cabled to is what pans it.

**`voiceBus` and `gBus` are gone.** Before the overhaul, every voice and
every percussion cell wrote to two places: its own patchBus tap (for cables)
*and* a dedicated always-on bus that `\woodland_fx` read and mixed
automatically. That automatic mix is gone — a voice's `tapOut` and a GVOICE
cell's `out` are now each source's *only* destination, and the Output row
(above) is the only thing that ever reads them. `\woodland_fx` itself
changed to match: it no longer takes a `busIn`/`gIn` pair at all, only
`outBus` — sixteen mono channels, each read through a fixed `Pan2` position
(`-1 + 2*i/15` for channel `i`), matching `topology.lua`'s own `pan` field
for O cell `i+1`.

**`sendBase` is one channel, not one per cell** (§2.11c). It is the input of
one shared effect, and what decides how much of a given cell arrives there is
that cell's own Send knob, applied as the gain on an ordinary patch synth from
that cell's tap into here. Mono, and centred at the far end: what places a
source in the image is the Out cell it is cabled to, and a send that arrived
elsewhere in the stereo field would put a hard-left instrument's tail in the
middle of the room.

The two new synth families (§2.13) take the same shape a gust already had —
one mono tap out, one summed mod input the cell's Cross knob scales — which is
why every cable pair among {FM, VA, GUST} is one rule in `dispatch.lua` over
one `CROSS` table rather than nine written out.

These are **audio** buses throughout, including the modulation ones, for the
same summing reason as before. Keep every offset identical to `bridge.BUS`
on the Lua side.

Patch synths, instantiated per cable, live in `gPatch`, unchanged:
`\wl_patch_aa` (straight pass) and `\wl_patch_ak` (amplitude-follow).
`InFeedback`, not `In`, on the source side, for the same order-independence
reason as always. `\woodland_fx` itself reads `outBus` with a plain `In.ar`
— `gFx` runs after `gPatch`, so this block's writes are already there.

### 7.4 Metering back-channel

Two families are metered, by the same mechanism: one control-rate
`Amplitude` follower per cell, written to a control bus, exposed to Lua as
one `addPoll` per channel. `getControlBusValue` reads the shared-memory
interface directly, so there is no OSC round trip per reading.

| Poll | Source | Read by | Drawn as |
|------|--------|---------|----------|
| `exc_lvl_<i>` | `\wl_exc_meter` over `excBase` | `exciter.start_meters` | folded into the same decaying flash a grain-fire uses, so an exciter's continuous level and a gated one's discrete hits both just light the cell |
| `out_lvl_<i>` | `\wl_out_meter` over `outBase`, **post-fader** | `mixer.start_meters` | the meter beside each fader on the mixer page (§4.1b), and the brightness of that Out cell on the grid (§5.1) |

The Output meters are read post-fader — the level from `outLevelBus` is
applied exactly as `\woodland_fx` applies it — because that is the only
reading that makes sense next to a fader: pull a channel down and its meter
falls with it, so what the meter says and what you hear are one statement.
Their release is slower than the exciters' (0.4 s against 0.2 s): these are
whole channels rather than one texture, and a meter that falls as fast as the
audio does flickers rather than reads. Both poll at 20 Hz.

### 7.5 Persistence

Unchanged mechanism. Graph format: a flat list of `{a_id, b_id, gain,
oneway}` plus per-cell character values — **both of them** now, the primary
and §4.2b's second knob — per-cell rule choices (gait / rule / mode, and the
rooted / snap flags), each LFO's Target and Param, the mixer's per-output
levels, and the sound-page parameters per voice, GVOICE cell, TM cell, gust
and sample cell.

The second knob is one more plain 0..1 per cell in the same shape as the
first (`state.character_b`), and it defaults per-gait and per-rule rather than
to a constant — so a patch saved before it existed loads with every T and R
cell doing exactly what it did, because every default is the number the gait
or rule used to hard-code.
Cell ids are stable strings (`"oak"`, `"d.skriker"`, `"r.drove"`, `"h.ley"`,
`"f.cuckoo"`, `"clk.toll"`, `"q4.4"`) — never coordinates — which is what let
the whole panel be re-cut twice now without the format changing. A saved
patch from before the overhaul that referenced a now-gone id (`"oak.trig"`,
`"c.moon"`, `"g.yaffle"`) fails to resolve on load and goes silently inert —
every consumer already nil-guards `topology.get`, so this needs no migration
code.

---

## 8. Sound engine — making it woody

Unchanged synthesis approach: modal synthesis (`DynKlank`-style, hand-built),
excited by short filtered noise bursts through a plain, tuneable, pinged
bank of resonant filters. The five things that make it sound like wood
(inharmonic mode ratios, frequency-dependent damping, a noise-burst exciter,
strike-position comb-notching, gentle nonlinearity) are all unchanged — see
the previous build phases for the detail, none of which the grid overhaul
touched.

**What the grid overhaul changed here:**

- **`\woodland_voice` lost its choke envelope** (`t_choke`/`chokeDepth`/
  `chokeTime`) and the separate `tapLevel` output-level knob, along with the
  `out`/`voiceBus` argument entirely — a voice's only destination is now its
  `tapOut` bus, unscaled; loudness is purely the Output-row cable's own gain.
- **`\wl_g_ping`/`\wl_g_noise`'s existing `out` argument now points at the
  new `gvoiceOutBase` patchBus range** instead of the old always-on `gBus` —
  no SynthDef signature change needed, just a different bus at construction
  time.
- **`\woodland_fx` reads only the Output row**, each channel scaled by its
  own mixer fader off a control bus (§4.1b), plus the gusts' and the sample
  cells' two self-mixed stereo beds. See §7.3.
- **`\wl_heartwood` is gone** with the family (§2.5). `\wl_smp` takes its
  place: a looping `PlayBuf` retriggered from the top, under an `Env.perc`
  whose two times are the cell's own knobs.
- **Six exciter recipes survive** (bracken, ember, gorse, windfall, mistle,
  wisp) of the original twenty; the other fourteen SynthDefs were removed
  outright rather than left unreferenced.

**Per-voice defaults**, unchanged:

| Voice | Fundamental | Structure | Damp exp | Decay | Notes |
|-------|-------------|-----------|----------|-------|-------|
| Oak   | 55 Hz  | 0.55 bar  | 1.1 | 1.2 s  | heavy, dark — the kick end |
| Hazel | 220 Hz | 0.95 bar  | 1.3 | 0.28 s | dry clack |
| Alder | 98 Hz  | odd-only  | 0.8 | 1.6 s  | hollow tube — the tom |
| Rowan | 330 Hz | 0.75 bar  | 0.6 | 1.8 s  | bright, bell-adjacent |

**GVOICE defaults**, unchanged, `topology.lua`'s `GVOICE_CELLS` table:

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
voice_mod(voice, balance)
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
gust_note(i, hz, force)         gust_pitch(i, hz)
gust_attack(i, s)               gust_decay(i, s)
gust_timbre(i, v)               gust_cross(i, v)
gust_amp(i, v)                  gust_pan(i, v)
gust_space(mix, time, fb)       lfo_rate(i, hz)
smp_load(i, path)               smp_note(i, force)
smp_attack(i, s)                smp_decay(i, s)
smp_speed(i, v)                 smp_level(i, v)
smp_pan(i, v)
master_level(v)                 out_level(i, v)
colour(key, v)
```

`voice_choke` and `voice_tap` are gone — the socket collapse (§2.2) removed
both discrete choke and the separate per-voice output-level knob.
`rain_load`/`rain_volume`/`rain_excite` are gone too, and so are the
`amb_load`/`amb_volume` pair that briefly replaced the first two: the
recordings belong to the sample cells now (`smp_load`, `smp_note`,
`smp_attack`, `smp_decay`, `smp_speed`, `smp_level`, `smp_pan`), and
`rain_excite` has no successor at all. `heart_conductance` is gone with the
heartwood; `out_level` is new (§4.1b), and `colour` is new (§4.4) — one
command for the master chain's eight knobs rather than eight named ones,
since they are eight arguments on one synth and the key *is* the argument
name.

**CPU budget.** 4 voices x 6 modes = 24 resonators, plus 6 always-on GVOICE
cells and up to 6 exciters (lazily allocated), ~50 patch synths worst case,
12 gusts and their shared delay line, 4 sines, 4 sample players, and the
master colour chain (§4.4) — two amplitude followers, a Compander, four
short delay lines, two LPFs, two BPFs and a Latch, all stereo, all always
running whether or not any of the eight knobs is up. Smaller
across the board than
before the overhaul — the trims (§2) bought back headroom the same way the
original design's four-voices-not-six trade did.

---

## 9. Build order

Each phase ends in something testable on the device. Phases 1-6d are the
instrument as it stood before the grid overhaul; what follows is additive.

1. **The light show.** topology + lexicon + grid render + hold/tap patching +
   network and cell screens. No audio at all.
2. **First sound.** SC engine with the modal voices and `strike`. One D cell
   (Knocker, since removed — see the grid overhaul below) driving them.
3. **Rhythm.** The gaits + D↔D phase coupling + the 2 ms scheduler.
4. **Exciters.** S cells (since renamed E), the audio-rate patch matrix.
5. **Heartwood.** The diffusion lattice, both discrete and continuous paths.
5b. **Grove.** The pitch fields, their modes and coupling.
5c. **Weather as a groove knob.** `quantise.lua`, Swing/Scatter.
6. **The re-cut.** Four voices with named T/P/M/O sockets, twenty exciters,
   the weave, the climate, the per-voice sound page.
6b. **The global param page.** `gparam.lua`'s nine-parameter list replaces
   the old network view.
7. **The re-name.** The script becomes Canopy; reverb and the output
   Compressor removed; the always-on rain ambience added (since grown into
   the mixer's four loops — see 11 below).
6c. **The re-cut's re-cut.** Six R cells become G cells (§2.7b).
6d. **The Turing Machines.** Four TM cells join the D core (§2.3b).
8. **Life.** Metering back-channel groundwork (still narrower than spec'd).
9. **Persistence and polish.** PARAMS, PSET + graph save/load.

10. **The grid overhaul.** A second re-cut, this time around an explicit
    Output row and a single cable point per voice — the two things the
    original androgynous-socket premise (§1) always implied but the panel
    never actually did. In order:
    - **Mechanical re-cut.** Every surviving cell family (T, TM, R, H, F,
      GVOICE, E) moved to new coordinates and trimmed to a smaller count;
      Climate removed outright; the six G cells renamed to GVOICE and split
      into F(ping)/N(noise) display groups.
    - **Voice-socket collapse.** The T/P/M/O cluster became one point per
      voice; `dispatch.lua`'s handler table rebuilt around "what's at the
      other end" instead of "which socket"; discrete choke dropped;
      Hardness/Depth/Balance moved onto the sound page (§5.5).
    - **The Output row.** Sixteen new O cells, `\woodland_fx` rewritten to
      read only them, `voiceBus`/`gBus` and the automatic mix removed
      entirely (§7.3, §8).
    - **Clock cells.** Four new C cells (§2.9), replacing Climate's old
      letter with an unrelated, much simpler pure-source flasher; Knocker's
      old clock-locking job moved to them, and Skriker's new `swarm` gait
      took Knocker's old seat in the trigger block.
    - **Q4/Q6 sequencers.** Two new step-sequencer lanes, the first genuinely
      step-based cell type on a panel that otherwise ran entirely on
      phase-coupling and diffusion. Cut again shortly afterward; the twelve
      gusts (§2.11) took their cells.
    - **Spec and test-suite pass.** This document, and the offline harness's
      coverage, brought back in step with the code.

11. **The screen and the transport.** Five changes that are all about
    *playing* the instrument rather than about what it can make. In order:
    - **The widget grid** (§5.2b). `screenui.lua` rewritten around an
      inverted header bar and a 4×2 grid of knobs and boxed readouts, in
      place of the two-column text list every page used to be.
      `test/screen.lua`'s collision model rewritten with it: backgrounds and
      frames may hold text, knob gauges may not, and nothing may be
      half-clipped.
    - **External clock and transport** (§4.1c). `clock.transport` handlers in
      `Canopy.lua`; `rambler.resync` so a Start does
      not flush what a Stop froze; `gparam`'s BPM row becomes a readout under
      an external source.
    - **Inspect dimming** (§5.1b). An open cell page dims the panel to that
      cell and its cables.
    - **Output-row exclusivity** (§2.1). `patch.lua`'s `displace_output`: a
      source cabled to a second Out cell moves rather than fans out. Regrow's
      "sometimes a second Output cable" branch dropped with it.
    - **The mixer** (§4.1b). Three more soundscape loops beside Rain, a page
      of faders of their own on `K3`, `\wl_rain` generalised into four
      `\wl_amb`s over one shared bus — and the old Excite path removed
      rather than multiplied by four.

12. **The interface pass.** Nine changes, all of them about the panel being
    legible and aimable rather than about what it can make. In order:
    - **Descriptions** (§5.3). Every cell's line in `lexicon.lua` and every
      pair's line in the §6 matrix rewritten: the effect first, in the
      plainest word available, and no dash standing in for a clause. Six type
      pairs that had no line at all were given one.
    - **LFO parameter targeting** (§2.12). An LFO's page gains **Depth**,
      **Target** and **Param**: pick one of the cells it is cabled to and one
      row of that cell's own settings page, and the LFO moves that knob.
      Implemented entirely in Lua at control rate (`lfo.apply`, on a 40 Hz
      metro) rather than as new buses — every page in the script is the same
      get/set/push object, so read-base, set-modulated, push, write-base-back
      reaches every parameter on the panel instead of the four that had a
      bus. `Param = "signal"` is the old audio-rate behaviour and the
      default; `dispatch.lua` drops its own spec for a pair the LFO is
      modulating, so a cable is never heard twice.
    - **Named families on the header** (§5.2c). The one-letter panel code in
      front of a cell's name becomes a word: `Voice: Oak`, `Trigger: Hob`,
      `Process: Tangle`, `Exciter: Ember`. `topology.family` /
      `topology.label` own the mapping; a cell already named for its family
      gets no prefix.
    - **Numbered families** (§2.9, §2.11). Twelve cells of one mechanic are
      `Gust 1`–`Gust 12` and four are `Clock 1`–`Clock 4`. The ids are
      unchanged, so saved patches still load.
    - **Renames** (§4.1). Scatter is **Rain** and Drops is **Plonks** on the
      global page. The state keys are unchanged for the same reason the cell
      ids are.
    - **Gust cross-modulation** (§2.11, §8). `Cross` was inaudible: a gust's
      output tap is scaled for a mix (`env * amp * 0.3`), so at full Cross it
      bent the receiving gust's pitch by about a fifth of a semitone. The mod
      input is now scaled back up to near unity before the soft-limit, and
      the bend is two octaves rather than a fifth, so two gusts cabled
      together genuinely FM each other.
    - **Clock division** (§2.9). The ratio list runs down to 1/128 of a beat
      instead of stopping at 1/8. The knob is split at its centre — divisions
      below, multiples above — so 1× stays on the middle detent despite the
      list no longer being symmetric.
    - **Sample players replace the heartwood** (§2.5).
    - **The mixer is built from the patch** (§4.1b). No fixed contents: the
      master, then one fader per Output cell something is actually cabled to,
      appearing and disappearing with the cables, capped at sixteen because
      the Output row is sixteen cells long. Each channel is a control-bus
      level read by `\woodland_fx`, distinct from a cable's own gain. The
      gusts' Space/Delay/Regen rows moved to the global page, which is two
      pages now.

13. **The pages pass.** Three changes that are really one change: giving each
    family the page it needs, and letting `K3`/`K2` walk a single stack
    through them (§4.1). In order:
    - **The gusts page** (§2.11b). Five family knobs — Pitch, Timbre, Attack,
      Cross, Level — that move all twelve cells *together*, plus the
      Space/Delay/Regen of the delay line they share, which came off the
      global page's awkward second half. The five are offsets, not values, so
      they preserve whatever spread the player has put between the twelve;
      the per-cell rows report the effective value while `E2` goes on moving
      the cell's own knob. No family Decay, because the global page's Decay
      already reaches every gust — which is what lands the page on exactly
      eight rows, one screen, no seam.
    - **Drums** (§4.1e). The seat the delay rows left free on the global page,
      which is back to eight rows and one screen. A switch saying whether the
      global Plonks, Decay and Pitch reach the six `GVOICE` cells as well as
      the four voices. Off by default, and off now genuinely detaches Decay
      too, which is a behaviour change from when it reached them
      unconditionally.
    - **The Colour page** (§4.4, §8). Eight processors across the master
      output, spliced into `\woodland_fx` between the summed mix and the
      master fader: Tape, Crush, Alias, Loss, Chorus, Swirl, Shape and Comp.
      Every one a genuine bypass at its default, so a patch that never opens
      the page sounds as it did before it existed. One `colour(key, v)`
      command rather than eight named ones. Four new shapes in
      `lib/glyph.lua` (§5.2c) to keep the "no two alike" rule on a page that
      is half degradation.
    - **Swing defaults to 0** (§4.1). A fresh patch arrives straight.
    - **The value line, back** (§5.2d). Every widget on every page prints its
      own reading between the shape and the name, in the parameter's own
      unit, and the edge view prints its cable's gain — which is §5.2c's one
      named cost, paid off. The shape box goes from 26×19 to 26×13 to fit it;
      `word`, `dots`, `stack` and `flag` re-cut for the shorter box;
      `screenui.shorten` gives a long reading up at the unit, then the
      decimals, then whole words, and never at the front. The widget grid
      draws in passes rather than widget by widget, purely so the level calls
      the value line would have cost stay inside the frame budget.

---

## 10. Risks and open decisions

**Risks**

| Risk | Mitigation |
|------|------------|
| Lua pulse jitter (~1-2 ms) | fractional-overshoot latency offset to SC; keep the audible strike scheduled in SC, not the Lua tick |
| CPU ceiling on CM3 | the mode-count knob, lazy exciters, smaller cell counts after the grid overhaul |
| Feedback instability on voice↔voice audio | per-voice DC block + tanh + limiter; conservative default gain on voice↔voice edges |
| Runaway on voice↔voice *pulses* | the 28 ms per-voice refractory, the per-tick emit cap, and the one-tick deferral on every pulse-cell hop |
| A weave chain that multiplies faster than it decays | a weight floor every decaying rule terminates on, a capped pending queue |
| OSC metering flooding | 30 Hz cap, local decay in Lua, drop-tolerant (still unbuilt) |
| Patch becomes unreadable at 30+ cables | patch reveal on hold is the primary reader |
| A silent patch that looks like it should be playing | the Output row makes this the *expected* first-five-minutes experience now, not a bug — the cell view and patch reveal are what teach a new player to look for an O cable |

**Decisions for you**

1. **Grid 128.** Unchanged: the layout needs 16x8, and both re-cuts have
   needed it more than the original design did.
2. **Arc.** Still out of scope for v1.
3. **Regrow.** Still seeds cell settings as well as cables — and now also
   seeds at least one Output cable per voice it uses, or its own "a patch
   that already plays" promise would be silently false.
4. **One-way cables.** Still kept as an advanced escape hatch.
5. **Climate.** Cut outright rather than relocated (§2.9). If a "long game"
   modulator is wanted back, it needs a new letter and new coordinates —
   there is no reserved space for it any more.
6. **Choke.** Cut outright rather than resolved by cable-gain sign (§2.2) —
   the simpler of the two options the grid overhaul considered. If the
   discrete "duck it" gesture is missed in practice, the fallback (positive
   gain strikes, negative gain chokes) is still on the table and touches
   only `dispatch.lua`'s `HANDLERS["voice<-*"]` functions.
7. **Skriker's `swarm` gait.** A specific proposal for Knocker's replacement,
   not a settled one — free to rename or redesign; nothing downstream
   depends on the exact shape.
