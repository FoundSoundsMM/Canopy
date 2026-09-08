-- sample.lua
-- §2.5: the eight Sample cells -- two mirrored diagonals of four -- and the
-- settings page for one.
--
-- the right-hand four were the heartwood: a diffusion lattice whose whole
-- control surface was one "conductance" knob standing in for a hop delay and
-- a loss at once, and whose output was a pulse emerging from a different cell
-- some time later. the left-hand four were the grove's pitch fields (§2.6).
-- both families are gone, and this is what took their seats.
--
-- what a sample cell is. a pulse down a cable plays a recording from the top;
-- so does K1+tap. it plays under an envelope with a slow attack and a slow
-- fall, both set per cell, so a thunder roll can take four seconds to arrive
-- and twelve to leave -- that swell is the whole instrument, and it is what
-- the page is mostly about.
--
-- THE RECORDING IS A KNOB. it used to be a field on the cell in topology.lua,
-- one .wav per seat, fixed at load: four cells, four files, and a family
-- exactly as big as the folder that shipped with the script. the File row
-- below walks every playable file in that folder instead, so a seat is a
-- player rather than a sound, anything dropped into audio/ is on the panel
-- without touching a line of code, and eight seats are eight things that can
-- be sounding at once rather than four things that can only ever be those
-- four. see sample.scan.
--
-- ONE SHOT OR LOOP. a one-shot is what this family has always been: the
-- recording plays once, from the top, and stops -- whether or not the
-- envelope is still open. a looping cell holds instead: the first pulse
-- swells it in and leaves it running round the buffer, and the next pulse on
-- the same cell lets it go. that is a bed rather than a hit, which is exactly
-- what a two-minute field recording usually wants to be, and it is the one
-- thing the four fixed cells could never do without a Clock cell wedged
-- against them. one-shot is the default: it is what a pulse means everywhere
-- else on the panel.
--
-- it holds its own Level knob, the way a gust does, because a field
-- recording's loudness is a property of the recording rather than of the
-- cable carrying it -- Thunder.wav and Sea.wav are nowhere near each other
-- to start with, and levelling them at the mixer would mean re-levelling
-- every time one is re-cabled. §8.6's per-recording trim (FILE_TRIM) is the
-- same argument one level down.
--
-- IT IS HEARD WITHOUT A CABLE, like a gust and unlike everything else that
-- makes a sound here: the engine routes it to the main mix, dead centre --
-- unlike a gust, this family carries no pan of its own. it spent one build
-- cabled to an Output cell like a voice, on the principle that one rule
-- about what is audible beats two --
-- and the principle is right, but a field recording is a bed. the thing you
-- reach for one to do is fill the room under a patch, and spending an Output
-- seat and a cable on each of eight of them to get there was a tax on the one
-- family that never wanted the placement. a cable to an Output cell is still
-- allowed and still means what it means; it just places a second copy.
--
-- the page object is the same shape voice.lua/gust.lua/lfo.lua expose --
-- PARAMS with get/set/text/push, plus nudge/param/PARAM_COUNT -- so
-- cellparam.lua hands it to screenui and gridui through the one code path
-- they already have.

local topology = wl("topology")
local state    = wl("state")
local bridge   = wl("bridge")

local sample = {}

-- deliberately much longer at the top than a gust's: "slow" here means the
-- length of a whole passage, not the length of a note. a swell that takes
-- twenty seconds to arrive is the reason this family exists.
sample.ATTACK_MIN, sample.ATTACK_MAX = 0.02, 20.0
sample.DECAY_MIN, sample.DECAY_MAX = 0.10, 40.0

-- log-mapped, both of them, and around the cell's own default rather than
-- around the middle of the range: the useful half of a swell time is its
-- bottom, exactly as in gust.lua.
sample.ATTACK_OCTAVES = 3
sample.DECAY_OCTAVES = 2.5

-- playback rate, in octaves either side of the recording's own speed. a
-- thunder roll at half speed is a different weather system, and pitching
-- cicadas up is the cheapest new sound on the panel.
sample.SPEED_OCTAVES = 1.5

