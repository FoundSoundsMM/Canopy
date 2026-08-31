# WOODLAND — design & implementation spec

A monome norns script for grid (128). Four modal/pinged-filter voices, a
sealed core of pulse-makers and clocks, small percussion cells, weave
transforms, a heartwood lattice, pitch fields and step sequencers, patched by
hand, with an explicit Output row deciding what is ever heard at all.
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
   — except the two Q4/Q6 lanes (§2.10), which are deliberately the one
   place on the panel that *is* step data, because a shift register and a
   phase oscillator don't cover everything a step ever wants to mean.
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
 5    ·   F   ·   ·   ·   C   T   T   T   T   C   ·   ·   ·   H   ·
 6    E   E   F   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   H   ·   R
 7    E   M   ·   F   ·  Q4  Q4  Q4  Q4   ·   ·   ·   H   R   M   R
 8    E   E   E   ·   ·  Q6  Q6  Q6  Q6  Q6  Q6   ·   ·   R   R   R

 O = output (16)       M = voice (4)         F = grove field / percussion-ping
 N = percussion-noise  TM = Turing Machine   C = clock (4)
 T = trigger source (8) H = heartwood (4)    R = weave (6)
 Q4/Q6 = step sequencers                     E = exciter (6)
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

**Cell counts.** 16 O + 4 voice + 8 T(D) + 4 TM + 4 C(clock) + 4 H + 4 F(grove)
+ 6 R + 6 GVOICE(F/N) + 6 E + 10 SEQ(Q4/Q6) = 72 live cells; 56 dark.

### 2.1 The Output row — O (16)

By default **nothing is heard**. The top row is sixteen output cells; position
along it sets pan, hard left at column 1 to hard right at column 16. Cabling a
voice, a percussion (GVOICE) cell, an exciter or a heartwood node to one of
these is the only way its audio ever reaches the speakers — there is no
automatic mix left anywhere in the engine (§7.3, §8).

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
  Q4/Q6 step, a GVOICE answer, or another voice) always **strikes** it, force
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
T/R cables only, deliberately — a heartwood or voice cable's usual meaning is
diffusion or colouring, not gating.

### 2.5 Heartwood — H (4)

Not a bus. A **diffusion lattice**. Trimmed from a ring of 8 to a simple
**chain of 4** for the grid overhaul — fewer cells, and a chain rather than a
ring is the natural shape for that few. Signals injected at one node spread
outward with a per-hop delay and loss, emerging from the other nodes at
different times and amplitudes. Both pulses and streams diffuse.

```
(16,4) Taproot -- (15,5) Mycel -- (14,6) Wyrd -- (13,7) Ley
```

Taproot and Ley are the two ends of the chain (one neighbour each); Mycel and
Wyrd each have two. Per-node **conductance** (E2 while holding) still sets
local hop delay and loss the same way it always did. A H↔H cable adds a
shortcut edge on top of the chain — the diffusion lattice a pulse walks is
the chain plus whatever the player has patched.

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

### 2.10 Step sequencers — Q4 / Q6 (10, internally type `SEQ`, new)

Two lanes, four and six physical cells respectively, modeled directly on the
TM cells' shape: no phase of its own, no free clock — the only thing that
ever moves either lane is a pulse cabled in.

| Lane | Cells |
|------|-------|
| Q4 | (7,7) (8,7) (9,7) (10,7) |
| Q6 | (6,8) (7,8) (8,8) (9,8) (10,8) (11,8) |

Both lanes are centred on the sixteen-column panel, Q4 sitting symmetrically
inside Q6 — a 4-cell lane starts at column 7 and a 6-cell lane at column 6.

Each of the physical cells in a lane is independently a cable endpoint *and*
independently switchable on and off (a UI toggle, not a cable —
`state.step_active`). Two gestures reach it, and they are the same two that
reach every other per-cell setting on the panel: `K1` + tap the cell, which
is the panel-wide "fire this cell" gesture, or the **Step** row on its
settings page, which is deliberately row one.

A step's three states — empty, armed, and under the playhead — are spread
across the grid's brightness range rather than bunched at the bottom, so a
running lane is visibly running; the driver cell also reads a notch above an
ordinary empty step, since it is the one cell in the lane a cable has to land
on for the playhead to move at all.

