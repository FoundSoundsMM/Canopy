# Woodland

A monome norns script for grid (128). Full design in
[`docs/woodland-spec.md`](docs/woodland-spec.md).

## Status: build phase 6 — "the re-cut"

Phases 1–5c built the instrument the spec describes: the patch graph and
grid/screen UI, the SC engine's modal voices, all the D-cell gaits with
D↔D Kuramoto coupling on a 2 ms scheduler, the exciters and the audio-rate
patch matrix, the heartwood diffusion lattice on both its discrete and
continuous sides, the grove's wandering pitch fields, and Weather as a
groove knob sweeping quantise → swing → chaos.

Phase 6 re-cuts the panel around what it turned out to be for: a
generative, organic drum machine.

```
     1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
1    ·   T   ·   S   S   S   S   S   S   S   S   S   S   ·   T   ·
2    P   V   M   R   R   R   R   R   R   R   R   R   R   P   V   M
3    ·   O   ·   F   H   ·   ·   ·   ·   ·   ·   H   F   ·   O   ·
4    C   ·   C   F   H   ·   D   D   D   D   ·   H   F   C   ·   C
5    C   ·   C   F   H   ·   D   D   D   D   ·   H   F   C   ·   C
6    ·   T   ·   F   H   ·   ·   ·   ·   ·   ·   H   F   ·   T   ·
7    P   V   M   R   R   R   R   R   R   R   R   R   R   P   V   M
8    ·   O   ·   S   S   S   S   S   S   S   S   S   S   ·   O   ·
```

`·` is dark and inert — an unregistered coordinate, not a cell you can
reach. The shape of what is left is what makes the panel readable.

- **Four voices, in the corners, with named sockets.** Six anonymous nodes
  per voice became four that each mean exactly one thing: **T** takes a
  pulse and strikes; **P** takes a pitch field (and its own knob is a depth
  multiplier on everything the fields do to that voice); **M** takes a
  stream — one input, one balance knob deciding whether it is injected into
  the resonator or bends the body — and a pulse there chokes; **O** is the
  voice's output. The **V** cell in the middle is not a socket at all.
- **The O socket closes the loop.** It is androgynous in the way the spec
  always wanted: continuously it is the voice's audio on a bus, so O→M is
  one voice ringing another and O→S is a voice colouring an exciter;
  discretely it is a pulse the instant the voice is struck, so a drum can
  trigger a drum. The pulse half costs nothing — Lua is the thing doing the
  striking, so it already knows — which is why voice↔voice feedback landed
  without ever needing the metering back-channel. A 28 ms per-voice
  refractory is what keeps a loop ringing rather than screaming.
- **The weave** (`weave.lua`) — twenty **R** cells, two rows of ten. A D
  cell decides *when*; an R cell decides what happens to a pulse on its way
  somewhere: divide, mult, delay, echo, chance, accent, sift, meet, hocket,
  swing, blur, latch, fill, rest, flam, ghost, roll, swell, mask, shift.
  `K1 + E2` swaps the rule exactly as it swaps a gait. Patch a straight
  four to the bar through Sedge and Drove and Bramble and it stops being a
  metronome and starts being a part, without a step ever being programmed.
  The three reactive gaits (divider, echo, coincidence) moved out of
  `rambler.lua` and into here, which is what they always were.
- **The climate** (`climate.lua`) — eight **C** cells in the outer corners,
  running on the scale of a piece rather than a bar: tide, creep, season,
  gust, breath, wane, flourish, shiver, from six seconds to ten minutes a
  turn. Cable one to any cell and that cell's own knob is walked around.
  The knob is never overwritten — a climate writes a separate offset that
  is summed on read, so the setting you left is the setting you left and
  pulling the cable puts it back exactly. This is the difference between a
  patch that loops and a patch that goes somewhere.
- **Twenty exciters** instead of ten. The original ten were weather and
  undergrowth; the second ten are aimed at a kit — skein (metal shimmer),
  flint (click), husk (scrape), tinder (fizz), mire (sub), glim (ping),
  rasp (buzz), cicada (chirr), hail (impacts), reed (breath).
