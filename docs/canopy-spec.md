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
 2    ·   M   ·   ·   ·   F   F   F   N   N   N   ·   ·   ·   M   ·
 3    ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·
 4    F   ·   ·  TM  TM   C   T   T   T   T   C  TM  TM   ·   ·   H
 5    ·   F   ·   ·   ·   C   T   T   T   T   C   ·   ·   ·   S   ·
 6    E   ·   F   ·   ·   ·   L   L   L   L   ·   ·   ·   S   ·   R
 7    E   E   ·   F   ·   G   G   G   G   G   G   ·   S   ·   R   R
 8    E   E   E   ·   ·   G   G   G   G   G   G   ·   ·   R   R   R

 O = output (16)       M = voice (4)         F = grove field / percussion-ping
 N = percussion-noise  TM = Turing Machine   C = clock (4)
 T = trigger source (8) S = sample player (4) R = weave (6)
 G = gust (12)         L = LFO (4)           E = exciter (6)
 · = unregistered coordinate, dark and inert
```

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
+ 4 F(grove) + 6 R + 6 GVOICE(F/N) + 6 E + 12 G(gust) + 4 L(LFO) = 78 live
cells; 50 dark.

### 2.1 The Output row — O (16)

By default **nothing is heard**. The top row is sixteen output cells; position
along it sets pan, hard left at column 1 to hard right at column 16. Cabling a
voice, a percussion (GVOICE) cell or an exciter to one of these is the only
way its audio ever reaches the speakers — with two deliberate exceptions, the
gusts (§2.11) and the sample players (§2.5), each of which pans itself by
where its cell sits and mixes itself in. There is no other automatic mix left
anywhere in the engine (§7.3, §8).

**The row is exclusive: one source, one slot.** Position along the row *is*
pan, so a source cabled to two O cells is one source at two pan positions at
once — which reads on the panel as a patching mistake and sounds like a
widened, phase-smeared copy of itself nobody asked for. Cabling a source that
is already on the row to a second O cell therefore **moves** it: the cable it
had is pulled first, at the same gain, so the gesture reads as dragging the
source along the row rather than as adding to it. (`lib/patch.lua`'s
`displace_output`; `patch.toggle` returns `"moved"` rather than `"added"` so
the panel can say so.) Everything else about a source's patch is untouched —
it may still fan out to as many non-Output cells as it likes.

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

Two things it shares with a gust (§2.11) rather than with a voice: it is
**heard without an Output cable** — the engine pans it by where the cell sits
and mixes it in — and it holds its own Level, because there is no Output
cable whose gain would otherwise be deciding that. It emits no answering
pulse: a swell measured in seconds is not an event anything downstream could
be timed against, and a family with no pulse out cannot be half of a feedback
loop.

**What was here before.** These four seats were the **heartwood**, a
diffusion lattice: a pulse injected at one node spread outward with a per-hop
delay and loss and emerged from the others later and quieter, under a single
"conductance" knob standing in for both quantities at once. It was the
hardest family on the panel to hear the shape of and the hardest to aim, and
it is cut outright — `lib/heartwood.lua`, `\wl_heartwood`, the `heart_in` /
`heart_out` bus families and every H pair in the §6 matrix with it. The four
recordings these cells play are the same four the mixer used to run as an
always-on bed (§4.1b); they are played now rather than left running.

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

Unchanged in every respect except coordinates. Four independent 8-bit
shift-register sequencers, no phase or gait of their own — the only thing
that ever moves a register is a pulse cabled into it.

| Cell   | Name       | Counterpart |
|--------|------------|-------------|
| (4,4)  | Padfoot    | Tatterfoal  |
| (5,4)  | Barghest   | Puck        |
| (12,4) | Puck       | Barghest    |
| (13,4) | Tatterfoal | Padfoot     |

Each incoming pulse shifts the register (with Prob/Drift/Bias deciding
whether the falling-off bit loops or a fresh Bias-skewed coin is flipped),
updates the pitch it feeds to any voice it's cabled to (Bits summed,
binary-weighted, scaled by Range, snapped, then summed alongside whatever
fields are also reaching that voice — the socket collapse changed *how* that
cable is made, not what it does once it lands), and answers with a pulse of
its own if the Tap-selected bit reads high. Eight parameters, one sound page,
unchanged (§5.5-shaped, same eight rows: Length, Prob, Drift, Bias, Range,
Bits, Tap, Level).

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
| Decay  | 0.05 – 30 s; rides `state.decay`, so the global Decay macro reaches it |
| Timbre | how hard the triangle is folded: flute at 0, horn at 1 |
| Cross  | how deeply whatever is cabled in modulates this gust |
| Level  | this cell's own level in the mix |

Two things a gust does that nothing else except a sample cell (§2.5) does.
**It is heard uncabled** — the engine pans it by the column it sits in and
mixes it in, through one delay line shared by all twelve (Space / Delay /
Regen on the global page). An Output cable is still allowed and still means
what it means; it just places a second copy. And **its pitch is not its
own**: the cell's seat plus its Pitch knob is pulled onto the global Scale
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

### 2.12 The LFOs — L (4, internally type `LFO`)

Four free-running sines on the row directly above the gusts. No sound of
their own; a cable out of one is the whole point.

| Row | What it does |
|--------|--------------|
| Speed  | 0.02 – 20 Hz, log-mapped |
| Depth  | how far it swings the chosen knob, either side of where you left it |
| Target | which of the cells this LFO is cabled to it is aimed at |
| Param  | which row of *that cell's* settings page it moves |

**Param decides what kind of thing the cable is.** Its first entry is
`signal`, and on `signal` the cable is an ordinary audio-rate one:
`dispatch.lua` builds the same spec any other continuous source would get
(into a voice's mod path, an exciter's colour, a gust's cross-mod input, or
an Output cell, where a Speed up in the audio range is heard as a plain
tone). Pick any other entry and the cable stops being audio entirely: Lua
moves that named knob instead, and dispatch drops its own spec for the pair
so the cable is never heard twice.

**How the knob is moved.** Every settings page in the script is the same
object — a list of rows with `get` / `set` / `push` — so modulating one needs
no new machinery: read the base value, set the modulated one, push it, write
the base straight back (`lfo.apply`, on its own 40 Hz metro in `Canopy.lua`).
The stored number never moves, so the screen keeps showing where the player
left the knob and turning it still works while the LFO runs. It costs one OSC
message per LFO per frame — what turning one encoder costs — and it reaches
every parameter on the panel rather than the four families that had a bus.
Changing Target or Param puts the knob it was holding back where the player
left it.

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
| E1 | pick one of seven global params (§5.2) |
| E2 / E3 | nudge the picked param, coarse / fine |
| K1 + E3 | Master level |
| K3 | **the mixer** (§4.1b) — from anywhere, including an open cell page, whose focus it drops on the way; a second K3 goes on to **the map** (§4.1d), and a third back to the mixer |
| K2 | **back** — off the mixer or the map, or out of an open cell page, to the main screen; on the main screen, **Still** |
| K1 + K2 | **Regrow** — a seeded patch that already plays (hold to confirm) |
| K1 + K3 | **Clearing** — cut every cable (hold to confirm) |

**The ten global params** (`lib/gparam.lua`), in E1 order: BPM, Swing, Rain,
Scale, Plonks, Decay, Pitch — then the gusts' shared delay line, Space,
Delay and Regen, on a second page. It was nine, then seven when Rain and
Excite left for the mixer, and ten again when the delay line came back from
it (§4.1b).

Two of these are renamed and nothing else about them changed. **Rain** was
Scatter: it is the knob that makes everything land a little off the grid and
then a lot, which is what weather does to a rhythm, and "scatter" named the
mechanism rather than the sound. **Plonks** was Drops, for the same reason.
The state keys are unchanged (`scatter`, `drops`) — five other files read
them, and the rename is of the word on the panel, not of the mechanism.

**K2 and K3 are one shallow stack**, not a different pair of jobs per page.
K3 steps down from the main screen into the mixer, then the map (§4.1d),
trading the two back and forth from there rather than adding a third level;
K2 always comes back up to the main screen in one press, off either one.
Still keeps K2 because the main screen is the one place with nothing to
come back from, and freezing the patch is a fair reading of "there is
nothing above this". K3's old job — closing a cell page — is K2's now, along
with everything else that means "up one", checked first so an open cell page
closes before the mixer/map step does.

**Regrow** always wires exactly one Output cable per voice it uses, or a
freshly regrown patch would strike voices nobody can hear — the whole point
of the gesture ("a patch that already plays") depends on it. Exactly one, not
one-or-two: the row is exclusive (§2.1), so a second would only move the
first.

### 4.1b The mixer page — K3

The master, then **one fader for every Output cell the patch is actually
using** (`lib/mixer.lua`). The page has no fixed contents: cable a source to
Out 5 and Out 5 appears; pull that cable and it goes. An unpatched patch is
one fader and a lot of space, which is the honest picture; a fully patched
one is sixteen, which is the cap because the Output row is sixteen cells
long. `E1` picks a fader, `E2`/`E3` move it coarse/fine — the same page shape
as §5.2 and §5.5.

The master is first rather than last: it is the one channel that is always
there, and a list whose contents change under you wants a fixed thing at the
top for the cursor to come back to. It is the same number `K1`+`E3` has
always moved, given a face. A channel appears at unity, not at zero — a fader
that materialised silent would read as the cable not having worked.

**A channel fader and a cable's gain are different things.** A cable's gain
says how much of *that source* arrives at *that* pan position; several
sources can land on one Out cell. The fader is the channel: everything
arriving there, together, after the fact. It is the knob you reach for when
one side of the image is too loud, which is not a question about any one
cable. Engine side it is one channel of a control bus read by
`\woodland_fx` (`out_level(i, v)`), lagged and squared, so a fader can be
set one channel at a time.

**What used to be here.** Four always-on soundscape loops — Rain, Cicada,
Thunder, Sea — with a fader each, plus the master, plus the gusts' shared
delay line, which together came to exactly eight rows and one screen. The
loops are the four sample cells now (§2.5), played rather than left running;
the delay line went to the global page, where the rest of the patch-wide
numbers already were. What is left is the one thing a mixer is actually for.

The four recordings still load once each at init, at the same engine indices
— they belong to `sample.init` rather than to this page now. The old
**Excite** knob (the same rain audio fed continuously into every voice's
resonator) has no successor at all: the six E cells (§2.4) are the panel's
excitation sources, and `\woodland_voice` is excited only by its own strike
burst and by whatever a cable puts on its mod path.

Engine side: `smp_load(i, path)`, `smp_note(i, force)` and the four knob
setters, with one `\wl_smp` synth per cell summing into a single shared
stereo `smpBus` that `\woodland_fx` reads. Level and pan are applied inside
each `\wl_smp` rather than at the reader, so four cells cost one bus. Every
knob is held engine-side whether or not that cell's `Buffer.read` has
completed, so pushing a whole page at init — which `sample.init` does —
loses nothing; a missing file simply leaves that one cell silent and does not
touch the other three.

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

### 4.1d The map page — K3, again

`K3` a second time (from the mixer) goes on to the map: every registered
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

A third `K3` goes back to the mixer: once off the main screen, `K3` alone
walks back and forth between the two rather than stacking a third level, and
`K2` still comes all the way back up to the main screen from either one.

### 4.2 Holding a grid cell

| Control | Function |
|---------|----------|
| E1 | select which cable at this cell is focused (ALL → 1..n) |
| E2 | the cell's **character** parameter (see below) |
| E3 | attenuvert — focused cable's gain, or that sound's **decay** when ALL is selected |
| K1 + E2 | swap the rule this cell runs on (T: gait, R: rule, F: mode) |
| K2 + K3 | sever all cables at this cell |

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

---

## 5. Displays

### 5.1 Grid brightness (0-15)

| Cell | Idle | Live |
|------|------|------|
| O | 1 unpatched, 5 patched | — a pure destination, no flash of its own |
| Voice | 3 unpatched, 6 patched | 12 while its sound page is open |
| T | 3 | flash 15 on pulse, decay ~120 ms; base rises with coupling strength |
| R | 2 | base rises with how much is cabled through it; flashes on the way *out* |
| GVOICE | 2 unpatched, 4 patched | 10 while its sound page is open; flash on being struck |
| E | 3 unpatched, 5 patched | flash on a grain firing, decay ~120 ms |
| H | 2 | local lattice energy |
| F | 2 | where the field currently sits; flash on each step |
| C | 2 | flash on each clock crossing — a pure flasher, no idle "value" reading |
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

`lib/gparam.lua`'s seven global macros, drawn as §5.2c's widget grid. `E1`
walks the list, `E2` moves the picked param coarsely and `E3` finely. Seven
fits on one page.

### 5.2b Screen — the widget grid

Every full-screen page in the script — global (§5.2), mixer (§4.1b), and
every cell page (§5.3, §5.5) — is drawn by one routine in `lib/screenui.lua`,
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
alike.** `lib/glyph.lua` holds the vocabulary — twenty-two shapes, one named
by each row's own `glyph` field. A Decay draws a falling tail and the tail
gets longer; a Prob draws a field of dots and the field gets denser; a Length
draws a row of steps and more of them light; a Tap draws the eight bits of
the register and points at the one it reads.

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
a block the shape occupies the first 19 rows and the label's baseline is at
26, so the ascenders start two pixels below where the shape stops and the
bottom row's descenders land on 63. Four columns of 32; the shape is 26 wide,
inset 3 either side.

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
accumulate, the fill is what costs. The measured cost of a full page is 145
commands on the global page, 147 on a voice's, 124 on the mixer.

**What it costs.** There is now nowhere on the panel to read an exact number.
You can set Tune by ear but not to `+3.00 st`, and you cannot match two cells
by eye — the mixer's Delay row, whose whole point was a millisecond figure
you match to the tempo, is where that bites hardest, and it is left
consistent with everything else rather than made an exception, because one
row that prints a number is a row that looks broken. If the exception is ever
wanted, the cheap version keeps all of the above: show the value in the
header's name slot **only while an encoder is actually turning**, and let it
fall back to the name a second later.

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
- **D** — the gait's phase as a sweeping bar with its cycle ticked. A metric
  gait sweeps evenly and a swung or euclidean one does not, so the bar says
  which you are on without reading the word. `rambler.info(id).phase`.

A type with no scope keeps its sentence, which is what lets the rest land one
family at a time.

`test/screen.lua` is the authority on the geometry: two words may never share
pixels; a word may sit inside a box but never inside a shape, and never
half-clipped by anything. It also asserts that every row names a shape, that
the shape exists, and that **no page shows the same shape twice** — the two
exceptions are named there, the mixer (five faders in a row is what a mixer
looks like; the repetition is the reading) and a D cell's Gait and Grid,
which are both words and have no other shape to be.

`test/render.lua` is the other half: it rasterises the real `screenui.lua`
into a PGM per view, so the drawing can be looked at without a norns on the
desk. It asserts nothing — geometry tests cannot tell you whether a Decay
looks like a decay.

### 5.3 Screen — Cell view (a cell held or open)

The same widget grid as §5.2c, for whichever page that cell's type has
(`lib/cellparam.lua`, or `voice`/`gvoice`/`tm`'s own). The header's tag
carries the panel letter and its dots the page number. Holding is a glance —
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
it, without taking the encoders off the patch — unchanged. Twelve parameters
is the only list in the script long enough to paginate on §5.2c's eight-wide
grid.

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
| **TM** cell | clocks the shift register one step; answers with a pulse of its own if the Tap bit reads high afterward — §2.8 |
| **GUST** cell | plays its note; answers with a pulse of its own a tick later — §2.11 |
| **SMP** cell | plays its recording from the top; answers with nothing — §2.5 |

**Streams** (live SC synths for as long as the cable exists):

|            | Voice (mod path) | E (exciter) | GUST (cross-mod in) |
|------------|-------------------|-------------|----------------|
| **Voice**  | the other voice's own audio, unconditionally (§2.2) | the voice's audio colours the exciter | the voice bends the gust's core |
| **E**      | the stream drives the body or excites it, per Balance | cross-modulation: each modulates the other's colour | the exciter bends the gust's core |
| **GUST**   | the gust drives the voice's mod path | the gust rides the exciter's colour | cross-modulation: each FMs the other (§2.11) |
| **LFO**    | on `Param = "signal"` only — otherwise it moves a named knob instead (§2.12) | as above | as above |

**To an Output cell** — a source's own audio, panned at that O cell's fixed
position (§2.1): a voice, a GVOICE cell, an E cell, a gust or an LFO can all
reach one. Nothing else can, and an O cell never talks back. A gust already
mixes itself, so a cable there is a second, deliberately-placed copy; a
sample cell mixes itself and has no Output cable at all.

**Neither** — the families that carry a number rather than a pulse or a
stream:

| Pair | Meaning |
|------|---------|
| **F → voice** | the field tunes it; the voice's own Depth knob (§5.5) scales it, and negative gain inverts the contour |
| **F → E** | the exciter's Colour rides the field's line |
| **F ↔ F** | the two fields pull together (apart, at negative gain) |
| **TM → voice** | the register's own pitch tunes it, summed alongside whatever fields are also cabled there |

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
- **A TM cell cabled straight to a voice carries both halves of §2.8 at
  once**, and neither shadows the other: the pulse half (this table, above)
  fires whenever the TM cell's own answering pulse happens to be routed
  there, striking the voice exactly as any other pulse source would; the
  number half is a live, always-on contribution to that voice's tuning, read
  fresh every time the voice retunes for any reason at all.
- **T↔T at negative gain** produces anti-phase locking.
- **R↔R** is transforms in series, and the chain *is* the pattern.
- **F is a source only.** A field never emits a pulse and never writes a
  stream, so its whole column is one-way.
- **C is a source only** (§2.9) — the same "cables are undirected, so a
  reactive pulse-in would fire on the return leg of the ordinary use" reason
  climate always had, kept even though climate itself is gone.
- **GVOICE behaves as its own pulse source**, the same as an R cell — a Clock
  cell cannot reach it with anything but a pulse (no single knob to walk, and
  there's no weather left to walk it with anyway), and a GVOICE cell is not a
  target for a field either (both cables are legal to draw and mean nothing).
- **Gusts and drums chain freely** — either answers its own trigger with a
  pulse a tick later, so one can drive the next, and a cycle between two is
  safe by the same one-tick construction as a T↔T cable. A sample cell
  deliberately does not answer, so it can only ever be the end of such a
  chain.

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
    tm.lua                   -- the four TM-cell shift-register sequencers +
                               their eight-parameter page (§2.8)
    clockcell.lua            -- the four C-cell clock flashers (§2.9)
    quantise.lua             -- the groove: Swing/Rain place a gait's emission
    exciter.lua              -- E-cell control layer (audio side lives in SC)
    sample.lua               -- the four S-cell sample players (§2.5)
    gust.lua                 -- the twelve G-cell drone synths (§2.11)
    lfo.lua                  -- the four L-cell sines, and what each moves
    grove.lua                -- pitch fields: modes, coupling, voice retuning
    voice.lua                -- the eleven-parameter voice sound page (§5.5)
    gvoice.lua               -- the six GVOICE-cell drums + their sound page
    gparam.lua                -- the ten-parameter global page (§4.1, §5.2)
    mixer.lua                 -- master + one fader per live output (§4.1b)
    gridui.lua                -- grid render + hold/tap state machine
    screenui.lua              -- the widget grid (§5.2c): global / mixer /
                                 cell / edge views, plus the map (§4.1d)
    glyph.lua                 -- the shape vocabulary (§5.2c): one drawn
                                 shape per parameter, named by its `glyph`
    bridge.lua                -- engine command wrapper
  lib/Engine_Canopy.sc      -- SC: modal voices, GVOICE drums, exciters, the
                               gusts and their delay line, the four sample
                               players, the sines, the patch matrix, the
                               Output row's fixed-pan mix
  audio/*.wav               -- Rain, Cicada, Thunder, Sea: one per S cell
  README.md
```

