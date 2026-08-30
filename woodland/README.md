# Woodland

A monome norns script for grid (128). Full design in
[`docs/woodland-spec.md`](../docs/woodland-spec.md).

## Status: build phase 1 — "the light show"

Implemented: topology, lexicon, the patch graph, grid render, hold/tap
patching, and the network/cell/edge/lexicon/meters screens. **No audio
engine yet** — this is fully playable as a light show, per the spec's
build order (§9), so every UI decision can be checked on real hardware
before any DSP exists.

Not yet built: SC engine, D-cell gaits and phase coupling, S-cell audio,
the heartwood lattice, voice feedback, live metering, PARAMS/PSET
persistence.

## Install

Copy this folder to `~/dust/code/woodland` on norns (or symlink it), then
select **woodland** from the norns script menu. A grid is required.

## Controls (current)

- Hold a cell, tap another: patch them together (tap again to unpatch).
- Hold two cells together: E3 sets that edge's gain.
- Hold a cell + `K1`, tap another: one-way cable.
- Hold a cell + `K2`+`K3`: sever every cable at that cell.
- Hold a cell: `E1` selects the focused cable, `E2` is its character
  parameter, `E3` is the focused cable's gain (or the cell's trim, when
  no cable is focused).
- Nothing held: `E1`/`E2`/`E3` are Canopy/Weather/Level; `K2` toggles
  Still; `K3` cycles Network → Meters → Lexicon (paging through the
  lexicon before advancing).
- `K1`+`K2` (hold ~1s): Regrow — a seeded random patch.
- `K1`+`K3` (hold ~1s): Clearing — cut every cable.

## Layout

```
woodland.lua              entry: init, grid/key/enc handlers, redraw loops
lib/
  topology.lua             the map: cell records, coords, types, adjacency
  lexicon.lua               names, descriptions, per-cell defaults
  patch.lua                 the cable graph: add/remove/trim, serialisation
  state.lua                 shared runtime UI state
  gridui.lua                grid render + hold/tap state machine
  screenui.lua               network / cell / edge / lexicon / meters views
```

(`dispatch.lua`, `rambler.lua`, `exciter.lua`, `heartwood.lua`, `voice.lua`,
`bridge.lua`, and `lib/Engine_Woodland.sc` land in later phases.)
