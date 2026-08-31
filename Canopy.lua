-- canopy
--
-- four modal voices in the corners, a sealed core of pulse-makers, and four
-- banks of things to do to a pulse on its way between them. every socket is
-- both an input and an output; a cable is an undirected coupling.
--
-- hold a cell, tap another: patch them together.
-- hold a cell, tap a connected one: unpatch them.
-- hold two cells together: read/set that edge's gain on E3.
-- tap a voice or a percussion (G) cell: edit its sound. tap it again: back
-- to the patch.
-- K1 + tap a D cell: root it to the clock, or set it wild.
-- K1 + tap an F cell: snap its field to the scale, or set it free.
-- hold a D/R/F/C cell, K1+E2: swap its gait / rule / mode / shape.
-- E1/E2/E3 with nothing held: the global param page -- E1 picks one of nine
-- (BPM, Swing, Scatter, Scale, Drops, Decay, Pitch, Rain, Excite), E2/E3
-- nudge it coarse/fine. K1+E3: master level.
-- K3: close the sound page (nothing else to cycle to now).
-- K2: freeze the pulse gaits (Still).
-- K1+K2 (hold): Regrow -- a seeded patch that already plays.
-- K1+K3 (hold): Clearing -- cut every cable.
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
-- rain recording, with its own dry level (Rain) and how much it excites the
-- four resonators (Excite). Scale is pentatonic-only now, shorthand "Pent".
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
local tm       = wl("tm") -- §2.3b: four TM cells, loaded for their patch/state listeners
local gparam   = wl("gparam")
local rambler  = wl("rambler")
local exciter  = wl("exciter") -- loaded for its patch/state listeners; see lib/exciter.lua
local heartwood = wl("heartwood")
local grove     = wl("grove")
local weave     = wl("weave")   -- Regrow seeds rules through it; also loaded
local climate   = wl("climate") -- for the listeners each of them registers

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
  local scells  = shuffled(ids_of("S"))
  local fcells  = shuffled(ids_of("F"))
  local ccells  = shuffled(ids_of("C"))
  local hcells  = shuffled(ids_of("H"))

  local n_voices = math.min(#voices, 2 + math.random(3))
  local used_d = {}

  for i = 1, n_voices do
    local v = voices[i]
    local d = take(dcells)
    if not d then break end
    seed_d(d)
    table.insert(used_d, d)

    -- half the time the pulse goes through a transform on its way to the
    -- trigger, which is where most of the character of a part comes from.
    local trig = v .. ".trig"
    local r = (math.random() < 0.55) and seed_r(take(rcells)) or nil
    if r then
      patch.add(d, r, gain(0.6, 1.0), false)
      patch.add(r, trig, gain(0.5, 0.95), false)
    else
      patch.add(d, trig, gain(0.5, 0.95), false)
    end

    -- something under the voice: an exciter on the mod socket, and sometimes
    -- the same pulse gating that exciter into a grain rather than a wash.
    if math.random() < 0.7 then
      local s = take(scells)
      if s then
        patch.add(s, v .. ".mod", gain(0.3, 0.8), false)
        if math.random() < 0.5 then patch.add(d, s, gain(0.4, 0.9), false) end
      end
    end

    -- and now and then a field on the pitch socket, which is the difference
    -- between a drum part and a tune.
    if math.random() < 0.45 then
      local f = take(fcells)
      if f then
        -- a modest range: at the top of the knob a field is two octaves wide,
        -- which is a melody nobody asked for under a drum part.
        state.character[f] = 0.15 + math.random() * 0.4
        patch.add(f, v .. ".pitch", gain(0.4, 0.9), false)
      end
    end
  end

  -- a second transform hung off an existing pulse-maker: two parts out of one
  -- clock, which is what makes the patch sound arranged rather than layered.
  if #used_d > 0 and math.random() < 0.6 then
    local r = seed_r(take(rcells))
    local d = used_d[math.random(#used_d)]
    local v = voices[math.random(n_voices)]
    if r and v then
      patch.add(d, r, gain(0.5, 0.9), false)
      patch.add(r, v .. ".trig", gain(0.4, 0.8), false)
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

  -- one voice ringing another: the cable the panel did not have until the O
  -- socket landed.
  if n_voices >= 2 and math.random() < 0.45 then
    patch.add(voices[1] .. ".out", voices[2] .. ".mod", gain(0.2, 0.5), true)
  end

  -- into the wood, and out of it somewhere else.
  if #used_d > 0 and math.random() < 0.4 then
    local h = take(hcells)
    if h then
      patch.add(used_d[math.random(#used_d)], h, gain(0.4, 0.8), false)
      local h2 = take(hcells)
      local v = voices[math.random(n_voices)]
      if h2 and v then patch.add(h2, v .. ".mod", gain(0.2, 0.6), false) end
    end
  end

  -- and finally the weather, on whatever is most worth moving slowly.
  for _ = 1, math.random(2) do
    local c = take(ccells)
    local target = (math.random() < 0.5) and used_d[math.random(math.max(#used_d, 1))]
                                        or scells[#scells]
    if c and target then
      -- somewhere in the middle of the period knob: slow enough to be a
      -- change rather than a wobble, fast enough to happen while you listen.
      state.character[c] = 0.25 + math.random() * 0.45
      local gg = gain(0.3, 0.8)
      if math.random() < 0.4 then gg = -gg end
      patch.add(c, target, gg, false)
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

function key(n, z)
  if n == 1 then
    keystate.k1 = (z == 1)
  elseif n == 2 then
    if z == 1 then
      k2_solo_press = not keystate.k1 and not keystate.k3
    end
    keystate.k2 = (z == 1)
    if z == 0 and #state.held == 0 and k2_solo_press then
      state.global.still = not state.global.still
      state.set_event(state.global.still and "Still" or "resumed", 1.5)
    end
  elseif n == 3 then
    if z == 1 then
      k3_solo_press = not keystate.k1 and not keystate.k2
    end
    keystate.k3 = (z == 1)
    if z == 0 and #state.held == 0 and k3_solo_press then
      -- the sound page is a mode, so K3 is its way out as well as the grid's:
      -- you should never have to remember which voice cell you tapped. with
      -- no page open, K3 has nothing left to do -- the global param page is
      -- always the screen underneath everything else now.
      if state.voice_edit then
        state.voice_edit = nil
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

-- §5.5: E2 is coarse and E3 is fine on the same parameter. eight knobs on two
-- encoders would otherwise mean either a slow one or an imprecise one, and a
-- resonator's decay wants both -- swept across two octaves to find the sound,
-- then moved a hair to make it sit.
local VP_COARSE = 1 / 80
local VP_FINE = 1 / 500

function enc(n, d)
  if gridui.on_norns_enc(n, d, keystate) then return end

  if state.voice_edit then
    -- §2.7b/§2.3b: a G cell's or a TM cell's sound page is the same shape,
    -- just a different PARAMS list.
    local cell = topology.get(state.voice_edit)
    local pm = (cell and cell.type == "G") and gvoice
               or (cell and cell.type == "TM") and tm
               or voice
    if n == 1 then
      state.vparam_focus = util.clamp((state.vparam_focus or 1) + d,
                                      1, pm.PARAM_COUNT)
    else
      local p = pm.nudge(state.voice_edit, state.vparam_focus or 1,
                         d * ((n == 2) and VP_COARSE or VP_FINE))
      state.set_event(p.label .. " " .. p.text(state.voice_edit), 0.5)
    end
    return
  end

  -- §5.2 the global param page: E1 walks gparam.PARAMS, E2/E3 nudge the one
  -- under the cursor coarse/fine -- same shape as the voice page above, for
  -- the nine macros that reach every voice at once (lib/gparam.lua). K1+E3
  -- stays master level, unrelated to the nine and untouched by this.
  if n == 3 and keystate.k1 then
    state.global.level = util.clamp(state.global.level + d / 500, 0, 1)
    bridge.master_level(state.global.level)
  elseif n == 1 then
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
  heartwood.init()
  grove.init()
  gparam.init() -- adopts the clock's tempo, pushes the other eight (§5.2)
  exciter.start_meters() -- §7.4: per-exciter activity polls
  bridge.master_level(state.global.level)
  -- §4.1 the always-on rain ambience: the engine loads it async and starts
  -- \wl_rain once it's ready, so this can fire before anything downstream of
  -- it (rain_volume/rain_excite) is pushed without losing either.
  bridge.rain_load(_path.code .. "Canopy/audio/Rain.wav")
  rambler.start()
end

function cleanup()
  if screen_metro then screen_metro:stop() end
  if grid_metro then grid_metro:stop() end
  rambler.stop()
  cancel_confirm()
end