**One door for every pulse.** Unchanged: a T cell wrapping, an R cell passing
something on, a voice/GVOICE/TM/GUST answering — all go out through
`rambler.emit_from`, so trails, the fan-out cap and the one-tick deferral
that makes cycles safe are written exactly once.

**Module loading.** Unchanged — `wl()`, defined in `Canopy.lua`.

### 7.2 Lua / SC split

Unchanged. **Lua owns:** the patch graph, all pulse generation, coupling and
transformation, the grove's pitch fields, the clock cells, the LFOs'
knob-targeting half (§2.12), all UI. **SC owns:**
every sample of audio, the audio-rate patch matrix, and continuous
modulation.

### 7.3 SC bus topology

```
groups:  gSrc -> gPatch -> gVoice -> gTap -> gFx

ambBus          2  the four ambience loops' shared dry sum (§4.1b).
                   each \wl_smp applies its own Level and pan before writing
                   here, so four sample cells cost one bus. read only by
                   \woodland_fx -- nothing feeds a voice from it.

patchBus        6  exciter outputs        (excBase         0)
                6  per-E colour-mod sums  (colourModBase   6)
                4  per-voice mod path in  (modInBase      12)
                4  per-voice audio tap    (voiceOutBase   16)
                6  per-GVOICE audio tap   (gvoiceOutBase  20)
               16  Output row (§2.1)      (outBase        26)
               12  per-GUST audio tap     (gustOutBase    42)
               12  per-GUST cross-mod in  (gustModBase    54)
                4  per-LFO sine tap       (lfoOutBase     66)
               --
               70  total
```

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

