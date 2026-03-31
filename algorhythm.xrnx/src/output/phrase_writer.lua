-- Phrase writer: converts step arrays into Renoise native phrases
-- Phase 4: voices sharing the same instrument_index are consolidated into
-- one phrase using separate note columns (max 12 per phrase).

local PhraseWriter = {}
local Scales = require("src/utils/scales")

local EMPTY = renoise.PatternLine.EMPTY_NOTE

-- Write one column of a phrase for a single voice.
-- Prob %    = global fire probability (voice.probability).
-- Gate %    = note length as % of step duration; implemented as NOTE_OFF insertion.
-- Ratchet   = number of evenly-spaced note triggers within one step (1=off, 2-4=retrigger).
-- Delay     = per-step timing offset written to note_column.delay_value (0-255).
-- Pitch A/B = selected per step by ab_map, then scale-quantized.
local function write_column(phrase, col_idx, pattern, voice)
  local global_prob  = math.max(0, math.min(voice.probability or 100, 100))
  local num_lines    = phrase.number_of_lines
  local vel_map      = voice.vel_map
  local gate_map     = voice.gate_map
  local ratchet_map  = voice.ratchet_map
  local delay_map    = voice.delay_map
  local pitch_a      = voice.pitch_a_map
  local pitch_b      = voice.pitch_b_map
  local scale_idx    = voice._scale_index or 1
  local root         = voice._root_note   or 0
  local ab_map       = voice.pitch_ab_map
  local map_steps    = voice.steps or 16
  local step_size    = math.max(1, math.floor(num_lines / map_steps))
  local NOTE_OFF_VAL = renoise.PatternLine.NOTE_OFF

  -- Clear the entire column first so stale data from previous renders doesn't linger
  for s = 1, num_lines do
    local nc = phrase:line(s).note_columns[col_idx]
    nc.note_value   = EMPTY
    nc.volume_value = 255
    nc.delay_value  = 0
  end

  -- Forward pass: write notes + gate NOTE_OFFs
  for step = 1, num_lines do
    local ms       = (math.floor((step - 1) / step_size) % map_steps) + 1
    local pat_step = pattern[step]

    -- Prob %: global fire probability applied uniformly to every active step
    if pat_step and (global_prob >= 100 or math.random(100) <= global_prob) then
      local nc = phrase:line(step).note_columns[col_idx]

      -- Pitch A/B: per-step probability (ab_map); 100=always A, 0=always B
      local raw_note
      if pitch_a and pitch_b then
        local ab_prob = (ab_map and ab_map[ms]) or 50
        raw_note = (math.random(100) <= ab_prob) and (pitch_a[ms] or voice.note_value or 48)
                                                  or (pitch_b[ms] or voice.note_value or 48)
      else
        raw_note = voice.note_value or 48
      end

      -- Scale-quantize if a non-chromatic scale is active
      local note
      if scale_idx and scale_idx > 1 then
        note = Scales.quantize(raw_note, scale_idx, root)
      else
        note = math.max(0, math.min(raw_note, 119))
      end
      nc.note_value   = note
      local vel = (vel_map and vel_map[ms]) and vel_map[ms] or (voice.velocity or 100)
      nc.volume_value = math.max(0, math.min(vel, 127))

      -- Delay: per-step timing offset (0-255)
      if delay_map and delay_map[ms] then
        nc.delay_value = math.max(0, math.min(delay_map[ms], 255))
      end

      -- Gate %: insert NOTE_OFF based on gate % of step_size.
      -- Only meaningful when step_size > 1.
      if step_size > 1 then
        local gate_pct   = (gate_map and gate_map[ms]) and gate_map[ms] or 100
        local gate_lines = math.max(1, math.floor((gate_pct / 100) * step_size))
        local off_line   = step + gate_lines
        if off_line <= num_lines then
          local off_nc = phrase:line(off_line).note_columns[col_idx]
          if off_nc.note_value == EMPTY then
            off_nc.note_value = NOTE_OFF_VAL
          end
        end
      end
    end
  end

  -- Ratchet post-pass: duplicate the note at evenly-spaced sub-line positions.
  -- Only works when step_size > 1 (multiple phrase lines per pattern step).
  if step_size > 1 and ratchet_map then
    for step = 1, num_lines do
      local ms = (math.floor((step - 1) / step_size) % map_steps) + 1
      local r  = math.max(1, math.floor(ratchet_map[ms] or 1))
      if r > 1 then
        local nc = phrase:line(step).note_columns[col_idx]
        if nc.note_value ~= EMPTY and nc.note_value ~= NOTE_OFF_VAL then
          local sub_interval = step_size / r
          for hit = 1, r - 1 do
            local sub_line = step + math.floor(hit * sub_interval)
            if sub_line <= num_lines then
              local sub_nc = phrase:line(sub_line).note_columns[col_idx]
              if sub_nc.note_value == EMPTY then
                sub_nc.note_value   = nc.note_value
                sub_nc.volume_value = nc.volume_value
              end
            end
          end
        end
      end
    end
  end
