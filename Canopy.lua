-- canopy
--
-- four modal voices in the corners, a sealed core of pulse-makers, and four
-- banks of things to do to a pulse on its way between them. every socket is
-- both an input and an output; a cable is an undirected coupling.
--
-- one gesture vocabulary, the same on every cell of every type:
-- tap a cell: toggle its settings page. tap it again: back to the patch.
-- hold a cell: glance at that same page until you let go.
-- hold a cell, E1/E2/E3: pick a row, move it coarse/fine.
-- press a gust (the ten G cells on the bottom two rows): it sounds its note,
--   on the way down. the release still toggles its page like any other cell.
-- K1 + tap a cell: fire it -- strike a voice or a drum, sound a gust, fire an
--   exciter, pulse a trigger/transform/register/clock.
-- hold a cell, tap another: patch them together.
-- hold a cell, tap a connected one: unpatch them.
-- hold two cells together: read/set that edge's gain on E3.
-- E1/E2/E3 with nothing held: the global param page -- E1 picks one of ten
-- (BPM, Swing, Scatter, Scale, Drops, Decay, Pitch, then the gusts' shared
-- delay: Space, Delay, Regen), E2/E3 nudge it coarse/fine. K1+E3: master
-- level.
-- K3: the mixer -- faders for the four soundscape loops and the master. from
-- an open cell page it goes there too, dropping that cell's focus. K3 again
-- goes on to the map page -- every cell, lit if it's cabled, dim if it isn't.
-- holding or tapping a cell open from there still goes straight to that
-- cell's own settings page, same as everywhere else -- letting go or closing
-- it comes back to the map. a third K3 goes back to the mixer, so the two
-- trade places until K2 backs all the way out.
-- K2: back. off the mixer or the map, or out of an open cell page, to the
-- main screen; with nothing to come back from, it freezes the pulse gaits
-- (Still).
-- K1+K2 (hold): Regrow -- a seeded patch that already plays.
-- K1+K3 (hold): Clearing -- cut every cable.
--
-- externally clocked: set the system clock source to MIDI (or Link) in
-- PARAMS and the whole patch runs off it -- tempo, rooted gaits, and
-- Start/Stop, which freeze and unfreeze the gaits exactly as K2's Still
-- does. see clock.transport below.
--
-- build phase 5: the heartwood diffusion lattice, discrete and continuous.
-- build phase 5b: the grove -- wandering pitch fields (now F cells), plus an
-- always-on per-voice detune drift in SC.
-- build phase 5c: Weather is the groove knob -- quantise -> swing -> chaos
-- (lib/quantise.lua) -- and E3 is the transport tempo.
-- build phase 6, the re-cut: four voices with T/P/M/O sockets instead of six
-- with four anonymous ones, the O socket finally closing voice<->voice
-- feedback, the weave (lib/weave.lua -- twenty pulse transforms), the climate
-- (lib/climate.lua -- eight very slow modulators), twenty exciters instead of
-- ten, and a per-voice sound page instead of one Grain macro. the metering
-- back-channel and PARAMS/PSET persistence are still ahead
-- (docs/canopy-spec.md §9 has the build order).
-- build phase 6b: the network view -- the patch drawn as a lit map with
-- dotted cable wires -- is gone, replaced by §5.2's global param page
-- (lib/gparam.lua): the same E1-select/E2-E3-nudge shape as the sound page,
-- for nine macros instead of one voice. Weather is gone with it, split into
-- independent Swing and Scatter; Scale, Drops, global Decay, global Pitch and
-- an output Compressor are new.
-- build phase 7, the re-name: the script becomes Canopy. no more reverb (the
-- old Canopy knob and its FreeVerb are gone entirely) and no more output
-- Compressor. the old Rain macro -- trigger/field wildness -- is renamed
-- Scatter, freeing "Rain" for something literal: an always-on loop of a real
-- rain recording, with its own dry level. Scale is pentatonic-only now,
-- shorthand "Pent".
-- the gusts (§2.11): the two step-sequencer lanes that briefly sat on the
-- bottom two rows are gone, and their ten cells are ten small drone synths
-- instead (lib/gust.lua) -- a folded triangle core with a slow attack and a
-- slow decay you set per cell, loosely after a Ciat-Lonbarde Deerhorn and
-- deliberately not a clone of one. press one and it sounds; a pulse cabled
-- in sounds it too. they are the one family heard without a cable: each is
-- panned by the column it sits in, and all ten share one delay line off the
-- global page. cable two together and they cross-modulate.
-- the re-cut's re-cut: six of the bottom weave row's R cells become G cells
-- (lib/gvoice.lua) -- small, plain drum voices (three pinged resonant
-- filters, three noise-with-decay) with a six-parameter sound page of their
-- own, same shape as a voice's. the top weave row is reshuffled to keep the
-- coolest rules; the six it gave up are still reachable by K1+E2, just no
-- longer anyone's default cell (docs/canopy-spec.md §2.7/§2.7b).

