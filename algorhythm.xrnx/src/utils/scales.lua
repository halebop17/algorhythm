-- Scale definitions, note quantization, and note naming

local Scales = {}

-- Interval sets relative to root (semitone offsets)
Scales.DEFINITIONS = {
  { name = "Minor",      intervals = {0, 2, 3, 5, 7, 8, 10} },
  { name = "Major",      intervals = {0, 2, 4, 5, 7, 9, 11} },
  { name = "Phrygian",   intervals = {0, 1, 3, 5, 7, 8, 10} },
  { name = "Dorian",     intervals = {0, 2, 3, 5, 7, 9, 10} },
  { name = "Lydian",     intervals = {0, 2, 4, 6, 7, 9, 11} },
  { name = "Mixolydian", intervals = {0, 2, 4, 5, 7, 9, 10} },
  { name = "Locrian",    intervals = {0, 1, 3, 5, 6, 8, 10} },
  { name = "Chromatic",  intervals = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11} },
}

Scales.NAMES = {}
for i, s in ipairs(Scales.DEFINITIONS) do
  Scales.NAMES[i] = s.name
end

Scales.ROOT_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

-- Convert MIDI note number to display string: 48 → "C-4"
function Scales.note_name(note_value)
  if note_value < 0 or note_value > 119 then return "---" end
  local labels = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
  local octave   = math.floor(note_value / 12)
  local semitone = (note_value % 12) + 1
  return labels[semitone] .. octave
end

-- Quantize a MIDI note to the nearest degree in the given scale
function Scales.quantize(note_value, scale_index, root_note)
  local scale = Scales.DEFINITIONS[scale_index]
  if not scale then return note_value end
  note_value = math.max(0, math.min(119, note_value))
  local octave   = math.floor(note_value / 12)
  local relative = (note_value % 12 - root_note + 12) % 12
  local best_interval = scale.intervals[1]
  local best_dist     = 12
  for _, interval in ipairs(scale.intervals) do
    local dist = math.min(math.abs(interval - relative), 12 - math.abs(interval - relative))
    if dist < best_dist then
      best_dist     = dist
      best_interval = interval
    end
  end
  local result = octave * 12 + ((root_note + best_interval) % 12)
  return math.max(0, math.min(119, result))
end

-- Return all scale notes within an octave range (for SCALE_WALK mode)
function Scales.notes_in_range(scale_index, root_note, oct_min, oct_max)
  local scale = Scales.DEFINITIONS[scale_index]
  if not scale then return {} end
  local notes = {}
  for oct = oct_min, oct_max do
    for _, interval in ipairs(scale.intervals) do
      local note = oct * 12 + root_note + interval
      if note >= 0 and note <= 119 then
        notes[#notes + 1] = note
      end
    end
  end
  table.sort(notes)
  return notes
end

return Scales
