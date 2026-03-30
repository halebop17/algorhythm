-- AlgoRhythm — Main UI panel
-- Phase 1: single-voice layout with euclidean algorithm and Render to Phrase

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
local PhraseWriter = require("src/output/phrase_writer")

local MainPanel = {}

-- ─── Persistent state ────────────────────────────────────────────────────────
local state  = SongState.new()
local dialog = nil
local vb     = nil

-- ─── Algorithm registry ──────────────────────────────────────────────────────
local ALGORITHMS = {
  { id = VoiceState.ALGO_EUCLIDEAN, label = "Euclidean",  mod = Euclidean  },
  { id = VoiceState.ALGO_BRESENHAM, label = "Bresenham",  mod = Bresenham  },
  { id = VoiceState.ALGO_CELLULAR,  label = "Cellular",   mod = Cellular   },
  { id = VoiceState.ALGO_MARKOV,    label = "Markov",     mod = Markov     },
  { id = VoiceState.ALGO_LOGISTIC,  label = "Logistic",   mod = Logistic   },
  { id = VoiceState.ALGO_PERLIN,    label = "Perlin",     mod = Perlin     },
  { id = VoiceState.ALGO_RANDOM,    label = "Random",     mod = RandomW    },
}

local ALGO_LABELS = {}
for _, a in ipairs(ALGORITHMS) do ALGO_LABELS[#ALGO_LABELS + 1] = a.label end

-- ─── Step grid colours ───────────────────────────────────────────────────────
local COL_ACTIVE   = {76, 182, 139}   -- teal green
local COL_INACTIVE = {40,  40,  40}   -- dark grey
local GRID_STEPS   = 16               -- Phase 1: fixed 16-slot display

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function algo_index_for(voice)
  for i, a in ipairs(ALGORITHMS) do
    if a.id == voice.algorithm then return i end
  end
  return 1
end

-- Build params table for any algorithm from voice state
local function algo_params(voice)
  return {
    steps           = voice.steps,
    pulses          = voice.pulses,
    offset          = voice.offset,
    density         = voice.density / 100.0,
    hit_probability = voice.density / 100.0,
    stay_weight     = 0.7,
    rule            = voice._ca_rule       or 30,
    generation      = voice._ca_generation or 0,
    r               = voice._logistic_r    or 3.7,
    threshold       = 0.5,
    time_offset     = voice._perlin_offset or 0.0,
    frequency       = 1.0,
    seed            = state.seed,
  }
end

-- Generate pattern for voice v_idx and cache it
local function generate_pattern(v_idx)
  local voice = state.voices[v_idx]
  local algo  = ALGORITHMS[algo_index_for(voice)]
  voice._cached_pattern = algo.mod.generate(algo_params(voice))
  return voice._cached_pattern
end

-- Refresh step-grid button colours for voice v_idx
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

-- Safe list of instrument names from the current song
local function instrument_names()
  local song = renoise.song()
  if not song or #song.instruments == 0 then
    return {"(no instruments)"}
  end
  local names = {}
  for i, inst in ipairs(song.instruments) do
    names[i] = string.format("%02d %s", i, inst.name ~= "" and inst.name or "---")
  end
  return names
end

-- ─── UI builders ─────────────────────────────────────────────────────────────

-- 16-button step grid row for voice v_idx
local function build_step_grid(v_idx)
  local row = vb:row {spacing = 2}
  for s = 1, GRID_STEPS do
    row:add_child(vb:button {
      id     = "step_v" .. v_idx .. "_s" .. s,
      text   = "",
      color  = COL_INACTIVE,
      width  = 14,
      height = 14,
    })
  end
  return row
end

-- Single voice lane panel
local function build_voice_lane(v_idx)
  local voice = state.voices[v_idx]

  return vb:column {
    style  = "group",
    margin = 6,
    spacing = 5,

    -- Row 1: name + algorithm chooser
    vb:row {
      spacing = 8,
      vb:text  {text = voice.name, font = "bold", width = 64},
      vb:text  {text = "Algorithm:"},
      vb:chooser {
        id    = "algo_v" .. v_idx,
        items = ALGO_LABELS,
        value = algo_index_for(voice),
        notifier = function(idx)
          voice.algorithm = ALGORITHMS[idx].id
          update_voice(v_idx)
        end,
      },
    },

    -- Row 2: rhythm parameters
    vb:row {
      spacing = 12,
      vb:column {spacing = 2,
        vb:text {text = "Steps"},
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
      vb:column {spacing = 2,
        vb:text {text = "Pulses"},
        vb:valuebox {
          id = "pulses_v" .. v_idx, min = 0, max = voice.steps, value = voice.pulses,
          notifier = function(val)
            voice.pulses = val
            update_voice(v_idx)
          end,
        },
      },
      vb:column {spacing = 2,
        vb:text {text = "Offset"},
        vb:valuebox {
          id = "offset_v" .. v_idx, min = 0, max = 31, value = voice.offset,
          notifier = function(val)
            voice.offset = val
            update_voice(v_idx)
          end,
        },
      },
      vb:column {spacing = 2,
        vb:text {text = "Prob %"},
        vb:valuebox {
          id = "prob_v" .. v_idx, min = 1, max = 100, value = voice.probability,
          notifier = function(val)
            voice.probability = val
          end,
        },
      },
    },

    -- Row 3: output target — instrument + note
    vb:row {
      spacing = 8,
      vb:text {text = "Instrument:"},
      vb:popup {
        id    = "inst_v" .. v_idx,
        items = instrument_names(),
        value = math.min(voice.instrument_index, math.max(1, #renoise.song().instruments)),
        width = 180,
        notifier = function(idx)
          voice.instrument_index = idx
        end,
      },
      vb:text {text = "Note:"},
      vb:valuebox {
        id = "note_v" .. v_idx, min = 0, max = 119, value = voice.note_value,
        notifier = function(val)
          voice.note_value = val
          local lbl = vb.views["note_lbl_v" .. v_idx]
          if lbl then lbl.text = Scales.note_name(val) end
        end,
      },
      vb:text {
        id   = "note_lbl_v" .. v_idx,
        text = Scales.note_name(voice.note_value),
        width = 36,
      },
    },

    -- Row 4: step grid
    build_step_grid(v_idx),
  }
end

-- Global controls bar
local function build_global_bar()
  return vb:row {
    style   = "group",
    margin  = 6,
    spacing = 10,

    vb:text {text = "Scale:"},
    vb:popup {
      id = "scale_global", items = Scales.NAMES, value = state.scale_index, width = 100,
      notifier = function(idx) state.scale_index = idx end,
    },

    vb:text {text = "Root:"},
    vb:popup {
      id = "root_global", items = Scales.ROOT_NAMES, value = state.root_note + 1, width = 55,
      notifier = function(idx) state.root_note = idx - 1 end,
    },

    vb:text {text = "Seed:"},
    vb:valuebox {
      id = "seed_global", min = 0, max = 9999, value = state.seed,
      notifier = function(val)
        state.seed = val
        for vi = 1, #state.voices do update_voice(vi) end
      end,
    },

    vb:text {text = "Evolve:"},
    vb:chooser {
      id = "evolve_global", items = {"Off", "Slow", "Fast"}, value = 1,
      notifier = function(idx)
        local modes = {SongState.EVOLVE_OFF, SongState.EVOLVE_SLOW, SongState.EVOLVE_FAST}
        state.evolve_mode = modes[idx]
      end,
    },
  }
end

-- Action bar
local function build_action_bar()
  return vb:row {
    margin  = 4,
    spacing = 8,

    vb:button {
      text  = "Randomize",
      width = 90,
      notifier = function()
        state.seed = math.random(0, 9999)
        local sg = vb.views["seed_global"]
        if sg then sg.value = state.seed end
        for vi = 1, #state.voices do update_voice(vi) end
      end,
    },

    vb:button {
      text  = "Render to Phrase",
      width = 130,
      notifier = function()
        local ok = true
        for vi, voice in ipairs(state.voices) do
          local pattern = voice._cached_pattern
          if not pattern or #pattern == 0 then
            pattern = generate_pattern(vi)
          end
          ok = PhraseWriter.write_voice(voice, pattern)
          if not ok then break end
        end
        if ok then
          renoise.app():show_message("AlgoRhythm: Pattern written to phrase(s).")
        end
      end,
    },
  }
end

-- ─── Public entry point ──────────────────────────────────────────────────────

function MainPanel.show()
  -- Bring existing dialog to front if open
  if dialog and dialog.visible then
    dialog:show()
    return
  end

  vb = renoise.ViewBuilder()

  -- Generate initial patterns before building views
  for vi = 1, #state.voices do
    generate_pattern(vi)
  end

  -- Build voice lanes
  local lanes = vb:column {spacing = 4}
  for vi = 1, #state.voices do
    lanes:add_child(build_voice_lane(vi))
  end

  local content = vb:column {
    margin    = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
    spacing   = 8,
    min_width = 620,

    vb:row {
      vb:text {text = "AlgoRhythm", font = "bold", style = "strong"},
    },

    build_global_bar(),
    lanes,
    build_action_bar(),
  }

  dialog = renoise.app():show_custom_dialog("AlgoRhythm", content)

  -- Refresh step grids now that views exist
  for vi = 1, #state.voices do
    refresh_grid(vi)
  end
end

return MainPanel
