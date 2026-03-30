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
local Evolve       = require("src/state/evolve")

local MainPanel = {}

local state  = SongState.new()
local dialog = nil
local vb     = nil

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

local COL_ACTIVE   = {76, 182, 139}
local COL_INACTIVE = {40,  40,  40}
local GRID_STEPS   = 16

local VOICE_COLORS = {
  {210,  70,  55},
  {220, 145,  45},
  { 70, 150, 215},
  {150,  90, 215},
  { 70, 210, 115},
  {215, 195,  45},
  {215, 115, 175},
  {110, 195, 195},
}

local ROOT_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

local PHRASE_LENGTH_VALUES = {0, 32, 64, 128, 256, 512}
local PHRASE_LENGTH_LABELS = {"Auto", "32", "64", "128", "256", "512"}

-- Total dialog inner width (content column width)
local PANEL_W = 660

local rebuild  -- forward declaration

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
  local pattern = state.voices[v_idx]._cached_pattern or {}
  for s = 1, GRID_STEPS do
    local btn = vb.views["step_v" .. v_idx .. "_s" .. s]
    if btn then
      btn.color = (pattern[s] == true) and COL_ACTIVE or COL_INACTIVE
    end
  end
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
  return n ~= "" and n or ("Instr " .. idx)
end

-- ── step grid ─────────────────────────────────────────────────────────────────

local function build_step_grid(v_idx)
  local row = vb:row { spacing = 1 }
  for s = 1, GRID_STEPS do
    row:add_child(vb:button {
      id    = "step_v" .. v_idx .. "_s" .. s,
      text  = "",
      color = COL_INACTIVE,
      width = 10, height = 10,
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
          id = "steps_v" .. v_idx, min = 1, max = 32, value = voice.steps,
          notifier = function(val)
            voice.steps  = val
            voice.pulses = math.min(voice.pulses, val)
            local pb = vb.views["pulses_v" .. v_idx]
            if pb then pb.max = val; pb.value = voice.pulses end
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
              voice.note_value = val
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
  }

  -- ── header (always visible) ───────────────────────────────────────────────

  local header = vb:row {
    spacing = 6,

    vb:button {
      id    = "expand_btn_v" .. v_idx,
      text  = voice._expanded and "v" or ">",
      width = 20, height = 22,
      notifier = function()
        voice._expanded = not voice._expanded
        local pv = vb.views["params_v"      .. v_idx]
        if pv then pv.visible = voice._expanded end
        local eb = vb.views["expand_btn_v"  .. v_idx]
        if eb then eb.text = voice._expanded and "v" or ">" end
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
    header,
    params_panel,
  }
end

-- ── helpers: build pattern table for all voices ──────────────────────────────

local function collect_patterns()
  local patterns = {}
  for vi = 1, #state.voices do
    patterns[vi] = generate_baked_pattern(vi)
    refresh_grid(vi)
  end
  return patterns
end

-- Returns phrase count for the instrument of voice 1 (used for slot max).
local function current_phrase_count()
  local song = renoise.song()
  if not song or #state.voices == 0 then return 1 end
  local inst = song.instruments[state.voices[1].instrument_index]
  return (inst and #inst.phrases > 0) and #inst.phrases or 1
end

-- Sync phrase_slot_box max to actual phrase count (min 1).
local function update_slot_max()
  local sv = vb and vb.views["phrase_slot_box"]
  if not sv then return end
  local cnt = current_phrase_count()
  sv.max   = math.max(sv.min, cnt)
  sv.value = math.min(sv.value, sv.max)
  state.phrase_slot = sv.value
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
      text = "+ Voice", width = 75,
      notifier = function()
        local v = state:add_voice()
        if v then
          local song = renoise.song()
          if song then
            v.instrument_index        = song.selected_instrument_index
            v._instrument_initialized = true
          end
          v._expanded = true
          rebuild()
        end
      end,
    },

    vb:text { text = "", width = 8 },

    vb:button {
      text = "Randomize", width = 90,
      notifier = function()
        state.seed = math.random(0, 100)
        local sg = vb.views["seed_global"]
        if sg then sg.value = state.seed end
        for vi, voice in ipairs(state.voices) do
          Evolve.full_randomize(voice, state.seed + vi)
        end
        if PhraseWriter.write_all(state.voices, collect_patterns(), state.phrase_slot) then
          renoise.app():show_status("AlgoRhythm: Randomized → phrase " .. state.phrase_slot)
          update_slot_max()
        end
      end,
    },

    vb:button {
      text = "Mutate", width = 75,
      notifier = function()
        for _, voice in ipairs(state.voices) do
          Evolve.mutate(voice)
        end
        if PhraseWriter.write_all(state.voices, collect_patterns(), state.phrase_slot) then
          renoise.app():show_status("AlgoRhythm: Mutated → phrase " .. state.phrase_slot)
          update_slot_max()
        end
      end,
    },

    vb:button {
      text = "Render to Phrase", width = 130,
      notifier = function()
        if PhraseWriter.write_all(state.voices, collect_patterns(), state.phrase_slot) then
          renoise.app():show_status("AlgoRhythm: Written → phrase " .. state.phrase_slot)
          update_slot_max()
        end
      end,
    },

    vb:valuebox {
      id      = "phrase_slot_box",
      min     = 1,
      max     = math.max(1, current_phrase_count()),
      value   = state.phrase_slot,
      notifier = function(val)
        state.phrase_slot = val
      end,
    },

    vb:button {
      text  = "Append Phrase",
      width = 110,
      notifier = function()
        -- Insert a new phrase right after the current slot and advance to it
        local new_slot = state.phrase_slot + 1
        if PhraseWriter.write_all(state.voices, collect_patterns(), new_slot, true) then
          state.phrase_slot = new_slot
          local sv = vb.views["phrase_slot_box"]
          if sv then
            sv.max   = new_slot
            sv.value = new_slot
          end
          renoise.app():show_status("AlgoRhythm: Appended → phrase " .. new_slot)
        end
      end,
    },
  }
end

-- ── rebuild ───────────────────────────────────────────────────────────────────

rebuild = function()
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
    PhraseWriter.write_all(state.voices, patterns, state.phrase_slot)
  end
end

return MainPanel