The **last** cell of each lane is the **driver**: a pulse there advances the
lane's shared playhead by one step and, if the step it lands on is active,
fires a pulse from that step's own cell — the traditional "clock the whole
sequence" gesture. A pulse on any **other** cell in the lane fires that one
step directly and immediately, if it's active, independent of the playhead
entirely — patching a trigger straight into an individual step overrides it.
Both directions go through the shared pulse door (`rambler.emit_from`), and
`SEQ` is a member of `topology.PULSE_TYPES`, so a pulse arriving at any cell
in a lane gets the same one-tick inbox deferral every other pulse-cell target
does — a cable into or out of a lane is safe from runaway by the same
construction as everywhere else on the panel.

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
| Tap a **SEQ** cell (nothing else held) | toggle that step active/inactive |
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
| K3 | **the mixer** (§4.1b) — from anywhere, including an open cell page, whose focus it drops on the way |
| K2 | **back** — off the mixer, or out of an open cell page, to the main screen; on the main screen, **Still** |
| K1 + K2 | **Regrow** — a seeded patch that already plays (hold to confirm) |
| K1 + K3 | **Clearing** — cut every cable (hold to confirm) |

**The seven global params** (`lib/gparam.lua`), in E1 order: BPM, Swing,
Scatter, Scale, Drops, Decay, Pitch. It was nine: Rain and Excite left when
the one rain loop became four (§4.1b).

**K2 and K3 are one shallow stack**, not a different pair of jobs per page.
K3 goes down into the mixer from wherever you are; K2 comes back up one
level. Still keeps K2 because the main screen is the one place with nothing
to come back from, and freezing the patch is a fair reading of "there is
nothing above this". K3's old job — closing a cell page — is K2's now, along
with everything else that means "up one".

**Regrow** always wires exactly one Output cable per voice it uses, or a
freshly regrown patch would strike voices nobody can hear — the whole point
of the gesture ("a patch that already plays") depends on it. Exactly one, not
one-or-two: the row is exclusive (§2.1), so a second would only move the
first.

### 4.1b The mixer page — K3

Four always-on soundscape loops (`lib/mixer.lua`), each a stereo field
recording under `audio/`, each looping from init regardless of anything else
on the panel, each with its own fader — plus the master, which is the same
number `K1`+`E3` has always moved, given a face.

| Fader | Sample | Engine index |
|-------|--------|--------------|
| Rain | `audio/Rain.wav` | 0 |
| Cicada | `audio/Cicada.wav` | 1 |
| Thunder | `audio/Thunder.wav` | 2 |
| Sea | `audio/Sea.wav` | 3 |
| Master | — | — |

All four start at 0, so the script says nothing until it is asked to. `E1`
picks a fader, `E2`/`E3` move it coarse/fine — the same page shape as §5.2
and §5.5.

**They are a dry mix and nothing else.** The old **Excite** knob — the same
rain audio fed continuously into every voice's resonator, whether or not
anything was patched — is gone rather than multiplied by four. These are
soundscapes to sit the patch inside; the six E cells (§2.4) are still the
panel's excitation sources, and `\woodland_voice` is back to being excited
only by its own strike burst and by whatever a cable puts on its mod path.

Engine side: `amb_load(i, path)`, `amb_volume(i, v)`, and one `\wl_amb`
synth per loop summing into a single shared stereo `ambBus` that
`\woodland_fx` reads. Each fader is applied (squared, and lagged) inside its
own `\wl_amb` rather than at the reader, so four loops cost one bus. The
faders are held engine-side whether or not that loop's `Buffer.read` has
completed, so pushing them at init — which `mixer.init` does — loses nothing;
a missing file simply leaves that one loop silent and does not touch the
other three.

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
| Start | un-Still, and both sequencer lanes (§2.10) go back to before their first step, so the next driving pulse lands on step 1 |
| Reset (song-position jump, no stop) | the lanes only; nothing freezes |

Stop being Still — the *same flag* `K2` writes, not a parallel record of its
own — is what makes a remote stop and a local freeze the same state, which is
the only way the two can never disagree. `K2` resumes from an external stop
for the same reason. The one thing Start has to do beyond clearing the flag is drop the
scheduled/inbox/source queues (`rambler.resync`): `tick()` returns *before*
those drains while Still, so a stop leaves entries sitting there with
timestamps already in the past, and without clearing them the first tick
after a Start would fire the lot in one block.

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
| SEQ | — no character knob; a plain tap toggles the step instead | — |
| O | — a pure destination; nothing to turn | — |
| T cell | rate / clock relation | gait-dependent |
| R cell | the transform's own amount | rule-dependent |
| E cell | **Colour** — the source's filter/character | 0..1 |
| H cell | **Conductance** — hop delay and loss | 0..1 |
| F cell | **Range** — how far the field roams (25 cents .. 2 octaves) | 0..1 |
| C cell | **Ratio** — multiple/division of the master clock | 1/8x .. 8x |

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
| T / R / H / F / C / TM / SEQ / O | nothing — no sound of their own | — |

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
| SEQ | 2 | +2 while the step is active, +4 while the playhead is on it; flashes on firing |
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

