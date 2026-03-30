-- Logistic map chaos source (Phase 2)
-- x(n+1) = r * x(n) * (1 - x(n))
-- r < 3.0  → stable fixed point
-- r ≈ 3.5  → period-2 / period-4 oscillation
-- r > 3.8  → chaotic; dense, unpredictable patterns
-- r = 4.0  → fully chaotic
--
-- params table:
--   steps     (int)          : number of steps
--   r         (number 2–4)   : bifurcation parameter
--   threshold (number 0–1)   : values above this become a hit (default 0.5)
--   seed      (int)          : selects starting x0 (deterministic)

local Logistic = {}

function Logistic.generate(params)
  local steps     = math.max(1,   math.floor(params.steps or 16))
  local r         = math.max(2.0, math.min(params.r         or 3.7, 4.0))
  local threshold = math.max(0.0, math.min(params.threshold or 0.5, 1.0))
  local seed      = params.seed or 42

  -- Derive a starting x0 in (0,1) deterministically from seed
  math.randomseed(seed)
  local x = 0.1 + math.random() * 0.8  -- avoid 0 and 1

  -- Discard transient (warm up the map)
  for _ = 1, 50 do
    x = r * x * (1 - x)
  end

  local pattern = {}
  for i = 1, steps do
    x = r * x * (1 - x)
    pattern[i] = x > threshold
  end

  return pattern
end

return Logistic
