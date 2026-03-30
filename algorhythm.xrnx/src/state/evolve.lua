-- Evolve system: mutates voice parameters over time (Phase 5)

local VoiceState = require("src/state/voice_state")

local Evolve = {}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Returns either +d or -d with equal probability
local function pm(d)
  return (math.random(2) == 1) and d or -d
end

-- ── per-algorithm natural mutations ──────────────────────────────────────────

local function mutate_algo(v)
  local a = v.algorithm
  local s = v.steps

  if a == VoiceState.ALGO_EUCLIDEAN then
    -- ±1 on pulses and/or offset for subtle groove shifts
    v.pulses = clamp(v.pulses + pm(1), 1, s)
    v.offset = ((v.offset + pm(1)) % s + s) % s

  elseif a == VoiceState.ALGO_BRESENHAM then
    -- Rotate weight vector slightly; shift offset
    v._bres_weight = clamp((v._bres_weight or 1.0) + pm(0.1), 0.1, 2.0)
    v.offset = ((v.offset + pm(1)) % s + s) % s

  elseif a == VoiceState.ALGO_CELLULAR then
    -- Cellular naturally evolves by stepping to the next generation
    v._ca_generation = (v._ca_generation or 0) + 1

  elseif a == VoiceState.ALGO_LOGISTIC then
    -- Nudge r: approaches chaos near 4.0, backs off below 2.5
    v._logistic_r = clamp((v._logistic_r or 3.7) + pm(0.02), 2.5, 4.0)

  elseif a == VoiceState.ALGO_PERLIN then
    -- Advance time offset for smooth organic drift
    v._perlin_offset = (v._perlin_offset or 0.0) + 0.125

  elseif a == VoiceState.ALGO_MARKOV then
    -- Nudge stay-weight (self-loop probability) ±5 %
    v._markov_stay = clamp((v._markov_stay or 0.7) + pm(0.05), 0.1, 0.95)

  elseif a == VoiceState.ALGO_RANDOM then
    -- Shift density ±5 pp
    v.density = clamp(v.density + pm(5), 0, 100)
  end
end

-- ── public API ───────────────────────────────────────────────────────────────

-- Called on each detected bar boundary.
-- speed: "slow" (every 4 bars) | "fast" (every bar)
-- Returns true when a mutation was actually applied.
function Evolve.tick(voice, bar_count, speed)
  local interval = (speed == "fast") and 1 or 4
  if bar_count % interval ~= 0 then return false end
  mutate_algo(voice)
  return true
end

-- Small manual delta mutation (Mutate button).
function Evolve.mutate(voice)
  mutate_algo(voice)
end

-- Full re-randomization (Randomize button or new seed).
-- seed: number — caller should pass a unique seed per voice to avoid identical patterns
function Evolve.full_randomize(voice, seed)
  if seed then math.randomseed(seed) end
  local s = voice.steps
  voice.pulses          = math.random(1, math.max(1, s))
  voice.offset          = math.random(0, math.max(0, s - 1))
  voice._bres_weight    = math.random(10, 200) / 100.0
  voice._logistic_r     = 2.5 + math.random(0, 150) / 100.0
  voice._perlin_offset  = math.random(0, 100) / 10.0
  voice._markov_stay    = math.random(10, 90) / 100.0
  voice._ca_generation  = math.random(0, 20)
  voice.density         = math.random(10, 90)
end

return Evolve
