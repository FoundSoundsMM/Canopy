# WOODLAND — design & implementation spec

A monome norns script for grid (128). Six modal/pinged-filter voices ringed by
androgynous nodes, patched by hand into a central cluster of pulse-makers and
exciters. Inspired by the Ciat-Lonbarde Plumbutter; dressed in British woodland
folklore.

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
4. **Everything is named.** Every one of the 60 live cells has a name from
   woodland or British folklore. Names are the interface's memory.
5. **Coupling, not sequencing.** Pulse cells do not "send to" each other, they
   *entrain* to each other. Rhythms emerge from phase-pulling, not step data.
6. **Feedback is a feature.** Voice audio can be patched into another voice's
   exciter. It must self-limit musically rather than be prevented.

---

## 2. Grid topology (16 x 8)

Coordinates are `(x, y)`, x = column 1..16, y = row 1..8, matching `g.key(x,y,z)`.

```
      1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
 1  [   ][ k ][   ][   ][   ][   ][   ][ k ][ m ][   ][   ][   ][   ][   ][ k ][   ]
 2  [ m ][OAK][ s ][   ][   ][   ][   ][ Y E W ][   ][   ][   ][   ][ s ][ASH][ m ]
 3  [   ][ p ][   ][   ][ D ][ D ][ D ][ p ][ s ][ S ][ S ][ S ][   ][   ][ p ][   ]
 4  [   ][   ][   ][   ][ D ][ D ][ H ][ H ][ H ][ H ][ S ][ S ][   ][   ][   ][   ]
 5  [   ][   ][   ][   ][ S ][ S ][ H ][ H ][ H ][ H ][ D ][ D ][   ][   ][   ][   ]
 6  [   ][ p ][   ][   ][ S ][ S ][ S ][ s ][ p ][ D ][ D ][ D ][   ][   ][ p ][   ]
 7  [ m ][ROW][ s ][   ][   ][   ][   ][ALDER  ][   ][   ][   ][   ][ s ][HAZ][ m ]
 8  [   ][ k ][   ][   ][   ][   ][   ][ m ][ k ][   ][   ][   ][   ][   ][ k ][   ]

 k = knock node   s = sway node   p = sap node   m = moss node
 D = pulse cell   S = exciter cell   H = heartwood cell
 blank = unlit bezel (inert; see §7.4 for the shift layer)
```

The whole figure is 180-degree rotationally symmetric about the centre. Every D
cell has an S counterpart at `(17-x, 9-y)` and vice versa; every voice has an
opposite. This is regularised from the sketch — the hand-drawn version was
one cell off symmetry in row 5.

### 2.1 Voices (6)

| # | Name  | Cells              | Character |
|---|-------|--------------------|-----------|
| 1 | Oak   | (2,2)              | low, heavy, long — the trunk |
| 2 | Rowan | (2,7)              | bright, bell-adjacent, protective |
| 3 | Ash   | (15,2)             | hollow tube, odd-harmonic, spear-straight |
| 4 | Hazel | (15,7)             | dry, clacky, short, very inharmonic |
| 5 | Yew   | (8,2) + (9,2)      | darkest, longest decay, churchyard drone |
| 6 | Alder | (8,7) + (9,7)      | wet, comb-shifted, drifting — the water tree |

Voices 5 and 6 are two cells wide; both cells behave identically (either lights,
either responds to hold).

### 2.2 Voice nodes (24)

Four per voice. Each has a fixed role, and a compound name: `Oak·Knock`,
`Yew·Moss`, etc. All 24 names are unique by construction.

| Role  | In (what a cable delivers to the voice)              | Out (what the node emits) |
|-------|------------------------------------------------------|---------------------------|
| Knock | pulses strike the resonator (force = edge gain)      | a pulse each time the voice is struck (rebound) |
| Sway  | stream bends pitch + structure (bipolar)             | the voice's amplitude envelope as a stream |
| Sap   | stream is injected audio-rate into the resonator     | the voice's audio output tap |
| Moss  | stream sets damping + brightness; a pulse chokes it  | the voice's spectral centroid as a stream |

