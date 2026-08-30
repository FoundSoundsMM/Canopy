# Woodland

A monome norns script for grid (128). Full design in
[`docs/woodland-spec.md`](docs/woodland-spec.md).

## Status: build phase 5b — "grove"

Phase 1 (topology, lexicon, the patch graph, grid render, hold/tap
patching, the network/cell/edge/lexicon/meters screens), phase 2 (the SC
engine: six modal voices per the §8 woodiness recipe, `strike`, the Grain
macro, Canopy/master level), phase 3 (all ten D-cell gaits, D↔D Kuramoto
coupling, the 2 ms scheduler, rooted/wild, Moss chokes) and phase 4 (the
ten exciter recipes, D→S gating, the audio-rate patch matrix) are done.

Phase 5 builds the heartwood (§2.5) — "not a bus, a diffusion lattice" —
and it is the last of the spec's original five cell types to become real:

- **The discrete lattice** (`heartwood.lua`). A pulse cabled into a
  heartwood node enters the lattice and spreads outward through the ring
  of 8 and its two chord rungs, hop by hop, emerging from every node it
  reaches through whatever that node is cabled to — later and quieter the
  further it has travelled. It rides the same 2 ms tick as the ramblers,
  and freezes with them under Still.
- **The continuous lattice** (`\wl_heartwood`). The same eight nodes as an
  audio-rate feedback delay network, so a *stream* patched into one
  diffuses the same way a pulse does. Per-node hop delay and loss are read
  from the same conductance mapping on both sides.
- **Conductance** (E2 on an H cell) sets that node's hop delay and loss
  together: a poor conductor is one slow, lossy thud that dies within a
  hop; a good one is short hops that let energy circulate the ring for a
  long time. Full conductance sits deliberately just under
  self-oscillation.
- **H↔H cables** add a shortcut path across the lattice, on both the pulse
  and the stream side, and a one-way one makes the lattice directional in
  a way the ring itself never is.
- **The rest of §6's H column.** D→H injects, H→D re-enters the rambler
  inbox (so a D→H→D loop is bounded exactly the way D↔D is), H→Knock
  strikes, H→S fires a grain, H→Sap/Sway/Moss taps the emergence bus into
  a voice, S↔H diffuses a stream and gets the lattice's colour back.
- H cells light from lattice energy on the grid, and their cell screen
  reads out hop, loss and what is still circulating.

Phase 5b builds the **grove** (§2.6) — eight new P cells, out of the spec's
build order and on purpose. Six fixed-pitch resonators is one chord however
alive the rhythm on top of it is, and that was audible long before feedback
or metering were.

- **Pitch fields** (`grove.lua`). A P cell is a wandering pitch a voice can be
  cabled into. Its **mode** is what a gait is to a D cell — the shape of the
  line, swappable with `K1 + E2` — and E2 is **Range**, how far it travels,
  logarithmic from a 25-cent shimmer to two octaves, meaning the same thing
  in every mode.
- **Three clocks move it.** Every voice a field tunes re-tunes just before it
  is struck, so *one cable* turns an existing rhythm into a melody with
  nothing else patched. A D→P or H→P cable steps the field on its own clock
  instead, so the line need not be locked to the rhythm playing it. And the
  continuous modes ride the same 2 ms tick as the ramblers, freezing with
  them under Still.
- **Snap.** Fields quantise to a minor pentatonic by default; `K1 + tap` sets
  one free to sit between the notes. Below the smallest interval in the scale
  a field ignores snap either way — at small Range this is a microtonal
  detuner, at large Range a melody.
- **P↔P** is D↔D's Kuramoto term one domain over: positive gain pulls two
  fields onto a consonance, negative pushes them into contrary motion.
- **The rest of §6's P column.** P→S makes a pitched exciter's Colour ride the
  line. A P cell never emits a pulse, which is what makes its column one-way
  and unable to feed back.
- **Detune drift** (`\woodland_voice`). Separately from any of that, every
  voice now carries a continuous few-cents wander generated in SC — three
  incommensurate slow shapes, per-voice phase offsets — on by default whether
  or not anything is cabled, and deepened (to a 35-cent ceiling) by a wide
  field. Plus a per-strike detune of the same order, scaled by Weather: the
  pitch half of the organic-rhythm wobble dispatch already applies to force
  and hardness.

Not yet built: node *outputs* (Sway's amplitude-envelope tap, Moss's
spectral centroid, Sap's audio tap for voice↔voice feedback — so node↔node
cables, node→lattice, and the "S↔S also modulates level" half of §6 are
still no-ops), voice↔voice feedback itself, the metering back-channel,
PARAMS/PSET persistence.

## Install