-- a sample is a long sound and a key is a fast gesture, so -- like a gust --
-- a re-press part way up the swell is a legitimate thing to want and gets
-- only a floor short enough to be inaudible.
sample.REFRACTORY = 0.02

local last_note = {}   -- id -> util.time() of the last note that landed
local held = {}        -- id -> true while a looping cell is running
local last_path = {}   -- id -> the path last handed to the engine

local function vp_get(key, default)
  return function(id) return state.get_vparam(id, key, default) end
end

local function vp_set(key)
  return function(id, v) return state.set_vparam(id, key, v) end
end

-- the folder (§2.5) ----------------------------------------------------------
-- one folder, the script's own audio/, scanned once at init. one and not
-- several because the row that picks a file has twenty-eight pixels to print
-- its name in: a list that spanned two directories would need a path on the
-- screen to be readable, and there is no room for one. drop a .wav in there
-- and it is on the panel next time the script loads.

sample.EXTENSIONS = {wav = true, aif = true, aiff = true, flac = true}

-- the four that ship with the script, and the fallback when the folder cannot
-- be read at all (norns' util.scandir missing, which is the offline test
-- harness, or a folder that is not there). a fallback rather than an error:
-- Buffer.read has no path back to Lua, so a missing file is already
-- indistinguishable from a Level of zero, and a cell with nothing to play is
-- a cell that makes no sound rather than a script that will not start.
sample.SHIPPED = {"Cicada.wav", "Rain.wav", "Sea.wav", "Thunder.wav"}

