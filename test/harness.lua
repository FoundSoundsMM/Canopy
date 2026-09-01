-- offline harness: stubs enough of norns to run the phase-3 scheduler on a
-- virtual clock, so gait behaviour and coupling can be checked without hardware.
local ROOT = arg[1] or os.getenv("ROOT") or "."

T = 0
TEMPO = 120

util = {}
function util.time() return T end
function util.clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
function util.round(x) return math.floor(x + 0.5) end
function util.linlin(a, b, c, d, x) return c + (d - c) * ((x - a) / (b - a)) end

clock = {}
function clock.get_tempo() return TEMPO end
function clock.get_beats() return T * TEMPO / 60 end
function clock.run(f) return 1 end
function clock.cancel() end
function clock.sleep() end
-- §4.3: norns' transport callbacks. the real ones are stubs a script
-- overwrites; so are these, and test/transport.lua calls them by hand.
clock.transport = {start = function() end, stop = function() end,
                   reset = function() end}

metro = {}
function metro.init() return {start = function() end, stop = function() end} end

poll = {}
function poll.set(name, callback)
  return {name = name, callback = callback, time = 0.1,
          start = function() end, stop = function() end}
end

-- the clock_tempo param E3 writes through, and the clock_source param
-- gparam.external_clock reads. the real ones live in norns' PARAMS menu;
-- here they are two numbers a test can move. CLOCK_SOURCE follows norns'
-- own list: 1 internal, 2 midi, 3 link, 4 crow.
CLOCK_SOURCE = 1
params = {
  set = function(_, k, v)
    if k == "clock_tempo" then TEMPO = v
    elseif k == "clock_source" then CLOCK_SOURCE = v end
  end,
  get = function(_, k)
    if k == "clock_tempo" then return TEMPO
    elseif k == "clock_source" then return CLOCK_SOURCE end
  end,
}

-- norns' global paths table. only `.code` is used (Canopy.lua's mixer.init
-- call) and only for string concatenation -- nothing here touches disk.
_path = {code = "/home/we/dust/code/"}

