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
