-- Phrase writer: converts step arrays into Renoise native phrases
-- Phase 4: voices sharing the same instrument_index are consolidated into
-- one phrase using separate note columns (max 12 per phrase).

local PhraseWriter = {}

local EMPTY = renoise.PatternLine.EMPTY_NOTE

-- Write one column of a phrase for a single voice.
local function write_column(phrase, col_idx, pattern, voice)
  local prob = math.max(0, math.min(voice.probability or 100, 100))
  local num_lines = phrase.number_of_lines
  for step = 1, num_lines do
    local nc = phrase:line(step).note_columns[col_idx]
    if pattern[step] and (prob >= 100 or math.random(100) <= prob) then
      nc.note_value   = math.max(0, math.min(voice.note_value or 48,  119))
      nc.volume_value = math.max(0, math.min(voice.velocity   or 100, 127))
    else
      nc.note_value   = EMPTY
      nc.volume_value = 255
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

