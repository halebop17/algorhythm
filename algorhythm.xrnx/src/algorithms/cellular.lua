-- 1D Cellular Automata rhythm generator (Phase 2)
-- Applies elementary 1D CA rules (30, 90, 110) to produce a step pattern.
-- The pattern naturally evolves each bar by stepping to the next generation.
--
-- params table:
--   steps      (int)       : total steps (= cell count)
--   rule       (int)       : CA rule number — 30 (chaotic), 90 (fractal), 110 (complex)
--   generation (int)       : which generation to read (0 = initial seed row)
--   seed       (int)       : initial row seed for RNG

local Cellular = {}

-- Apply one generation of a 1D elementary CA rule to a boolean row
local function step_ca(row, rule_number)
  local n = #row
  local next_row = {}
  for i = 1, n do
    local left   = row[((i - 2) % n) + 1] and 1 or 0
    local center = row[i]                   and 1 or 0
    local right  = row[(i % n) + 1]        and 1 or 0
    local index  = left * 4 + center * 2 + right  -- 0-7
    -- Extract bit from rule number
    next_row[i] = ((rule_number >> index) & 1) == 1
  end
  return next_row
end

function Cellular.generate(params)
  local steps      = math.max(1, math.floor(params.steps      or 16))
  local rule       = math.floor(params.rule       or 30)
  local generation = math.max(0, math.floor(params.generation or 0))
  local seed       = params.seed or 42

  -- Build initial row from seed
  math.randomseed(seed)
  local row = {}
  for i = 1, steps do
    row[i] = math.random() > 0.5
  end
  -- Always activate the centre cell for rule 110 / 90 classic seeding
  row[math.ceil(steps / 2)] = true

  -- Iterate to the requested generation
  for _ = 1, generation do
    row = step_ca(row, rule)
  end

  return row
end

return Cellular
