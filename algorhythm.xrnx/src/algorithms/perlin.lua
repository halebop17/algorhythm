-- Perlin-style smooth noise rhythm generator (Phase 2)
-- Uses value noise with cosine interpolation — same smooth organic drift
-- as Perlin noise but without the gradient table complexity.
-- Advancing `time_offset` each bar produces a slowly morphing pattern.
--
-- params table:
--   steps       (int)         : number of steps
--   time_offset (number)      : advances over time for Evolve mode (0.0 = initial)
--   threshold   (number 0–1)  : noise values above this become a hit (default 0.45)
--   frequency   (number)      : spatial frequency of noise (default 1.0; higher = busier)
--   seed        (int)         : seeds the random lattice

local Perlin = {}

-- Cosine-interpolated value noise
local function noise_1d(t, lattice)
  local n   = #lattice
  local i   = math.floor(t) % n
  local frac = t - math.floor(t)
  local a   = lattice[(i     % n) + 1]
  local b   = lattice[((i+1) % n) + 1]
  local cos_t = (1 - math.cos(frac * math.pi)) * 0.5
  return a + cos_t * (b - a)
end

function Perlin.generate(params)
  local steps       = math.max(1,   math.floor(params.steps       or 16))
  local time_offset = params.time_offset or 0.0
  local threshold   = math.max(0.0, math.min(params.threshold     or 0.45, 1.0))
  local frequency   = math.max(0.1, params.frequency               or 1.0)
  local seed        = params.seed or 42

  -- Build a random lattice of 64 gradient values
  math.randomseed(seed)
  local LATTICE_SIZE = 64
  local lattice = {}
  for i = 1, LATTICE_SIZE do
    lattice[i] = math.random()
  end

  local pattern = {}
  for i = 0, steps - 1 do
    local t = (i / steps) * frequency + time_offset
    local v = noise_1d(t * LATTICE_SIZE, lattice)
    pattern[i + 1] = v > threshold
  end

  return pattern
end

return Perlin
