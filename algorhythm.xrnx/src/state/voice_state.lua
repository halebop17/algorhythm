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
VoiceState.ALGO_STRAIGHT  = "straight"

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
  self.midi_device_name    = nil
  self._straight_interval  = 4   -- 4=quarter, 2=eighth, 1=sixteenth, 3=triplet
  self._cached_pattern     = nil  -- last generated bool[]
  -- Phase 6a/6b: per-step expression maps
  self.vel_min  = 1;   self.vel_max  = 127  -- range clamp for velocity lane
  self.gate_min = 1;   self.gate_max = 100  -- range clamp for gate lane
  self:init_step_maps(self.steps)
  return self
end

-- Initialise all per-step maps to defaults for `steps` steps.
function VoiceState:init_step_maps(steps)
  self.vel_map      = {}
  self.gate_map     = {}
  self.pitch_a_map  = {}
  self.pitch_b_map  = {}
  self.pitch_ab_map = {}
  self.ratchet_map  = {}
  self.delay_map    = {}
  local base = self.note_value or 48
  for i = 1, steps do
    self.vel_map[i]      = 100
    self.gate_map[i]     = 100
    self.pitch_a_map[i]  = base
    self.pitch_b_map[i]  = base
    self.pitch_ab_map[i] = 50
    self.ratchet_map[i]  = 1
    self.delay_map[i]    = 0    -- 0 = no delay
  end
end

-- Resize maps when steps changes; preserve existing values, fill new slots with defaults.
function VoiceState:resize_maps(new_steps)
  local base = self.note_value or 48
  for i = self.steps + 1, new_steps do
    self.vel_map[i]      = self.vel_map[i]      or 100
    self.gate_map[i]     = self.gate_map[i]     or 100
    self.pitch_a_map[i]  = self.pitch_a_map[i]  or base
    self.pitch_b_map[i]  = self.pitch_b_map[i]  or base
    self.pitch_ab_map[i] = self.pitch_ab_map[i] or 50
    self.ratchet_map[i]  = self.ratchet_map[i]  or 1
    self.delay_map[i]    = self.delay_map[i]    or 0
  end
  for i = new_steps + 1, #self.vel_map      do self.vel_map[i]      = nil end
  for i = new_steps + 1, #self.gate_map     do self.gate_map[i]     = nil end
  for i = new_steps + 1, #self.pitch_a_map  do self.pitch_a_map[i]  = nil end
  for i = new_steps + 1, #self.pitch_b_map  do self.pitch_b_map[i]  = nil end
  for i = new_steps + 1, #self.pitch_ab_map do self.pitch_ab_map[i] = nil end
  for i = new_steps + 1, #self.ratchet_map  do self.ratchet_map[i]  = nil end
  for i = new_steps + 1, #self.delay_map    do self.delay_map[i]    = nil end
end

return VoiceState
