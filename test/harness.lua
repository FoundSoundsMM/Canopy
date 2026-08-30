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

screen = setmetatable({}, {__index = function() return function() end end})
grid = {connect = function() return {key = nil, led = function() end, all = function() end,
                                     refresh = function() end} end}

local function fresh_calls()
  return {
    strike = {}, choke = {},
    exciter_on = {}, exciter_off = {}, exciter_colour = {}, exciter_gated = {}, exciter_gate = {},
    patch_add = {}, patch_gain = {}, patch_free = {},
    voice_sap = {}, voice_sway = {}, voice_moss = {},
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
    elseif k == "voice_sap" then
      table.insert(CALLS.voice_sap, {t = T, voice = a[1], v = a[2]})
    elseif k == "voice_sway" then
      table.insert(CALLS.voice_sway, {t = T, voice = a[1], v = a[2]})
    elseif k == "voice_moss" then
      table.insert(CALLS.voice_moss, {t = T, voice = a[1], v = a[2]})
    end
  end
end})

_woodland_mods = {}
function wl(name)
  local m = _woodland_mods[name]
  if m == nil then
    m = dofile(ROOT .. "/lib/" .. name .. ".lua")
    _woodland_mods[name] = m
  end
  return m
end

-- a fresh, fully-reset copy of every module
function fresh(seed)
  math.randomseed(seed or 1)
  T = 0
  CALLS = fresh_calls()
  _woodland_mods = {}
  local M = {}
  for _, n in ipairs({"topology", "patch", "state", "bridge", "dispatch", "voice", "rambler", "exciter"}) do
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
