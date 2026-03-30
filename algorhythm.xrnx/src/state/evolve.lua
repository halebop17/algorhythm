-- Evolve system: mutates voice parameters over time (Phase 5 — stub)

local Evolve = {}

-- Called on each bar boundary. Returns true if a mutation was applied.
-- voice_state: VoiceState, bar_count: int, speed: "slow"|"fast"
function Evolve.tick(voice_state, bar_count, speed)
  -- TODO Phase 5
  -- Slow = mutate every 4 bars; Fast = every 1 bar
  local interval = (speed == "fast") and 1 or 4
  if bar_count % interval ~= 0 then return false end

  -- Dispatch to per-algorithm mutation
  local algo = voice_state.algorithm
  if algo == "euclidean" then
    -- ±1 pulse rotation
    voice_state.offset = (voice_state.offset + 1) % voice_state.steps
  elseif algo == "cellular" then
    -- Cellular naturally evolves by stepping generation
    voice_state._ca_generation = (voice_state._ca_generation or 0) + 1
  elseif algo == "logistic" then
    -- Nudge r toward chaos ceiling
    voice_state._logistic_r = math.min(4.0, (voice_state._logistic_r or 3.5) + 0.01)
  elseif algo == "perlin" then
    -- Advance time offset for smooth drift
    voice_state._perlin_offset = (voice_state._perlin_offset or 0) + 0.125
  end

  return true
end

-- Full randomization from a new seed
function Evolve.randomize(voice_state, seed)
  math.randomseed(seed or os.time())
  voice_state.pulses = math.random(1, math.max(1, voice_state.steps))
  voice_state.offset = math.random(0, voice_state.steps - 1)
end

-- Small delta mutation (±1 on params)
function Evolve.mutate(voice_state)
  local delta = 1
  local s = voice_state.steps
  voice_state.pulses = math.max(1, math.min(s, voice_state.pulses + math.random(-delta, delta)))
  voice_state.offset = ((voice_state.offset + math.random(-delta, delta)) % s + s) % s
end

return Evolve
