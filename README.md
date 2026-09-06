# Canopy

A monome norns script for grid (128). Full design in
[`docs/canopy-spec.md`](docs/canopy-spec.md).

## Status: the grid overhaul, and the screen after it

A second re-cut of the panel, on top of everything build phases 1–7 (and 6b,
6c, 6d) already built: an explicit Output row, one cable point per voice
instead of four sockets, and Climate replaced by a small Clock family. Full
detail and rationale in
[`docs/canopy-spec.md`](docs/canopy-spec.md) §2/§9; this is the short version.

Since then, five changes that are all about *playing* it rather than about
what it can make (spec §4.1b, §4.3, §5.1b, §5.2b):

- the screen draws **one shape per parameter** — a 4×2 grid where no two
  widgets look alike, under an 8px header, each with its own reading printed
  under it in whatever unit the parameter is in (seconds, semitones, hertz,
  cents, ×multiples, per cent, a count of steps);
- the whole patch can be **externally clocked and started/stopped over MIDI**;
- opening a cell's page **dims the rest of the panel** down to that cell;
- a source can only sit in **one Output slot** — a second one moves it;
- three more soundscape loops join Rain (Cicada, Thunder, Sea) on a new
  **mixer page**, reached with `K3` and left with `K2`.

And an interface pass on top of that, which is where the panel stands now:

- **the heartwood is gone**, and the four seats it had are four **sample
  players** — Rain, Cicada, Thunder and Sea. A pulse plays one, under a slow
  attack and a slow fall you set per cell;
- **the mixer is built from the patch**: one channel for every Output cell
  something is actually cabled to, appearing and disappearing with the
  cables, up to sixteen. There is no master row — that is one number over the
  whole instrument, and it is on `K1`+`E3` where it always was. Each channel
  is named after the instrument on it and carries a live meter;
- **an LFO picks what it moves.** Cable one to a cell and its page gains a
  **Target** and a **Param** row: pick any knob on that cell's own settings
  page and the LFO moves it, by **Depth**, around wherever you left it;
- **the screen says what a cell is in words** — `Voice: Oak`, `Trigger: Hob`,
  `Exciter: Ember` — instead of the one-letter panel code (`M Oak`, `T Hob`)
  there was no legend to look up;
- **the four sample players are routed**, like every other source: they used
  to mix themselves, panned by their own seat, and take an Output cable now
  — which is what puts them back on the mixer page as channels called Rain,
  Cicada, Thunder and Sea;
- **a clock cell can be a gate instead**: its new **Mode** row switches it
  from a pulse on a division of the transport to a trigger that is simply
  always high, holding whatever it is cabled to open — a modal voice rings
  continuously, a sample plays on, a gust swells in and stays;
- **an Output cell carries one source.** A second one landing there evicts
  the first, the same way a source landing on a second Out cell moves itself.
  That is what lets a channel be named after its instrument;
- **Scale starts on P.Maj**, the major pentatonic, rather than on free, and
  the four scales are abbreviated to fit the shape that draws them — free,
  P.Maj, P.Min, E.Pn1, E.Pn2;
- **Rain draws rainfall**, light at the bottom of the knob and heavy at the
  top, and it is the one shape on the panel that moves on its own;
- the gusts are **Gust 1–12** and the clocks **Clock 1–4**, twelve and four of
  one thing rather than twelve and four folk names;
- a **clock cell divides down to 1/128** of a beat, not 1/8, with 1× on the
  middle detent;
- **Cross on a gust is deep enough to hear**: two gusts cabled together now
  genuinely FM each other, over two octaves at full Cross;
- **Scatter is Rain** and **Drops is Plonks** on the global page.

And a pages pass on top of *that*, which is where it stands today — three
changes that are really one change, about giving each family the page it
needs (spec §2.11b, §4.1c, §4.4):

- **the gusts have a page of their own**, between the main screen and the
  mixer. Five knobs — **Pitch**, **Timbre**, **Attack**, **Cross**, **Level**
  — that move all twelve cells *together*, and the **Space / Delay / Regen**
  of the delay line they share, which used to be the global page's awkward
  second half. The five are **offsets, not values**: each sits at a centre
  meaning "leave them alone", so sliding one keeps whatever spread you have
  put between the twelve, and turning it back to the middle puts them exactly
  where they were. There is no family Decay because there already is one —
  the global page's Decay reaches every gust, one `K2` away;
