# Canopy

A monome norns script for grid (128). Full design in
[`docs/canopy-spec.md`](docs/canopy-spec.md).

## Status: the grid overhaul

A second re-cut of the panel, on top of everything build phases 1–7 (and 6b,
6c, 6d) already built: an explicit Output row, one cable point per voice
instead of four sockets, Climate replaced by a small Clock family, and two
new step-sequencer lanes. Full detail and rationale in
[`docs/canopy-spec.md`](docs/canopy-spec.md) §2/§9; this is the short version.

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
```

`·` is dark and inert — an unregistered coordinate, not a cell you can
reach. The shape of what is left is what makes the panel readable.

- **Nothing is heard by default.** The top row is sixteen Output cells;
  position sets pan, hard left to hard right. Cabling a voice, a percussion
  cell, an exciter or a heartwood node to one is the only way it's ever
  audible — the fixed automatic panning every voice used to get for free is
  gone, along with the always-on mix that used to carry it.
- **One cable point per voice, not four.** The old T/P/M/O socket cluster is
  gone; each voice (Oak, Hazel, Alder, Rowan) is now a single **M** cell that
  is simultaneously the tap-to-open-sound-page target and the sole cable
  endpoint. What a cable does when it lands there is decided by what's at
  the other end: a pulse always strikes it now (discrete choke is gone —
  there's no socket left to carry the difference); a stream (an exciter or
  the heartwood) always drives its mod path, per the sound page's own new
  **Balance** knob; a field or a Turing Machine cell tunes it, per the new
  **Depth** knob; cabling to another voice is fully symmetric — each side's
  audio feeds the other's mod path, and either can strike the other.
  **Hardness**, **Depth** and **Balance** — the old sockets' own knobs — now
  live as three extra rows on the voice's sound page.
- **Climate is gone; Clock is new.** The eight slow C-cell modulators
  (tide, creep, season, ...) are cut outright, not relocated. The letter is
  reused for something unrelated: four small cells that flash on a
  multiple/division of the master clock, feeding the trigger block next to
  them — the job Knocker's old `metric` gait used to do by default. Knocker
  itself is gone; **Skriker** takes its seat in the trigger block with a new
  gait, `swarm` — a short, unpredictable cluster of 2-4 hits.
- **The percussion cells are renamed and moved.** The six small drum voices
  (three pinged filters, three noise bursts) are unchanged mechanically but
  now sit in row 2 next to the voices, reading **F** (ping) and **N**
  (noise) on the panel instead of **G**.
- **Two new step-sequencer lanes, Q4 and Q6.** No phase of their own, like a
  Turing Machine — only a pulse cabled in moves them. Every physical cell in
  a lane is independently tap-toggleable (on/off) and independently
  cable-able; the *last* cell in a lane is the "driver" — a pulse there
  advances the lane's shared playhead and fires whichever step it lands on,
  while a pulse on any other cell in the lane fires that step directly,
  bypassing the playhead entirely.
- **The weave, heartwood, grove and exciters are all trimmed**, not changed:
  6 weave rules (was 14), a 4-node heartwood chain (was an 8-node ring), 4
  pitch fields (was 8), 6 exciters (was 20). Every weave rule and grove mode
  not given a dedicated seat is still reachable by `K1+E2` cycling, the same
  pattern the panel has used since it was first trimmed at build phase 6c.

Everything from build phases 1–7 not mentioned above — the gait bank, the
Kuramoto coupling, Swing/Scatter, Regrow (now also wiring an Output cable per
voice, or a regrown patch would be silent), the sound page shape, the always-
on rain ambience — is unchanged. See `docs/canopy-spec.md` for the full
build-order history.

## Install

From Maiden (norns' web REPL) — the GitHub repo is still named `Woodland`,
so this installs into `~/dust/code/Woodland`; rename that folder to `Canopy`
afterward so it matches `engine.name` and the script menu entry below:

```
;install https://github.com/FoundSoundsMM/Woodland
```

or copy this repo to `~/dust/code/Canopy` by hand. Then select
**Canopy** from the norns script menu. A grid is required.

## Controls

- Hold a cell, tap another: patch them together (tap again to unpatch). Every
  cell on the panel is a legal endpoint now, including a voice.
- Hold two cells together: `E3` sets that edge's gain.
- Hold a cell + `K1`, tap another: one-way cable.
- Hold a cell + `K2`+`K3`: sever every cable at that cell.
- Hold a cell: `E1` selects the focused cable, `E2` is that cell's one
  character parameter, `E3` is the focused cable's gain — or, with no cable
  focused, that sound's decay: a voice's ring time in seconds, or an
  exciter's envelopes as a ratio. A voice, a percussion cell and a Turing
  Machine cell have no single character knob — they have the sound page
  instead.
- Tap a **voice**, **percussion** or **Turing Machine** cell: open its sound
  page. `E1` picks a parameter, `E2`/`E3` move it coarsely and finely. Tap
  the cell again (or press `K3`) to go back. Holding the cell shows the same
  page without taking the encoders off the patch.
- Tap a **Q4/Q6 sequencer** cell (nothing else held): toggle that step on or
  off.
- Hold a **T**/**R**/**F** cell + `K1`, turn `E2`: swap its gait / rule /
  mode.
- `K1` + tap a T cell (nothing else held): root it to the norns clock, or
  set it wild — euclidean, figure and metric are the gaits with something to
  root to. Same gesture on an F cell snaps its field to the scale, or sets
  it free.
- Nothing held: `E1` picks one of nine global params (BPM, Swing, Scatter,
  Scale, Drops, Decay, Pitch, Rain, Excite), `E2`/`E3` nudge it coarse/
  fine. `K1`+`E3` is the master level; `K2` toggles Still.
- **Swing and Scatter are the groove knobs.** At Swing 0 / Scatter 0 every
  pulse — however freely its cell runs — snaps onto a grid line, and
  unrelated gaits cohere into one groove: each cell quantises to the coarsest
  of 8th/16th/32nd/64th that fits inside its own cycle, and a burst is
  triggered on the beat with its ratchet on a subdivision. Turning Swing up
  warps the grid so off-beats land late and beats stay put. Turning Scatter
  up loosens the snap and grows jitter in its place, until at 1 nothing is
  held at all — Scatter also scales gait-rate drift, D↔D coupling and
  pitch-field wander. What the weave emits is deliberately *not*
  re-quantised — those pulses are derived from one that was already placed,
  and snapping a flam or a swung off-beat back onto the grid would undo the
  only thing it does.
- **Rain and Excite are the literal rain.** `audio/Rain.wav` loops from init
  regardless of anything else on the panel; Rain is its own dry level in the
  mix (0 by default, so it says nothing until asked to), and Excite is how
  much that same audio continuously drives every voice's resonator, whether
  or not anything is patched.
- `K1`+`K2` (hold ~1s): Regrow — a seeded patch that already plays.
- `K1`+`K3` (hold ~1s): Clearing — cut every cable.

## Layout

```
Canopy.lua                  entry: init, grid/key/enc handlers, Regrow
lib/
  topology.lua              the map: cell records, coords, types, adjacency
  lexicon.lua               names, descriptions, each cell type's one knob
  patch.lua                 the cable graph: add/remove/trim, serialisation
  quantise.lua              the groove: Swing/Scatter place a gait's emission
  state.lua                 shared runtime UI state
  gridui.lua                grid render + hold/tap state machine
  screenui.lua              global param / cell / edge / voice views
  dispatch.lua              §6 type-interaction matrix: pulse events
                             (-> voice, GVOICE, E, F, H) and the continuous
                             patch matrix (E<->E, E->voice, E<->H, H<->H,
                             H->voice, voice<->voice, *->O)
  rambler.lua               the eight T-cell gaits, the coupling scheduler,
                             and the shared pulse bus everything emits through
  weave.lua                 the six R-cell pulse transforms
  clockcell.lua             the four C-cell clock flashers (§2.9)
  sequencer.lua             the Q4/Q6 step-sequencer lanes (§2.10)
  voice.lua                 the eleven-parameter voice sound page (§5.5)
  gparam.lua                the nine-parameter global page (§4.1, §5.2)
  exciter.lua               E-cell control layer: lazy alloc, gating, Colour
  heartwood.lua             the diffusion lattice's discrete-event side
  grove.lua                 the pitch fields: modes, coupling, voice retuning
  gvoice.lua                the six GVOICE-cell drums + their sound page
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Canopy.sc          SC: four modal voices, six percussion cells, six
                             exciters, the patch matrix, the four-node
                             heartwood, the Output row's fixed-pan mix
