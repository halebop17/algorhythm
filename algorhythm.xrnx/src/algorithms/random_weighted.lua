-- Weighted random rhythm generator
-- Each step fires independently at a given density probability.
-- Simple and immediate: density 50% = roughly every other step fires.
--
-- params table:
--   steps   (int)         : number of steps
--   density (number 0–1)  : probability each step fires (0=silent, 1=all steps)
--   seed    (int)         : random seed

local RandomWeighted = {}

function RandomWeighted.generate(params)
  local steps   = math.max(1, math.floor(params.steps   or 16))
  local density = math.max(0.0, math.min(params.density or 0.5, 1.0))
  local seed    = params.seed or 42

  math.randomseed(seed)

  local pattern = {}
  for i = 1, steps do
    pattern[i] = math.random() < density
  end

  return pattern
end

return RandomWeighted