`lib/gparam.lua`'s seven global macros, drawn as §5.2b's widget grid. `E1`
walks the list, `E2` moves the picked param coarsely and `E3` finely. Seven
fits on one page.

### 5.2b Screen — the widget grid

Every full-screen page in the script — global (§5.2), mixer (§4.1b), and
every cell page (§5.3, §5.5) — is drawn by one routine in `lib/screenui.lua`,
and it is not a list any more.

It used to be: a two-column list of `label ....... value` rows with a
hairline bar under each. That was compact, and it read like a settings menu —
rows of small type you parse left to right, one at a time, while the thing
you are editing is making noise. An Elektron box solves the same problem the
opposite way round: a title bar that never moves, and then a fixed grid of
widgets, each showing its value as a *shape* you read at a glance and its
name as a word underneath. You look at the grid, not at the rows.

**The header bar.** Inverted — a filled bar with the text knocked out of it,
which is what makes it read as a title rather than as one more row. Eleven
pixels, and always the same six things in the same places:

| | |
|-|-|
| transport | a filled triangle running, a filled square frozen. Still and an external Stop are the same state (§4.1c), so one glyph reports both |
| tag chip | two or three characters saying what kind of page this is: a cell's panel letter, `MIX`, `G` |
| page dots | one per page, filled for the one you are on — eight pixels where "1/2" would cost twenty |
| name | the page's name, or — for a few seconds after anything happens — what just happened |
| value | the full, untrimmed reading of whatever the cursor is on: the one thing on the screen that is never abbreviated |
| tempo chip | inverted again, at the right edge. `ext` when something else is deciding it |

**The grid.** 4 × 2, eight to a page, a longer list paginating rather than
wrapping back over itself.

- a parameter whose reading is a **quantity** draws as a **knob**: a circle,
  a bright arc from the start of a 270° sweep to the value, and a radial
  pointer. Three strokes and no more than three — at fifteen frames a second
  eight of these plus a header is the whole screen budget.
- a parameter whose reading is a **word** — a gait, a scale, on/off — draws
  as a **boxed readout** instead, filled and inverted when focused, outlined
  when not. A pointer angle tells you nothing about "euclidean".
