-- AlgoRhythm — Audition / step-preview engine
-- Uses Renoise 3.5 API: trigger_instrument_note_on/off + add_timer.
-- A single shared timer ticks at 1/16-note intervals (derived from BPM + LPB).
-- Each voice tracks its own step pointer so polyrhythm works correctly.

local Scales   = require("src/utils/scales")
local Audition = {}

-- ── Module state ─────────────────────────────────────────────────────────────

local _active   = false
local _step_fn  = nil          -- reference kept so we can remove_timer
local _voices   = {}           -- array of { voice, pattern, step }
local _held     = {}           -- { inst_idx, note } pairs awaiting note_off
local _stop_cb  = nil          -- optional callback fired when playback stops

-- ── Internal helpers ──────────────────────────────────────────────────────────

-- Resolve the note to play for a given voice + step (mirrors phrase_writer logic).
local function resolve_note(voice, step)
  local pitch_a = voice.pitch_a_map
  local pitch_b = voice.pitch_b_map
  local ab_map  = voice.pitch_ab_map
  local raw_note
  if pitch_a and pitch_b then
    local ab_prob = (ab_map and ab_map[step]) or 50
    -- Use A when prob >= 50 (deterministic preview — no randomness mid-audition)
    raw_note = (ab_prob >= 50)
               and (pitch_a[step] or voice.note_value or 48)
               or  (pitch_b[step] or voice.note_value or 48)
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
  -- Remove the step timer
  if _step_fn then
    pcall(function() renoise.tool():remove_timer(_step_fn) end)
    _step_fn = nil
  end
  -- Send note-off for every held note to prevent hangs
  local song = renoise.song()
  if song then
    for _, h in ipairs(_held) do
      pcall(function()
        song:trigger_instrument_note_off(h.inst_idx, 1, h.note)
      end)
    end
  end
  _held   = {}
  _active = false
  _voices = {}
  -- Notify UI
  local cb = _stop_cb
  _stop_cb = nil
  if cb then pcall(cb) end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Start auditioning a list of voices.
--   voices_in  — array of VoiceState objects (each must have _cached_pattern)
--   song_state — SongState (for scale / root context)
--   on_stop    — optional function() called when audition is stopped
function Audition.start(voices_in, song_state, on_stop)
  -- Stop any currently running audition first
  if _active then stop_impl() end

  local song = renoise.song()
  if not song then return end

  _stop_cb = on_stop
  _held    = {}
  _voices  = {}

  for _, v in ipairs(voices_in) do
    local pat = v._cached_pattern
    if pat and #pat > 0 then
      -- Propagate scale/root from song_state into voice so resolve_note can read them
      if song_state then
        v._scale_index = song_state.scale_index
        v._root_note   = song_state.root_note
      end
      _voices[#_voices + 1] = { voice = v, pattern = pat, step = 0 }
    end
  end

  if #_voices == 0 then
    if on_stop then pcall(on_stop) end
    return
  end

  -- Step duration: one line at current BPM / LPB.
  -- LPB = lines per beat; at LPB=4 one line = 1/16th note at 4/4.
  local bpm     = song.transport.bpm
  local lpb     = song.transport.lpb
  local step_ms = math.max(20, math.floor(60000.0 / bpm / lpb))

  _active = true

  _step_fn = function()
    if not _active then return end

    local s = renoise.song()
    if not s then stop_impl(); return end

    -- 1. Send note-offs for notes held from previous step
    for _, h in ipairs(_held) do
      pcall(function()
        s:trigger_instrument_note_off(h.inst_idx, 1, h.note)
      end)
    end
    _held = {}

    -- 2. Advance each voice's step pointer and fire note-ons
    for _, vc in ipairs(_voices) do
      vc.step = (vc.step % #vc.pattern) + 1   -- wraps: 1 → 2 → … → len → 1
      if vc.pattern[vc.step] then
        local voice    = vc.voice
        local note     = resolve_note(voice, vc.step)
        local vel_raw  = (voice.vel_map and voice.vel_map[vc.step]) or voice.velocity or 100
        local vol      = math.max(0.0, math.min(1.0, vel_raw / 127.0))
        local inst_idx = voice.instrument_index
        pcall(function()
          s:trigger_instrument_note_on(inst_idx, 1, note, vol)
        end)
        _held[#_held + 1] = { inst_idx = inst_idx, note = note }
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
