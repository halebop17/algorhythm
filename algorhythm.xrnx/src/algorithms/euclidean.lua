-- Euclidean rhythm generator (Bresenham/modular arithmetic formulation)
-- Distributes `pulses` as evenly as possible across `steps`.
-- E(3,8) → {T,F,F,T,F,F,T,F}  |  E(4,16) → {T,F,F,F,T,F,F,F,T,F,F,F,T,F,F,F}
--
-- params table:
--   steps   (int 1–32) : total number of steps
--   pulses  (int 0–steps) : number of active steps
--   offset  (int) : pattern rotation (positive = shift right)

local Euclidean = {}

function Euclidean.generate(params)
  local steps  = math.max(1, math.floor(params.steps  or 16))
  local pulses = math.max(0, math.min(math.floor(params.pulses or 4), steps))
  local offset = math.floor(params.offset or 0)

  local pattern = {}

  if pulses == 0 then
    for i = 1, steps do pattern[i] = false end
    return pattern
  end

  if pulses >= steps then
    for i = 1, steps do pattern[i] = true end
    return pattern
  end

  -- Bresenham distribution: generate a pulse wherever the running quotient increments
  local prev = -1
  for i = 0, steps - 1 do
    local curr = math.floor(i * pulses / steps)
    pattern[i + 1] = (curr ~= prev)
    prev = curr
  end

  -- Apply rotation offset
  offset = ((offset % steps) + steps) % steps
  if offset ~= 0 then
    local rotated = {}
    for i = 1, steps do
      rotated[i] = pattern[((i - 1 + offset) % steps) + 1]
    end
    return rotated
  end

  return pattern
end

return Euclidean
