-- Markov chain rhythm generator (Phase 2)
-- Walks a weighted transition table to produce a step sequence.
-- With a high self-loop weight, the pattern has momentum (grooves).
-- With low self-loop weight, it changes state rapidly (busy patterns).
--
-- params table:
--   steps          (int)   : number of steps to generate
--   hit_probability (number 0–1) : base probability of emitting a hit in the "on" state
--   stay_weight    (number 0–1) : how strongly the chain stays in its current state (0=unstable, 1=static)
--   seed           (int)   : random seed

local Markov = {}

function Markov.generate(params)
  local steps           = math.max(1, math.floor(params.steps            or 16))
  local hit_prob        = math.max(0, math.min(params.hit_probability     or 0.7, 1))
  local stay            = math.max(0, math.min(params.stay_weight         or 0.7, 1))
  local seed            = params.seed or 42

  math.randomseed(seed)

  -- Two states: 0 = silent, 1 = active
  -- Transition matrix: [current_state][1=stay, 2=flip]
  -- From active:   P(stay active) = stay,    P(go silent) = 1-stay
  -- From silent:   P(stay silent) = stay,    P(go active) = 1-stay

  local state   = math.random() < hit_prob and 1 or 0
  local pattern = {}

  for i = 1, steps do
    pattern[i] = (state == 1) and (math.random() < hit_prob)
    -- Transition
    if math.random() > stay then
      state = 1 - state
    end
  end

  return pattern
end

return Markov
