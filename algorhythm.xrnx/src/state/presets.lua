-- AlgoRhythm — Preset save/load module
-- Presets capture all voice algorithm params + expression maps.
-- Instrument assignments are always preserved (never overwritten by a preset).

local Presets = {}

-- ── Simple Lua-value serializer ───────────────────────────────────────────────

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil" then
    return "nil"
  elseif t == "boolean" or t == "number" then
    return tostring(v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "table" then
    -- Detect pure sequential array (integer keys 1..n, no holes, no extra keys)
    local n = #v
    local count = 0
    for _ in pairs(v) do count = count + 1 end
    local is_array = (n > 0 and count == n)

    if is_array then
      local parts = {}
      for i = 1, n do parts[i] = serialize(v[i]) end
      return "{" .. table.concat(parts, ",") .. "}"
    else
      local ni = indent .. "  "
      local parts = {}
      -- Sort keys for deterministic output
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return type(a) < type(b)
      end)
      for _, k in ipairs(keys) do
        local val = v[k]
        if val ~= nil then
          local key_str
          if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            key_str = k
          else
            key_str = "[" .. serialize(k) .. "]"
          end
          parts[#parts + 1] = ni .. key_str .. "=" .. serialize(val, ni)
        end
      end
      return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
  end
  return "nil"
end

-- ── Built-in presets (read-only) ──────────────────────────────────────────────

Presets.BUILTIN = {
  {
    name = "4-on-the-Floor",
    scale_index = 1, root_note = 0, phrase_length = 0,
    voices = {
      { algorithm = "straight", steps = 16, pulses = 4, offset = 0,
        probability = 100, density = 50, note_value = 36,
        octave_min = 3, octave_max = 5, velocity = 100,
        _straight_interval = 4 },
    }
  },
  {
    name = "Tresillo",
    scale_index = 1, root_note = 0, phrase_length = 0,
    voices = {
      { algorithm = "euclidean", steps = 8, pulses = 3, offset = 0,
        probability = 100, density = 50, note_value = 36,
        octave_min = 3, octave_max = 5, velocity = 100},
    }
  },
  {
    name = "Clave 3-2",
    scale_index = 1, root_note = 0, phrase_length = 0,
    voices = {
      { algorithm = "euclidean", steps = 16, pulses = 5, offset = 0,
        probability = 100, density = 50, note_value = 36,
        octave_min = 3, octave_max = 5, velocity = 100 },
    }
  },
  {
    name = "House Groove",
    scale_index = 1, root_note = 0, phrase_length = 0,
    voices = {
      { algorithm = "euclidean", steps = 16, pulses = 4, offset = 0,
        probability = 100, density = 50, note_value = 36,
        octave_min = 3, octave_max = 5, velocity = 100 },
      { algorithm = "euclidean", steps = 16, pulses = 2, offset = 4,
        probability = 100, density = 50, note_value = 38,
        octave_min = 3, octave_max = 5, velocity = 90 },
    }
  },
  {
    name = "Breakbeat",
    scale_index = 1, root_note = 0, phrase_length = 128,
    voices = {
      { algorithm = "euclidean", steps = 16, pulses = 5, offset = 0,
        probability = 100, density = 50, note_value = 48,
        octave_min = 3, octave_max = 5, velocity = 100,
        vel_map = {100,70,90,60,100,80,70,100,60,90,80,70,100,60,80,70} },
    }
  },
  {
    name = "Perlin Drift",
    scale_index = 1, root_note = 0, phrase_length = 0,
    voices = {
      { algorithm = "perlin", steps = 16, pulses = 8, offset = 0,
        probability = 100, density = 55, note_value = 48,
        octave_min = 3, octave_max = 5, velocity = 100 },
    }
  },
  {
    name = "Trap Hats",
    scale_index = 1, root_note = 0, phrase_length = 128,
    voices = {
      { algorithm = "straight", steps = 16, pulses = 16, offset = 0,
        probability = 75, density = 50, note_value = 48,
        octave_min = 3, octave_max = 5, velocity = 100,
        _straight_interval = 1,
        vel_map     = {100,50,80,40,100,60,50,100,40,80,60,50,100,40,60,50},
        ratchet_map = {  1, 1, 1, 1,  2, 1, 1,  1, 1, 1, 2, 1,  1, 1, 1, 1} },
    }
  },
  {
    name = "Acid Bassline",
    scale_index = 1, root_note = 0, phrase_length = 128,
    voices = {
      { algorithm = "euclidean", steps = 16, pulses = 9, offset = 0,
        probability = 100, density = 50, note_value = 36,
        octave_min = 2, octave_max = 4, velocity = 100,
        gate_map     = {100,50,100,100,50,100,50,100,100,50,100,50,100,100,50,100},
        pitch_a_map  = { 36,36, 48, 36,43, 36,36, 48, 36,43, 36,36, 48, 43,36, 36},
        pitch_b_map  = { 36,43, 36, 48,36, 43,36, 36, 48,36, 43,48, 36, 36,43, 36},
        pitch_ab_map = {100,50, 50, 50,30,100,50, 50, 50,30, 50,50,100, 50,50, 30} },
    }
  },
}

-- ── User preset file I/O ──────────────────────────────────────────────────────

local function user_file_path()
  return renoise.tool().bundle_path .. "user_presets.lua"
end

function Presets.load_user()
  local path = user_file_path()
  local f = io.open(path, "r")
  if not f then return {} end
  local src = f:read("*a")
  f:close()
  if not src or src == "" then return {} end
  local fn = loadstring("return " .. src)
  if not fn then return {} end
  local ok, result = pcall(fn)
  if not ok or type(result) ~= "table" then return {} end
  return result
end

local function save_user_list(list)
  local path = user_file_path()
  local f = io.open(path, "w")
  if not f then return false end
  f:write(serialize(list))
  f:close()
  return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Returns ordered list of display names.
function Presets.list_names()
  local names = {}
  for _, p in ipairs(Presets.BUILTIN) do
    names[#names + 1] = p.name
  end
  local user = Presets.load_user()
  for _, p in ipairs(user) do
    names[#names + 1] = p.name
  end
  return names
end

function Presets.is_builtin(idx)
  return idx <= #Presets.BUILTIN
end

-- Returns the preset data table for a given popup index (1-based).
function Presets.get_by_index(idx)
  if idx <= #Presets.BUILTIN then
    return Presets.BUILTIN[idx]
  end
  local user = Presets.load_user()
  local ui = idx - #Presets.BUILTIN
  return user[ui]
end

-- Save current state as a named user preset (overwrites if name exists).
function Presets.save(name, state)
  local data = Presets.state_to_data(state)
  data.name = name
  local user = Presets.load_user()
  local found = false
  for i, p in ipairs(user) do
    if p.name == name then
      user[i] = data
      found = true
      break
    end
  end
  if not found then
    user[#user + 1] = data
  end
  return save_user_list(user)
end

-- Delete a user preset by display name.
function Presets.delete(name)
  local user = Presets.load_user()
  for i, p in ipairs(user) do
    if p.name == name then
      table.remove(user, i)
      break
    end
  end
  save_user_list(user)
end

-- ── Serialize state → data table ─────────────────────────────────────────────

function Presets.state_to_data(state)
  local data = {
    scale_index   = state.scale_index,
    root_note     = state.root_note,
    phrase_length = state.phrase_length,
    voices        = {},
  }
  for i, voice in ipairs(state.voices) do
    local function copy_map(m)
      if not m then return nil end
      local c = {}
      for j = 1, #m do c[j] = m[j] end
      return c
    end
    local vd = {
      algorithm          = voice.algorithm,
      steps              = voice.steps,
      pulses             = voice.pulses,
      offset             = voice.offset,
      probability        = voice.probability,
      density            = voice.density,
      note_value         = voice.note_value,
      octave_min         = voice.octave_min,
      octave_max         = voice.octave_max,
      velocity           = voice.velocity,
      _straight_interval = voice._straight_interval,
      _bres_weight       = voice._bres_weight,
      _logistic_r        = voice._logistic_r,
      _perlin_offset     = voice._perlin_offset,
      _perlin_freq       = voice._perlin_freq,
      _markov_stay       = voice._markov_stay,
      vel_map            = copy_map(voice.vel_map),
      gate_map           = copy_map(voice.gate_map),
      pitch_a_map        = copy_map(voice.pitch_a_map),
      pitch_b_map        = copy_map(voice.pitch_b_map),
      pitch_ab_map       = copy_map(voice.pitch_ab_map),
      ratchet_map        = copy_map(voice.ratchet_map),
      delay_map          = copy_map(voice.delay_map),
    }
    data.voices[i] = vd
  end
  return data
end

-- ── Apply data table → state ──────────────────────────────────────────────────
-- VoiceState is passed in so this module doesn't depend on it directly.
-- Instrument assignments on existing voices are always preserved.

function Presets.apply(data, state, VoiceState)
  if not data then return false end

  state.scale_index   = data.scale_index   or 1
  state.root_note     = data.root_note     or 0
  state.phrase_length = data.phrase_length or 0

  -- Remove excess voices
  while #state.voices > #data.voices do
    table.remove(state.voices)
  end

  for i, vdata in ipairs(data.voices) do
    local is_new = (state.voices[i] == nil)
    local voice  = state.voices[i] or VoiceState.new("Voice " .. i, i)
    state.voices[i] = voice

    -- New voices get instrument auto-assigned by show(); existing keep their assignment.
    if is_new then
      voice._instrument_initialized = false
    end

    voice.algorithm          = vdata.algorithm or "euclidean"
    voice.steps              = vdata.steps     or 16
    voice.pulses             = vdata.pulses    or 4
    voice.offset             = vdata.offset    or 0
    voice.probability        = vdata.probability or 100
    voice.density            = vdata.density     or 50
    voice.note_value         = vdata.note_value  or 48
    voice.octave_min         = vdata.octave_min  or 3
    voice.octave_max         = vdata.octave_max  or 5
    voice.velocity           = vdata.velocity    or 100
    voice._straight_interval = vdata._straight_interval or 4
    voice._bres_weight       = vdata._bres_weight
    voice._logistic_r        = vdata._logistic_r
    voice._perlin_offset     = vdata._perlin_offset
    voice._perlin_freq       = vdata._perlin_freq
    voice._markov_stay       = vdata._markov_stay
    voice._cached_pattern    = nil

    -- Reinit maps to defaults for the new step count, then overlay preset maps.
    voice:init_step_maps(voice.steps)
    local function overlay(target, src)
      if src then
        for j = 1, math.min(#src, voice.steps) do
          target[j] = src[j]
        end
      end
    end
    overlay(voice.vel_map,      vdata.vel_map)
    overlay(voice.gate_map,     vdata.gate_map)
    overlay(voice.pitch_a_map,  vdata.pitch_a_map)
    overlay(voice.pitch_b_map,  vdata.pitch_b_map)
    overlay(voice.pitch_ab_map, vdata.pitch_ab_map)
    overlay(voice.ratchet_map,  vdata.ratchet_map)
    overlay(voice.delay_map,    vdata.delay_map)
  end

  return true
end

return Presets