Positions — corner voices: **Knock** points away from centre vertically, **Sap**
toward centre vertically, **Sway** toward centre horizontally, **Moss** away
horizontally. Centre voices have no horizontal neighbours, so **Knock + Moss**
sit on the outer row and **Sap + Sway** sit on the inner row, buried inside the
woodland.

```
Oak    knock(2,1)  sway(3,2)   sap(2,3)   moss(1,2)
Rowan  knock(2,8)  sway(3,7)   sap(2,6)   moss(1,7)
Ash    knock(15,1) sway(14,2)  sap(15,3)  moss(16,2)
Hazel  knock(15,8) sway(14,7)  sap(15,6)  moss(16,7)
Yew    knock(8,1)  moss(9,1)   sap(8,3)   sway(9,3)
Alder  knock(9,8)  moss(8,8)   sap(9,6)   sway(8,6)
```

### 2.3 Pulse cells — D (10)

All ten share one core object: a **rambler**, a free-running phase oscillator
that emits a pulse on wrap. What differs is its *gait* — the rule that shapes
when the phase advances and how a pulse is weighted. Gaits are per-cell
defaults, swappable with `K1 + E2` while holding the cell.

Cells are paired across the symmetry axis as counterparts.

| Cell   | Name     | Default gait | Counterpart |
|--------|----------|--------------|-------------|
| (5,3)  | Knocker  | metric — locks to norns clock, integer division | Hunt |
| (6,3)  | Hob      | euclidean — k pulses in n | Puck |
| (7,3)  | Grim     | divider — passes every Nth *incoming* pulse | Barguest |
| (5,4)  | Shuck    | slow and heavy — very low rate, high weight | Gabriel |
| (6,4)  | Boggart  | burst — one wrap fires a ratchet of 2-7 | Spriggan |
| (12,5) | Gabriel  | drifter — fast, free, strongest coupling constant | Shuck |
| (11,5) | Spriggan | coincidence — fires when two inputs arrive inside a window | Boggart |
| (10,6) | Barguest | echo — re-emits incoming pulses, tapped, with decay | Grim |
| (11,6) | Puck     | stochastic — Bernoulli gate at the wrap | Hob |
| (12,6) | Hunt     | accelerando — rate ramps across a cycle then resets | Knocker |

**Coupling.** When two D cells are cabled, they phase-pull each other
(Kuramoto):

```
dphi_i  =  rate_i * dt  +  K * sum_j ( g_ij * sin(2*pi*(phi_j - phi_i)) )
```

`g_ij` is the edge gain (bipolar). Positive gain pulls toward sync; negative
gain pushes toward anti-phase. `K` scales with the global **Weather** macro.
This is the whole rhythm engine — no step sequencer anywhere.

Metric gaits (Knocker, Hob) are *rooted* to the norns clock by default; free
gaits are *wild*. `K1 + tap` a D cell toggles rooted/wild.

**Organic rhythm.** The phase/coupling math above stays exact — it is
calibrated for Kuramoto stability, and for the gait-rate counts the test
suite checks; nudging it risks the whole rhythm engine. What's humanized
instead is every pulse's *audible result*: dispatch gives each triggered
strike/choke/grain a small parameter wobble (force, hardness, strike
position, choke depth/time, grain amp/dur each move a few percent per hit)
on top of the edge-gain/weight shaping already there, so no two hits sound
quite the same the way a real mallet never repeats itself either. Timing
itself is untouched — the wobble is on *what* a pulse sounds like, not
*when* it lands.

### 2.4 Exciter cells — S (10)

Continuous stream sources — noise colours, textures, and slow modulators. They
are what the resonators eat. Each runs as a SynthDef on its own audio bus, and
is only instantiated when it has at least one cable (lazy allocation).

| Cell   | Name     | Source | Counterpart |
|--------|----------|--------|-------------|
| (12,3) | Bracken  | dry rustle — bandpassed white + crackle | Beck |
| (11,3) | Gorse    | prickly high band, resonant, spiky | Loam |
| (10,3) | Ember    | crackle/pop — exponential impulse noise | Drizzle |
| (12,4) | Windfall | grain bursts — short enveloped clusters | Hollow |
| (11,4) | Mistle   | pitched chirps — formant/bird-shaped | Wisp |
| (6,5)  | Wisp     | slow wandering random walk (control-rate) | Mistle |
| (5,5)  | Hollow   | wind in a trunk — pink noise through a long comb | Windfall |
| (7,6)  | Drizzle  | sparse droplets — dust with a decaying tail | Ember |
| (6,6)  | Loam     | dark brown noise, heavily lowpassed | Gorse |
| (5,6)  | Beck     | burbling filtered noise, self-moving cutoff | Bracken |

