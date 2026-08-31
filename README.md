# Canopy

A monome norns script for grid (128). Full design in
[`docs/canopy-spec.md`](docs/canopy-spec.md).

## Status: the grid overhaul, and the screen after it

A second re-cut of the panel, on top of everything build phases 1–7 (and 6b,
6c, 6d) already built: an explicit Output row, one cable point per voice
instead of four sockets, Climate replaced by a small Clock family, and two
new step-sequencer lanes. Full detail and rationale in
[`docs/canopy-spec.md`](docs/canopy-spec.md) §2/§9; this is the short version.

Since then, five changes that are all about *playing* it rather than about
what it can make (spec §4.1b, §4.3, §5.1b, §5.2b):

- the screen is a **Digitakt-style widget grid** — an inverted title bar and
  a 4×2 grid of knobs and boxed readouts — instead of a list of text rows;
- the whole patch can be **externally clocked and started/stopped over MIDI**;
- opening a cell's page **dims the rest of the panel** down to that cell;
- a source can only sit in **one Output slot** — a second one moves it;
- three more soundscape loops join Rain (Cicada, Thunder, Sea) on a new
  **mixer page**, reached with `K3` and left with `K2`.

```
     1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
1    O   O   O   O   O   O   O   O   O   O   O   O   O   O   O   O
2    ·   M   ·   M   ·   F   F   F   N   N   N   ·   M   ·   M   ·
3    ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·
4    F   ·   ·  TM  TM   C   T   T   T   T   C  TM  TM   ·   ·   H
5    ·   F   ·   ·   ·   C   T   T   T   T   C   ·   ·   ·   H   ·
6    E   ·   F   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   H   ·   R
7    E   E   ·   F   ·   ·  Q4  Q4  Q4  Q4   ·   ·   H   ·   R   R
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
  is simultaneously the tap-to-open-settings-page target and the sole cable
  endpoint. All four sit together on row 2, two either side of the percussion
  block — they used to be split two-and-two between rows 2 and 7, where the
  pair down among the exciters and the weave read as scenery and the panel
  looked like it had two voices on it. What a cable does when it lands there is decided by what's at
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
  a lane is independently switchable on and off (`K1`+tap it, or the **Step**
  row on its page) and independently cable-able; the *last* cell in a lane is
  the "driver" — a pulse there advances the lane's shared playhead and fires
  whichever step it lands on, while a pulse on any other cell in the lane
  fires that step directly, bypassing the playhead entirely. Both lanes are
  centred on the panel, Q4 sitting symmetrically inside Q6, and the three
  states a cell can be in — empty, armed, and under the playhead — are spread
  across the brightness range rather than bunched at the bottom, so a running
  lane visibly runs.
- **The weave, heartwood, grove and exciters are all trimmed**, not changed:
  6 weave rules (was 14), a 4-node heartwood chain (was an 8-node ring), 4
  pitch fields (was 8), 6 exciters (was 20). Every weave rule and grove mode
  not given a dedicated seat is still reachable from the **Rule** / **Mode**
  row on that cell's settings page.

Everything from build phases 1–7 not mentioned above — the gait bank, the
Kuramoto coupling, Swing/Scatter, Regrow (now also wiring exactly one Output
cable per voice, or a regrown patch would be silent), the sound page shape —
is unchanged. See `docs/canopy-spec.md` for the full build-order history.

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

One gesture vocabulary, identical on every cell of every type. Nothing on the
panel has a gesture that only it responds to any more.

| gesture | what it does |
| --- | --- |
| **tap** a cell | toggle its settings page open / closed |
| **hold** a cell | glance at that same page, until you let go |
| **hold** a cell, `E1` / `E2` / `E3` | pick a row, move it coarse / fine |
| `K1` + **tap** a cell | fire it |
| **hold** one cell, **tap** another | cable them (tap again to unpatch) |
| **hold** one + `K1`, **tap** another | one-way cable |
| **hold two** cells | `E3` sets that cable's gain |
| **hold** a cell + `K2`+`K3` | sever every cable at that cell |

- **The settings page.** Every cell type has one, and it is the same object
  every time: a grid of eight widgets, `E1` to pick one, `E2`/`E3` to move it
  coarsely and finely. It is the same page whether you tapped it open or are
  just holding the cell — holding is a glance that borrows the encoders and
  gives them back, tapping latches it (press `K2`, or tap the cell again, to
  close). A list longer than eight pages rather than crowding; the header's
  dots say which page you are on. What used to be a modifier gesture is a
  widget on the page now: a T cell's **Gait** and **Clock** (rooted / wild),
  an R cell's **Rule**, an F cell's **Mode** and **Snap**, a sequencer
  step's **Step**, an E cell's **Decay**.
- **With a page open, the panel dims to that cell.** The cell you are
  inspecting goes to full, what it is cabled to stays readable, and
  everything else drops to a floor — so the grid is showing the same one
  thing the screen is. Close the page and the panel comes back.
- **`K1` + tap fires the cell**, whatever it is: a voice or a percussion cell
  strikes, an exciter fires one grain, a T / R / TM / C cell sends one pulse
  out of its own door, and a Q4/Q6 cell puts its step in or takes it out.
  This is how you audition a voice without patching anything — and if nothing
  it makes can reach an Output cell, directly or down the chain, it says
  **no output cable** rather than leaving you wondering.
- Nothing held: `E1` picks one of seven global params (BPM, Swing, Scatter,
  Scale, Drops, Decay, Pitch), `E2`/`E3` nudge it coarse/fine. `K1`+`E3` is
  the master level.
- **`K3` is the mixer, `K2` is back.** `K3` opens the mixer from anywhere,
  including from an open cell page — which it closes on the way, dropping
  that cell's focus. `K2` is the way back up: off the mixer, or out of a cell
  page, to the main screen. On the main screen, with nothing to come back
  from, `K2` is Still as it always was.
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
- **The mixer is four soundscape loops and the master.** `audio/Rain.wav`,
  `Cicada.wav`, `Thunder.wav` and `Sea.wav` all loop from init regardless of
  anything else on the panel; each fader is that loop's own dry level in the
  mix, 0 by default, so nothing says anything until it is asked to. They are
  a dry mix and nothing else — there is no path from a loop into a voice's
  resonator. (There used to be, when Rain was alone: the old **Excite** knob.
  It is gone rather than multiplied by four. The six E cells are still the
  panel's excitation sources.)
- **One source, one Output slot.** Position along the Output row *is* pan, so
  cabling a source to a second Out cell **moves** it rather than adding a
  second cable — the gesture reads as dragging it along the row. It keeps the
  gain it already had, and the rest of its patch is untouched.
- **Externally clocked.** Set `PARAMS > CLOCK > source` to **MIDI** (or Link)
  and the whole patch runs off it: the tempo, every clock-rooted T cell, and
  Start / Stop. A **Stop** is Still — gaits freeze, resonators ring out, and
  nothing that was in flight floods out when it resumes. A **Start** unfreezes
  and puts both sequencer lanes back to the top. With an external source
  selected, the BPM row becomes a readout and says `ext`.
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
  gridui.lua                grid render + the one gesture vocabulary
  cellparam.lua             a settings page for every cell type that did
                             not already have one (T, R, F, E, H, C, Q, Out)
  screenui.lua              the Digitakt-style widget grid: the global page,
                             the mixer page, the cell page, the edge view
  mixer.lua                 the four soundscape loops + the master (§4.1b)
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
  gparam.lua                the seven-parameter global page (§4.1, §5.2)
  exciter.lua               E-cell control layer: lazy alloc, gating, Colour
  heartwood.lua             the diffusion lattice's discrete-event side
  grove.lua                 the pitch fields: modes, coupling, voice retuning
  gvoice.lua                the six GVOICE-cell drums + their sound page
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Canopy.sc          SC: four modal voices, six percussion cells, six
                             exciters, the patch matrix, the four-node
                             heartwood, the Output row's fixed-pan mix
audio/
  Rain.wav                  the four always-on soundscape loops, mixed on
  Cicada.wav                 the mixer page (K3). ~66 MB together; Thunder
  Thunder.wav                and Cicada are minutes long, so between them
  Sea.wav                    they hold ~130 MB of scsynth buffer at runtime
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

- `rhythm.lua` — every gait produces pulses (including Skriker's new
  `swarm`), rooted gaits lock to the transport exactly, euclidean and figure
  play the counts they claim, Kuramoto locking at positive and negative
  gain, Still, and a densely cross-patched graph (including a voice-out
  loop) staying bounded.
- `weave.lua` — every one of the six surviving rules emits, divide/mult/mask
  produce the exact counts they promise (still reachable by cycling even
  though nothing defaults to them any more), sift gates on weight, accent
  reshapes without dropping, hocket round-robins its cables, delay is
  musical rather than millisecond, a chain of the multiplying rules with a
  voice loop in it stays bounded.
- `clockcell.lua` — a Clock cell fires at the expected multiple/division of
  the master clock, Ratio changes take effect, it never reacts to an
  incoming pulse (a pure source, same as Climate always was), and it
  freezes under Still.
- `sequencer.lua` — Q4/Q6 lane registration and driver flags, toggling a
  step affects only that step, a pulse on a non-driver step fires it
  directly regardless of the playhead, a pulse on the driver advances the
  playhead and fires whichever step it lands on only if that step is
  active, and a SEQ↔SEQ cable loop stays bounded the same way a TM↔TM one
  does.
- `screen.lua` — nothing on the 128x64 panel may overlap anything else. A
  recording screen stub gives every draw a bounding box, and every view the
  script can be in — the global page, the mixer, every widget of every cell's
  page held and open, a heavily cabled cell, every type pair on the edge
  view, and a header carrying a long message next to an `ext` tempo — is
  checked for collisions and for running off the panel. Two words may never
  share pixels; a word may sit inside a box (the inverted header bar, a chip,
  a widget's readout) but never inside a knob gauge, and never half-clipped
  by anything. This is the test the two original overlap bugs (a 2px bar
  under an 8px row, and a twelve-row list wrapping back over itself on a
  ten-row page) would have failed, and it is what pins the widget grid's
  geometry now.
- `gridui.lua` — the panel is key-for-key what the sketch it was drawn from
  says, all four voices are on row 2, both sequencer lanes are centred; a tap
  opens and closes the settings page on every cell type; `K1`+tap strikes a
  voice or a drum, grains an exciter, pulses a trigger and toggles a
  sequencer step, and warns when a voice has no path to an Output; the
  hold/tap cable gesture and its one-way variant are unharmed by either.
- `groove.lua` — the Swing/Scatter groove: divisions, lock, Swing ramping in
  and landing off-beats late without moving the grid, bursts triggered on the
  beat, Scatter letting go independently of Swing, and the grid following the
  transport.
- `decay.lua` — every voice decays against its own id directly (no more
  socket to forward through), an exciter gets the same knob as a ratio, and
  cells with no sound of their own store nothing.
- `exciter.lua` — lazy alloc/off, pulse-cable gating, Colour forwarding, and
  the patch matrix: a voice↔exciter cable resolves to *both* directions'
  spec (the exciter driving the voice's mod path, and the voice colouring
  the exciter) on one ordinary cable, and to only the relevant half on a
  one-way one.
- `heartwood.lua` — trimmed to the 4-node chain (`taproot`–`mycel`–`wyrd`–
  `ley`): a pulse injected at one end emerges from the others later and
  quieter, conductance spanning "dies within one hop" to "circulates", an
  H↔H shortcut closing a loop a bare chain can't, a T→H→T loop staying
  bounded, and the continuous matrix resolving a voice↔H cable to both
  directions at once, the same shape as voice↔exciter.
- `grove.lua` — trimmed to the 4 surviving fields: a cabled field retunes
  the voice *before* the strike, Range bounds it, snap lands on scale
  tones, a pulse steps a field with nothing struck, F↔F converges at
  positive gain, cabling straight to the voice's own point (no more P
  socket) works, and a bare voice still never plays the same pitch twice.
- `voice.lua` — the socket collapse: no more `.trig`/`.pitch`/`.mod`/`.out`
  ids, every cell is a legal cable endpoint including a voice, the sound
  page's three new rows (Hardness/Depth/Balance) push correctly, Tune as a
  real transposition, Body and Damp sweeping around each voice's own
  baseline, a voice answering with a pulse on every strike, and the
  refractory bounding a self-loop.
- `gvoice.lua` — the six percussion cells under their new `GVOICE` type and
  `gv.*` ids, same six-parameter page and strike/answer mechanic as before
  the rename.
- `tm.lua` — the four Turing Machine cells at their new coordinates,
  register stepping, Tap-gated answering pulse, and pitch feeding a voice
  directly (no more P socket to route through).
- `gparam.lua` — the global param page: E1 clamped at both ends, BPM's
  coarse/fine steps and clock/floor/ceiling clamping, Scale's one-entry-per-
  flick detent, Drops widening the per-strike spread, global Decay and
  Pitch reaching the engine for every voice at once, and an external clock
  source turning BPM into a readout that follows the incoming tempo.
- `mixer.lua` — the four soundscape loops load once each at the engine
  indices the `.sc` file expects, each fader is independent and forwards to
  its own loop, no loop excites anything, `K3`/`K2` move between the main
  screen, a cell page and the mixer in the documented order, and an external
  Start/Stop freezes and unfreezes the patch, resets the sequencer lanes and
  does not flood on resume.
- `smoke.lua` — loads `Canopy.lua` itself and exercises every screen
  view, the sound page, and every control against the new 72-cell panel.
- `soak.lua` — the same, but against a *strict* norns stub: `screen`, `util`
  and `clock` expose only the functions norns actually has, so calling one it
  doesn't is an error rather than a silent no-op. Redraws from every state
  (every cell held one at a time, every type pair held in twos, the
  global page with a live patch), thousands of random gestures with the
  scheduler running, and the per-frame screen command and paint budgets.
  This is the test that catches "the screen died but the grid still works".
- `perf.lua` — what the 2 ms tick costs, including the new Clock and
  sequencer ticks. Cheap on a dev machine, but the CM3 is the budget that
  matters, so re-check it there if the scheduler ever feels like the thing
  making the UI stutter.

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
context). This check never calls `amb_load`, so it never touches the
samples under `audio/` — an unloaded loop is silent, not an error.