-- §8.6 per-RECORDING output trim, keyed by filename. it used to be per cell
-- (topology's SMP_CELLS), which was right for exactly as long as a cell owned
-- one recording: measured, the four shipped files run from -42 to -55 LUFS,
-- so at one shared engine constant the quietest of them was thirteen decibels
-- down before anything had been touched. the engine's constant is set by
-- Cicada, the quietest, and these bring the other three back down to it.
--
-- anything not named here is 1.0 -- no trim. a file the player dropped in
-- themselves has not been measured and guessing at it would be worse than
-- leaving it alone: what the Level knob is for is exactly this.
sample.FILE_TRIM = {
  ["Cicada.wav"]  = 1.00,
  ["Rain.wav"]    = 0.21,
  ["Thunder.wav"] = 0.25,
  ["Sea.wav"]     = 0.36,
}

local files = {}    -- {name = "Rain.wav", label = "Rain"}, sorted by name
local dir = nil     -- the folder they were found in, trailing slash included

local function extension_of(name)
  return (name:match("%.([%a%d]+)$") or ""):lower()
end

-- the name without its extension, which is what the File row prints. the row
-- is 28px wide -- five or six characters of norns' font -- so ".wav" on the
-- end would cost most of the name, and every entry in the list has it.
local function label_of(name)
  return (name:gsub("%.[%a%d]+$", ""))
end

local function add_file(name)
  if not sample.EXTENSIONS[extension_of(name)] then return end
  files[#files + 1] = {name = name, label = label_of(name)}
end

-- read `d` and keep every playable file in it, sorted by name so the row's
-- order is the same on every load and a saved patch comes back on the file it
-- was left on. norns' util.scandir is the only thing here that touches disk;
-- without it (the offline harness) the shipped four stand in.
function sample.scan(d)
  dir = d
  files = {}
  local names = nil
  if util and util.scandir then
    local ok, list = pcall(util.scandir, d)
    if ok and type(list) == "table" then names = list end
  end
  if names then
    for _, name in ipairs(names) do
      -- scandir marks directories with a trailing slash; there is no
      -- recursion here, so they are simply not files.
      if not name:match("/$") then add_file(name) end
    end
  else
    for _, name in ipairs(sample.SHIPPED) do add_file(name) end
  end
  table.sort(files, function(a, b) return a.name < b.name end)
  return files
end

function sample.files()
  return files
end

-- which file this cell comes up on: its seat number, wrapped round the list.
-- so the eight seats spread across whatever is in the folder rather than all
-- landing on the first entry -- with the four shipped files that is each
-- diagonal playing all four, and with eight files in there it is eight cells
-- on eight different recordings the first time the script is opened.
--
-- returned as the KNOB position rather than as an index, because that is what
-- state.get_vparam stores and the row has to round-trip through it.
function sample.file_default(id)
  local cell = topology.get(id)
  local n = #files
  if n == 0 or not cell then return 0 end
  return ((cell.index % n) + 0.5) / n
end

-- the knob is a plain continuous 0..1 and the position is DERIVED from it
-- rather than stored -- the same arrangement synth.RATIOS has, so the row
-- round-trips through its own getter and needs none of cellparam's unrounded
-- accumulator.
function sample.file_index(id)
  local n = #files
  if n == 0 then return 0 end
  local v = state.get_vparam(id, "file", sample.file_default(id))
  return util.clamp(math.floor(v * n) + 1, 1, n)
end

function sample.file(id)
  return files[sample.file_index(id)]
end

function sample.file_name(id)
  local f = sample.file(id)
  return f and f.name or nil
end

function sample.file_path(id)
  local f = sample.file(id)
  return (f and dir) and (dir .. f.name) or nil
end

-- hand this cell's file to the engine, but only if it is not already holding
-- it: a File row moves several detents per entry and Buffer.read is a disk
-- read that frees and restarts the cell's synth. every other knob survives
-- the reload (the engine's smpArgs), so this is safe to call whenever.
function sample.push_file(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return end
  local path = sample.file_path(id)
  if not path or last_path[id] == path then return end
  last_path[id] = path
  bridge.smp_load(cell.index, path)
end

-- one shot or loop -----------------------------------------------------------

function sample.looping(id)
  return state.get_vparam(id, "loop", 0) >= 0.5
end

function sample.set_looping(id, on)
  state.set_vparam(id, "loop", on and 1 or 0)
end

-- is this cell running its loop right now? the grid reads it, so a held cell
-- is visibly held rather than only audibly.
function sample.is_held(id)
  return held[id] == true
end

-- envelope ------------------------------------------------------------------

function sample.attack_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return nil end
  local a = state.get_vparam(id, "attack", 0.5)
  return util.clamp(cell.attack * (2 ^ ((a - 0.5) * 2 * sample.ATTACK_OCTAVES)),
                    sample.ATTACK_MIN, sample.ATTACK_MAX)
end

-- Decay rides on state.decay rather than on a vparam of its own, the way a
-- voice's, a GVOICE cell's and a gust's all do, so the global Decay macro
-- (§4.1) reaches these as well.
function sample.decay_seconds(id)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return nil end
  local d = state.get_decay(id)
  return util.clamp(cell.decay * (2 ^ ((d - 0.5) * 2 * sample.DECAY_OCTAVES))
                      * wl("voice").decay_mult_ratio(),
                    sample.DECAY_MIN, sample.DECAY_MAX)
end

function sample.speed_ratio(id)
  local v = state.get_vparam(id, "speed", 0.5)
  return 2 ^ ((v - 0.5) * 2 * sample.SPEED_OCTAVES)
end

function sample.level(id)
  return state.get_vparam(id, "level", 0.7)
end

-- §8.6 this cell's Level with its RECORDING's trim folded in -- voice.amp's
-- copy for the field recordings, with one wrinkle those do not have.
--
-- the engine SQUARES `level` (it is the fader law for these cells: it keeps
-- the bottom of the travel usable rather than jumping straight to loud). so a
-- trim that is to come out the far side as a plain gain has to go in as its
-- square root, or a 0.22 would land as a 0.05. every trim is at most 1, which
-- is what keeps this inside the engine's own `level.clip(0, 1)` at every
-- position of the knob.
function sample.amp(id)
  local name = sample.file_name(id)
  return sample.level(id) * math.sqrt((name and sample.FILE_TRIM[name]) or 1)
end

-- sounding --------------------------------------------------------------------

-- play this cell's sample. `force` is how hard -- K1+tap is full, a pulse
-- arrives at whatever weight and cable gain it has left. returns true if
-- anything actually went out, so callers can decide whether to flash and
-- whether to answer.
--
-- on a one-shot cell that is a note from the top. on a looping one it is a
-- TOGGLE: the first arrival opens the gate and starts the buffer round, the
-- next lets it go. a toggle rather than a gate because there is nothing on
-- the far end of a cable to release it -- a pulse is an instant, and the only
-- family that sends a sustained anything is a Clock cell on High, which has
-- its own path to the same argument (bridge.smp_hold).
function sample.play(id, force)
  local cell = topology.get(id)
  if not cell or cell.type ~= "SMP" then return false end
  local now = util.time()
  -- `>= 0` as well as `< refractory`, same as dispatch.strike_voice: a clock
  -- that has gone backwards (a reload, the test harness rewinding its virtual
  -- time) must read as "long ago" rather than latch the cell silent.
  local since = now - (last_note[id] or -1)
  if since >= 0 and since < sample.REFRACTORY then return false end
  last_note[id] = now

  local f = util.clamp(force or 1, 0, 1)
  if sample.looping(id) then
    if held[id] then
      held[id] = nil
      bridge.smp_gate(cell.index, false)
      state.flash(id, f)
      return true
    end
    held[id] = true
    bridge.smp_gate(cell.index, true)
  end
  bridge.smp_note(cell.index, f)
  state.flash(id, f)
  return true
end

-- let go of a looping cell without playing it: what a Mode change back to
-- one-shot has to do, or the cell would be left sounding with nothing on the
-- page able to stop it.
function sample.release(id)
  local cell = topology.get(id)
  if not cell or not held[id] then return end
  held[id] = nil
  bridge.smp_gate(cell.index, false)
end

-- §5.1: how brightly the cell sits. the same shape a gust's indicator has --
-- open page brightest, cabled next, idle dim -- with the trigger flash on
-- top, and one addition: a looping cell that is actually running sits at the
-- cabled level whether or not it is cabled, because it is audible and the
-- panel should say so. the real envelope is seconds long and only SC knows
-- where it is; the flash is the trigger, not the sound.
function sample.level_at(id, base)
  base = base or 2
  local lvl = (state.cell_edit == id) and 10
           or ((wl("patch").degree(id) > 0 or held[id]) and 5 or base)
  return state.flash_level(id, lvl)
end

-- the page ---------------------------------------------------------------------
-- seven rows: which recording, how it plays, the two envelope times, speed,
-- level, and how much of it goes to the send.

sample.PARAMS = {
  {
    -- §2.5 which recording. `word` for the same reason the Scale row uses it:
    -- the value IS a name, and no pointer angle or bar ever said "Thunder".
    -- the ticks underneath (glyph_data) are what a box alone could not say --
    -- that there are eleven files in the folder and this is the fourth --
    -- which is the whole of what makes the row scrollable rather than a
    -- setting you poke at.
    key = "file", label = "File", glyph = "word",
    default = 0,
    steps_fn = function() return math.max(1, #files) end,
    get = function(id) return state.get_vparam(id, "file", sample.file_default(id)) end,
    set = vp_set("file"),
    text = function(id)
      local f = sample.file(id)
      return f and f.label or "-"
    end,
    glyph_data = function(id)
      return {idx = sample.file_index(id) - 1, total = math.max(1, #files)}
    end,
    push = function(id)
      sample.push_file(id)
      -- the trim is the recording's, so the Level the engine is holding was
      -- computed for the file this cell has just stopped playing.
      bridge.smp_level(topology.get(id).index, sample.amp(id))
    end,
  },
  {
    -- one shot or loop. a switch and not a value, so it draws as a flag and
    -- takes two detents to flip -- the same shape and the same feel as a
    -- Clock cell's Mode row and an LFO's Sync.
    key = "loop", label = "Mode", glyph = "flag", default = 0,
    stepped = true, steps_fn = function() return 2 end,
    get = function(id) return sample.looping(id) and 1 or 0 end,
    set = function(id, v)
      local on = v >= 0.5
      -- turning the loop off while it is running has to stop it: the toggle
      -- that would have stopped it is the row being turned off.
      if not on then sample.release(id) end
      sample.set_looping(id, on)
    end,
    text = function(id) return sample.looping(id) and "loop" or "once" end,
    push = function(id)
      bridge.smp_loop(topology.get(id).index, sample.looping(id))
    end,
  },
  {
    key = "attack", label = "Attack", glyph = "rampup", default = 0.5,
    get = vp_get("attack", 0.5), set = vp_set("attack"),
    text = function(id) return string.format("%.2f s", sample.attack_seconds(id)) end,
    push = function(id)
      bridge.smp_attack(topology.get(id).index, sample.attack_seconds(id))
    end,
  },
  {
    key = "decay", label = "Decay", glyph = "ramp",
    get = function(id) return state.get_decay(id) end,
    set = function(id, v)
      state.decay[id] = util.clamp(v, 0, 1)
      return state.decay[id]
    end,
    text = function(id) return string.format("%.2f s", sample.decay_seconds(id)) end,
    push = function(id)
      bridge.smp_decay(topology.get(id).index, sample.decay_seconds(id))
    end,
  },
  {
    key = "speed", label = "Speed", glyph = "marker", default = 0.5,
    get = vp_get("speed", 0.5), set = vp_set("speed"),
    text = function(id) return string.format("x%.2f", sample.speed_ratio(id)) end,
    push = function(id)
      bridge.smp_speed(topology.get(id).index, sample.speed_ratio(id))
    end,
  },
  {
    key = "level", label = "Level", glyph = "fader", default = 0.7,
    get = vp_get("level", 0.7), set = vp_set("level"),
    text = function(id) return string.format("%.2f", sample.level(id)) end,
    push = function(id)
      bridge.smp_level(topology.get(id).index, sample.amp(id))
    end,
  },
  -- §2.11c how much of this recording goes to the shared send effect.
  wl("send").row(),
}

sample.PARAM_COUNT = #sample.PARAMS

function sample.param(i)
  return sample.PARAMS[util.clamp(i, 1, #sample.PARAMS)]
end

-- the same contract every other cell page's nudge has, with one addition: a
-- row that declares `steps_fn` is scaled so one entry takes about three
-- detents rather than a fraction of the knob's travel. File needs it (a
-- folder of four files across eighty detents is twenty detents an entry) and
-- so does Mode; cellparam owns the arithmetic, as it does for every page it
-- builds itself.
function sample.nudge(id, i, delta)
  local p = sample.param(i)
  p.set(id, util.clamp(p.get(id) + wl("cellparam").scale(p, delta), 0, 1))
  p.push(id)
  return p
end

function sample.push_all(id)
  for _, p in ipairs(sample.PARAMS) do p.push(id) end
end

function sample.each()
  local ids = {}
  for id, cell in topology.each() do
    if cell.type == "SMP" then table.insert(ids, id) end
  end
  return ids
end

-- init -------------------------------------------------------------------------
-- `d` is the folder the recordings live in (Canopy.lua passes
-- norns.state.path .. "audio/"). the loads are async on the SC side and every
-- knob below is held there whether or not the buffer has landed, so the order
-- of these does not matter -- see Engine_Canopy.sc's smp_load.

function sample.init(d)
  sample.scan(d)
  for _, id in ipairs(sample.each()) do
    local cell = topology.get(id)
    -- always centre now (topology.lua's SMP_CELLS carry no pan of their
    -- own) -- pushed once and never again, the same shape a gust's fixed pan
    -- has, in case a future build gives this row something to move.
    bridge.smp_pan(cell.index, cell.pan or 0)
    sample.push_all(id)
  end
end

-- the global Decay macro and a per-cell Decay row both land here.
state.on_decay_change(function(id)
  local cell = topology.get(id)
  if cell and cell.type == "SMP" then
    bridge.smp_decay(cell.index, sample.decay_seconds(id))
  end
end)

return sample
