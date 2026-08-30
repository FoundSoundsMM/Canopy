# Woodland

A monome norns script for grid (128). Full design in
[`docs/woodland-spec.md`](docs/woodland-spec.md).

## Status: build phase 3 — "rhythm"

Phase 1 (topology, lexicon, the patch graph, grid render, hold/tap
patching, the network/cell/edge/lexicon/meters screens) and phase 2 (the
SC engine: six modal voices per the §8 woodiness recipe, `strike`, the
Grain macro, Canopy/master level) are done.

Phase 3 makes it an instrument that keeps time:

- **All ten gaits.** metric, euclidean, divider, slow, burst, drifter,
  coincidence, echo, stochastic, accelerando. Seven free-run on a phase;
  three (divider, echo, coincidence) are purely reactive and only speak
  when spoken to.
- **D↔D Kuramoto coupling.** Cabled pulse cells phase-pull each other;
  positive gain locks in phase, negative gain locks anti-phase. Weather
  (E2) scales the coupling constant *and* a slow drift on every free
  rate. This is the whole rhythm engine — there is no step sequencer.
- **The 2 ms scheduler.** One metro advancing every phase, applying
  coupling, and draining scheduled taps (burst ratchets, echo repeats).
- **Rooted vs wild.** Metric and euclidean gaits lock to `clock.get_beats()`
  exactly rather than integrating a rate, so they stay tight to the
  transport. `K1` + tap a D cell toggles it.
- **Moss chokes.** A pulse into a Moss node ducks that voice
  (`voice_choke`, new in the engine), which is the second of the two
  things §6 says a pulse can do to a voice node.
- D cells are now live on the grid: flash 15 on a pulse decaying over
  ~120 ms, over a base that rises with coupling strength. Pulses render
  as dots travelling their cables on the network screen.

Not yet built: S-cell audio and the audio-rate patch matrix, the
heartwood lattice, voice↔voice feedback, the metering back-channel,
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
  dispatch.lua              §6 type-interaction matrix (the pulse half)
  rambler.lua               all ten D-cell gaits + the coupling scheduler
  voice.lua                 voice state: forwards Grain to the engine
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Woodland.sc        SC: six modal voices, strike, choke, canopy
test/
  run.sh                    offline test run (needs `lua`, no hardware)
```

(`exciter.lua` and `heartwood.lua` land in later phases.)

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
graph are all checkable on a laptop. `smoke.lua` loads `Woodland.lua`
itself and exercises every screen view and control. `perf.lua` reports
what the 2 ms tick costs — cheap on a dev machine, but the CM3 is the
budget that matters, so re-check it there if the scheduler ever feels
like the thing making the UI stutter.

The `.sc` engine still needs SuperCollider to compile it; there is no SC
install in the dev environment, so Maiden's compile log is the first
place to look if a session comes up silent.