**Key behaviour:** an S cell is continuous *until a pulse is cabled into it*.
A D→S cable turns the exciter into an enveloped grain, fired by that pulse.
This is the central "man with red steam" move — pulses make sources into
gestures. S↔S cables cross-modulate each other's colour.

### 2.5 Heartwood — H (8)

Not a bus. A **diffusion lattice**. Signals injected at one heartwood node
spread outward through the lattice with a per-hop delay and loss, emerging from
the other nodes at different times and amplitudes. Both pulses and streams
diffuse. Topology: a ring of 8 (wrapping left-to-right) with vertical rungs.

```
(7,4) Taproot -- (8,4) Mycel  -- (9,4) Wyrd     -- (10,4) Ley
   |               |              |                 |
(7,5) Barrow  -- (8,5) Warren -- (9,5) Holloway -- (10,5) Hearth
   |___________________________________________________|   (wrap)
```

Per-node **conductance** (E2 while holding) sets local hop delay and loss.
Low conductance = a signal dies within one hop. High conductance = energy
circulates the ring for a long time, producing self-sustaining rhythmic
patterns and long spectral smears. The heartwood is the closest thing the
instrument has to a memory.

Yew's and Alder's Sap/Sway nodes sit directly against the heartwood edge, so
those two voices are physically rooted into it.

### 2.6 Grove — P (8)

Six fixed-pitch resonators is one chord, however alive the rhythm on top of
it is. The grove is the answer: eight **pitch fields**, two vertical seams at
`x=4` and `x=13` flanking the D/S/H core, paired across the same 180° symmetry
(`x → 17-x`, `y → 9-y`) as the D and S counterparts.

```
(4,3) Cuckoo    (13,3) Wren
(4,4) Nightjar  (13,4) Merlin
(4,5) Curlew    (13,5) Plover
(4,6) Bittern   (13,6) Raven
```

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
deliberate: the **mode** is the P cell's gait (swappable with `K1 + E2`), and
a mode only decides the *shape* of the line. How far it travels is E2's
**Range**, logarithmic from a 25-cent shimmer to two octaves, so Range means
the same thing in every mode.

**Three clocks move a field**, and they are different on purpose:

1. **A strike.** Every voice a field tunes re-tunes immediately before it is
   struck. This is the important one: *one cable* turns an existing rhythm
   into a melody, with no sequencer and nothing else patched.
2. **A pulse.** A D→P or H→P cable steps the field on its own clock, so the
   line need not be locked to the rhythm playing it.
3. **Time.** The continuous modes (wander, gravity) and the P↔P pull run on
   the 2 ms scheduler, decimated to every 8th tick, and freeze under Still
   with everything else.

**Snap.** By default a field quantises to a minor pentatonic — with mode banks
this inharmonic, anything denser stops reading as a scale and starts reading
as an out-of-tune one. `K1 + tap` a P cell sets it free to sit between the
notes. A field narrower than the smallest interval in the scale ignores snap
either way: at small Range this is a microtonal detuner, at large Range it is
a melody, and quantising the small end would just pin it to the root.

**P↔P** is the pitch counterpart of D↔D's Kuramoto term, on position rather
than phase: positive gain pulls two fields toward each other (converging on a
consonance), negative pushes them apart into contrary motion.

**A P cell never emits a pulse.** Its whole output is a number of semitones.
That is what makes a D→P→Knock chain unable to feed itself, and it is why P
contributes nothing to the continuous patch matrix — there is no stream to
route, only `voice_pitch`/`exciter_colour` calls out of `grove.lua`.

