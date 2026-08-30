# Woodland

A monome norns script for grid (128). Full design in
[`docs/woodland-spec.md`](../docs/woodland-spec.md).

## Status: build phase 2 — "first sound"

Phase 1 (topology, lexicon, the patch graph, grid render, hold/tap
patching, the network/cell/edge/lexicon/meters screens) is done.

Phase 2 adds the SC engine: six modal voices (`Engine_Woodland.sc`, the
§8 woodiness recipe — inharmonic mode ratios, frequency-dependent damping,
a noise-burst exciter, strike-position comb notching, gentle
nonlinearity), `strike`, the Grain macro, and Canopy/master level. One D
cell — Knocker, the only one with a gait implemented so far — drives
voices via cables to their Knock nodes, through a new dispatch layer
(`dispatch.lua`) that maps the §6 type-interaction matrix, and a
scheduler (`rambler.lua`) that advances D-cell phase and fires on wrap.

The engine file hasn't been compiled/run on real SuperCollider yet (no SC
install in the dev environment) — Lua-side logic is tested with a mocked
`engine`, but the `.sc` itself wants a first run on hardware. If Maiden's
compile log shows an error, that's the place to look first.

Not yet built: the other 9 D-cell gaits, D↔D phase coupling, S-cell audio
and the audio-rate patch matrix, the heartwood lattice, voice↔voice
feedback, live metering, PARAMS/PSET persistence.

## Install

From Maiden (norns' web REPL):

```
;install https://github.com/FoundSoundsMM/Woodland
```

or copy this repo to `~/dust/code/Woodland` by hand. Then select
**Woodland** from the norns script menu. A grid is required.

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
Woodland.lua               entry: init, grid/key/enc handlers, redraw loops
lib/
  topology.lua              the map: cell records, coords, types, adjacency
  lexicon.lua                names, descriptions, per-cell defaults
  patch.lua                  the cable graph: add/remove/trim, serialisation
  state.lua                  shared runtime UI state
  gridui.lua                 grid render + hold/tap state machine
  screenui.lua                network / cell / edge / lexicon / meters views
  dispatch.lua                §6 type-interaction matrix (D->Knock so far)
  rambler.lua                 D-cell gaits + phase scheduler (metric only)
  voice.lua                   voice state: forwards Grain to the engine
  bridge.lua                  Lua-side wrapper around the engine commands
  Engine_Woodland.sc          SC: six modal voices, strike, canopy
```

(`exciter.lua` and `heartwood.lua` land in later phases.)
