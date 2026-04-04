-- AlgoRhythm — Main UI panel
-- Phase 3r: alignment, collapsible lanes, instrument name in header, redesigned params

local SongState    = require("src/state/song_state")
local VoiceState   = require("src/state/voice_state")
local Scales       = require("src/utils/scales")
local Euclidean    = require("src/algorithms/euclidean")
local Bresenham    = require("src/algorithms/bresenham")
local Cellular     = require("src/algorithms/cellular")
local Markov       = require("src/algorithms/markov")
local Logistic     = require("src/algorithms/logistic")
local Perlin       = require("src/algorithms/perlin")
local RandomW      = require("src/algorithms/random_weighted")
local Straight     = require("src/algorithms/straight")
local PhraseWriter = require("src/output/phrase_writer")
local Audition     = require("src/output/audition")
local Evolve       = require("src/state/evolve")
local Presets      = require("src/state/presets")

local MainPanel = {}

local state  = SongState.new()
local dialog = nil
local vb     = nil
local last_preset_idx = 1  -- remembered across rebuilds so popup stays on selected preset

local ALGORITHMS = {
  { id = VoiceState.ALGO_EUCLIDEAN, label = "Euclidean", mod = Euclidean },
  { id = VoiceState.ALGO_BRESENHAM, label = "Bresenham", mod = Bresenham },
  { id = VoiceState.ALGO_CELLULAR,  label = "Cellular",  mod = Cellular  },
  { id = VoiceState.ALGO_MARKOV,    label = "Markov",    mod = Markov    },
  { id = VoiceState.ALGO_LOGISTIC,  label = "Logistic",  mod = Logistic  },
  { id = VoiceState.ALGO_PERLIN,    label = "Perlin",    mod = Perlin    },
  { id = VoiceState.ALGO_RANDOM,    label = "Random",    mod = RandomW   },
  { id = VoiceState.ALGO_STRAIGHT,  label = "Straight",  mod = Straight  },
}