- which one a parameter gets is decided from its text at draw time (does the
  reading start with a digit, a sign, or the decay multiplier's `x`?), not
  from a flag on the parameter. That keeps the one page contract every module
  already shares, and a row that changes from a number to a word — Scale's
  `free` at position zero — changes widget with it.
- the label under each widget is the parameter's name, clipped to the column.
  The value is never clipped: it is in the header in full.

**Four columns, not the Digitakt's five.** At five a column is 25px, and 25px
of this font is four or five characters — which turns both `Scatter` and
`Scale` into `Sca.`, two adjacent parameters that now read identically. 32px
fits the longest label the panel has. It also means eight to a page rather
than ten, which lands every page in the script except a voice's twelve on one
screen.

`test/screen.lua` is the authority on the geometry: two words may never share
pixels; a word may sit inside a box (the header bar, a chip, a widget's
readout) but never inside a knob gauge, and never half-clipped by anything.

### 5.3 Screen — Cell view (a cell held or open)

The same widget grid as §5.2, for whichever page that cell's type has
(`lib/cellparam.lua`, or `voice`/`gvoice`/`tm`'s own). The header's tag chip
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
is the only list in the script long enough to paginate on §5.2b's eight-wide
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
| **SEQ** cell (driver) | advances the lane's shared playhead; if the new step is active, fires a pulse from it |
| **SEQ** cell (non-driver) | if that step is active, fires a pulse from it directly, independent of the playhead |

**Streams** (live SC synths for as long as the cable exists):

|            | Voice (mod path) | E (exciter) | H (heartwood) |
|------------|-------------------|-------------|----------------|
| **Voice**  | the other voice's own audio, unconditionally (§2.2) | the voice's audio colours the exciter | the voice pours into the wood |
| **E**      | the stream drives the body or excites it, per Balance | cross-modulation: each modulates the other's colour | the stream diffuses through the lattice, and what the lattice makes of it comes back as colour |
| **H**      | the lattice returns into the voice | — | direct link — short-circuits two lattice points, adds a shortcut path |

**To an Output cell** — a source's own audio, panned at that O cell's fixed
position (§2.1): a voice, a GVOICE cell, an E cell, or an H cell (its
emergence) can all reach one. Nothing else can, and an O cell never talks
back.

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
- **SEQ cells chain freely** — one lane's firing step can drive or fire a
  step in another lane, deferred a tick like every other pulse-cell pair, so
  a cycle between two lanes is safe by the same one-tick construction as a
  T↔T cable.

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
    sequencer.lua            -- the Q4/Q6 step-sequencer lanes (§2.10)
    quantise.lua             -- the groove: Swing/Scatter place a gait's emission
    exciter.lua              -- E-cell control layer (audio side lives in SC)
    heartwood.lua            -- diffusion lattice
    grove.lua                -- pitch fields: modes, coupling, voice retuning
    voice.lua                -- the eleven-parameter voice sound page (§5.5)
    gvoice.lua               -- the six GVOICE-cell drums + their sound page
    gparam.lua                -- the seven-parameter global page (§4.1, §5.2)
    mixer.lua                 -- the four soundscape loops + master (§4.1b)
    gridui.lua                -- grid render + hold/tap state machine
    screenui.lua              -- the widget grid (§5.2b): global / mixer /
                                 cell / edge views
    bridge.lua                -- engine command wrapper
  lib/Engine_Canopy.sc      -- SC: modal voices, GVOICE drums, exciters, patch
                               matrix, heartwood, the four ambience loops,
                               the Output row's fixed-pan mix
  audio/*.wav               -- Rain, Cicada, Thunder, Sea: the mixer's loops
  README.md
```

**One door for every pulse.** Unchanged: a T cell wrapping, an R cell passing
something on, a voice/GVOICE/TM/SEQ answering — all go out through
`rambler.emit_from`, so trails, the fan-out cap and the one-tick deferral
that makes cycles safe are written exactly once.

**Module loading.** Unchanged — `wl()`, defined in `Canopy.lua`.

### 7.2 Lua / SC split

Unchanged. **Lua owns:** the patch graph, all pulse generation, coupling and
transformation, the heartwood lattice's discrete-event side, the grove's
pitch fields, the clock cells, the sequencer lanes, all UI. **SC owns:**
every sample of audio, the audio-rate patch matrix, and continuous
modulation.

### 7.3 SC bus topology

```
groups:  gSrc -> gPatch -> gVoice -> gTap -> gFx

ambBus          2  the four ambience loops' shared dry sum (§4.1b).
                   each \wl_amb applies its own fader before writing here,
                   so four loops cost one bus. read only by \woodland_fx --
                   nothing feeds a voice from it any more.

patchBus        6  exciter outputs        (excBase         0)
                6  per-E colour-mod sums  (colourModBase   6)
                4  per-voice mod path in  (modInBase      12)
                4  per-voice audio tap    (voiceOutBase   16)
                6  per-GVOICE audio tap   (gvoiceOutBase  20)
                4  heartwood injection    (heartInBase    26)
                4  heartwood emergence    (heartOutBase   30)
               16  Output row (§2.1)      (outBase        34)
               --
               50  total
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
/ mode, and the rooted / snap flags), the sequencer lanes' `state.step_active`
flags, and the sound-page parameters per voice, GVOICE cell and TM cell.
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
- **`\woodland_fx` reads only the Output row.** See §7.3.
- **`\wl_heartwood` shrank from 8 nodes (ring + two chords) to 4 (a plain
  chain)** — same conductance-to-hop/loss mapping, fewer `c*` args.
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
heart_conductance(i, v)
master_level(v)
amb_load(i, path)               amb_volume(i, v)
```

`voice_choke` and `voice_tap` are gone — the socket collapse (§2.2) removed
both discrete choke and the separate per-voice output-level knob.
`rain_load`/`rain_volume`/`rain_excite` are gone too: the first two are
`amb_load`/`amb_volume` with a loop index in front (§4.1b), and the third has
no successor at all.

**CPU budget.** 4 voices x 6 modes = 24 resonators, plus 6 always-on GVOICE
cells and up to 6 exciters (lazily allocated), ~50 patch synths worst case, a
4-node heartwood, four stereo sample loops. Smaller across the board than
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
    - **Q4/Q6 sequencers.** Two new step-sequencer lanes (§2.10), the first
      genuinely step-based cell type on a panel that otherwise runs entirely
      on phase-coupling and diffusion.
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
      `Canopy.lua`; `rambler.resync` and `sequencer.reset` so a Start does
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
