-- MIDI output path (Phase 4)
-- Real-time note on/off via renoise.Midi.create_output_device()
-- CRITICAL: tracks all sent note-ons; must send note-offs on Stop/Mutate/close
--           to prevent hanging MIDI notes.

local MidiUtils  = require("src/utils/midi_utils")

local MidiOutput = {}

local _device      = nil          -- open MIDI output device handle
local _active_notes = {}          -- { [channel] = { [note] = true } }

-- Open a MIDI output device by name. Closes any previously open device first.
function MidiOutput.open(device_name)
  MidiOutput.close()
  if not device_name or device_name == "" then return false end
  local ok, err = pcall(function()
    _device = renoise.Midi.create_output_device(device_name)
  end)
  if not ok then
    renoise.app():show_error("AlgoRhythm: Could not open MIDI device '" .. device_name .. "': " .. tostring(err))
    _device = nil
    return false
  end
  return true
end

-- Send a raw 3-byte MIDI message if device is open
function MidiOutput.send(message)
  if _device then
    _device:send(message)
  end
end

-- Send note-on and record it for cleanup
function MidiOutput.note_on(channel, note, velocity)
  if not _device then return end
  _device:send(MidiUtils.note_on(channel, note, velocity))
  _active_notes[channel] = _active_notes[channel] or {}
  _active_notes[channel][note] = true
end

-- Send note-off and clear tracking record
function MidiOutput.note_off(channel, note)
  if not _device then return end
  _device:send(MidiUtils.note_off(channel, note))
  if _active_notes[channel] then
    _active_notes[channel][note] = nil
  end
end

-- Send note-off for every tracked active note (call on Stop / Mutate / plugin close)
function MidiOutput.kill_all_notes()
  for channel, notes in pairs(_active_notes) do
    for note in pairs(notes) do
      if _device then
        _device:send(MidiUtils.note_off(channel, note))
      end
    end
  end
  _active_notes = {}
end

-- Close the device (sends all note-offs first)
function MidiOutput.close()
  MidiOutput.kill_all_notes()
  if _device then
    _device:close()
    _device = nil
  end
end

-- Check if a device is currently open
function MidiOutput.is_open()
  return _device ~= nil
end

-- Return list of available MIDI output device names
function MidiOutput.available_devices()
  return MidiUtils.available_output_devices()
end

return MidiOutput