**Detune drift.** Separately from all of the above, every voice carries a
continuous few-cents wander generated in SC (`driftDepth`/`driftRate`, three
incommensurate slow shapes summed, per-voice phase offsets). It is on by
default at ~6 cents whether or not anything is cabled — it is why an untouched
patch no longer repeats one identical note — and cabling a wide field into a
voice deepens it, to a ceiling of 35 cents. Above that it stops sounding like
wood and starts sounding out of tune. There is a per-strike detune of the same
order in `grove.on_strike`, scaled by Weather: the pitch half of §2.3's
organic-rhythm wobble.

---

## 3. Patching grammar

| Gesture | Result |
|---------|--------|
| Hold cell A, tap unconnected cell B | make cable A↔B at default gain (+0.6) |
| Hold cell A, tap connected cell B | remove cable A↔B |
| Hold A, hold B (both down) | screen focuses that edge; E3 sets its gain directly |
| Hold cell A + `K2` and `K3` together | sever every cable at A |
| Hold A, `K1` + tap B | make a **one-way** cable A→B (advanced; drawn differently) |

Cables are undirected and bipolar. Gain range `-1.0 .. +1.0` through zero.
Negative gain inverts: streams are phase-inverted, pulse coupling becomes
repulsion, damping modulation reverses. Attenuversion is the main expressive
control after the patch itself.

Constraints: no self-cables; no duplicate edges; a soft cap of 64 cables.

---

## 4. Norns controls

### 4.1 Nothing held on the grid

| Control | Function |
|---------|----------|
| E1 | **Canopy** — global space/reverb amount |
| E2 | **Weather** — global wildness: coupling strength K, gait drift, exciter variance |
| E3 | Master level |
| K2 | **Still** — freeze all pulse gaits; resonators ring out. Tap again to resume |
| K3 | cycle screen view: Network → Meters → Lexicon |
| K1 + K2 | **Regrow** — seeded random patch (hold to confirm) |
| K1 + K3 | **Clearing** — cut every cable (hold to confirm) |

### 4.2 Holding a grid cell

| Control | Function |
|---------|----------|
| E1 | select which cable at this cell is focused (ALL → 1..n) |
| E2 | the cell's **character** parameter (see below) |
| E3 | attenuvert — focused cable's gain, or node trim when ALL is selected |
| K1 + E2 | secondary character parameter (D cells: swap gait; P cells: swap mode) |
| K2 + K3 | sever all cables at this cell |

**E2 per cell type — the one thing that matters about that cell:**

| Cell type | E2 = | Range |
|-----------|------|-------|
| Voice | **Grain** — macro morph of the woody spectrum, soft/hollow → hard/dry | 0..1 |
| Knock node | strike hardness (mallet) | 0..1 |
| Sway node | bend depth and target balance (pitch ↔ structure) | -1..1 |
| Sap node | injection filter — how much of the stream reaches the resonator | 0..1 |
| Moss node | damping curve — even vs frequency-weighted | 0..1 |
| D cell | rate / clock relation | gait-dependent |
| S cell | **Colour** — the source's filter/character | 0..1 |
| H cell | **Conductance** — hop delay and loss | 0..1 |
| P cell | **Range** — how far the field roams (25 cents .. 2 octaves) | 0..1 |

Deeper per-voice controls (base pitch, mode count, drive, pan, scale snap) live
in the norns PARAMS menu, not on the grid.

---

## 5. Displays

### 5.1 Grid brightness (0-15)

| Cell | Idle | Live |
|------|------|------|
| Voice | 4 | amplitude envelope, 4→15, with the resonant tail visible |
| Voice node | 2 unpatched, 6 patched | flash on a Lua-known pulse arriving (Knock strike, Moss choke), decay ~120 ms, weighted by force/depth; continuous magnitude from a stream still needs the metering back-channel (§7.4) |
| D | 3 | flash 15 on pulse, decay ~120 ms; base rises with coupling strength |
| S | 3 unpatched, 5 patched | flash on a D→S grain firing, decay ~120 ms, weighted by amp; continuous stream-amplitude shimmer still needs the metering back-channel (§7.4) |
| H | 2 | local lattice energy — signals are visibly seen spreading |
| P | 2 | where the field currently sits, so a rising line climbs the cell; flash on each step |
| bezel | 0 | — |