audio/
  Rain.wav                  the always-on rain ambience (Rain/Excite, §4.1)
test/
  run.sh                    offline test run (needs `lua`, no hardware)
  sc_check.sh               headless SuperCollider compile/load check
```

## A note on `include`

norns' global `include()` is `dofile`-based: it re-executes the file and
returns a **new table** every call. `topology`, `patch` and `state` are
shared mutable singletons, so plain `include()`s would hand `gridui`,
`screenui` and the scheduler three separate patch graphs that never see
each other's cables. Every module here is loaded through the `wl()` memo
defined at the top of `Canopy.lua` instead. If you add a lib, load its
dependencies with `wl("name")`, never `include()`.

## Tests

```
sh test/run.sh
```

Stubs norns (`util`, `clock`, `metro`, `screen`, `grid`, `engine`) and
drives the scheduler on a virtual clock, so everything below is checkable
on a laptop against the stubbed `engine.*` call log — there is no SC here
to actually render audio.

- `rhythm.lua` — every gait produces pulses, rooted gaits lock to the
  transport exactly, euclidean and figure play the counts they claim,
  Kuramoto locking at positive and negative gain, Still, and a densely
  cross-patched graph (now including a voice-out loop) staying bounded.
- `weave.lua` — every one of the twenty rules emits, divide/mult/mask
  produce the exact counts they promise, sift gates on weight, accent
  reshapes without dropping, hocket round-robins its cables without ever
  going back out of the one the pulse came in on, delay is musical rather
  than millisecond, a chain of the multiplying rules with a voice-out loop
  in it stays bounded, and swapping a rule resets what the old one counted.
- `climate.lua` — a cabled climate moves the far cell's effective knob and
  not its setting, severing restores it exactly, E2 still works underneath,
  two climates average rather than race, every shape moves and stays in
  range, a pulse landing on a climate does nothing to it (see the C handler
  in `dispatch.lua` for why that matters), and Still freezes it.
- `groove.lua` — the Swing/Scatter groove: divisions, lock, Swing ramping in
  and landing off-beats late without moving the grid, bursts triggered on the
  beat, Scatter letting go independently of Swing, and the grid following the
  transport.
- `decay.lua` — every voice starts on its own ring time, the knob moves it
  in seconds, a socket hands the gesture to its voice, an exciter gets the
  same knob as a ratio, and cells with no sound of their own store nothing.
- `exciter.lua` — lazy alloc/off, pulse-cable gating, Colour forwarding,
  and the patch matrix resolving cables to the right SC bus numbers.
- `heartwood.lua` — a pulse injected at one node emerges from the others
  later and quieter, conductance spanning "dies within one hop" to
  "circulates", H↔H shortcuts beating the ring, a D→H→D loop staying
  bounded, and Still freezing what is in flight.
- `grove.lua` — a cabled field retunes the voice *before* the strike, Range
  bounds it, snap lands on scale tones, a pulse steps a field with nothing
  struck, F↔F converges at positive gain, severing hands the voice back its
  fundamental, and a bare voice still never plays the same pitch twice.
- `voice.lua` — the four sockets and the dark corners of a cluster, the
  sound page pushing all nine at init, Tune as a real transposition, Body
  and Damp sweeping around each voice's own baseline, the P socket's depth,
  the O socket answering with a pulse on every strike and resolving to an
  audio tap, and the refractory bounding a self-loop.
- `gparam.lua` — the global param page: E1 clamped at both ends, BPM's
  coarse/fine steps and clock/floor/ceiling clamping, Scale's one-entry-per-
  flick detent and quantising `grove.hz` only once it isn't free, Drops
  widening the per-strike spread, global Decay and Pitch reaching the engine
  for every voice at once, and Rain/Excite forwarding to the engine.
- `smoke.lua` — loads `Canopy.lua` itself and exercises every screen
  view, the sound page, and every control.
- `soak.lua` — the same, but against a *strict* norns stub: `screen`, `util`
  and `clock` expose only the functions norns actually has, so calling one it
  doesn't is an error rather than a silent no-op. Redraws from every state
  (all 92 cells held one at a time, all 130 type pairs held in twos, the
  global page with a live patch), 4000 random gestures with the scheduler
  running, and the per-frame screen command and paint budgets. This is the
  test that catches "the screen died but the grid still works".
- `perf.lua` — what the 2 ms tick costs. Cheap on a dev machine, but the
  CM3 is the budget that matters, so re-check it there if the scheduler
  ever feels like the thing making the UI stutter.

## SuperCollider toolchain (optional, for compile-checking off-device)

`Engine_Canopy.sc` extends `CroneEngine`, a norns-specific class that
isn't part of stock SuperCollider, so checking it compiles needs SC itself
plus norns' Crone architecture:

```
brew install --cask supercollider
```

then, from an sclang session (open the app once, or run any `.scd` file —
sclang has no `-e` flag), install the
[norns-sc](https://github.com/madskjeldgaard/norns-sc) quark, which packages
Crone for desktop use:

```supercollider
Quarks.install("https://github.com/madskjeldgaard/norns-sc");
```

Then:

```
sh test/sc_check.sh
```

symlinks `lib/Engine_Canopy.sc` into SC's Extensions folder, headlessly
boots Crone, loads the engine, and reports pass/fail with a real exit code —
the same thing Maiden's compile log tells you on-device, runnable locally.
`Crone.context` is only set once the server's async boot finishes, so the
check polls for it rather than guessing a fixed delay (a fixed delay races
the boot and makes `Engine_Canopy:alloc`'s `context.server` read a nil
context). This check never calls `rain_load`, so it never touches
`audio/Rain.wav` — a missing or unloaded sample is silent, not an error.
