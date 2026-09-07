-- send.lua
-- §2.11c the send bus, and the page it is set from.
--
-- what changed and why. the twelve gust cells shared one delay line, and its
-- three knobs -- Space, Delay, Regen -- sat on the gusts page because that is
-- whose delay it was. it was also the only effect on the panel with any sense
-- of a room in it, and every other family on the instrument was dry: a snare
-- could be compressed, saturated, crushed and folded on the Colour page, and
-- could not be put in the same space as the drone underneath it.
--
-- so the line is a SEND now. every cell that makes a sound has a Send row on
-- its own page saying how much of it goes there, the gusts still arrive the
-- way they always did, and the three knobs (plus a Tone, which the line needs
-- now that it is not only carrying drones) have moved off the gusts page onto
-- one of their own, one K3 past the mixer -- which is where they belong once
-- they stop being about one family: with the master pages, next to the faders
-- and the colour chain.
--
-- how a send is built, and why there is no `send` argument on any SynthDef.
-- the panel already has a general way to route one cell's audio into
-- something at a gain: the patch matrix (\wl_patch_aa, dispatch.lua). a send
-- is exactly that -- one source's own tap bus into one shared bus, at the
-- gain that cell's Send knob is set to -- so this file builds them as ordinary
-- patch synths rather than teaching seven SynthDefs about a new argument.
-- adding a Send row to a family that grows one later is then a line in
-- SOURCES below and nothing else at all.
--
-- the ids these claim are deliberately far away from the cable ids
-- dispatch.lua uses (`edge.id * 10 + i`, which with patch.MAX_CABLES of 64
-- cannot exceed a few hundred). they are one flat block from SEND_ID_BASE,
-- one per source cell in registration order, so a send never collides with a
-- cable and never moves when the graph does.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local send = {}

local COARSE, FINE = 1 / 80, 1 / 500

-- every family that makes a sound and has a tap bus, and which bus that is.
-- `bias` is what to subtract from the cell's own `index` to get its 0-based
-- slot -- the Output row and the sample cells number from 0, everything else
-- from 1, which is a wart the rest of the codebase already carries and this
-- is not the file to fix it in.
--
-- an exciter is deliberately absent. it is a texture that runs continuously
-- into whatever it is cabled to rather than a note, and a send on one is a
-- wash of delayed noise under the patch at all times; if you want that, cable
-- the exciter to a voice and send the voice.
local SOURCES = {
  voice  = {bus = "voice_out",  bias = 1},
  GVOICE = {bus = "gvoice_out", bias = 1},
  GUST   = {bus = "gust_out",   bias = 1},
  SMP    = {bus = "smp_out",    bias = 0},
  FM     = {bus = "fm_out",     bias = 1},
  VA     = {bus = "va_out",     bias = 1},
}

send.SOURCES = SOURCES

function send.is_source(cell)
  return (cell and SOURCES[cell.type]) and true or false
end

-- the per-cell amount ---------------------------------------------------------

-- zero by default, and it has to be: a patch that has never opened this page
-- must sound exactly as it did before the page existed, and a send that
-- arrived at some tasteful starting value would put every drum in a room
-- nobody asked for.
send.DEFAULT = 0

function send.amount(id)
  return state.get_vparam(id, "send", send.DEFAULT)
end

-- squared on the way to the engine, for the same reason a fader is: the
-- bottom of the knob's travel is where a send is actually useful, and a
-- linear one jumps from "not there" to "in a cave" over the first third.
function send.gain(id)
  local v = send.amount(id)
  return v * v
end

-- the cells with a send, in registration order -- which is what fixes each
-- one's patch id, so the id never moves.
local order = nil

local function each_source()
  if order then return order end
  order = {}
  for id, cell in topology.each() do
    if SOURCES[cell.type] then table.insert(order, id) end
  end
  return order
end

send.ID_BASE = 100000

local slot_of = nil

local function slot(id)
  if not slot_of then
    slot_of = {}
    for i, cid in ipairs(each_source()) do slot_of[cid] = i - 1 end
  end
  return slot_of[id]
end

-- what is currently live engine-side, so a push only sends what moved: a
-- patch_add is a synth allocation and a patch_free is an audible cut, and
-- neither belongs on an encoder detent that did not change anything.
local live = {}

-- push one cell's send. at zero the patch synth is freed outright rather than
-- left running at a gain of nothing -- there is no reason to hold a synth per
-- silent source, and this is how the page costs nothing until it is used.
function send.push(id)
  local cell = topology.get(id)
  local src = cell and SOURCES[cell.type]
  if not src then return end
  local sid = send.ID_BASE + slot(id)
  local g = send.gain(id)

  if g <= 0 then
    if live[id] then
      bridge.patch_free(sid)
      live[id] = nil
    end
    return
  end

  if not live[id] then
    bridge.patch_add(sid, "aa", bridge.bus(src.bus, cell.index - src.bias),
                     bridge.bus("send", 0), g)
    live[id] = g
  elseif live[id] ~= g then
    bridge.patch_gain(sid, g)
    live[id] = g
  end
end

function send.push_all()
  for _, id in ipairs(each_source()) do send.push(id) end
end