**Patch reveal** — while a cell is held: held cell solid 15; every cell cabled to
it blinks at 13 in sync; every other node/D/S/H cell (a valid patch target) is
floored to a minimum readable brightness so it doesn't vanish; voice cells
(never cable endpoints themselves) scale ×0.4 toward black. This is how you
read a patch — and see what's still available to patch into — on the grid.

### 5.2 Screen — Network view (nothing held)

The full 16x8 map drawn at 7px pitch (112x56, centred), with cables drawn as
**actual lines** between cell centres. Line brightness = |gain|; one-way cables
get a short arrowhead; negative-gain cables are drawn dashed. Pulses render as
a dot travelling the line. Bottom line: the most recent event.

```
 ·  ▪  ·           ▪ ▪           ·  ▪  ·
 ▪ [O] ▪ ─────╮   [ YEW ]       ▪ [A] ▪
 ·  ▪  ·      ╰──▪ ▪ ▪ ▪ ▪ ▪ ▪   ·  ▪  ·
              ▪ ▪ ░ ░ ░ ░ ▪ ▪
              ▪ ▪ ░ ░ ░ ░ ▪ ▪
 ·  ▪  ·      ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪    ·  ▪  ·
 ▪ [R] ▪         [ ALDER ]      ▪ [H] ▪
 ·  ▪  ·           ▪ ▪           ·  ▪  ·
 Knocker -> Oak.Knock
```

### 5.3 Screen — Cell view (a cell held)

```
 OAK                          voice 1
 ─────────────────────────────────────
 grain      ▐▓▓▓▓▓▓▓░░░░░       0.62
 trim       ▐────●────▌        +0.35
 ─────────────────────────────────────
 3 cables   ▸ Knocker           +0.80
             Bracken            -0.40
             Wyrd·heartwood     +0.55
 ─────────────────────────────────────
 K2+K3 sever
```

Two cells held → an edge view: both names, one bipolar gain bar, and a short
description of what actually flows across that edge given the two types.

### 5.4 Lexicon view

A scrollable list of all 68 named cells with type, coordinates and a one-line
description. This is the manual, on the device.

---

## 6. Type interaction matrix

What a cable *means* is derived from the pair of endpoint types. This table is
the authority; implement it as a dispatch table, not as branching.

|            | Voice node | D (pulse) | S (exciter) | H (heartwood) | P (grove) |
|------------|-----------|-----------|-------------|---------------|-----------|
| **Voice node** | audio/CV cross-feed both ways: each node's out feeds the other's in, per role | pulse strikes / chokes the node; node's own event-out resets D's phase | S's stream drives the node; node's follower stream modulates S's colour | node injects into the lattice; lattice returns to the node | the field tunes this node's voice; gain sets depth, and inverts the contour when negative |
| **D** | — | mutual phase coupling (Kuramoto) + mutual triggering | D pulse envelopes S into a grain; S stream modulates D's rate | pulse enters the lattice and diffuses | each pulse steps the field to a new degree |
| **S** | — | — | cross-modulation: each modulates the other's colour and level | stream diffuses through the lattice | the exciter's colour rides the field's line |
| **H** | — | — | — | direct link — short-circuits two lattice points, adds a shortcut path | a pulse out of the lattice steps the field |
| **P** | — | — | — | — | the two fields pull together (apart, at negative gain) |

Notes on the awkward pairs:

- **Voice↔Voice (via Sap nodes)** is one resonator exciting another. It is a
  feedback path by definition. Every voice bus gets a DC blocker, soft
  saturation, and a per-voice limiter so a loop howls musically instead of
  clipping. Do not prevent the loop.
- **Node↔Node on the same voice** is allowed and useful (Sway → Moss on Oak is
  self-damping).
- **D↔D at negative gain** produces anti-phase locking — the most reliable way
  to get a stable interlocking two-part rhythm.
- **P is a source only.** A field never emits a pulse and never writes a
  stream, so its whole column is one-way and nothing in it can feed back.

---

## 7. Software architecture

### 7.1 File layout