engine.name = "Canopy"

-- norns' global include() is dofile-based: it re-executes the file and hands
-- back a NEW table every call. topology/patch/state are shared mutable
-- singletons, so plain include()s would give gridui, screenui and the
-- scheduler three separate patch graphs that never see each other's cables.
-- everything goes through this memo instead. globals outlive a script, so the
-- table is cleared here -- at load time -- to keep reloads clean.
_canopy_mods = {}

function wl(name)
  local m = _canopy_mods[name]
  if m == nil then
    m = include("Canopy/lib/" .. name)
    _canopy_mods[name] = m
  end
  return m
end

local topology = wl("topology")
local patch    = wl("patch")
local state    = wl("state")
local gridui   = wl("gridui")
local screenui = wl("screenui")
local bridge   = wl("bridge")
local voice    = wl("voice")
local gvoice   = wl("gvoice")
local gust     = wl("gust")   -- §2.11: the ten drone cells on the bottom rows
local tm       = wl("tm") -- §2.3b: four TM cells, loaded for their patch/state listeners
local gparam   = wl("gparam")
local mixer    = wl("mixer")
local rambler  = wl("rambler")
local exciter  = wl("exciter") -- loaded for its patch/state listeners; see lib/exciter.lua
local heartwood = wl("heartwood")
local grove     = wl("grove")
local weave     = wl("weave")   -- Regrow seeds rules through it; also loaded
                                 -- for the listeners each of them registers

local g = nil
local screen_metro, grid_metro
local keystate = {k1 = false, k2 = false, k3 = false}

local CONFIRM_HOLD = 1.0
local confirm_clock = nil

local function cancel_confirm()
  if confirm_clock then
    clock.cancel(confirm_clock)
    confirm_clock = nil
  end
  state.confirm = nil
end

-- Regrow (K1+K2, held) ------------------------------------------------------
-- the old version drew random cables between random cells. on a panel of
-- thirty that was a fair coin; on a panel of ninety it is mostly cables
-- between two things that have nothing to say to each other, and what you got
-- back was silence. this one builds a patch with a *shape* -- a couple of
-- pulse-makers, some of them routed through the weave, landing on triggers;
-- an exciter under each voice that plays; sometimes a field, sometimes some
-- weather, sometimes one voice feeding another -- and then lets the dice
-- decide everything else. it is still a different patch every time. it is
-- just always a patch that plays.
--
-- it also seeds the *settings* of the cells it uses, which the old one never
-- did. it has to: half the weave blocks a pulse at its default knob (Sift's
-- threshold sits above most weights, Meet wants two sources it has not got),
-- so a Regrow that only drew cables drew silent ones about half the time.
-- the pairs below are all rules that pass something, at knob settings that
-- pass most of it.

local REGROW_GAITS = {
  -- gait, knob, root it to the clock? weighted toward the ones that keep
  -- time, because a patch that arrives already in time is one you can start
  -- playing with rather than one you have to fix first.
  {"metric", 0.50, true},  {"metric", 0.75, true},
  {"euclidean", 0.55, true}, {"euclidean", 0.40, true},
  {"figure", 0.30, true},  {"figure", 0.62, true},  {"figure", 0.88, true},
  {"slow", 0.60, false},   {"burst", 0.35, false},
  {"stochastic", 0.62, false}, {"drifter", 0.14, false},
  {"accelerando", 0.30, false},
}