-- the row every sounding cell's page ends with. one object per call rather
-- than one shared table, because a page row is looked up by identity in a few
-- places and sharing one across seven pages would make "which page is this
-- row on" unanswerable.
function send.row()
  return {
    key = "send", label = "Send", glyph = "lattice", default = send.DEFAULT,
    get = function(id) return send.amount(id) end,
    set = function(id, v) return state.set_vparam(id, "send", v) end,
    text = function(id) return string.format("%.2f", send.amount(id)) end,
    push = function(id) send.push(id) end,
  }
end

-- the effect's own knobs ------------------------------------------------------
-- these numbers used to live in lib/gust.lua as gust.SPACE and are unchanged
-- in what they do, how far they go and where they are stored -- a patch saved
-- before this page existed comes back on the same settings. Tone is the one
-- new one: the damping in the feedback loop, which was a fixed 3200 Hz and
-- had to become a knob once the line stopped only carrying drones.

send.FX = {
  space = 0.35,   -- how much of the delayed signal is heard, 0..1
  delay = 0.38,   -- the line's own time in seconds
  regen = 0.45,   -- how much comes back round, 0..1
  tone  = 0.5,    -- the damping in the loop; 0.5 is about the old fixed value
}

send.DELAY_MIN, send.DELAY_MAX = 0.02, 2.0
send.REGEN_MAX = 0.92

-- the same log map \wl_gust_space uses, so the screen prints the frequency
-- the loop is actually damped at.
send.TONE_MIN, send.TONE_MAX = 700, 11900

local function fx_values()
  -- the key on state.global stays `gust_space`: it is the same three numbers
  -- in the same place, and renaming it would silently discard them out of
  -- every patch saved before this page existed.
  state.global.gust_space = state.global.gust_space or {}
  local t = state.global.gust_space
  for k, v in pairs(send.FX) do
    if t[k] == nil then t[k] = v end
  end
  return t
end

function send.get_fx(key)
  return fx_values()[key]
end

function send.set_fx(key, v)
  local t = fx_values()
  if key == "delay" then
    t[key] = util.clamp(v, send.DELAY_MIN, send.DELAY_MAX)
  elseif key == "regen" then
    t[key] = util.clamp(v, 0, send.REGEN_MAX)
  else
    t[key] = util.clamp(v, 0, 1)
  end
  return t[key]
end

function send.tone_hz()
  return send.TONE_MIN
       * ((send.TONE_MAX / send.TONE_MIN) ^ send.get_fx("tone"))
end

function send.push_fx()
  bridge.gust_space(send.get_fx("space"), send.get_fx("delay"),
                    send.get_fx("regen"), send.get_fx("tone"))
end

-- the page --------------------------------------------------------------------
-- four rows, one screen, in the order the signal goes through them: how loud
-- the tail is, how far apart the repeats are, how many there are, and what
-- colour they are.
--
-- the page object is the same shape gparam's, gust's and mixer's are --
-- PARAMS with get/set/text/frac/push, E1 to pick, E2/E3 coarse/fine -- so
-- screenui and Canopy.lua drive it through the code path they already have.

local function fx_row(key, label, gl, text_fn, frac_fn, coarse, fine)
  return {
    key = "send_" .. key, label = label, glyph = gl,
    coarse = coarse or COARSE, fine = fine or FINE,
    get = function() return send.get_fx(key) end,
    set = function(v) send.set_fx(key, v) end,
    text = text_fn, frac = frac_fn,
    push = function() send.push_fx() end,
  }
end

send.PARAMS = {
  fx_row("space", "Space", "peak",
    function() return string.format("%.2f", send.get_fx("space")) end,
    function() return send.get_fx("space") end),
  -- in seconds on the wire and milliseconds on the screen, not a 0..1 knob:
  -- a delay time is a number you want to read, and often one you want to
  -- match to the tempo by eye.
  fx_row("delay", "Delay", "steps",
    function() return string.format("%.0f ms", send.get_fx("delay") * 1000) end,
    function()
      return (send.get_fx("delay") - send.DELAY_MIN)
             / (send.DELAY_MAX - send.DELAY_MIN)
    end,
    0.01, 0.002),
  fx_row("regen", "Regen", "combs",
    function() return string.format("%.2f", send.get_fx("regen")) end,
    function() return send.get_fx("regen") / send.REGEN_MAX end),
  fx_row("tone", "Tone", "tilt",
    function() return string.format("%.0f Hz", send.tone_hz()) end,
    function() return send.get_fx("tone") end),
}

send.PARAM_COUNT = #send.PARAMS

function send.param(i)
  return send.PARAMS[util.clamp(i, 1, #send.PARAMS)]
end

-- the same nudge contract gparam.nudge, mixer.nudge and colour.nudge have.
function send.nudge(i, delta, is_coarse)
  local p = send.param(i)
  if not p then return nil end
  local step = (is_coarse and p.coarse or p.fine) or p.coarse
  local v = p.get() + delta * step
  p.set(v)
  p.push()
  return p
end

-- how many cells are currently sending anything, for the page header: this is
-- the one page on the panel whose whole point is a thing happening somewhere
-- else, so it says how many somewhere-elses there are.
function send.active_count()
  local n = 0
  for _, id in ipairs(each_source()) do
    if send.amount(id) > 0 then n = n + 1 end
  end
  return n
end

function send.init()
  send.push_fx()
  send.push_all()
end

return send