```
woodland/
  woodland.lua              -- entry: init, grid/key/enc handlers, redraw loops
  lib/
    topology.lua            -- the map: cell records, coords, types, adjacency
    lexicon.lua             -- names, descriptions, per-cell defaults
    patch.lua               -- graph: add/remove/trim edges, serialisation
    dispatch.lua            -- the §6 type-interaction matrix
    rambler.lua             -- D-cell gaits + the phase-coupling scheduler
    exciter.lua             -- S-cell control layer (audio side lives in SC)
    heartwood.lua           -- diffusion lattice
    grove.lua               -- pitch fields: modes, coupling, voice retuning
    voice.lua               -- voice state, param mapping, node roles
    gridui.lua              -- grid render + hold/tap state machine
    screenui.lua            -- network / cell / edge / lexicon views
    bridge.lua              -- engine command wrapper, throttling, meter cache
  lib/Engine_Woodland.sc    -- SC: modal voices, exciters, patch matrix, canopy
  README.md
```

### 7.2 Lua / SC split

**Lua owns:** the patch graph, all pulse generation and coupling, the heartwood
lattice's discrete-event side, the grove's pitch fields, all UI. **SC owns:**
every sample of audio, the audio-rate patch matrix, and continuous modulation
— including the per-voice detune drift (§2.6), which is a few cents moving
continuously and so far too fine-grained to push over OSC without either
flooding it or stepping audibly.

Pulses are generated in Lua because they must be visualised, coupled, and
rewired live — all of which are painful in SC. The cost is timing jitter; see
§8.

**Scheduler.** One `clock.run` coroutine at a 2 ms tick advances all rambler
phases and applies coupling. On a phase wrap, compute the fractional overshoot
and pass it to the engine as a latency offset so SC can schedule the strike
accurately despite the coarse tick.

### 7.3 SC bus topology

```
groups:  gSrc -> gPatch -> gVoice -> gTap -> gFx

audio buses    10  exciter outputs (one per S cell)
                6  voice exciter-inputs (summing)
                6  voice outputs
                1  main

control buses  24  voice modulation inputs (4 per voice: pitch, damp, bright, pos)
               60  meter buses (one per live cell)
```

Patch synths, instantiated per cable, live in `gPatch`:

- `\patch_aa` — `Out.ar(dst, In.ar(src) * gain)`
- `\patch_ak` — `Out.kr(dst, LPF(Amplitude(In.ar(src)),20) * gain)`
- `\patch_kk` — `Out.kr(dst, In.kr(src) * gain)`

Voice params read `base + In.kr(modBus)`. Lua sets `base`; cables write to
`modBus`. Removing a cable frees its synth. ~64 patch synths worst case.

### 7.4 Metering back-channel

One `\watcher` synth in `gFx` reads all 60 meter buses and sends an OSC message
at 30 Hz:

```supercollider
SendReply.kr(Impulse.kr(30), '/wl_meters', In.kr(meterBus, 60));
```

forwarded to `NetAddr("127.0.0.1", 10111)` — norns' OSC in port — and picked up
by `osc.event(path, args)`. Lua caches the array and *decays it locally* between
messages so the grid stays smooth if a packet is dropped. (Verify the port and
the SendReply→NetAddr forwarding pattern against the norns version in use;
`addPoll` is scalar-only and will not carry a 60-element array.)

The 60 is the pre-grove cell count and stays right: a P cell has no audio to
meter, and its position is already a Lua-side number the grid reads directly.

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
character values. Cell ids are stable strings (`"oak.knock"`, `"d.knocker"`,
`"h.warren"`) — never coordinates — so the layout can change without breaking
saved patches.

---

## 8. Sound engine — making it woody

Modal synthesis (`DynKlank`-style, hand-built), excited by short filtered
noise bursts through a plain, tuneable, pinged bank of resonant filters — no
body-cavity diffuser any more (see the FM/noise addendum below for why). Six
recipe parameters per voice, all reachable from Grain (E2) as a macro plus
individually from PARAMS.

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

**Per-voice defaults:**

| Voice | Fundamental | Structure | Damp exp | Decay | Notes |
|-------|-------------|-----------|----------|-------|-------|
| Oak   | 65 Hz  | 0.55 bar  | 1.1 | 2.4 s | heavy, dark, slow |
| Rowan | 330 Hz | 0.75 bar  | 0.6 | 1.8 s | bright, bell-adjacent |
| Ash   | 146 Hz | odd-only  | 0.8 | 1.2 s | hollow tube |
| Hazel | 220 Hz | 0.95 bar  | 1.3 | 0.35 s | dry clack |
| Yew   | 49 Hz  | 0.35 bar  | 0.4 | 6.0 s | longest, drone-capable |
| Alder | 98 Hz  | 0.6 bar   | 0.9 | 2.0 s | into a short drifting comb |