These are **audio** buses throughout, including the modulation ones, for the
same summing reason as before. Keep every offset identical to `bridge.BUS`
on the Lua side.

Patch synths, instantiated per cable, live in `gPatch`, unchanged:
`\wl_patch_aa` (straight pass) and `\wl_patch_ak` (amplitude-follow).
`InFeedback`, not `In`, on the source side, for the same order-independence
reason as always. `\woodland_fx` itself reads `outBus` with a plain `In.ar`
— `gFx` runs after `gPatch`, so this block's writes are already there.

### 7.4 Metering back-channel

Unchanged: still unbuilt, still the shape described before the overhaul.

### 7.5 Persistence

Unchanged mechanism. Graph format: a flat list of `{a_id, b_id, gain,
oneway}` plus per-cell character values, per-cell rule choices (gait / rule
/ mode, and the rooted / snap flags), each LFO's Target and Param, the mixer's
per-output levels, and the sound-page parameters per voice, GVOICE cell, TM
cell, gust and sample cell.
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
```

`voice_choke` and `voice_tap` are gone — the socket collapse (§2.2) removed
both discrete choke and the separate per-voice output-level knob.
`rain_load`/`rain_volume`/`rain_excite` are gone too, and so are the
`amb_load`/`amb_volume` pair that briefly replaced the first two: the
recordings belong to the sample cells now (`smp_load`, `smp_note`,
`smp_attack`, `smp_decay`, `smp_speed`, `smp_level`, `smp_pan`), and
`rain_excite` has no successor at all. `heart_conductance` is gone with the
heartwood; `out_level` is new (§4.1b).

**CPU budget.** 4 voices x 6 modes = 24 resonators, plus 6 always-on GVOICE
cells and up to 6 exciters (lazily allocated), ~50 patch synths worst case,
12 gusts and their shared delay line, 4 sines, and 4 sample players. Smaller
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