- **A sound page per voice** (§5.5). Tap a voice cell and the screen
  becomes nine parameters — Tune, Bend, Decay, Body, Damp, Bright, Drive,
  Strike, Level — with `E1` picking one and `E2`/`E3` moving it coarsely
  and finely. Tap it again to go back. The old Grain macro is gone: it
  morphed four of these together behind one knob because there was nowhere
  to put four knobs, and a drum you can only shape through a macro is a
  drum you cannot tune.
- **Tune reaches lower, and Bend is new.** Tune's down side now spans three
  octaves instead of two — Oak's root can fall well under 10 Hz — and Bend
  is a strike-triggered pitch drop, decaying to Tune's pitch over ~60 ms.
  Bend at 0 is a no-op; turned up on a voice tuned low, it's most of the way
  to an 808 kick.
- **Held cells now name themselves.** The cell view prints a one-line,
  plain-English gloss of what the cell does, right under its name — pulled
  from `lexicon.lua`'s `describe`, which existed but was never wired into a
  screen. The numbers below it mean more once you know what they belong to.
- **A new eighth gait, `figure`** — a bank of sixteen-step patterns on the
  clock (four, backbeat, offbeat, tresillo, son, rumba, bossa, shiko).
  Euclidean gives an even spread of k in n and nothing else; this is where
  the crooked ones live.
- **Regrow rebuilt.** `K1+K2` no longer draws random cables between random
  cells — on a panel this size that was silence about half the time. It
  builds a patch with a shape (pulse-makers through the weave onto
  triggers, an exciter under each voice, sometimes a field, sometimes some
  weather, sometimes one voice feeding another) and seeds the settings of
  the cells it uses, so every Regrow plays.
- **The lexicon pages are gone.** They were a manual you had to leave the
  patch to read; what was worth reading off them is already printed on the
  cell and edge views, at the moment you are holding the thing it is about.
- **The network view's cables are dim and dotted.** At full brightness and
  solid, twenty cables is a ball of wool. An inverting cable is drawn with
  the dots further apart. The travelling pulse dots stay bright — they are
  what the view is for. Everything on that view is bucketed by brightness and
  painted once per level, so the whole frame is ~16 cairo paint calls at the
  64-cable cap rather than ~250; the per-frame command count is asserted in
  `test/soak.lua`, because overrunning it wedges matron's screen queue and
  takes the front panel down with it.

### Build phase 6b — the global param page

The network view described above, and the meters view cycled alongside it,
are gone — replaced by a nine-parameter list (§5.2, `gparam.lua`): the same
E1-select/E2-E3-nudge shape the voice sound page already had, for macros that
reach every voice at once. Weather is gone with it, split into independent
**Swing** and **Rain**. New: **Scale** (quantises every voice's pitch to a
scale, 0 = free), **Drops** (random pitch offset per strike), a global
**Decay** multiplier, a global **Pitch** transpose, and an output
**Compressor**. Canopy moved into the same list rather than keeping its own
bare encoder.

Not yet built: the metering back-channel (§7.4 — so continuous audio-rate
cell response is not lit), and PARAMS/PSET persistence.

## Install

