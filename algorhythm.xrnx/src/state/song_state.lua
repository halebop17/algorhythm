-- SongState: global settings shared across all voice lanes

local VoiceState = require("src/state/voice_state")

local SongState = {}
SongState.__index = SongState

SongState.EVOLVE_OFF  = "off"
SongState.EVOLVE_SLOW = "slow"
SongState.EVOLVE_FAST = "fast"

function SongState.new()
  local self = setmetatable({}, SongState)
  self.scale_index = 1    -- index into Scales.DEFINITIONS
  self.root_note   = 0    -- 0=C, 1=C#, … 11=B
  self.seed        = 42
  self.evolve_mode   = SongState.EVOLVE_OFF
  self.phrase_length  = 0     -- 0 = voice.steps (auto); 32/64/128/256/512 = baked length
  self.append_count   = 1     -- how many phrases Append inserts
  self.voices         = { VoiceState.new("Voice 1", 1) }
  return self
end

-- Add a voice lane (max 6)
function SongState:add_voice()
  if #self.voices >= 6 then return nil end
  local v = VoiceState.new("Voice " .. (#self.voices + 1), #self.voices + 1)
  self.voices[#self.voices + 1] = v
  return v
end

-- Remove a voice lane by index (min 1 lane)
function SongState:remove_voice(index)
  if #self.voices <= 1 then return end
  table.remove(self.voices, index)
  -- Re-number phrase slots
  for i, v in ipairs(self.voices) do
    v.phrase_index = i
  end
end

return SongState
