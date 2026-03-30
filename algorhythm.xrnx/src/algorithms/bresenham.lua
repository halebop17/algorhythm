-- Bresenham multi-voice distribution
-- Uses the Bresenham line error-accumulation method to distribute pulses.
-- Unlike Euclidean (Bjorklund), Bresenham accumulates an error term and fires
-- a hit whenever the error crosses the threshold — producing a subtly different
-- feel, especially with the `weight` parameter which skews the distribution
-- toward the front or back of the cycle.
--
-- params table:
--   steps   (int 1–32)       : total steps
--   pulses  (int 0–steps)    : active steps
--   offset  (int)            : rotation
--   weight  (number 0.1–2.0) : <1 = hits cluster early, >1 = hits cluster late (default 1.0)

local Bresenham = {}

function Bresenham.generate(params)
  local steps  = math.max(1, math.floor(params.steps  or 16))
  local pulses = math.max(0, math.min(math.floor(params.pulses or 4), steps))
  local offset = math.floor(params.offset or 0)
  local weight = math.max(0.1, math.min(params.weight or 1.0, 2.0))

  local pattern = {}

  if pulses == 0 then
    for i = 1, steps do pattern[i] = false end
    return pattern
  end
  if pulses >= steps then
    for i = 1, steps do pattern[i] = true end
    return pattern
  end

  -- Bresenham error accumulation with weight skew
  local error = 0
  local threshold = steps
  local increment = pulses * weight * 2  -- weighted step size

  for i = 1, steps do
    error = error + increment
    if error >= threshold then
      pattern[i] = true
      error = error - threshold * 2
    else
      pattern[i] = false
    end
  end

  -- Correct pulse count if weight skew caused drift (clamp to exact pulse count)
  local count = 0
  for _, v in ipairs(pattern) do if v then count = count + 1 end end
  -- If we have too many, clear trailing hits; if too few, fill from front
  if count > pulses then
    local removed = 0
    for i = steps, 1, -1 do
      if pattern[i] and removed < (count - pulses) then
        pattern[i] = false; removed = removed + 1
      end
    end
  elseif count < pulses then
    local added = 0
    for i = 1, steps do
      if not pattern[i] and added < (pulses - count) then
        pattern[i] = true; added = added + 1
      end
    end
  end

  -- Apply rotation
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

return Bresenham