From Maiden (norns' web REPL):

```
;install https://github.com/FoundSoundsMM/Woodland
```

or copy this repo to `~/dust/code/Woodland` by hand. Then select
**Woodland** from the norns script menu. A grid is required.

## Controls

- Hold a cell, tap another: patch them together (tap again to unpatch).
- Hold two cells together: `E3` sets that edge's gain.
- Hold a cell + `K1`, tap another: one-way cable.
- Hold a cell + `K2`+`K3`: sever every cable at that cell.
- Hold a cell: `E1` selects the focused cable, `E2` is that cell's one
  character parameter, `E3` is the focused cable's gain — or, with no cable
  focused, that sound's decay: a voice's ring time in seconds, or an
  exciter's envelopes as a ratio. Holding any of a voice's four sockets
  moves that voice's decay, since a socket is part of the voice rather than
  a sound of its own.
- Tap a **voice** cell: open its sound page. `E1` picks one of nine
  parameters, `E2`/`E3` move it coarsely and finely. Tap the cell again (or
  press `K3`) to go back. Holding the cell shows the same page without
  taking the encoders off the patch.
- Hold a **D**/**R**/**F**/**C** cell + `K1`, turn `E2`: swap its gait /
  rule / mode / shape.
- `K1` + tap a D cell (nothing else held): root it to the norns clock, or
  set it wild — metric, euclidean and figure are the ones with something to
  root to. Same gesture on an F cell snaps its field to the scale, or sets
  it free.
- Nothing held: `E1` picks one of nine global params (BPM, Swing, Rain,
  Scale, Drops, Decay, Pitch, Compressor, Canopy), `E2`/`E3` nudge it coarse/
  fine. `K1`+`E3` is the master level; `K2` toggles Still.
- **Swing and Rain are the groove knobs.** At Swing 0 / Rain 0 every pulse —
  however freely its cell runs — snaps onto a grid line, and unrelated gaits
  cohere into one groove: each cell quantises to the coarsest of
  8th/16th/32nd/64th that fits inside its own cycle, and a burst is triggered
  on the beat with its ratchet on a subdivision. Turning Swing up warps the
  grid so off-beats land late and beats stay put. Turning Rain up loosens the
  snap and grows jitter in its place, until at 1 nothing is held at all and
  the patch is rainfall in a forest — Rain also scales gait-rate drift,
  D↔D coupling and pitch-field wander. What the weave emits is deliberately
  *not* re-quantised — those pulses are derived from one that was already
  placed, and snapping a flam or a swung off-beat back onto the grid would
  undo the only thing it does.
- `K1`+`K2` (hold ~1s): Regrow — a seeded patch that already plays.
- `K1`+`K3` (hold ~1s): Clearing — cut every cable.

## Layout

```
Woodland.lua                entry: init, grid/key/enc handlers, Regrow
lib/
  topology.lua              the map: cell records, coords, types, adjacency
  lexicon.lua               names, descriptions, each cell type's one knob
  patch.lua                 the cable graph: add/remove/trim, serialisation
  quantise.lua              the groove: Swing/Rain place a gait's emission
  state.lua                 shared runtime UI state
  gridui.lua                grid render + hold/tap state machine
  screenui.lua              global param / cell / edge / voice views
  dispatch.lua              §6 type-interaction matrix: pulse events
                             (-> T/P/M, S, F, H) and the continuous patch
                             matrix (S<->S, S->M, S<->H, H<->H, H->M, O->*)
  rambler.lua               the eight D-cell gaits, the coupling scheduler,
                             and the shared pulse bus everything emits through
  weave.lua                 the twenty R-cell pulse transforms
  climate.lua               the eight C-cell slow modulators
  voice.lua                 voice sockets + the nine-parameter sound page
  gparam.lua                the nine-parameter global page (§4.1, §5.2)
  exciter.lua               S-cell control layer: lazy alloc, gating, Colour
  heartwood.lua             the diffusion lattice's discrete-event side
  grove.lua                 the pitch fields: modes, coupling, voice retuning
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Woodland.sc        SC: four modal voices with an output tap, twenty
                             exciters, the patch matrix, the heartwood delay
                             network, glide + pitch drift
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
defined at the top of `Woodland.lua` instead. If you add a lib, load its
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
- `groove.lua` — the Swing/Rain groove: divisions, lock, Swing ramping in and
  landing off-beats late without moving the grid, bursts triggered on the
  beat, Rain letting go independently of Swing, and the grid following the
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
  for every voice at once, and Compressor forwarding to the engine.
- `smoke.lua` — loads `Woodland.lua` itself and exercises every screen
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

`Engine_Woodland.sc` extends `CroneEngine`, a norns-specific class that
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

symlinks `lib/Engine_Woodland.sc` into SC's Extensions folder, headlessly
boots Crone, loads the engine, and reports pass/fail with a real exit code —
the same thing Maiden's compile log tells you on-device, runnable locally.
`Crone.context` is only set once the server's async boot finishes, so the
check polls for it rather than guessing a fixed delay (a fixed delay races
the boot and makes `Engine_Woodland:alloc`'s `context.server` read a nil
context).