- **Drums** — the seat the delay rows left free on the global page. A switch
  saying whether the global **Plonks**, **Decay** and **Pitch** reach the six
  percussion cells as well as the four voices. Off, they are drums; on, the
  kit transposes with the patch, breathes on every hit and rings for as long
  as everything else does;
- **a Colour page**, one `K3` past the mixer: eight processors across the
  master output. **Tape** (saturation, top end coming off as it is driven,
  and a slow wow), **Crush** (sixteen bits down to about three), **Alias**
  (sample rate held down to a few hundred hertz), **Loss** (a low-bitrate
  codec — the band closing from the top, surviving partials warbling, pre-echo
  ahead of every transient), **Chorus** and **Swirl** (its depth and its
  rate), **Shape** (a bipolar transient designer — softer attacks below the
  middle, snappier above) and **Comp** (one knob doing threshold, ratio and
  makeup, with a 4 ms attack so a drum's click gets out before the gain comes
  down). Every one of them is a genuine bypass at its default, so a patch
  that never opens the page sounds exactly as it did before the page existed;
- **Swing defaults to 0.** A fresh patch arrives straight, and shuffle is
  something you add rather than something you have to find and turn down.

```
     1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
1    O   O   O   O   O   O   O   O   O   O   O   O   O   O   O   O
2    ·   M   ·   M   ·   F   F   F   N   N   N   ·   M   ·   M   ·
3    ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·
4    F   ·   ·  TM  TM   C   T   T   T   T   C  TM  TM   ·   ·   S
5    ·   F   ·   ·   ·   C   T   T   T   T   C   ·   ·   ·   S   ·
6    E   ·   F   ·   ·   ·   L   L   L   L   ·   ·   ·   S   ·   R
7    E   E   ·   F   ·   G   G   G   G   G   G   ·   S   ·   R   R
8    E   E   E   ·   ·   G   G   G   G   G   G   ·   ·   R   R   R
```

`O` output · `M` voice · `F`/`N` percussion (ping / noise) · `TM` register ·
`C` clock · `T` trigger · `S` sample player · `E` exciter · `R` weave ·
`G` gust · `L` LFO · `F` (column 1–4 diagonal) pitch field.

`·` is dark and inert — an unregistered coordinate, not a cell you can
reach. The shape of what is left is what makes the panel readable.

- **Nothing is heard by default.** The top row is sixteen Output cells;
  position sets pan, hard left to hard right. Cabling a voice, a percussion
  cell or an exciter to one is the only way it's ever
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
  there's no socket left to carry the difference); a stream (an exciter, a
  gust, an LFO) always drives its mod path, per the sound page's own new
  **Balance** knob; a field or a Turing Machine cell tunes it, per the new
  **Depth** knob; cabling to another voice is fully symmetric — each side's
  audio feeds the other's mod path, and either can strike the other.
  **Hardness**, **Depth** and **Balance** — the old sockets' own knobs — now
  live as three extra rows on the voice's sound page.
- **Climate is gone; Clock is new.** The eight slow C-cell modulators
  (tide, creep, season, ...) are cut outright, not relocated. The letter is
  reused for something unrelated: four small cells that flash on a
  multiple/division of the master clock, feeding the trigger block next to
  them — the job Knocker's old `metric` gait used to do by default. Each also
  has a second mode, **High**, in which it stops clocking and simply holds
  whatever it is cabled to open. Knocker
  itself is gone; **Skriker** takes its seat in the trigger block with a new
  gait, `swarm` — a short, unpredictable cluster of 2-4 hits.
- **The percussion cells are renamed and moved.** The six small drum voices
  (three pinged filters, three noise bursts) are unchanged mechanically but
  now sit in row 2 next to the voices, reading **F** (ping) and **N**
  (noise) on the panel instead of **G**.
