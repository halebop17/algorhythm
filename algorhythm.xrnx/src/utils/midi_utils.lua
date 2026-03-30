-- MIDI and timing utilities

local MidiUtils = {}

-- Beat duration in milliseconds at a given BPM
function MidiUtils.beat_ms(bpm)
  return 60000.0 / bpm
end

-- Step (1/16th note) duration in milliseconds
function MidiUtils.step_ms(bpm, steps_per_beat)
  return MidiUtils.beat_ms(bpm) / (steps_per_beat or 4)
end

-- Encode a MIDI note-on message (channel 1-based)
function MidiUtils.note_on(channel, note, velocity)
  return {0x90 + (channel - 1), note % 0x80, velocity % 0x80}
end

-- Encode a MIDI note-off message
function MidiUtils.note_off(channel, note)
  return {0x80 + (channel - 1), note % 0x80, 0}
end

-- Safely read current song BPM
function MidiUtils.current_bpm()
  local song = renoise.song()
  return song and song.transport.bpm or 120
end

-- List available MIDI output device names
function MidiUtils.available_output_devices()
  return renoise.Midi.available_output_devices()
end

return MidiUtils
