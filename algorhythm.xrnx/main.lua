-- AlgoRhythm — Algorithmic rhythm and phrase generator for Renoise
-- Phase 1: single-voice euclidean MVP
-- Enable sandbox error reporting during development
_AUTO_RELOAD_DEBUG = true

local main_panel = require("src/ui/main_panel")

-- Register tool menu entry
renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:AlgoRhythm...",
  invoke = main_panel.show,
}

-- Optional keybinding
renoise.tool():add_keybinding {
  name = "Global:Tools:Open AlgoRhythm",
  invoke = main_panel.show,
}

-- ── Bar-boundary detection for Evolve system ─────────────────────────────────
-- Poll every 100 ms. A pattern-loop wrap (line steps backward) counts as one
-- bar boundary and triggers Evolve.tick for every active voice lane.

local _last_line  = nil
local _bar_count  = 0

renoise.tool():add_timer(function()
  local song = renoise.song()
  if not song then _last_line = nil; return end
  local transport = song.transport
  if not transport.playing then _last_line = nil; return end

  local cur_line = transport.playback_pos.line
  if _last_line ~= nil and cur_line < _last_line then
    _bar_count = _bar_count + 1
    main_panel.on_bar_tick(_bar_count)
  end
  _last_line = cur_line
end, 100)