local ALGO_LABELS = {}
for _, a in ipairs(ALGORITHMS) do ALGO_LABELS[#ALGO_LABELS + 1] = a.label end

local USES_PULSES = {
  [VoiceState.ALGO_EUCLIDEAN] = true,
  [VoiceState.ALGO_BRESENHAM] = true,
}

local COL_ACTIVE   = {76, 182, 139}   -- green: hit step within voice.steps
local COL_INACTIVE = {58,  58,  62}   -- visible mid-gray: no-hit within voice.steps
local COL_GHOST    = {28,  28,  32}   -- near-black with slight blue: beyond voice.steps
local COL_VEL      = {220, 145,  45}  -- amber: velocity lane
local COL_GATE     = { 70, 150, 215}  -- blue:  gate lane
local GRID_STEPS   = 16

local VOICE_COLORS = {
  { 25,  35, 120},   -- voice 1: dark navy
  {  0, 120, 185},   -- voice 2: ocean blue
  {  0, 200, 220},   -- voice 3: bright cyan
  {240, 225, 190},   -- voice 4: cream
}

local ROOT_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

local PHRASE_LENGTH_VALUES = {0, 32, 64, 128, 256, 512}
local PHRASE_LENGTH_LABELS = {"Auto", "32", "64", "128", "256", "512"}

-- Total dialog inner width (content column width)
local PANEL_W = 660

local rebuild  -- forward declaration

-- ── Preset bar ───────────────────────────────────────────────────────────────

local function build_preset_bar()
  local names = Presets.list_names()
  if #names == 0 then names = {"(none)"} end
  local safe_idx = math.max(1, math.min(last_preset_idx, #names))

  return vb:row {
    spacing = 6,
    vb:text { text = "Preset:", width = 50 },
    vb:popup {
      id    = "preset_popup",
      items = names,
      value = safe_idx,
      width = 168,
    },
    vb:button {
      text = "Load", width = 48,
      notifier = function()
        local pp   = vb.views["preset_popup"]
        local idx  = pp and pp.value or 1
        local data = Presets.get_by_index(idx)
        if data then
          last_preset_idx = idx
          Presets.apply(data, state, VoiceState)
          rebuild()
        end
      end,
    },
    vb:text { text = "|", width = 10 },
    vb:textfield {
      id    = "preset_name_field",
      text  = "",
      width = 140,
    },
    vb:button {
      text = "Save", width = 48,
      notifier = function()
        local tf   = vb.views["preset_name_field"]
        local name = (tf and tf.text or ""):match("^%s*(.-)%s*$")
        if name == "" then
          renoise.app():show_error("Enter a preset name first.")
          return
        end
        if Presets.save(name, state) then
          -- Position popup on the saved preset after rebuild
          local all_names = Presets.list_names()
          for i, n in ipairs(all_names) do
            if n == name then last_preset_idx = i; break end
          end
          renoise.app():show_status("AlgoRhythm: Saved preset '" .. name .. "'.")
          rebuild()
        else
          renoise.app():show_error("AlgoRhythm: Could not write preset file.")
        end
      end,
    },
    vb:button {
      text = "Delete", width = 56,
      notifier = function()
        local pp  = vb.views["preset_popup"]
        local idx = pp and pp.value or 1
        if Presets.is_builtin(idx) then
          renoise.app():show_error("Built-in presets cannot be deleted.")
          return
        end
        local user = Presets.load_user()
        local ui   = idx - #Presets.BUILTIN
        local pname = user[ui] and user[ui].name or ""
        if pname == "" then return end
        Presets.delete(pname)
        last_preset_idx = 1
        renoise.app():show_status("AlgoRhythm: Deleted preset '" .. pname .. "'.")
        rebuild()
      end,
    },
  }
end

-- ── helpers ──────────────────────────────────────────────────────────────────

local function algo_index_for(voice)
  for i, a in ipairs(ALGORITHMS) do
    if a.id == voice.algorithm then return i end
  end
  return 1
end

local function algo_label(algo_id)
  for _, a in ipairs(ALGORITHMS) do
    if a.id == algo_id then return a.label end
  end
  return "?"
end

local function algo_params(voice)
  return {
    steps           = voice.steps,
    pulses          = voice.pulses,
    offset          = voice.offset,
    weight          = voice._bres_weight      or 1.0,
    density         = voice.density / 100.0,
    hit_probability = voice.density / 100.0,
    stay_weight     = voice._markov_stay      or 0.7,
    rule            = voice._ca_rule          or 30,
    generation      = voice._ca_generation    or 0,
    r               = voice._logistic_r       or 3.7,
    threshold       = voice._threshold        or 0.5,
    time_offset     = voice._perlin_offset    or 0.0,
    frequency       = voice._perlin_freq      or 1.0,
    division_steps  = voice._straight_interval or 4,
    seed            = state.seed,
  }
end

local function generate_pattern(v_idx)
  local voice = state.voices[v_idx]
  local algo  = ALGORITHMS[algo_index_for(voice)]
  voice._cached_pattern = algo.mod.generate(algo_params(voice))
  return voice._cached_pattern
end

-- Baked evolution: save/restore voice mutation params around multi-block generation
local function save_voice_params(voice)
  return {
    pulses         = voice.pulses,
    offset         = voice.offset,
    density        = voice.density,
    _bres_weight   = voice._bres_weight,
    _logistic_r    = voice._logistic_r,
    _perlin_offset = voice._perlin_offset,
    _markov_stay   = voice._markov_stay,
    _ca_generation = voice._ca_generation,
  }
end

local function restore_voice_params(voice, saved)
  for k, v in pairs(saved) do voice[k] = v end
end

-- Generate a pattern respecting state.phrase_length.
-- When phrase_length > voice.steps: fills the phrase with multiple evolving blocks.
-- Voice params are temporarily mutated between blocks then fully restored.
local function generate_baked_pattern(v_idx)
  local voice  = state.voices[v_idx]
  local algo   = ALGORITHMS[algo_index_for(voice)]
  local steps  = voice.steps
  local total  = (state.phrase_length > 0) and state.phrase_length or steps
  if total <= steps then
    return generate_pattern(v_idx)
  end
  local saved    = save_voice_params(voice)
  local result   = {}
  local n_blocks = math.ceil(total / steps)
  for b = 1, n_blocks do
    local block = algo.mod.generate(algo_params(voice))
    local take  = math.min(#block, total - #result)
    for i = 1, take do result[#result + 1] = block[i] end
    if b < n_blocks then Evolve.mutate(voice) end
  end
  restore_voice_params(voice, saved)
  voice._cached_pattern = result
  return result
end

local function refresh_grid(v_idx)
  if not vb then return end
  local voice   = state.voices[v_idx]
  local pattern = voice._cached_pattern or {}
  for s = 1, GRID_STEPS do
    local btn = vb.views["step_v" .. v_idx .. "_s" .. s]
    if btn then
      if s > voice.steps then
        btn.color = COL_GHOST
      elseif pattern[s] then
        btn.color = COL_ACTIVE
      else
        btn.color = COL_INACTIVE
      end
    end
  end
end

-- Update slider values and show/hide step columns for both expr lanes.
local function refresh_expr_lane(v_idx)
  if not vb then return end
  local voice = state.voices[v_idx]
  local configs = {
    { key = "vel",      map = voice.vel_map,      max_val = 127 },
    { key = "gate",     map = voice.gate_map,     max_val = 100 },
    { key = "pitch_a",  map = voice.pitch_a_map,  max_val = 119 },
    { key = "pitch_b",  map = voice.pitch_b_map,  max_val = 119 },
    { key = "pitch_ab", map = voice.pitch_ab_map, max_val = 100 },
    { key = "ratchet",  map = voice.ratchet_map,  max_val = 4   },
    { key = "delay",    map = voice.delay_map,    max_val = 255 },
  }
  for _, lc in ipairs(configs) do
    for s = 1, 16 do
      local col = vb.views["expr_" .. lc.key .. "_col_v" .. v_idx .. "_s" .. s]
      local sl  = vb.views["expr_" .. lc.key .. "_sl_v"  .. v_idx .. "_s" .. s]
      if col then col.visible = (s <= voice.steps) end
      if sl and lc.map[s] then sl.value = lc.map[s] end
      local vl = vb.views["expr_" .. lc.key .. "_val_v"  .. v_idx .. "_s" .. s]
      if vl and lc.map[s] then vl.text = string.format("%3d", lc.map[s]) end
    end
  end
end

-- Build the expression sub-panel for one voice lane (pre-builds all 16 slots per lane).
local function build_expr_panel(v_idx)
  local voice = state.voices[v_idx]
  local COL_PITCH_B  = {110, 195, 195}
  local COL_PITCH_AB = {160, 120, 200}

  -- ── Single-lane configs (shown one at a time via dropdown) ────────────────
  local LANE_CONFIGS = {
    { key = "vel",     label = "VELOCITY", color = COL_VEL,         min_val = 1, max_val = 127,
      map_fn = function() return voice.vel_map     end },
    { key = "gate",    label = "GATE %",   color = COL_GATE,        min_val = 1, max_val = 100,
      map_fn = function() return voice.gate_map    end },
    { key = "ratchet", label = "RATCHET",  color = {200, 90,  50},  min_val = 1, max_val = 4,
      map_fn = function() return voice.ratchet_map end },
    { key = "delay",   label = "DELAY",    color = {120, 200, 220}, min_val = 0, max_val = 255,
      map_fn = function() return voice.delay_map   end },
  }

  -- ── Pitch configs (always visible, stacked — Seqund-style) ───────────────
  local PITCH_CONFIGS = {
    { key = "pitch_a",  label = "Pitch A",  color = COL_ACTIVE,
      min_val = 0, max_val = 119,
      default = function() return voice.note_value or 48 end,
      map_fn  = function() return voice.pitch_a_map  end },
    { key = "pitch_ab", label = "Prob A/B", color = COL_PITCH_AB,
      min_val = 0, max_val = 100,
      default = function() return 50 end,
      map_fn  = function() return voice.pitch_ab_map end },
    { key = "pitch_b",  label = "Pitch B",  color = COL_PITCH_B,
      min_val = 0, max_val = 119,
      default = function() return voice.note_value or 48 end,
      map_fn  = function() return voice.pitch_b_map  end },
  }

  local LABEL_W = 72   -- width of the left label column in pitch rows

  -- ── Helper: pick a random in-scale note ──────────────────────────────────
  local function rand_pitch_note()
    if state.scale_index and state.scale_index > 1 then
      local pool = Scales.notes_in_range(
        state.scale_index, state.root_note,
        voice.octave_min or 3, voice.octave_max or 5)
      if pool and #pool > 0 then return pool[math.random(#pool)] end
    end
    local lo = (voice.octave_min or 3) * 12
    local hi = math.min((voice.octave_max or 5) * 12 + 11, 119)
    return math.random(lo, hi)
  end

  -- ── Build single-lane rows (Velocity / Gate / Ratchet / Delay) ───────────
  local lane_rows = {}
  for li, lc in ipairs(LANE_CONFIGS) do
    local row = vb:row {
      id      = "expr_" .. lc.key .. "_row_v" .. v_idx,
      spacing = 3,
      visible = (li == 1),
    }
    for s = 1, 16 do
      local si     = s
      local min_v  = lc.min_val
      local max_v  = lc.max_val
      local map_fn = lc.map_fn
      local col = vb:column {
        id      = "expr_" .. lc.key .. "_col_v" .. v_idx .. "_s" .. si,
        spacing = 2,
        visible = (si <= voice.steps),
      }
      col:add_child(vb:text {
        id    = "expr_" .. lc.key .. "_val_v" .. v_idx .. "_s" .. si,
        text  = string.format("%3d", math.floor(math.max(min_v, map_fn()[si] or max_v))),
        width = 26,
      })
      col:add_child(vb:minislider {
        id    = "expr_" .. lc.key .. "_sl_v" .. v_idx .. "_s" .. si,
        min   = min_v, max = max_v,
        value = math.max(min_v, map_fn()[si] or max_v),
        width = 26, height = 54,
        notifier = function(val)
          map_fn()[si] = math.floor(val)
          local lbl = vb.views["expr_" .. lc.key .. "_val_v" .. v_idx .. "_s" .. si]
          if lbl then lbl.text = string.format("%3d", math.floor(val)) end
        end,
      })
      col:add_child(vb:text { text = tostring(si), width = 26 })
      row:add_child(col)
    end
    lane_rows[li] = row
  end

  -- ── Build always-visible pitch rows (Pitch A / Prob A/B / Pitch B) ───────
  local pitch_rows = {}
  for _, pc in ipairs(PITCH_CONFIGS) do
    local pkey   = pc.key
    local pmap   = pc.map_fn
    local min_v  = pc.min_val
    local max_v  = pc.max_val
    local def_fn = pc.default

    -- Left label column: name + Rand + Reset buttons
    local lbl_col = vb:column { width = LABEL_W, spacing = 2 }
    lbl_col:add_child(vb:text { text = pc.label, font = "bold", width = LABEL_W })
    lbl_col:add_child(vb:button {
      text = "Rand", width = LABEL_W,
      notifier = function()
        local m = pmap()
        if pkey == "pitch_ab" then
          for i = 1, voice.steps do m[i] = math.random(0, 100) end
        else
          for i = 1, voice.steps do m[i] = rand_pitch_note() end
        end
        refresh_expr_lane(v_idx)
      end,
    })
    lbl_col:add_child(vb:button {
      text = "Reset", width = LABEL_W,
      notifier = function()
        local m = pmap(); local def = def_fn()
        for i = 1, voice.steps do m[i] = def end
        refresh_expr_lane(v_idx)
      end,
    })

    local row = vb:row {
      id      = "expr_" .. pkey .. "_row_v" .. v_idx,
      spacing = 3,
    }
    row:add_child(lbl_col)
    for s = 1, 16 do
      local si  = s
      local def = def_fn()
      local col = vb:column {
        id      = "expr_" .. pkey .. "_col_v" .. v_idx .. "_s" .. si,
        spacing = 2,
        visible = (si <= voice.steps),
      }
      col:add_child(vb:text {
        id    = "expr_" .. pkey .. "_val_v" .. v_idx .. "_s" .. si,
        text  = string.format("%3d", math.floor(math.max(min_v, pmap()[si] or def))),
        width = 26,
      })
      col:add_child(vb:minislider {
        id    = "expr_" .. pkey .. "_sl_v" .. v_idx .. "_s" .. si,
        min   = min_v, max = max_v,
        value = math.max(min_v, pmap()[si] or def),
        width = 26, height = 40,
        notifier = function(val)
          pmap()[si] = math.floor(val)
          local vl = vb.views["expr_" .. pkey .. "_val_v" .. v_idx .. "_s" .. si]
          if vl then vl.text = string.format("%3d", math.floor(val)) end
        end,
      })
      row:add_child(col)
    end
    pitch_rows[#pitch_rows + 1] = row
  end

  -- ── Control row (single-lane section) ────────────────────────────────────
  local ctrl = vb:row { spacing = 8 }
  ctrl:add_child(vb:button {
    id    = "expr_color_v" .. v_idx,
    text  = " ", width = 12, height = 14,
    color = LANE_CONFIGS[1].color,
  })
  ctrl:add_child(vb:text { text = "Lane:", width = 36 })
  ctrl:add_child(vb:popup {
    id    = "expr_lane_v" .. v_idx,
    items = {"Velocity", "Gate %", "Ratchet", "Delay"},
    value = 1,
    width = 110,
    notifier = function(idx)
      for li, lc in ipairs(LANE_CONFIGS) do
        local r = vb.views["expr_" .. lc.key .. "_row_v" .. v_idx]
        if r then r.visible = (li == idx) end
      end
      local cs = vb.views["expr_color_v" .. v_idx]
      if cs then cs.color = LANE_CONFIGS[idx].color end
      local tl = vb.views["expr_title_v" .. v_idx]
      if idx == 3 then
        if tl then tl.text = "── RATCHET (1=off, 2-4=retrigger) ──" end
      elseif idx == 4 then
        if tl then tl.text = "── DELAY (0=none, 255=full step late) ──" end
      else
        if tl then tl.text = "── " .. LANE_CONFIGS[idx].label .. " ──" end
      end
    end,
  })
  ctrl:add_child(vb:button {
    text = "Rand", width = 50,
    notifier = function()
      local lp  = vb.views["expr_lane_v" .. v_idx]
      local idx = lp and lp.value or 1
      local lc  = LANE_CONFIGS[idx]
      local map = lc.map_fn()
      if idx == 4 then
        for i = 1, voice.steps do map[i] = math.random(0, 127) end
      elseif idx == 3 then
        for i = 1, voice.steps do map[i] = math.random(1, 4) end
      else
        for i = 1, voice.steps do
          map[i] = math.random(math.floor(lc.max_val * 0.35), lc.max_val)
        end
      end
      refresh_expr_lane(v_idx)
    end,
  })
  ctrl:add_child(vb:button {
    text = "Reset", width = 50,
    notifier = function()
      local lp  = vb.views["expr_lane_v" .. v_idx]
      local idx = lp and lp.value or 1
      local lc  = LANE_CONFIGS[idx]
      local map = lc.map_fn()
      local reset_val
      if idx == 4 then reset_val = 0
      elseif idx == 3 then reset_val = 1
      else reset_val = lc.max_val end
      for i = 1, voice.steps do map[i] = reset_val end
      refresh_expr_lane(v_idx)
    end,
  })
  ctrl:add_child(vb:text {
    id   = "expr_title_v" .. v_idx,
    text = "── VELOCITY ──",
    font = "bold", width = 120,
  })

  -- ── Octave range (always visible above pitch rows) ────────────────────────
  local pitch_ctrl = vb:row {
    id      = "pitch_ctrl_v" .. v_idx,
    spacing = 8,
  }
  pitch_ctrl:add_child(vb:text { text = "Octave range:", width = LABEL_W })
  pitch_ctrl:add_child(vb:valuebox {
    id = "pitch_oct_min_v" .. v_idx,
    min = 0, max = 8, value = voice.octave_min or 3, width = 46,
    notifier = function(val) voice.octave_min = val end,
  })
  pitch_ctrl:add_child(vb:text { text = "to", width = 16 })
  pitch_ctrl:add_child(vb:valuebox {
    id = "pitch_oct_max_v" .. v_idx,
    min = 0, max = 8, value = voice.octave_max or 5, width = 46,
    notifier = function(val) voice.octave_max = val end,
  })
  pitch_ctrl:add_child(vb:text { text = "(used by Rand)", width = 100 })

  -- ── Assemble panel ────────────────────────────────────────────────────────
  local panel = vb:column {
    id      = "expr_panel_v" .. v_idx,
    visible = false,
    spacing = 6,
    margin  = 4,
  }
  panel:add_child(ctrl)
  for _, row in ipairs(lane_rows) do
    panel:add_child(row)
  end
  panel:add_child(vb:space { height = 4 })
  panel:add_child(pitch_ctrl)
  for _, row in ipairs(pitch_rows) do
    panel:add_child(row)
  end
  return panel
end

local function update_voice(v_idx)
  generate_pattern(v_idx)
  refresh_grid(v_idx)
end

local function refresh_algo_rows(v_idx, algo_id)
  if not vb then return end
  local rows = {
    ["row_pulses_v"   .. v_idx] = USES_PULSES[algo_id] or false,
    ["row_cellular_v" .. v_idx] = (algo_id == VoiceState.ALGO_CELLULAR),
    ["row_markov_v"   .. v_idx] = (algo_id == VoiceState.ALGO_MARKOV),
    ["row_logistic_v" .. v_idx] = (algo_id == VoiceState.ALGO_LOGISTIC),
    ["row_perlin_v"   .. v_idx] = (algo_id == VoiceState.ALGO_PERLIN),
    ["row_random_v"   .. v_idx] = (algo_id == VoiceState.ALGO_RANDOM),
    ["row_straight_v" .. v_idx] = (algo_id == VoiceState.ALGO_STRAIGHT),
  }
  for id, visible in pairs(rows) do
    local view = vb.views[id]
    if view then view.visible = visible end
  end
  local wc = vb.views["weight_col_v" .. v_idx]
  if wc then wc.visible = (algo_id == VoiceState.ALGO_BRESENHAM) end
  -- update collapsed-header algo label
  local al = vb.views["voice_algo_lbl_v" .. v_idx]
  if al then al.text = algo_label(algo_id) end
end

local function instrument_names()
  local song = renoise.song()
  if not song or #song.instruments == 0 then return {"(no instruments)"} end
  local names = {}
  for i, inst in ipairs(song.instruments) do
    names[i] = string.format("%02d %s", i, inst.name ~= "" and inst.name or "---")
  end
  return names
end

local function inst_short_name(idx)
  local song = renoise.song()
  if not song or idx < 1 or idx > #song.instruments then return "---" end
  local n = song.instruments[idx].name
  if n == "" then n = "Instr " .. idx end
  if #n > 20 then n = string.sub(n, 1, 20) end
  return n
end

-- ── step grid ─────────────────────────────────────────────────────────────────

local function build_step_grid(v_idx)
  local row = vb:row { spacing = 2 }
  for s = 1, GRID_STEPS do
    row:add_child(vb:button {
      id    = "step_v" .. v_idx .. "_s" .. s,
      text  = "",
      color = COL_INACTIVE,
      width = 14, height = 14,
    })
  end
  return row
end

-- ── voice lane ────────────────────────────────────────────────────────────────

local function build_voice_lane(v_idx)
  local voice = state.voices[v_idx]
  if voice._expanded == nil then voice._expanded = true end

  local song       = renoise.song()
  local inst_count = song and #song.instruments or 1
  local inst_idx   = math.min(voice.instrument_index, math.max(1, inst_count))
  local v_color    = VOICE_COLORS[((v_idx - 1) % #VOICE_COLORS) + 1]

  -- ── params panel (expandable) ────────────────────────────────────────────

  local params_panel = vb:column {
    id      = "params_v" .. v_idx,
    visible = voice._expanded,
    margin  = 4,
    spacing = 6,
    width   = PANEL_W,

    -- Row A: Algorithm | Steps | Instrument | Note
    vb:row {
      spacing = 10,

      vb:column { spacing = 2,
        vb:text { text = "Algorithm" },
        vb:popup {
          id    = "algo_v" .. v_idx,
          items = ALGO_LABELS,
          value = algo_index_for(voice),
          width = 110,
          notifier = function(idx)
            voice.algorithm = ALGORITHMS[idx].id
            refresh_algo_rows(v_idx, voice.algorithm)
            update_voice(v_idx)
          end,
        },
      },

      vb:column { spacing = 2,
        vb:text { text = "Steps" },
        vb:valuebox {
          id = "steps_v" .. v_idx, min = 1, max = 16, value = voice.steps,
          notifier = function(val)
            voice.steps  = val
            voice.pulses = math.min(voice.pulses, val)
            local pb = vb.views["pulses_v" .. v_idx]
            if pb then pb.max = val; pb.value = voice.pulses end
            voice:resize_maps(val)
            refresh_expr_lane(v_idx)
            update_voice(v_idx)
          end,
        },
      },

      vb:column { spacing = 2,
        vb:text { text = "Instrument" },
        vb:popup {
          id    = "inst_v" .. v_idx,
          items = instrument_names(),
          value = inst_idx,
          width = 200,
          notifier = function(idx)
            voice.instrument_index = idx
            -- update collapsed header
            local nl = vb.views["voice_inst_lbl_v" .. v_idx]
            if nl then nl.text = inst_short_name(idx) end
          end,
        },
      },

      vb:column { spacing = 2,
        vb:text { text = "Note" },
        vb:row { spacing = 4,
          vb:valuebox {
            id = "note_v" .. v_idx, min = 0, max = 83, value = math.min(voice.note_value, 83),
            notifier = function(val)
              local old = voice.note_value
              voice.note_value = val
              -- Shift pitch map steps that matched the old base note to the new one
              for i = 1, voice.steps do
                if voice.pitch_a_map[i] == old then voice.pitch_a_map[i] = val end
                if voice.pitch_b_map[i] == old then voice.pitch_b_map[i] = val end
              end
              refresh_expr_lane(v_idx)
              local lbl = vb.views["note_lbl_v" .. v_idx]
              if lbl then lbl.text = Scales.note_name(val) end
            end,
          },
          vb:text {
            id    = "note_lbl_v" .. v_idx,
            text  = Scales.note_name(math.min(voice.note_value, 83)),
            width = 36,
          },
        },
      },
    },

    -- Row B: Prob + Pulses + Offset + Weight (always visible; pulses/offset/weight hide for non-pulse algos)
    vb:row {
      id      = "row_pulses_v" .. v_idx,
      spacing = 10,
      visible = USES_PULSES[voice.algorithm] or false,

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id    = "prob_v" .. v_idx,
            min   = 1, max = 100, value = voice.probability,
            width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Pulses" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "pulses_v" .. v_idx, min = 0, max = voice.steps, value = voice.pulses,
            width = 80,
            notifier = function(val)
              voice.pulses = math.floor(val)
              local lbl = vb.views["pulses_lbl_v" .. v_idx]
              if lbl then lbl.text = tostring(math.floor(val)) end
              update_voice(v_idx)
            end,
          },
          vb:text { id = "pulses_lbl_v" .. v_idx, text = tostring(voice.pulses), width = 20 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Offset" },
        vb:valuebox {
          id = "offset_v" .. v_idx, min = 0, max = 31, value = voice.offset,
          notifier = function(val) voice.offset = val; update_voice(v_idx) end,
        },
      },
      vb:column {
        id      = "weight_col_v" .. v_idx,
        spacing = 2,
        visible = (voice.algorithm == VoiceState.ALGO_BRESENHAM),
        vb:text { text = "Weight" },
        vb:valuebox {
          id = "bres_weight_v" .. v_idx, min = 1, max = 20, value = 10,
          notifier = function(val)
            voice._bres_weight = val / 10.0
            update_voice(v_idx)
          end,
        },
      },
    },

    -- Row B2: Prob standalone row (shown when pulses row is hidden)
    -- REMOVED: Prob is now embedded as first column in every algo-specific row.

    -- Row D: Cellular
    vb:row {
      id      = "row_cellular_v" .. v_idx,
      spacing = 10,
      visible = (voice.algorithm == VoiceState.ALGO_CELLULAR),

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "prob_ca_v" .. v_idx,
            min = 1, max = 100, value = voice.probability, width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_ca_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_ca_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Rule" },
        vb:popup {
          id    = "ca_rule_v" .. v_idx,
          items = {"30 - chaotic", "90 - fractal", "110 - complex"},
          value = 1,
          notifier = function(idx)
            local rules = {30, 90, 110}
            voice._ca_rule = rules[idx]
            update_voice(v_idx)
          end,
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Generation" },
        vb:valuebox {
          id = "ca_gen_v" .. v_idx, min = 0, max = 64, value = 0,
          notifier = function(val) voice._ca_generation = val; update_voice(v_idx) end,
        },
      },
    },

    -- Row E: Markov
    vb:row {
      id      = "row_markov_v" .. v_idx,
      spacing = 10,
      visible = (voice.algorithm == VoiceState.ALGO_MARKOV),

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "prob_mk_v" .. v_idx,
            min = 1, max = 100, value = voice.probability, width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_mk_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_mk_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Density %" },
        vb:row { spacing = 6,
          vb:minislider {
            id    = "markov_density_v" .. v_idx,
            min   = 1, max = 100, value = voice.density,
            width = 100,
            notifier = function(val)
              voice.density = math.floor(val)
              local lbl = vb.views["markov_density_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
              update_voice(v_idx)
            end,
          },
          vb:text { id = "markov_density_lbl_v" .. v_idx, text = voice.density .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Momentum" },
        vb:valuebox {
          id = "markov_stay_v" .. v_idx, min = 1, max = 10, value = 7,
          notifier = function(val) voice._markov_stay = val / 10.0; update_voice(v_idx) end,
        },
      },
    },

    -- Row F: Logistic
    vb:row {
      id      = "row_logistic_v" .. v_idx,
      spacing = 10,
      visible = (voice.algorithm == VoiceState.ALGO_LOGISTIC),

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "prob_lg_v" .. v_idx,
            min = 1, max = 100, value = voice.probability, width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_lg_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_lg_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Chaos r" },
        vb:valuebox {
          id = "logistic_r_v" .. v_idx, min = 20, max = 40, value = 37,
          notifier = function(val) voice._logistic_r = val / 10.0; update_voice(v_idx) end,
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Threshold %" },
        vb:row { spacing = 6,
          vb:minislider {
            id    = "logistic_thresh_v" .. v_idx,
            min   = 1, max = 99, value = 50,
            width = 100,
            notifier = function(val)
              voice._threshold = val / 100.0
              local lbl = vb.views["logistic_thresh_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
              update_voice(v_idx)
            end,
          },
          vb:text { id = "logistic_thresh_lbl_v" .. v_idx, text = "50%", width = 34 },
        },
      },
    },

    -- Row G: Perlin
    vb:row {
      id      = "row_perlin_v" .. v_idx,
      spacing = 10,
      visible = (voice.algorithm == VoiceState.ALGO_PERLIN),

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "prob_pn_v" .. v_idx,
            min = 1, max = 100, value = voice.probability, width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_pn_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_pn_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Frequency" },
        vb:valuebox {
          id = "perlin_freq_v" .. v_idx, min = 1, max = 40, value = 10,
          notifier = function(val) voice._perlin_freq = val / 10.0; update_voice(v_idx) end,
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Threshold %" },
        vb:row { spacing = 6,
          vb:minislider {
            id    = "perlin_thresh_v" .. v_idx,
            min   = 1, max = 99, value = 45,
            width = 100,
            notifier = function(val)
              voice._threshold = val / 100.0
              local lbl = vb.views["perlin_thresh_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
              update_voice(v_idx)
            end,
          },
          vb:text { id = "perlin_thresh_lbl_v" .. v_idx, text = "45%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Time ofs" },
        vb:valuebox {
          id = "perlin_offset_v" .. v_idx, min = 0, max = 99, value = 0,
          notifier = function(val) voice._perlin_offset = val / 100.0; update_voice(v_idx) end,
        },
      },
    },

    -- Row H: Random
    vb:row {
      id      = "row_random_v" .. v_idx,
      spacing = 10,
      visible = (voice.algorithm == VoiceState.ALGO_RANDOM),

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "prob_rn_v" .. v_idx,
            min = 1, max = 100, value = voice.probability, width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_rn_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_rn_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Density %" },
        vb:row { spacing = 6,
          vb:minislider {
            id    = "random_density_v" .. v_idx,
            min   = 1, max = 100, value = voice.density,
            width = 100,
            notifier = function(val)
              voice.density = math.floor(val)
              local lbl = vb.views["random_density_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
              update_voice(v_idx)
            end,
          },
          vb:text { id = "random_density_lbl_v" .. v_idx, text = voice.density .. "%", width = 34 },
        },
      },
    },

    -- Row I: Straight
    vb:row {
      id      = "row_straight_v" .. v_idx,
      spacing = 10,
      visible = (voice.algorithm == VoiceState.ALGO_STRAIGHT),

      vb:column { spacing = 2,
        vb:text { text = "Prob %" },
        vb:row { spacing = 4,
          vb:minislider {
            id = "prob_st_v" .. v_idx,
            min = 1, max = 100, value = voice.probability, width = 100,
            notifier = function(val)
              voice.probability = math.floor(val)
              local lbl = vb.views["prob_st_lbl_v" .. v_idx]
              if lbl then lbl.text = math.floor(val) .. "%" end
            end,
          },
          vb:text { id = "prob_st_lbl_v" .. v_idx, text = voice.probability .. "%", width = 34 },
        },
      },
      vb:column { spacing = 2,
        vb:text { text = "Division" },
        vb:popup {
          id    = "straight_div_v" .. v_idx,
          items = {"1/4", "1/8", "1/16", "Triplet"},
          value = 1,
          width = 80,
          notifier = function(idx)
            local intervals = {4, 2, 1, 3}
            voice._straight_interval = intervals[idx]
            update_voice(v_idx)
          end,
        },
      },
    },

    -- ── Expression sub-panel (Phase 6a) ──────────────────────────────────────
    vb:row {
      spacing = 8,
      vb:button {
        id    = "expr_btn_v" .. v_idx,
        text  = "Expression ▼",
        width = 90, height = 18,
        notifier = function()
          voice._expr_expanded = not voice._expr_expanded
          local ep = vb.views["expr_panel_v" .. v_idx]
          if ep then ep.visible = voice._expr_expanded end
          local eb = vb.views["expr_btn_v" .. v_idx]
          if eb then eb.text = voice._expr_expanded and "Expression ▲" or "Expression ▼" end
        end,
      },
    },

    build_expr_panel(v_idx),
  }

  -- ── header (always visible) ───────────────────────────────────────────────

  local function reset_audition_btn()
    local ab = vb and vb.views["audition_btn_v" .. v_idx]
    if ab then ab.color = {200, 100, 0}; ab.text = "▶" end
  end

  local header = vb:row {
    spacing = 6,
    width   = PANEL_W - 8,  -- account for parent margin=4 on each side

    vb:button {
      id    = "expand_btn_v" .. v_idx,
      text  = voice._expanded and "▼" or "▶",
      width = 20, height = 22,
      notifier = function()
        voice._expanded = not voice._expanded
        -- Accordion: collapse all other voices when expanding this one
        if voice._expanded then
          for other_vi, other_voice in ipairs(state.voices) do
            if other_vi ~= v_idx and other_voice._expanded then
              other_voice._expanded = false
              local opv = vb.views["params_v" .. other_vi]
              if opv then opv.visible = false end
              local oeb = vb.views["expand_btn_v" .. other_vi]
              if oeb then oeb.text = "▶" end
            end
          end
        end
        local pv = vb.views["params_v"      .. v_idx]
        if pv then pv.visible = voice._expanded end
        local eb = vb.views["expand_btn_v"  .. v_idx]
        if eb then eb.text = voice._expanded and "▼" or "▶" end
      end,
    },

    vb:button {
      id    = "audition_btn_v" .. v_idx,
      text  = "▶",
      color = {200, 100, 0},
      width = 26, height = 22,
      notifier = function()
        local ab = vb.views["audition_btn_v" .. v_idx]
        if Audition.is_active() then
          Audition.stop()   -- stop_impl calls on_stop which resets button
        else
          if ab then ab.color = {50, 180, 80}; ab.text = "■" end
          -- Reset the All button too if it was active
          local all_btn = vb.views["audition_all_btn"]
          if all_btn then all_btn.color = {0,0,0}; all_btn.text = "▶ All" end
          state.voices[v_idx]._scale_index = state.scale_index
          state.voices[v_idx]._root_note   = state.root_note
          local pat = generate_baked_pattern(v_idx)
          Audition.start({{voice = state.voices[v_idx], pattern = pat}}, state.phrase_length, function()
            reset_audition_btn()
          end)
        end
      end,
    },

    vb:button {
      text  = "",
      color = v_color,
      width = 10, height = 10,
    },

    vb:text {
      id    = "voice_inst_lbl_v" .. v_idx,
      text  = inst_short_name(inst_idx),
      font  = "bold",
      width = 140,
    },

    build_step_grid(v_idx),

    vb:text {
      id    = "voice_algo_lbl_v" .. v_idx,
      text  = algo_label(voice.algorithm),
      width = 72,
    },

    vb:button {
      text  = "x",
      width = 20, height = 22,
      notifier = function()
        if #state.voices > 1 then
          state:remove_voice(v_idx)
          rebuild()
        end
      end,
    },
  }

  return vb:column {
    style   = "group",
    margin  = 4,
    spacing = 2,
    width   = PANEL_W,
    vb:space { width = PANEL_W - 8 },   -- force group border to always fill full width
    header,
    params_panel,
  }
end

-- ── helpers: build pattern table for all voices ──────────────────────────────

local function collect_patterns()
  local patterns = {}
  for vi = 1, #state.voices do
    state.voices[vi]._scale_index = state.scale_index
    state.voices[vi]._root_note   = state.root_note
    patterns[vi] = generate_baked_pattern(vi)
    refresh_grid(vi)
  end
  return patterns
end

-- Render always overwrites phrase slot 1.
local function get_render_slot()
  return 1
end

-- ── global bar ────────────────────────────────────────────────────────────────

local function build_global_bar()
  local root_row = vb:row { spacing = 2 }
  for i, name in ipairs(ROOT_NAMES) do
    local w = (string.len(name) > 1) and 26 or 20
    root_row:add_child(vb:button {
      id       = "root_btn_" .. i,
      text     = name,
      color    = ((i - 1) == state.root_note) and COL_ACTIVE or COL_INACTIVE,
      width    = w, height = 20,
      notifier = function()
        state.root_note = i - 1
        for j = 1, 12 do
          local b = vb.views["root_btn_" .. j]
          if b then b.color = ((j - 1) == state.root_note) and COL_ACTIVE or COL_INACTIVE end
        end
      end,
    })
  end

  return vb:column {
    style   = "group",
    margin  = 6,
    spacing = 6,
    width   = PANEL_W,

    vb:row {
      spacing = 10,
      vb:text { text = "Scale:", width = 42 },
      vb:popup {
        id = "scale_global", items = Scales.NAMES, value = state.scale_index, width = 110,
        notifier = function(idx) state.scale_index = idx end,
      },
      vb:text { text = "Root Note:", width = 68 },
      root_row,
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Seed:", width = 42 },
      vb:minislider {
        id    = "seed_global",
        min   = 0, max = 100, value = math.min(state.seed, 100),
        width = 140,
        notifier = function(val)
          state.seed = math.floor(val)
          local lbl = vb.views["seed_lbl_global"]
          if lbl then lbl.text = tostring(math.floor(val)) end
          for vi = 1, #state.voices do update_voice(vi) end
        end,
      },
      vb:text { id = "seed_lbl_global", text = tostring(math.min(state.seed, 100)), width = 28 },
      vb:text { text = "Evolve:", width = 48 },
      vb:popup {
        id    = "evolve_global",
        items = {"Off", "Slow", "Fast"},
        value = 1,
        width = 80,
        notifier = function(idx)
          local modes = {SongState.EVOLVE_OFF, SongState.EVOLVE_SLOW, SongState.EVOLVE_FAST}
          state.evolve_mode = modes[idx]
        end,
      },
      vb:text { text = "Phrase Length:", width = 92 },
      vb:popup {
        id      = "phrase_len_global",
        items   = PHRASE_LENGTH_LABELS,
        value   = 1,
        width   = 74,
        notifier = function(idx)
          state.phrase_length = PHRASE_LENGTH_VALUES[idx]
        end,
      },
    },
  }
end

-- ── action bar ────────────────────────────────────────────────────────────────

local function build_action_bar()
  return vb:row {
    margin = 4, spacing = 6,

    vb:button {
      text = "+ Voice", width = 70,
      notifier = function()
        local v = state:add_voice()
        if v then
          local song = renoise.song()
          if song then
            v.instrument_index        = song.selected_instrument_index
            v._instrument_initialized = true
          end
          v._expanded = false
          rebuild()
        end
      end,
    },

    vb:button {
      id    = "audition_all_btn",
      text  = "▶ All",
      width = 54,
      notifier = function()
        local ab = vb.views["audition_all_btn"]
        if Audition.is_active() then
          Audition.stop()
        else
          if ab then ab.color = {50, 180, 80}; ab.text = "■ All" end
          -- Reset per-voice audition buttons
          for vi = 1, #state.voices do
            local vb2 = vb.views["audition_btn_v" .. vi]
            if vb2 then vb2.color = {200, 100, 0}; vb2.text = "▶" end
          end
          local patterns = collect_patterns()
          local entries  = {}
          for vi, v in ipairs(state.voices) do
            entries[#entries + 1] = { voice = v, pattern = patterns[vi] or {} }
          end
          Audition.start(entries, state.phrase_length, function()
            local b = vb and vb.views["audition_all_btn"]
            if b then b.color = {0,0,0}; b.text = "▶ All" end
          end)
        end
      end,
    },

    vb:button {
      text = "Randomize", width = 80,
      notifier = function()
        state.seed = math.random(0, 100)
        local sg = vb.views["seed_global"]
        if sg then sg.value = state.seed end
        for vi, voice in ipairs(state.voices) do
          Evolve.randomize(voice, state.seed + vi)
        end
        local slot = get_render_slot()
        if PhraseWriter.write_all(state.voices, collect_patterns(), slot) then
          renoise.app():show_status("AlgoRhythm: Randomized → phrase " .. slot)
        end
      end,
    },

    vb:button {
      text = "Mutate", width = 65,
      notifier = function()
        for _, voice in ipairs(state.voices) do
          Evolve.mutate(voice)
        end
        local slot = get_render_slot()
        if PhraseWriter.write_all(state.voices, collect_patterns(), slot) then
          renoise.app():show_status("AlgoRhythm: Mutated → phrase " .. slot)
        end
      end,
    },

    vb:button {
      text = "Render to Phrase", width = 120,
      notifier = function()
        local slot = get_render_slot()
        if PhraseWriter.write_all(state.voices, collect_patterns(), slot) then
          renoise.app():show_status("AlgoRhythm: Written → phrase " .. slot)
        end
      end,
    },

    -- Separator: visually groups the Append controls together
    vb:text { text = "|", width = 10 },

    -- Count of phrases to append (1–16); arrows always active
    vb:valuebox {
      id    = "append_count_box",
      min   = 1, max = 16, value = state.append_count,
      width = 52,
      notifier = function(val) state.append_count = val end,
    },

    vb:button {
      text  = "Append Phrase",
      width = 110,
      notifier = function()
        local song = renoise.song()
        if not song or #state.voices == 0 then return end
        -- Save voice params so mutations don't persist after appending
        local saved = {}
        for vi, voice in ipairs(state.voices) do saved[vi] = save_voice_params(voice) end
        local count    = state.append_count
        local ok_count = 0
        for i = 1, count do
          if i > 1 then
            for _, voice in ipairs(state.voices) do Evolve.mutate(voice) end
          end
          local patterns = collect_patterns()
          local inst     = song.instruments[state.voices[1].instrument_index]
          local slot     = (inst and #inst.phrases or 0) + 1
          if PhraseWriter.write_all(state.voices, patterns, slot, true) then
            ok_count = ok_count + 1
          else
            break
          end
        end
        -- Restore voice params
        for vi, voice in ipairs(state.voices) do restore_voice_params(voice, saved[vi]) end
        for vi = 1, #state.voices do refresh_grid(vi) end
        if ok_count > 0 then
          renoise.app():show_status(string.format(
            "AlgoRhythm: Appended %d phrase(s)", ok_count))
        end
      end,
    },
  }
end

-- ── rebuild ───────────────────────────────────────────────────────────────────

rebuild = function()
  Audition.stop()
  if dialog and dialog.visible then dialog:close() end
  dialog = nil
  vb    = nil
  MainPanel.show()
end

-- ── show ─────────────────────────────────────────────────────────────────────

function MainPanel.show()
  if dialog and dialog.visible then
    dialog:show()
    return
  end

  local song = renoise.song()
  if song then
    local sel = song.selected_instrument_index
    for _, voice in ipairs(state.voices) do
      if not voice._instrument_initialized then
        voice.instrument_index        = sel
        voice._instrument_initialized = true
      end
    end
  end

  vb = renoise.ViewBuilder()

  for vi = 1, #state.voices do generate_pattern(vi) end

  local lanes = vb:column { spacing = 3, width = PANEL_W }
  for vi = 1, #state.voices do
    lanes:add_child(build_voice_lane(vi))
  end

  local content = vb:column {
    margin  = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
    spacing = 6,
    width   = PANEL_W,
    vb:row { vb:text { text = "AlgoRhythm", font = "bold", style = "strong" } },
    build_preset_bar(),
    build_global_bar(),
    lanes,
    build_action_bar(),
  }

  dialog = renoise.app():show_custom_dialog("AlgoRhythm", content)

  for vi = 1, #state.voices do refresh_grid(vi) end
end

-- ── Evolve callback (called by main.lua timer on each bar boundary) ──────────

function MainPanel.on_bar_tick(bar_count)
  if state.evolve_mode == SongState.EVOLVE_OFF then return end
  local any = false
  for vi, voice in ipairs(state.voices) do
    if Evolve.tick(voice, bar_count, state.evolve_mode) then
      update_voice(vi)
      any = true
    end
  end
  if any then
    local patterns = {}
    for vi, voice in ipairs(state.voices) do
      patterns[vi] = voice._cached_pattern or {}
    end
    PhraseWriter.write_all(state.voices, patterns, get_render_slot())
  end
end

return MainPanel
