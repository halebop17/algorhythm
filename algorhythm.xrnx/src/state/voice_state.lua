-- VoiceState: holds algorithm selection, parameters, and output config for one lane

local VoiceState = {}
VoiceState.__index = VoiceState

-- Pitch modes
VoiceState.PITCH_FIXED      = "fixed"       -- algorithm drives *when*; note is fixed
VoiceState.PITCH_SCALE_WALK = "scale_walk"  -- algorithm also drives *which* note (melody)

-- Algorithm IDs
VoiceState.ALGO_EUCLIDEAN = "euclidean"
VoiceState.ALGO_BRESENHAM = "bresenham"
VoiceState.ALGO_CELLULAR  = "cellular"
VoiceState.ALGO_MARKOV    = "markov"
VoiceState.ALGO_LOGISTIC  = "logistic"
VoiceState.ALGO_PERLIN    = "perlin"
VoiceState.ALGO_RANDOM    = "random"

function VoiceState.new(name, index)
  local self = setmetatable({}, VoiceState)
  self.name             = name or "Voice"
  self.algorithm        = VoiceState.ALGO_EUCLIDEAN
  self.steps            = 16
  self.pulses           = 4
  self.offset           = 0
  self.probability      = 100   -- 0–100 %: chance each active step actually fires
  self.density          = 50    -- 0–100 %: used by density-aware algorithms (Perlin, Random)
  self.pitch_mode       = VoiceState.PITCH_FIXED
  self.note_value       = 48    -- MIDI note (0–119); default C-4
  self.octave_min       = 3     -- for PITCH_SCALE_WALK
  self.octave_max       = 5
  self.velocity         = 100   -- 0–127
  self.instrument_index = 1     -- 1-based instrument index in Renoise
  self.phrase_index     = index or 1  -- phrase slot to write to
  self.output_mode      = "phrase"    -- "phrase" or "midi"  (Phase 4)
  self.midi_channel     = 1
  self.midi_device_name = nil
  self._cached_pattern  = nil   -- last generated bool[]
  return self
end

return VoiceState
