-- Phrase writer: converts a step array into a Renoise native phrase
-- Phase 1: single voice, single note column
-- Phase 4 (TODO): multi-voice consolidation into multiple note columns

local PhraseWriter = {}

-- Write one voice pattern to instrument.phrases[voice.phrase_index]
-- voice   : VoiceState
-- pattern : bool[] from any algorithm's generate()
-- Returns true on success, false on error (error already shown to user)
function PhraseWriter.write_voice(voice, pattern)
  local song = renoise.song()
  if not song then
    renoise.app():show_error("AlgoRhythm: No song is open.")
    return false
  end

  if #pattern == 0 then
    renoise.app():show_error("AlgoRhythm: Empty pattern — nothing to write.")
    return false
  end

  local inst_idx = voice.instrument_index
  if inst_idx < 1 or inst_idx > #song.instruments then
    renoise.app():show_error(
      string.format("AlgoRhythm: Instrument index %d is out of range (song has %d instruments).",
        inst_idx, #song.instruments))
    return false
  end

  local instrument = song.instruments[inst_idx]
  local phrase_idx = math.max(1, voice.phrase_index)

  -- Insert phrase slots until we have enough
  while #instrument.phrases < phrase_idx do
    instrument:insert_phrase_at(#instrument.phrases + 1)
  end

  local phrase = instrument.phrases[phrase_idx]

  -- Configure phrase dimensions
  local num_lines = math.max(1, math.min(#pattern, 512))
  phrase.number_of_lines = num_lines
  phrase.visible_note_columns = math.max(1, phrase.visible_note_columns)
  phrase.looping = true
  phrase.name    = voice.name

  -- Clear prior content
  phrase:clear()

  -- Write active steps
  local col_idx = 1  -- Phase 1: always column 1
  local prob = math.max(0, math.min(voice.probability or 100, 100))

  for step, active in ipairs(pattern) do
    if step > num_lines then break end
    if active then
      -- Apply per-step probability gate
      if prob >= 100 or math.random(100) <= prob then
        local line = phrase:line(step)
        local nc   = line.note_columns[col_idx]
        nc.note_value   = math.max(0, math.min(voice.note_value  or 48,  119))
        nc.volume_value = math.max(0, math.min(voice.velocity    or 100, 127))
      end
    end
  end

  return true
end

-- Phase 4 (TODO): write multiple voices sharing the same instrument into one
-- phrase using separate note columns per voice (max 12 columns).
function PhraseWriter.write_multi_voice(voices, patterns, phrase_idx)
  -- Placeholder until Phase 4: write each voice independently
  for i, voice in ipairs(voices) do
    PhraseWriter.write_voice(voice, patterns[i] or {})
  end
end

return PhraseWriter