end

-- Group voices by instrument_index.
local function group_by_instrument(voices, patterns)
  local groups = {}
  for i, voice in ipairs(voices) do
    local ii = voice.instrument_index
    if not groups[ii] then groups[ii] = {} end
    groups[ii][#groups[ii] + 1] = { voice = voice, pattern = patterns[i] or {} }
  end
  return groups
end

-- Public: write all voices, consolidating those on the same instrument.
-- voices  : array of VoiceState
-- patterns: array of bool[] (parallel to voices)
-- slot    : phrase slot number (1-based) to write to
-- insert  : if true, insert a NEW phrase at `slot` (pushing existing ones down)
--           if false/nil, overwrite/create phrase at `slot`
function PhraseWriter.write_all(voices, patterns, slot, insert)
  slot = math.max(1, slot or 1)
  local song = renoise.song()
  if not song then
    renoise.app():show_error("AlgoRhythm: No song is open.")
    return false
  end

  local groups = group_by_instrument(voices, patterns)

  for inst_idx, group in pairs(groups) do
    if inst_idx < 1 or inst_idx > #song.instruments then
      renoise.app():show_error(
        string.format("AlgoRhythm: Instrument %d out of range.", inst_idx))
      return false
    end

    local instrument = song.instruments[inst_idx]
    local num_cols   = math.min(#group, 12)

    local num_lines = 0
    for _, entry in ipairs(group) do
      num_lines = math.max(num_lines, #entry.pattern)
    end
    local names = {}
    for _, entry in ipairs(group) do names[#names+1] = entry.voice.name end
    local phrase_name = table.concat(names, "+")

    local ok, err = pcall(function()
      if insert then
        -- Insert a fresh phrase at `slot`, pushing existing phrases down
        local target = math.min(slot, #instrument.phrases + 1)
        instrument:insert_phrase_at(target)
      else
        -- Overwrite: create phrase slots up to `slot` if they don't exist yet
        while #instrument.phrases < slot do
          instrument:insert_phrase_at(#instrument.phrases + 1)
        end
      end

      local phrase = instrument.phrases[slot]
      phrase.number_of_lines      = math.max(1, math.min(num_lines, 512))
      phrase.visible_note_columns = math.max(1, math.min(num_cols, 12))
      phrase.looping              = true
      phrase.name                 = phrase_name

      for col, entry in ipairs(group) do
        if col > 12 then break end
        write_column(phrase, col, entry.pattern, entry.voice)
      end
    end)

    if not ok then
      renoise.app():show_error("AlgoRhythm: Write failed: " .. tostring(err))
      return false
    end
  end

  return true
end

-- Legacy single-voice write (backwards compat).
function PhraseWriter.write_voice(voice, pattern)
  return PhraseWriter.write_all({voice}, {pattern}, 1)
end

return PhraseWriter

