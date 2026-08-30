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

CALLS = {strike = {}, choke = {}}
engine = setmetatable({}, {__index = function(_, k)
  return function(...)
    local a = {...}
    if k == "strike" then
      table.insert(CALLS.strike, {t = T, voice = a[1], force = a[2]})
    elseif k == "voice_choke" then
      table.insert(CALLS.choke, {t = T, voice = a[1], depth = a[2]})
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
  CALLS = {strike = {}, choke = {}}
  _woodland_mods = {}
  local M = {}
  for _, n in ipairs({"topology", "patch", "state", "bridge", "dispatch", "voice", "rambler"}) do
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
