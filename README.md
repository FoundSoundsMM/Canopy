# Woodland

A monome norns script for grid (128). Full design in
[`docs/woodland-spec.md`](docs/woodland-spec.md).

## Status: build phase 4 — "exciters"

Phase 1 (topology, lexicon, the patch graph, grid render, hold/tap
patching, the network/cell/edge/lexicon/meters screens), phase 2 (the SC
engine: six modal voices per the §8 woodiness recipe, `strike`, the Grain
macro, Canopy/master level), and phase 3 (all ten D-cell gaits, D↔D
Kuramoto coupling, the 2 ms scheduler, rooted/wild, Moss chokes) are done.

Phase 4 makes the ten S cells real, and wires them into the rest of the
patch:

- **Ten exciter recipes.** Bracken, Gorse, Ember, Windfall, Mistle, Wisp,
  Hollow, Drizzle, Loam, Beck — each its own SC SynthDef per the §2.4
  table, not one shared macro. Lazily allocated: an S cell only runs
  while it has at least one cable (`exciter.lua`).
- **D → S gating.** An S cell free-runs until a D cell is cabled to it;
  once it is, the exciter goes silent between pulses and fires a short
  grain on each one (§2.4's "man with red steam" move).
- **The audio-rate patch matrix.** A generic pair of SC synths
  (`\wl_patch_aa`, `\wl_patch_ak`) realise the continuous half of the §6
  matrix: S → Sap injects a stream audio-rate into a voice's resonator,
  S → Sway bends pitch↔structure, S → Moss sets damping↔brightness, and
  S↔S cross-modulates colour. Driven by the patch graph, not a per-tick
  loop — a synth is added/freed/re-gained only when a cable actually
  changes (`dispatch.resync_matrix`).
- **Sap/Sway/Moss's own E2** (injection level, bend depth/balance, damping
  curve) now forwards to the engine (`voice.lua`), separate from Moss's
  existing pulse-choke path.
- **Colour** (E2 on an S cell) forwards live, same shape as Grain.

Not yet built: node *outputs* (Sway's amplitude-envelope tap, Moss's
spectral centroid, Sap's audio tap for voice↔voice feedback — so
node↔node cables and the "S↔S also modulates level" half of §6 are still
no-ops), the heartwood lattice, voice↔voice feedback itself, the metering
back-channel, PARAMS/PSET persistence.

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
  parameter, `E3` is the focused cable's gain (or the cell's trim, when
  no cable is focused).
- Hold a D cell + `K1`, turn `E2`: swap its gait.
- `K1` + tap a D cell (nothing else held): root it to the norns clock, or
  set it wild. Only metric and euclidean have anything to root to.
- Nothing held: `E1`/`E2`/`E3` are Canopy/Weather/Level; `K2` toggles
  Still; `K3` cycles Network → Meters → Lexicon (paging through the
  lexicon before advancing).
- `K1`+`K2` (hold ~1s): Regrow — a seeded random patch.
- `K1`+`K3` (hold ~1s): Clearing — cut every cable.

## Layout

```
Woodland.lua                entry: init, grid/key/enc handlers, redraw loops
lib/
  topology.lua              the map: cell records, coords, types, adjacency
  lexicon.lua               names, descriptions, per-cell defaults
  patch.lua                 the cable graph: add/remove/trim, serialisation
  state.lua                 shared runtime UI state
  gridui.lua                grid render + hold/tap state machine
  screenui.lua              network / cell / edge / lexicon / meters views
  dispatch.lua              §6 type-interaction matrix: pulse events (D->
                             Knock/Moss/S) and the continuous patch matrix
                             (S<->S, S<->Sap/Sway/Moss)
  rambler.lua               all ten D-cell gaits + the coupling scheduler
  voice.lua                 voice state: Grain + Sap/Sway/Moss's own E2
  exciter.lua               S-cell control layer: lazy alloc, gating, Colour
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Woodland.sc        SC: six modal voices, ten exciters, patch matrix
test/
  run.sh                    offline test run (needs `lua`, no hardware)
```

(`heartwood.lua` lands in a later phase.)

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
numbers and cleans up on removal — all against the stubbed `engine.*`
call log, since there's no SC to actually render audio here. `smoke.lua`
loads `Woodland.lua` itself and exercises every screen view and control.
`perf.lua` reports what the 2 ms tick costs — cheap on a dev machine, but
the CM3 is the budget that matters, so re-check it there if the scheduler
ever feels like the thing making the UI stutter.

The `.sc` engine still needs SuperCollider to compile it; there is no SC
install in the dev environment, so Maiden's compile log is the first
place to look if a session comes up silent.