**Engine commands:**

```
strike(voice, force, hardness, position)
voice_pitch(voice, hz)          voice_grain(voice, v)
voice_glide(voice, seconds)     voice_drift(voice, depth, rate, seed)
voice_damp(voice, v)            voice_bright(voice, v)
voice_pos(voice, v)             voice_drive(voice, v)
voice_amp(voice, v)             voice_modes(voice, n)
voice_fm(voice, ratio, depth)
voice_noise_tune(voice, v)      voice_noise_q(voice, v)
exciter_on(id, kind)            exciter_off(id)
exciter_set(id, key, v)         exciter_gate(id, dur, amp)
exciter_fm(id, ratio, depth)
patch_add(id, kind, src, dst, gain)
patch_gain(id, gain)            patch_free(id)
canopy(size, damp, mix)         watch(rate)
```

**CPU budget.** 6 voices x 6-8 modes = ~48 resonators, plus up to 10 exciters,
~64 patch synths, and one reverb. Tight but viable on a CM3. Mitigations:
global mode-count quality param (4 / 6 / 8), lazy exciter allocation, and
`patch_kk` synths at control rate wherever audio rate is not needed.

---

## 9. Build order

Each phase ends in something testable on the device.

1. **The light show.** topology + lexicon + grid render + hold/tap patching +
   network and cell screens. No audio at all. The instrument is fully playable
   as a light show and every UI decision is verifiable before any DSP exists.
2. **First sound.** SC engine with the six modal voices and `strike`. One D cell
   (Knocker) driving them from Lua. Prove the woodiness recipe here — it is the
   hardest thing to get right and everything else depends on it.
3. **Rhythm.** All ten gaits + D↔D phase coupling + the 2 ms scheduler.
4. **Exciters.** S cells, the audio-rate patch matrix, control-bus modulation,
   D→S gating.
5. **Heartwood.** The diffusion lattice, both discrete and continuous paths.
5b. **Grove.** The eight pitch fields, their modes and coupling, `glide` and
   the per-voice detune drift in SC. Out of build order deliberately: six
   fixed-pitch voices made every patch one chord, and that was audible long
   before feedback or metering were.
6. **Feedback.** Voice↔Voice via Sap, with limiting and saturation. Tune until
   loops howl musically.
7. **Life.** Metering back-channel → grid and screen animation.
8. **Persistence and polish.** PARAMS, PSET + graph save/load, Regrow, Clearing,
   clock sync, lexicon view, README.

---

## 10. Risks and open decisions

**Risks**

| Risk | Mitigation |
|------|------------|
| Lua pulse jitter (~1-2 ms) | fractional-overshoot latency offset to SC; keep the audible strike scheduled in SC, not the Lua tick |
| CPU ceiling on CM3 | mode-count quality param, lazy exciters, control-rate patches |
| Feedback instability on voice↔voice | per-voice DC block + tanh + limiter; conservative default gain on Sap↔Sap edges |
| 60-value OSC metering flooding | 30 Hz cap, local decay in Lua, drop-tolerant |
| Patch becomes unreadable at 30+ cables | patch reveal on hold is the primary reader; consider a "trace" mode that walks one signal path |

**Decisions for you**

1. **Grid 64.** The layout needs 16x8. Options: (a) grid 128 only; (b) a reduced
   8x8 layout — 4 voices, 4 D, 4 S, 4 H. Recommendation: 128 only for v1, note
   it in the README.
2. **Arc.** An arc would be a natural fit for the four attenuverters of a
   focused cell. Out of scope for v1?
3. **Regrow** — seeded random patching. Included above as a K1+K2 gesture
   because it suits the instrument, but it is an addition to your brief. Cut it
   if you would rather the patch always be hand-made.
4. **One-way cables** (K1 + tap) slightly break the androgynous premise. Kept as
   an advanced escape hatch. Say if you want them gone.
