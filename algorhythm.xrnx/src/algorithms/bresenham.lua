-- Bresenham multi-voice distribution (Phase 2)
-- Distributes pulses across steps using a weighted Bresenham line,
-- designed to interlock with other voices (no simultaneous hits).
--
-- params table:
--   steps       (int) : total steps
--   pulses      (int) : active steps
--   offset      (int) : rotation
--   weight      (number 0.5–2.0) : stretch/compress distribution (default 1.0)

local Bresenham = {}

function Bresenham.generate(params)
  -- TODO Phase 2: weighted Bresenham multi-voice implementation
  -- Fall back to euclidean distribution until Phase 2
  local steps  = math.max(1, math.floor(params.steps  or 16))
  local pulses = math.max(0, math.min(math.floor(params.pulses or 4), steps))
  local offset = math.floor(params.offset or 0)
  local pattern = {}

  local prev = -1
  for i = 0, steps - 1 do
    local curr = math.floor(i * pulses / steps)
    pattern[i + 1] = (curr ~= prev)
    prev = curr
  end

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
