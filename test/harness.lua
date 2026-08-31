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

metro = {}
function metro.init() return {start = function() end, stop = function() end} end

poll = {}
function poll.set(name, callback)
  return {name = name, callback = callback, time = 0.1,
          start = function() end, stop = function() end}
end

-- the clock_tempo param E3 writes through. the real one lives in norns'
-- PARAMS menu; here it just moves the harness's own TEMPO.
params = {
  set = function(_, k, v) if k == "clock_tempo" then TEMPO = v end end,
  get = function(_, k) if k == "clock_tempo" then return TEMPO end end,
}

-- norns' global paths table. only `.code` is used (Canopy.lua's rain_load
-- call) and only for string concatenation -- nothing here touches disk.
_path = {code = "/home/we/dust/code/"}

screen = setmetatable({}, {__index = function() return function() end end})
grid = {connect = function() return {key = nil, led = function() end, all = function() end,
                                     refresh = function() end} end}

local function fresh_calls()
  return {
    strike = {}, choke = {},
    exciter_on = {}, exciter_off = {}, exciter_colour = {}, exciter_gated = {}, exciter_gate = {},
    patch_add = {}, patch_gain = {}, patch_free = {},
    voice_mod = {}, voice_tap = {}, voice_structure = {},
    heart_conductance = {},
    voice_pitch = {}, voice_glide = {}, voice_drift = {},
    voice_decay = {}, exciter_decay = {}, voice_bend = {},
    rain_load = {}, rain_volume = {}, rain_excite = {},
  }
end
CALLS = fresh_calls()
engine = setmetatable({}, {__index = function(_, k)
  return function(...)
    local a = {...}
    if k == "strike" then
      table.insert(CALLS.strike, {t = T, voice = a[1], force = a[2]})
    elseif k == "voice_choke" then
      table.insert(CALLS.choke, {t = T, voice = a[1], depth = a[2]})
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
    elseif k == "voice_tap" then
      table.insert(CALLS.voice_tap, {t = T, voice = a[1], v = a[2]})
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
    elseif k == "rain_load" then
      table.insert(CALLS.rain_load, {t = T, path = a[1]})
    elseif k == "rain_volume" then
      table.insert(CALLS.rain_volume, {t = T, v = a[1]})
    elseif k == "rain_excite" then
      table.insert(CALLS.rain_excite, {t = T, v = a[1]})
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
  CALLS = fresh_calls()
  _canopy_mods = {}
  local M = {}
  for _, n in ipairs({"topology", "patch", "state", "bridge", "quantise",
                      "lexicon", "heartwood", "grove", "climate", "weave",
                      "dispatch", "voice", "rambler", "exciter", "gparam"}) do
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