-- screen.text_extents has to return a NUMBER (screenui.lua measures with it
-- before deciding what fits); everything else on the stub is a no-op. 5px per
-- character is close enough to norns' variable-width font for the layout
-- assertions in test/screen.lua to mean something.
screen = setmetatable({text_extents = function(str) return #tostring(str) * 5 end},
                      {__index = function() return function() end end})
grid = {connect = function() return {key = nil, led = function() end, all = function() end,
                                     refresh = function() end} end}

local function fresh_calls()
  return {
    strike = {},
    exciter_on = {}, exciter_off = {}, exciter_colour = {}, exciter_gated = {}, exciter_gate = {},
    patch_add = {}, patch_gain = {}, patch_free = {},
    voice_mod = {}, voice_structure = {},
    heart_conductance = {},
    voice_pitch = {}, voice_glide = {}, voice_drift = {},
    voice_decay = {}, exciter_decay = {}, voice_bend = {},
    amb_load = {}, amb_volume = {},
    g_strike = {}, g_pitch = {}, g_decay = {}, g_tone = {}, g_punch = {},
    g_drive = {}, g_amp = {},
    gust_note = {}, gust_pitch = {}, gust_attack = {}, gust_decay = {},
    gust_timbre = {}, gust_cross = {}, gust_amp = {}, gust_pan = {},
    gust_space = {},
  }
end
CALLS = fresh_calls()
engine = setmetatable({}, {__index = function(_, k)
  return function(...)
    local a = {...}
    if k == "strike" then
      table.insert(CALLS.strike, {t = T, voice = a[1], force = a[2]})
    elseif k == "exciter_on" then
      table.insert(CALLS.exciter_on, {t = T, index = a[1]})
    elseif k == "exciter_off" then
      table.insert(CALLS.exciter_off, {t = T, index = a[1]})
    elseif k == "exciter_colour" then
      table.insert(CALLS.exciter_colour, {t = T, index = a[1], v = a[2]})
    elseif k == "exciter_gated" then
      table.insert(CALLS.exciter_gated, {t = T, index = a[1], flag = a[2]})
    elseif k == "exciter_gate" then
      table.insert(CALLS.exciter_gate, {t = T, index = a[1], dur = a[2], amp = a[3]})
    elseif k == "patch_add" then
      table.insert(CALLS.patch_add, {t = T, id = a[1], kind = a[2], src = a[3], dst = a[4], gain = a[5]})
    elseif k == "patch_gain" then
      table.insert(CALLS.patch_gain, {t = T, id = a[1], gain = a[2]})
    elseif k == "patch_free" then
      table.insert(CALLS.patch_free, {t = T, id = a[1]})
    elseif k == "voice_mod" then
      table.insert(CALLS.voice_mod, {t = T, voice = a[1], v = a[2]})
    elseif k == "voice_structure" then
      table.insert(CALLS.voice_structure, {t = T, voice = a[1], v = a[2]})
    elseif k == "heart_conductance" then
      table.insert(CALLS.heart_conductance, {t = T, index = a[1], v = a[2]})
    elseif k == "voice_pitch" then
      table.insert(CALLS.voice_pitch, {t = T, voice = a[1], hz = a[2]})
    elseif k == "voice_glide" then
      table.insert(CALLS.voice_glide, {t = T, voice = a[1], v = a[2]})
    elseif k == "voice_drift" then
      table.insert(CALLS.voice_drift, {t = T, voice = a[1], depth = a[2], rate = a[3]})
    elseif k == "voice_decay" then
      table.insert(CALLS.voice_decay, {t = T, voice = a[1], secs = a[2]})
    elseif k == "exciter_decay" then
      table.insert(CALLS.exciter_decay, {t = T, index = a[1], scale = a[2]})
    elseif k == "voice_bend" then
      table.insert(CALLS.voice_bend, {t = T, voice = a[1], v = a[2]})
    elseif k == "amb_load" then
      table.insert(CALLS.amb_load, {t = T, index = a[1], path = a[2]})
    elseif k == "amb_volume" then
      table.insert(CALLS.amb_volume, {t = T, index = a[1], v = a[2]})
    elseif k == "g_strike" then
      table.insert(CALLS.g_strike, {t = T, index = a[1], force = a[2]})
    elseif k == "g_pitch" then
      table.insert(CALLS.g_pitch, {t = T, index = a[1], hz = a[2]})
    elseif k == "g_decay" then
      table.insert(CALLS.g_decay, {t = T, index = a[1], secs = a[2]})
    elseif k == "g_tone" then
      table.insert(CALLS.g_tone, {t = T, index = a[1], v = a[2]})
    elseif k == "g_punch" then
      table.insert(CALLS.g_punch, {t = T, index = a[1], v = a[2]})
    elseif k == "g_drive" then
      table.insert(CALLS.g_drive, {t = T, index = a[1], v = a[2]})
    elseif k == "g_amp" then
      table.insert(CALLS.g_amp, {t = T, index = a[1], v = a[2]})
    elseif k == "gust_note" then
      table.insert(CALLS.gust_note, {t = T, index = a[1], hz = a[2], force = a[3]})
    elseif k == "gust_pitch" then
      table.insert(CALLS.gust_pitch, {t = T, index = a[1], hz = a[2]})
    elseif k == "gust_attack" then
      table.insert(CALLS.gust_attack, {t = T, index = a[1], secs = a[2]})
    elseif k == "gust_decay" then
      table.insert(CALLS.gust_decay, {t = T, index = a[1], secs = a[2]})
    elseif k == "gust_timbre" then
      table.insert(CALLS.gust_timbre, {t = T, index = a[1], v = a[2]})
    elseif k == "gust_cross" then
      table.insert(CALLS.gust_cross, {t = T, index = a[1], v = a[2]})
    elseif k == "gust_amp" then
      table.insert(CALLS.gust_amp, {t = T, index = a[1], v = a[2]})
    elseif k == "gust_pan" then
      table.insert(CALLS.gust_pan, {t = T, index = a[1], v = a[2]})
    elseif k == "gust_space" then
      table.insert(CALLS.gust_space, {t = T, mix = a[1], time = a[2], fb = a[3]})
    end
  end
end})

_canopy_mods = {}
function wl(name)
  local m = _canopy_mods[name]
  if m == nil then
    m = dofile(ROOT .. "/lib/" .. name .. ".lua")
    _canopy_mods[name] = m
  end
  return m
end

-- a fresh, fully-reset copy of every module
function fresh(seed)
  math.randomseed(seed or 1)
  T = 0
  TEMPO = 120
  CLOCK_SOURCE = 1
  CALLS = fresh_calls()
  _canopy_mods = {}
  local M = {}
  for _, n in ipairs({"topology", "patch", "state", "bridge", "quantise",
                      "lexicon", "heartwood", "grove", "clockcell", "weave",
                      "dispatch", "voice", "gvoice", "rambler", "exciter",
                      "gparam", "mixer", "tm", "gust", "cellparam"}) do
    M[n] = wl(n)
  end
  return M
end

function run(M, seconds)
  local n = math.floor(seconds / M.rambler.TICK)
  for _ = 1, n do
    T = T + M.rambler.TICK
    M.rambler.tick()
  end
end

local fails, passes = 0, 0
function check(name, ok, detail)
  if ok then
    passes = passes + 1
    print(string.format("  ok    %s", name))
  else
    fails = fails + 1
    print(string.format("  FAIL  %s   %s", name, detail or ""))
  end
end
function report()
  print(string.format("\n%d passed, %d failed", passes, fails))
  os.exit(fails == 0 and 0 or 1)
end
