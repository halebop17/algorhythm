-- AlgoRhythm — Audition / step-preview engine
-- Uses Renoise 3.5 API: trigger_instrument_note_on/off + add_timer.
-- A single shared timer ticks at 1/16-note intervals (derived from BPM + LPB).
-- Each voice tracks its own step pointer so polyrhythm works correctly.
--
-- Public API:
--   Audition.start(entries, phrase_length, on_stop)
--     entries       = array of { voice = VoiceState, pattern = bool[] }
--     phrase_length = 0 → loop forever; N → stop after N ticks
--     on_stop       = optional callback fired when playback stops
--   Audition.stop()
--   Audition.is_active()

local Scales   = require("src/utils/scales")
local Audition = {}

-- ── Module state ─────────────────────────────────────────────────────────────

local _active      = false
local _step_fn     = nil   -- reference kept so we can remove_timer
local _voices      = {}    -- array of { voice, pattern, step }
local _held        = {}    -- { inst_idx, note } pairs awaiting note_off
local _stop_cb     = nil   -- optional callback fired when playback stops
local _global_step = 0     -- total ticks fired since audition started
local _max_steps   = 0     -- 0 = loop forever; >0 = stop after this many ticks

-- ── Internal helpers ──────────────────────────────────────────────────────────

-- Resolve the note to play for a given voice + step.
-- Maps are voice.steps long; wrap step index into that range for baked patterns.
local function resolve_note(voice, step)
  local vsteps  = voice.steps or 16
  local ms      = ((step - 1) % vsteps) + 1   -- wrap into map range
  local pitch_a = voice.pitch_a_map
  local pitch_b = voice.pitch_b_map
  local ab_map  = voice.pitch_ab_map
  local raw_note
  if pitch_a and pitch_b then
    local ab_prob = (ab_map and ab_map[ms]) or 50
    -- Use A when prob >= 50 (deterministic; no randomness mid-audition)
    raw_note = (ab_prob >= 50)
               and (pitch_a[ms] or voice.note_value or 48)
               or  (pitch_b[ms] or voice.note_value or 48)
  else
    raw_note = voice.note_value or 48
  end
  -- Scale-quantize if a non-chromatic scale is set on the voice
  local si   = voice._scale_index or 1
  local root = voice._root_note   or 0
  if si and si > 1 then
    raw_note = Scales.quantize(raw_note, si, root)
  end
  return math.max(0, math.min(119, math.floor(raw_note)))
end

local function stop_impl()
  if _step_fn then
    pcall(function() renoise.tool():remove_timer(_step_fn) end)
    _step_fn = nil
  end
  local song = renoise.song()
  if song then
    for _, h in ipairs(_held) do
      pcall(function() song:trigger_instrument_note_off(h.inst_idx, 1, h.note) end)
    end
  end
  _held        = {}
  _active      = false
  _voices      = {}
  _global_step = 0
  _max_steps   = 0
  local cb = _stop_cb
  _stop_cb = nil
  if cb then pcall(cb) end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Start auditioning a list of voice+pattern entries.
--   entries       — array of { voice = VoiceState, pattern = bool[] }
--   phrase_length — 0 = loop forever; N = stop after N ticks (one full baked phrase)
--   on_stop       — optional function() called when playback stops
function Audition.start(entries, phrase_length, on_stop)
  if _active then stop_impl() end

  local song = renoise.song()
  if not song then return end

  _stop_cb     = on_stop
  _held        = {}
  _voices      = {}
  _global_step = 0
  _max_steps   = phrase_length or 0

  for _, entry in ipairs(entries) do
    local pat = entry.pattern
    if pat and #pat > 0 then
      _voices[#_voices + 1] = { voice = entry.voice, pattern = pat, step = 0 }
    end
  end

  if #_voices == 0 then
    if on_stop then pcall(on_stop) end
    return
  end

  local bpm     = song.transport.bpm
  local lpb     = song.transport.lpb
  local step_ms = math.max(20, math.floor(60000.0 / bpm / lpb))

  _active = true

  _step_fn = function()
    if not _active then return end

    local s = renoise.song()
    if not s then stop_impl(); return end

    -- Check phrase_length limit BEFORE firing this tick
    if _max_steps > 0 and _global_step >= _max_steps then
      stop_impl(); return
    end
    _global_step = _global_step + 1

    -- Send note-offs for notes held from the previous step
    for _, h in ipairs(_held) do
      pcall(function() s:trigger_instrument_note_off(h.inst_idx, 1, h.note) end)
    end
    _held = {}

    -- Advance each voice's step pointer (independent wrap) and fire note-ons
    for _, vc in ipairs(_voices) do
      vc.step = (vc.step % #vc.pattern) + 1   -- wraps: 1 → 2 → … → len → 1
      if vc.pattern[vc.step] then
        local voice   = vc.voice
        local note    = resolve_note(voice, vc.step)
        local vsteps  = voice.steps or 16
        local ms      = ((vc.step - 1) % vsteps) + 1   -- wrap into map range
        local vel_raw = (voice.vel_map and voice.vel_map[ms]) or voice.velocity or 100
        local vol     = math.max(0.0, math.min(1.0, vel_raw / 127.0))
        local inst    = voice.instrument_index
        pcall(function() s:trigger_instrument_note_on(inst, 1, note, vol) end)
        _held[#_held + 1] = { inst_idx = inst, note = note }
      end
    end
  end

  renoise.tool():add_timer(_step_fn, step_ms)
end

function Audition.stop()
  stop_impl()
end

function Audition.is_active()
  return _active
end

return Audition