- **The bottom two rows are twelve gusts.** Two step-sequencer lanes (Q4 and
  Q6) sat here briefly and are gone: what the panel wanted there was not
  another way to make a pulse — it already has T, C, R and TM — but something
  to *play*. A gust is a small drone synth, loosely a Ciat-Lonbarde Deerhorn:
  a folded triangle under a slow swell and a slow fall you set per cell.
  Press one and it sounds; a pulse cabled in sounds it too. It is the one
  family heard without an Output cable, panned by the column it sits in, and
  all twelve share one delay line off the gusts page. Cable two together and
  they FM each other, as deeply as **Cross** on each is turned up.
- **Four LFOs sit on the row above them.** Plain sines, one knob each until
  you cable one somewhere — see **Target** and **Param** above.
- **The weave, grove and exciters are all trimmed**, not changed: 6 weave
  rules (was 14), 4 pitch fields (was 8), 6 exciters (was 20). Every weave
  rule and grove mode not given a dedicated seat is still reachable from the
  **Rule** / **Mode** row on that cell's settings page. The heartwood was
  trimmed too, from an 8-node ring to a 4-node chain, before being cut
  outright — see the sample players above.

Everything from build phases 1–7 not mentioned above — the gait bank, the
Kuramoto coupling, Swing/Rain, Regrow (now also wiring exactly one Output
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
  every time: a grid of eight widgets — a shape, its value, its name — `E1`
  to pick one, `E2`/`E3` to move it coarsely and finely. It is the same page whether you tapped it open or are
  just holding the cell — holding is a glance that borrows the encoders and
  gives them back, tapping latches it (press `K2`, or tap the cell again, to
  close). A list longer than eight pages rather than crowding; the header's
  dots say which page you are on. What used to be a modifier gesture is a
  widget on the page now: a T cell's **Gait** and **Clock** (rooted / wild),
  an R cell's **Rule**, an F cell's **Mode** and **Snap**, a C cell's
  **Ratio** and **Mode**, an E cell's **Decay**.
- **With a page open, the panel dims to that cell.** The cell you are
  inspecting goes to full, what it is cabled to stays readable, and
  everything else drops to a floor — so the grid is showing the same one
  thing the screen is. Close the page and the panel comes back.
- **`K1` + tap fires the cell**, whatever it is: a voice or a percussion cell
  strikes, an exciter fires one grain, a T / R / TM / C cell sends one pulse
  out of its own door, and a gust or a sample cell plays. This is how you
  audition a voice without patching anything — and if nothing it makes can
  reach an Output cell, directly or down the chain, it says **no output
  cable** rather than leaving you wondering. Gusts are the one exemption:
  they route themselves, so having no output cable is their normal state
  rather than the confusing one that warning exists for.
- Nothing held: `E1` picks one of eight global params — BPM, Swing, Rain,
  Scale, Plonks, Decay, Pitch, Drums — and `E2`/`E3` nudge it coarse/fine.
  `K1`+`E3` is the master level.
- **`K3` is forward, `K2` is back**, one page at a time down one stack:
  **main screen → gusts → mixer → colour → map**. Neither end wraps — `K3` on
  the map stays on the map, and `K2` on the main screen, with nothing to come
  back from, is Still as it always was. `K3` works from an open cell page too,
  which it closes on the way, dropping that cell's focus. The order is the
  signal's own: the gusts are the one family that routes itself, the mixer
  balances what the cables deliver, Colour is what the balanced mix goes
  through on its way out, and the map is the reference you check rather than
  a surface you play. Each page keeps its own `E1` cursor, so stepping away
  and back lands on the row you left.
- **Swing and Rain are the groove knobs.** At Swing 0 / Rain 0 every
  pulse — however freely its cell runs — snaps onto a grid line, and
  unrelated gaits cohere into one groove: each cell quantises to the coarsest
  of 8th/16th/32nd/64th that fits inside its own cycle, and a burst is
  triggered on the beat with its ratchet on a subdivision. Turning Swing up
  warps the grid so off-beats land late and beats stay put. Turning Rain
  up loosens the snap and grows jitter in its place, until at 1 nothing is
  held at all — Rain also scales gait-rate drift, D↔D coupling and
  pitch-field wander. (It reads **Rain** on the panel and `scatter` in the
  code: the rename is of the word, not of the mechanism.) What the weave emits is deliberately *not*
  re-quantised — those pulses are derived from one that was already placed,
  and snapping a flam or a swung off-beat back onto the grid would undo the
  only thing it does.
- **The mixer is your live outputs, by name, with meters.** It has no fixed
  contents and no master row: a channel appears for an Output cell the moment
  something is cabled to it, and goes again when the cable is pulled, up to
  sixteen. It is called after the instrument on it — "Thunder", not "Out 12"
  — because an Output cell carries exactly one source, and by the time six
  channels are open the pan position is the least useful thing about any of
  them. Every channel carries a live meter, read after its own fader, so
  pulling a channel down pulls its meter down too; the same reading lights
  that cell on the grid, which makes the Output row a sixteen-segment meter
  of the whole patch. A channel starts at unity, so one that has just
  appeared is not also silent. The fader and the cable's own gain are
  different things: the gain says how much of *that source* arrives at that
  pan position, and the fader is that instrument's level in the mix.
  `K1`+`E3` is still the master, from this page as from every other.
- **The four field recordings are cells now.** `audio/Rain.wav`,
  `Cicada.wav`, `Thunder.wav` and `Sea.wav` used to loop from init with a
  fader each. They are the four **S** cells on the right-hand diagonal
  instead: a pulse plays one from the top under an attack and a fall you set
  per cell, up to twenty seconds in and forty out. Each is cabled to an
  Output cell like every other source — they used to mix themselves, and
  don't any more, which is what puts them back on the mixer page under their
  own names. There is no path from one into a voice's resonator; the six E
  cells are still the panel's excitation sources.
- **An LFO picks what it moves.** Cable one anywhere and its page gains
  **Target** (which of the cells it is cabled to) and **Param** (which row of
  *that cell's* own settings page). It then moves exactly that knob, by
  **Depth**, around wherever you left it — the stored value never moves, so
  the screen keeps showing where you put it and turning it still works while
  the LFO runs. Param's first entry is **signal**, the old behaviour: no knob
  is modulated and the cable stays the plain audio-rate one, which is what an
  LFO cabled to an Output cell (a sine tone) wants.
- **One source, one Output slot.** Position along the Output row *is* pan, so
  cabling a source to a second Out cell **moves** it rather than adding a
  second cable — the gesture reads as dragging it along the row. It keeps the
  gain it already had, and the rest of its patch is untouched.
- **Externally clocked.** Set `PARAMS > CLOCK > source` to **MIDI** (or Link)
  and the whole patch runs off it: the tempo, every clock-rooted T cell, and
  Start / Stop. A **Stop** is Still — gaits freeze, resonators ring out, and
  nothing that was in flight floods out when it resumes. A **Start**
  unfreezes and drops whatever the freeze caught mid-flight rather than
  flushing it. With an external source selected, the BPM row becomes a
  readout and says `ext`.
- `K1`+`K2` (hold ~1s): Regrow — a seeded patch that already plays.
- `K1`+`K3` (hold ~1s): Clearing — cut every cable.

## Layout

```
Canopy.lua                  entry: init, grid/key/enc handlers, Regrow
lib/
  topology.lua              the map: cell records, coords, types, adjacency
  lexicon.lua               names, descriptions, each cell type's one knob
  patch.lua                 the cable graph: add/remove/trim, serialisation
  quantise.lua              the groove: Swing/Rain place a gait's emission
  state.lua                 shared runtime UI state
  gridui.lua                grid render + the one gesture vocabulary
  cellparam.lua             a settings page for every cell type that did
                             not already have one (T, R, F, E, C, Out)
  screenui.lua              the widget grid: the global page, the gusts
                             page, the mixer, the Colour page, the cell
                             page, the edge view, the map
  glyph.lua                 the shape vocabulary: twenty-eight drawn shapes,
                             one per parameter, no two alike, 26 x 13 with
                             the value line under each (§5.2d)
  mixer.lua                 one named, metered channel per live output (§4.1b)
  dispatch.lua              §6 type-interaction matrix: pulse events
                             (-> voice, GVOICE, GUST, SMP, E, F) and the
                             continuous patch matrix (E<->E, E->voice,
                             voice<->voice, GUST<->*, LFO->*, *->O)
  rambler.lua               the eight T-cell gaits, the coupling scheduler,
                             and the shared pulse bus everything emits through
  weave.lua                 the six R-cell pulse transforms
  clockcell.lua             the four C-cell clock flashers (§2.9)
  voice.lua                 the eleven-parameter voice sound page (§5.5)
  gparam.lua                the eight-parameter global page (§4.1, §5.2)
  colour.lua                the master colour chain's page (§4.4)
  exciter.lua               E-cell control layer: lazy alloc, gating, Colour
  sample.lua                the four S-cell sample players (§2.5)
  gust.lua                  the twelve G-cell drone synths (§2.11), and the
                             gusts page that moves all twelve at once (§2.11b)
  lfo.lua                   the four L-cell sines, and what each one moves
  grove.lua                 the pitch fields: modes, coupling, voice retuning
  gvoice.lua                the six GVOICE-cell drums + their sound page
  bridge.lua                Lua-side wrapper around the engine commands
  Engine_Canopy.sc          SC: four modal voices, six percussion cells, six
                             exciters, twelve gusts, four sample players,
                             four sines, the patch matrix, the Output row's
                             fixed-pan mix
audio/
  Rain.wav                  one per S cell, played rather than looped.
  Cicada.wav                 ~66 MB together; Thunder and Cicada are minutes
  Thunder.wav                long, so between them they hold ~130 MB of
  Sea.wav                    scsynth buffer at runtime
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
- `clockcell.lua` — Mode: High stops a cell clocking and holds every family
  at the far end of its cables open instead, letting go when the mode, the
  cable or the whole patch changes, with two High cells on one target
  counting as one grip; and a Clock cell fires at the expected multiple/division of
  the master clock, Ratio changes take effect, it never reacts to an
  incoming pulse (a pure source, same as Climate always was), and it
  freezes under Still.
- `screen.lua` — nothing on the 128x64 panel may overlap anything else. A
  recording screen stub gives every draw a bounding box, and every view the
  script can be in — the global page, the gusts page, the mixer, the Colour
  page (both at every row and with every knob at both ends of its travel),
  every widget of every cell's page held and open, a heavily cabled cell,
  every type pair on the edge view, and a header carrying a long message next
  to an `ext` tempo — is
  checked for collisions and for running off the panel. Two words may never
  share pixels; a word may sit inside a box but never inside a shape, and
  never half-clipped by anything. This is the test the two original overlap
  bugs (a 2px bar under an 8px row, and a twelve-row list wrapping back over
  itself on a ten-row page) would have failed, and it is what pins the widget
  grid's geometry now. It also holds the shape vocabulary to its own rule:
  every row names a shape, every shape it names exists, and **no page shows
  the same shape twice** — two exceptions, both named there.
- `render.lua` — not a test. It rasterises the real `screenui.lua` into a
  PGM per view so the panel can be looked at without a norns on the desk;
  a geometry check cannot tell you whether a Decay looks like a decay.
  `ROOT=$(pwd) SP=$(pwd)/test lua test/render.lua <outdir>`
- `gridui.lua` — the panel is key-for-key what the sketch it was drawn from
  says, all four voices are on row 2, and both gust rows and the LFO row
  above them are centred; a tap opens and closes the settings page on every
  cell type; `K1`+tap strikes a voice or a drum, grains an exciter, pulses a
  trigger and sounds a gust, and warns when a voice has no path to an Output;
  the hold/tap cable gesture and its one-way variant are unharmed by either.
- `groove.lua` — the Swing/Rain groove: divisions, lock, Swing ramping in
  and landing off-beats late without moving the grid, bursts triggered on the
  beat, Rain letting go independently of Swing, and the grid following the
  transport.
- `decay.lua` — every voice decays against its own id directly (no more
  socket to forward through), an exciter gets the same knob as a ratio, and
  cells with no sound of their own store nothing.
- `exciter.lua` — lazy alloc/off, pulse-cable gating, Colour forwarding, and
  the patch matrix: a voice↔exciter cable resolves to *both* directions'
  spec (the exciter driving the voice's mod path, and the voice colouring
  the exciter) on one ordinary cable, and to only the relevant half on a
  one-way one.
- `sample.lua` — the four sample cells on the seats the heartwood had, and
  no `H` cell left anywhere; one buffer loaded per cell at the engine index
  the `.sc` file expects; the envelope centred on each cell's own default and
  reaching seconds at the middle of the knob; the global Decay macro reaching
  them; a pulse playing one and — unlike a drum or a gust — nothing coming
  back out, so a cable loop through one cannot run away; a cable to an Output
  cell building an ordinary audio patch off that cell's own tap; and `K1`+tap
  warning "no output cable" until one is drawn.
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
- `gust.lua` — the twelve drone cells: where they sit and how their columns
  pan them, a press sounding a note, the note locking onto the global Scale
  and following a transpose, the envelope knobs and the global Decay macro
  reaching the engine in seconds, a pulse sounding one and getting a pulse
  back, two cabled together cross-modulating, a loop staying bounded — and
  the family page: the five macros as *offsets* that slide all twelve
  together while preserving the spread between them and leaving each cell's
  own stored knob untouched, clamping per cell at the ends, pushing all twelve
  when nudged, and the per-cell pages reading the effective value while `E2`
  still moves the cell's own knob.
- `tm.lua` — the four Turing Machine cells at their new coordinates,
  register stepping, Tap-gated answering pulse, and pitch feeding a voice
  directly (no more P socket to route through).
- `gparam.lua` — the global param page: eight rows on exactly one screen, E1
  clamped at both ends, BPM's coarse/fine steps and clock/floor/ceiling
  clamping, Scale's one-entry-per-flick detent, Plonks widening the per-strike
  spread, global Decay and Pitch reaching the engine for every voice at once,
  an external clock source turning BPM into a readout that follows the
  incoming tempo, Swing arriving at 0, and the **Drums** switch — off, the six
  percussion cells ignore Plonks, Decay and Pitch entirely and send no
  per-strike traffic; on, the kit transposes, breathes on every hit and takes
  the Decay multiplier, and the switch itself re-pushes all six on the way.
- `colour.lua` — the master colour chain: eight rows on one screen, every key
  one the engine will actually accept (checked against a hardcoded copy of
  `\colourKeys`, so the test cannot agree with itself), no two rows drawing
  the same shape, every row arriving at a genuine bypass, `init` pushing all
  eight exactly once at this module's own defaults, each knob clamping and
  forwarding its own key, and `K3`/`K2` reaching and leaving the page with
  `K1`+`E3` still the master from it.
- `mixer.lua` — the four recordings load once each at the engine indices the
  `.sc` file expects (they belong to the sample cells now, not to this page);
  the page is built from the patch, growing a channel as an Output cell is
  cabled to and losing it again when the cable is pulled, empty when nothing
  is cabled and never more than sixteen; each channel named after the
  instrument on it, renamed when a second source evicts the first, and drawn
  with a meter; each an independent 0..1 knob that forwards to its own
  output; `K3`/`K2` walk the whole five-page stack in the documented order,
  one page per press, stopping dead at both ends; and an external Start/Stop
  freezes and unfreezes the patch without flooding on resume.
- `smoke.lua` — loads `Canopy.lua` itself and exercises every screen
  view, the sound page, and every control against the 78-cell panel.
- `soak.lua` — the same, but against a *strict* norns stub: `screen`, `util`
  and `clock` expose only the functions norns actually has, so calling one it
  doesn't is an error rather than a silent no-op. Redraws from every state
  (every cell held one at a time, every type pair held in twos, all five
  full-screen pages walked with `K3` the way a player reaches them, the
  global page with a live patch), thousands of random gestures with the
  scheduler running, and the per-frame screen command and paint budgets --
  which the gusts page and the Colour page are both held to as well.
  This is the test that catches "the screen died but the grid still works".
- `perf.lua` — what the 2 ms tick costs, including the Clock cells and the
  LFOs' control-rate work (driven there at the tick rather than at
  Canopy.lua's 40 Hz metro, so that row is a deliberate overestimate). Cheap on a dev machine, but the CM3 is the budget that
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
context). This check never calls `smp_load`, so it never touches the
samples under `audio/` — an unloaded sample cell is silent, not an error.