From Maiden (norns' web REPL):

```
;install https://github.com/FoundSoundsMM/Woodland
```

or copy this repo to `~/dust/code/Woodland` by hand. Then select
**Woodland** from the norns script menu. A grid is required.

## Controls

- Hold a cell, tap another: patch them together (tap again to unpatch).
- Hold two cells together: E3 sets that edge's gain.
- Hold a cell + `K1`, tap another: one-way cable.
- Hold a cell + `K2`+`K3`: sever every cable at that cell.
- Hold a cell: `E1` selects the focused cable, `E2` is its character
  parameter (an H cell's is its conductance, a P cell's its range), `E3` is
  the focused cable's gain — or, with no cable focused, that sound's decay:
  a voice's ring time in seconds, or an exciter's envelopes as a ratio.
  Holding any of a voice's four nodes moves that voice's decay, since a node
  is part of the voice rather than a sound of its own.
- Hold a D cell + `K1`, turn `E2`: swap its gait. Same gesture on a P cell
  swaps its pitch-field mode.
- `K1` + tap a D cell (nothing else held): root it to the norns clock, or
  set it wild. Only metric and euclidean have anything to root to. Same
  gesture on a P cell snaps its field to the scale, or sets it free.
- Nothing held: `E1`/`E2`/`E3` are Canopy/Weather/Tempo, and `K1`+`E3` is
  the master level; `K2` toggles Still; `K3` cycles Network → Meters →
  Lexicon (paging through the lexicon before advancing).
- **Weather (`E2`) is the groove knob.** At 0 every pulse — however freely
  its cell runs — snaps onto a grid line, and unrelated gaits cohere into one
  groove: each cell quantises to the coarsest of 8th/16th/32nd/64th that fits
  inside its own cycle, and a burst is triggered on the beat with its ratchet
  on a subdivision. From 0 to 0.5 swing ramps in, warping the grid so
  off-beats land late and beats stay put. Past 0.5 the snap loosens and
  jitter grows in its place, until at 1 nothing is held at all and the patch
  is rainfall in a forest. The corner of the network view reads out the tempo
  and where the knob has it: `lock` / `swNN` / `lsNN` / `rain`.
- `K1`+`K2` (hold ~1s): Regrow — a seeded random patch.
- `K1`+`K3` (hold ~1s): Clearing — cut every cable.

## Layout

```
Woodland.lua                entry: init, grid/key/enc handlers, redraw loops
lib/
  topology.lua              the map: cell records, coords, types, adjacency
  lexicon.lua               names, descriptions, per-cell defaults
  patch.lua                 the cable graph: add/remove/trim, serialisation
  quantise.lua              the Weather groove: quantise -> swing -> chaos
  state.lua                 shared runtime UI state
  gridui.lua                grid render + hold/tap state machine
  screenui.lua              network / cell / edge / lexicon / meters views
  dispatch.lua              §6 type-interaction matrix: pulse events (->
                             Knock/Moss/S/H) and the continuous patch matrix
                             (S<->S, S<->Sap/Sway/Moss, S<->H, H<->H, H->node)
  rambler.lua               all ten D-cell gaits + the coupling scheduler
  voice.lua                 voice state: Grain + Sap/Sway/Moss's own E2
  exciter.lua               S-cell control layer: lazy alloc, gating, Colour
  heartwood.lua             the diffusion lattice's discrete-event side
  grove.lua                 the pitch fields: modes, coupling, voice retuning
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Woodland.sc        SC: six modal voices, ten exciters, patch matrix,
                             the heartwood delay network, glide + pitch drift
test/
  run.sh                    offline test run (needs `lua`, no hardware)
```

## A note on `include`

norns' global `include()` is `dofile`-based: it re-executes the file and
returns a **new table** every call. `topology`, `patch` and `state` are
shared mutable singletons, so plain `include()`s would hand `gridui`,
`screenui` and the scheduler three separate patch graphs that never see
each other's cables. Every module here is loaded through the `wl()` memo
defined at the top of `Woodland.lua` instead. If you add a lib, load its
dependencies with `wl("name")`, never `include()`.

## Tests

```
sh test/run.sh
```

Stubs norns (`util`, `clock`, `metro`, `screen`, `grid`, `engine`) and
drives the scheduler on a virtual clock, so gait rates, clock rooting,
Kuramoto locking, Still, and runaway-resistance on a densely cross-patched
graph are all checkable on a laptop. `exciter.lua` (the test, not the lib
of the same name) checks lazy alloc/off, D-cable gating, Colour
forwarding, and that the patch matrix resolves cables to the right SC bus
numbers and cleans up on removal — all against the stubbed `engine.*` call
log, since there's no SC to actually render audio here. `heartwood.lua`
(the test) injects a pulse at one lattice node and checks it emerges from
the others later and quieter, that conductance really does span "dies
within one hop" to "circulates", that an H↔H cable beats the ring to the
far side, that a D→H→D loop at full conductance stays bounded for 20 s,
and that Still freezes what is in flight rather than flushing it.
`grove.lua` (the test) checks that a cabled field really does retune a voice
*before* the strike lands, that Range is what bounds how far it goes, that a
snapped field lands on scale tones and a freed one does not, that a narrow
field ignores snap rather than collapsing onto the root, that a pulse steps a
field with nothing being struck at all, that a P↔P cable converges at positive
gain and does not at negative, that severing the cable hands the voice back
its own fundamental, and that a voice with no field at all still never plays
the same pitch twice.
`smoke.lua` loads `Woodland.lua` itself and exercises every screen view
and control.
`perf.lua` reports what the 2 ms tick costs — cheap on a dev machine, but
the CM3 is the budget that matters, so re-check it there if the scheduler
ever feels like the thing making the UI stutter.

The `.sc` engine still needs SuperCollider to compile it; there is no SC
install in the dev environment, so Maiden's compile log is the first
place to look if a session comes up silent.