local REGROW_RULES = {
  {"accent", 0.70}, {"swing", 0.50}, {"blur", 0.30}, {"flam", 0.40},
  {"ghost", 0.50},  {"mult", 0.15},  {"divide", 0.20}, {"mask", 0.80},
  {"shift", 0.85},  {"swell", 0.40}, {"fill", 0.30}, {"echo", 0.40},
}

local function ids_of(kind, filter)
  local out = {}
  for id, cell in topology.each() do
    if cell.type == kind and (not filter or filter(id, cell)) then
      table.insert(out, id)
    end
  end
  return out
end

local function shuffled(list)
  local t = {}
  for i, v in ipairs(list) do t[i] = v end
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

local function take(pool)
  if #pool == 0 then return nil end
  return table.remove(pool)
end

local function gain(lo, hi)
  return lo + math.random() * (hi - lo)
end

-- give one cell a gait/rule and a knob to go with it, and hand the id back so
-- the caller can carry on cabling with it.
local function seed_d(id)
  local pick = REGROW_GAITS[math.random(#REGROW_GAITS)]
  rambler.set_gait(id, pick[1])
  state.character[id] = pick[2]
  rambler.set_rooted(id, pick[3])
  return id
end

local function seed_r(id)
  if not id then return nil end
  local pick = REGROW_RULES[math.random(#REGROW_RULES)]
  weave.set_rule(id, pick[1])
  state.character[id] = pick[2]
  return id
end

local function do_regrow()
  patch.clear()

  local voices  = shuffled(ids_of("voice"))
  local dcells  = shuffled(ids_of("D"))
  local rcells  = shuffled(ids_of("R"))
  local ecells  = shuffled(ids_of("E"))
  local fcells  = shuffled(ids_of("F"))
  local hcells  = shuffled(ids_of("H"))
  local ocells  = shuffled(ids_of("O"))

  local n_voices = math.min(#voices, 2 + math.random(3))
  local used_d = {}

  for i = 1, n_voices do
    local v = voices[i]
    local d = take(dcells)
    if not d then break end
    seed_d(d)
    table.insert(used_d, d)

    -- half the time the pulse goes through a transform on its way to the
    -- voice, which is where most of the character of a part comes from. the
    -- socket collapse means the voice's own id is the cable target now --
    -- there is no separate ".trig" to reach for.
    local r = (math.random() < 0.55) and seed_r(take(rcells)) or nil
    if r then
      patch.add(d, r, gain(0.6, 1.0), false)
      patch.add(r, v, gain(0.5, 0.95), false)
    else
      patch.add(d, v, gain(0.5, 0.95), false)
    end

    -- something under the voice: an exciter feeding its mod path, and
    -- sometimes the same pulse gating that exciter into a grain rather than
    -- a wash.
    if math.random() < 0.7 then
      local e = take(ecells)
      if e then
        patch.add(e, v, gain(0.3, 0.8), false)
        if math.random() < 0.5 then patch.add(d, e, gain(0.4, 0.9), false) end
      end
    end

    -- and now and then a field, which is the difference between a drum part
    -- and a tune -- also cabled straight to the voice's own point now.
    if math.random() < 0.45 then
      local f = take(fcells)
      if f then
        -- a modest range: at the top of the knob a field is two octaves wide,
        -- which is a melody nobody asked for under a drum part.
        state.character[f] = 0.15 + math.random() * 0.4
        patch.add(f, v, gain(0.4, 0.9), false)
      end
    end

    -- and always an Output cable, or nothing regrown is ever heard. exactly
    -- one: the Output row is exclusive now (patch.lua's displace_output), so
    -- the second cable this used to draw about half the time would only have
    -- moved the first. `ocells` is shuffled and taken from, so no two voices
    -- land on the same pan position anyway.
    local o = take(ocells)
    if o then patch.add(v, o, gain(0.6, 1.0), false) end
  end

  -- a second transform hung off an existing pulse-maker: two parts out of one
  -- clock, which is what makes the patch sound arranged rather than layered.
  if #used_d > 0 and math.random() < 0.6 then
    local r = seed_r(take(rcells))
    local d = used_d[math.random(#used_d)]
    local v = voices[math.random(n_voices)]
    if r and v then
      patch.add(d, r, gain(0.5, 0.9), false)
      patch.add(r, v, gain(0.4, 0.8), false)
    end
  end

  -- coupling between two pulse-makers: the whole rhythm engine (§2.3), and
  -- the one thing here that can pull the patch somewhere nobody chose.
  if #used_d >= 2 and math.random() < 0.5 then
    local a, b = used_d[1], used_d[2]
    local gg = gain(0.3, 0.7)
    if math.random() < 0.3 then gg = -gg end
    patch.add(a, b, gg, false)
  end

  -- one voice ringing another: fully symmetric now the socket collapse made
  -- every voice one androgynous point (§1's own principle, finally taken at
  -- its word).
  if n_voices >= 2 and math.random() < 0.45 then
    patch.add(voices[1], voices[2], gain(0.2, 0.5), true)
  end

  -- §2.11 a gust or two, hung off a pulse-maker that is already running.
  -- no Output cable is drawn for them and none is needed -- a gust routes
  -- itself -- so this is the cheapest way for a regrown patch to arrive with
  -- something sustained under the percussion. the pair, when there is one,
  -- is cabled to each other rather than to anything else: two gusts
  -- cross-modulating is the most characteristic thing this family does, and
  -- a Regrow that never showed it would be hiding the good part.
  local gucells = shuffled(ids_of("GUST"))
  if #used_d > 0 and math.random() < 0.65 then
    local n_gu = (math.random() < 0.5) and 2 or 1
    local first
    for _ = 1, n_gu do
      local gu = take(gucells)
      if not gu then break end
      -- a long swell under a drum part, not a stab: bias the two envelope
      -- knobs upward from centre and keep the level modest.
      state.set_vparam(gu, "attack", 0.45 + math.random() * 0.4)
      state.decay[gu] = 0.5 + math.random() * 0.35
      state.set_vparam(gu, "timbre", 0.15 + math.random() * 0.45)
      state.set_vparam(gu, "level", 0.4 + math.random() * 0.25)
      -- seeding a cell's state is only half of it: unlike a gait or a rule,
      -- these numbers mean nothing until they reach the engine, and a gust
      -- is not re-pushed by being played.
      gust.push_all(gu)
      patch.add(used_d[math.random(#used_d)], gu, gain(0.5, 1.0), false)
      if first then
        patch.add(first, gu, gain(0.25, 0.6), false)
      else
        first = gu
      end
    end
  end

  -- into the wood, and out of it somewhere else.
  if #used_d > 0 and math.random() < 0.4 then
    local h = take(hcells)
    if h then
      patch.add(used_d[math.random(#used_d)], h, gain(0.4, 0.8), false)
      local h2 = take(hcells)
      local v = voices[math.random(n_voices)]
      if h2 and v then patch.add(h2, v, gain(0.2, 0.6), false) end
    end
  end

  state.set_event("regrew " .. patch.count() .. " cables", 1.5)
end

local function start_confirm(kind, label)
  state.confirm = {kind = kind, label = label, started = util.time(), duration = CONFIRM_HOLD}
  confirm_clock = clock.run(function()
    clock.sleep(CONFIRM_HOLD)
    if state.confirm and state.confirm.kind == kind then
      if kind == "regrow" then
        do_regrow()
      elseif kind == "clear" then
        patch.clear()
        state.set_event("cleared every cable", 1.5)
      end
    end
    state.confirm = nil
    confirm_clock = nil
  end)
end

-- press-context flags: was this key pressed alone, with the other two up?
local k2_solo_press, k3_solo_press = false, false

-- K2 is "back" and K3 steps down through the two full-screen pages below the
-- main one -- mixer, then map -- so the two keys are one shallow stack rather
-- than a different pair of jobs per page:
--
--   K2   with a cell page open -> the main screen (drops that cell's focus)
--        on the mixer or the map -> the main screen
--        on the main screen    -> Still, which is what it always was
--   K3   on the main screen    -> the mixer, dropping any cell focus with it
--        on the mixer          -> the map
--        on the map            -> the mixer
--
-- Still keeps K2 because the main screen is the one place with nothing to
-- come back from, and freezing the patch is a fair reading of "there is
-- nothing above this". K3's old job -- closing a cell page -- is still the
-- first thing K2 checks, along with everything else that means "up one",
-- which is also why that check runs before the mixer/map one below: an open
-- cell page closes first, however it got opened.

function key(n, z)
  if n == 1 then
    keystate.k1 = (z == 1)
  elseif n == 2 then
    if z == 1 then
      k2_solo_press = not keystate.k1 and not keystate.k3
    end
    keystate.k2 = (z == 1)
    if z == 0 and #state.held == 0 and k2_solo_press then
      if state.cell_edit then
        local cell = topology.get(state.cell_edit)
        state.cell_edit = nil
        state.set_event((cell and cell.name or "cell") .. ": closed", 1.2)
      elseif state.view == "mixer" or state.view == "map" then
        local was = state.view
        state.view = "global"
        state.set_event(was .. ": closed", 1.2)
      else
        state.global.still = not state.global.still
        state.set_event(state.global.still and "Still" or "resumed", 1.5)
      end
    end
  elseif n == 3 then
    if z == 1 then
      k3_solo_press = not keystate.k1 and not keystate.k2
    end
    keystate.k3 = (z == 1)
    if z == 0 and #state.held == 0 and k3_solo_press then
      -- one press away from anywhere, an open cell page included -- which it
      -- closes on the way, so the encoders are never pointed at a page the
      -- screen is not showing. from the main screen that's the mixer; from
      -- either the mixer or the map it's the other one, so K3 alone walks
      -- back and forth between them once you're off the main screen.
      state.cell_edit = nil
      if state.view == "mixer" then
        state.view = "map"
        state.set_event("map", 1.2)
      else
        state.view = "mixer"
        state.mparam_focus = state.mparam_focus or 1
        state.set_event("mixer", 1.2)
      end
    end
  end

  gridui.on_norns_key(n, z, keystate)

  if #state.held == 0 then
    if keystate.k1 and keystate.k2 and not state.confirm then
      start_confirm("regrow", "K1+K2 hold \xE2\x80\x94 Regrow")
    elseif keystate.k1 and keystate.k3 and not state.confirm then
      start_confirm("clear", "K1+K3 hold \xE2\x80\x94 Clearing")
    elseif state.confirm and not (keystate.k1 and (keystate.k2 or keystate.k3)) then
      cancel_confirm()
    end
  elseif state.confirm then
    cancel_confirm()
  end
end

-- E2 is coarse and E3 is fine on the same parameter. twelve knobs on two
-- encoders would otherwise mean either a slow one or an imprecise one, and a
-- resonator's decay wants both -- swept across two octaves to find the sound,
-- then moved a hair to make it sit. gridui owns the two step sizes now, since
-- the held glance and the open page have to move a row by the same amount.

function enc(n, d)
  if gridui.on_norns_enc(n, d, keystate) then return end

  -- the open settings page, whatever type of cell it belongs to. exactly the
  -- same call the held-cell glance above makes (lib/cellparam.lua hands both
  -- of them the same page object).
  if state.cell_edit then
    if gridui.page_enc(state.cell_edit, n, d) then return end
  end

  -- K1+E3 is master level from every screen, unrelated to whatever list is
  -- under the cursor. it is also the mixer's fifth fader -- the same number,
  -- reachable both ways.
  if n == 3 and keystate.k1 then
    state.global.level = util.clamp(state.global.level + d / 500, 0, 1)
    bridge.master_level(state.global.level)
    return
  end

  -- the map page itself is a reference, not a control surface -- nothing on
  -- it for E1/E2/E3 to move. by this point a held cell or an open one would
  -- already have consumed the turn above (that's a real settings page, same
  -- as on every other screen), so reaching here with view == "map" means
  -- there is genuinely nothing under the cursor.
  if state.view == "map" then return end

  -- §4.1b the mixer page (K3): the same E1-select/E2-E3-nudge shape as the
  -- global page, for the four soundscape loops and the master.
  if state.view == "mixer" then
    if n == 1 then
      state.mparam_focus = util.clamp((state.mparam_focus or 1) + d,
                                      1, mixer.PARAM_COUNT)
    else
      local p = mixer.nudge(state.mparam_focus or 1, d, n == 2)
      state.set_event(p.label .. " " .. p.text(), 0.5)
    end
    return
  end

  -- §5.2 the global param page: E1 walks gparam.PARAMS, E2/E3 nudge the one
  -- under the cursor coarse/fine -- same shape as the voice page above, for
  -- the macros that reach every voice at once (lib/gparam.lua).
  if n == 1 then
    state.gparam_focus = util.clamp((state.gparam_focus or 1) + d,
                                    1, gparam.PARAM_COUNT)
  else
    local p = gparam.nudge(state.gparam_focus or 1, d, n == 2)
    state.set_event(p.label .. " " .. p.text(), 0.5)
  end
end

function redraw()
  screenui.redraw()
end

-- §4.3 the external transport --------------------------------------------
-- norns' own clock owns the tempo source (PARAMS > CLOCK > source: internal,
-- MIDI, Link, crow) and calls these three back whichever source is running.
-- so there is no MIDI parsing here and no second clock: pick MIDI as the
-- source and the whole patch is externally clocked -- rooted gaits already
-- read clock.get_beats() rather than integrating a rate of their own
-- (rambler.advance_rooted), and gparam's BPM row becomes a readout of
-- whatever is arriving (gparam.external_clock).
--
-- what is left for the script to decide is what Start and Stop *mean* here,
-- and the answer is the one the panel already has a word for: Stop is Still
-- -- gaits freeze, resonators ring out, scheduled taps and queued traffic
-- freeze with them rather than flushing on resume (rambler.tick). that
-- makes an external stop and a K2 press exactly the same state, which is
-- the only way the two can never disagree.

local function transport_reset()
  -- every queue that froze mid-flight is dropped rather than flushed
  -- (rambler.resync, which also resyncs the weave, the lattice and the clock
  -- cells). nothing else on the panel keeps a playhead to put back -- the
  -- gusts hold a pitch, not a position, and a ringing one is left to ring.
  rambler.resync()
end

function clock.transport.start()
  gparam.adopt_tempo()
  state.global.still = false
  transport_reset()
  state.set_event("start", 1.5)
end

function clock.transport.stop()
  state.global.still = true
  state.set_event("stop", 1.5)
end

-- sent on its own by a source that has jumped its song position without
-- stopping (MIDI Song Position Pointer, Link's beat origin moving). the
-- patch is still running; only the scheduler's queues need clearing.
function clock.transport.reset()
  transport_reset()
end

function init()
  g = grid.connect()
  g.key = function(x, y, z)
    gridui.on_grid_key(x, y, z, keystate)
  end

  screen_metro = metro.init(function() redraw() end, 1 / 15, -1)
  screen_metro:start()

  grid_metro = metro.init(function()
    if g then gridui.grid_redraw(g) end
  end, 1 / 30, -1)
  grid_metro:start()

  voice.init()
  gvoice.init()
  gust.init()
  heartwood.init()
  grove.init()
  gparam.init() -- adopts the clock's tempo, pushes the rest (§5.2)
  exciter.start_meters() -- §7.4: per-exciter activity polls
  bridge.master_level(state.global.level)
  -- §4.1b the four always-on soundscape loops: the engine loads each async
  -- and starts its \wl_amb once that buffer is ready, holding the fader in
  -- the meantime, so pushing all four levels straight afterwards loses
  -- nothing (lib/mixer.lua).
  --
  -- norns.state.path, not a hardcoded "Canopy/" under _path.code: the
  -- installed script folder is not guaranteed to be named or cased exactly
  -- like this repo, and a wrong guess here fails silently -- Buffer.read
  -- has no error path back to Lua, so a missing loop is indistinguishable
  -- from its fader being at zero (see Engine_Canopy.sc's amb_load comment).
  mixer.init(norns.state.path .. "audio/")
  rambler.start()
end

function cleanup()
  if screen_metro then screen_metro:stop() end
  if grid_metro then grid_metro:stop() end
  rambler.stop()
  cancel_confirm()
end
