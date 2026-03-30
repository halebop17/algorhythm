# AlgoRhythm — Development Plan

## Overview

A Renoise `.xrnx` tool that generates algorithmic rhythms and phrases using multiple generator algorithms, with a multi-voice UI. Output goes to native Renoise phrases and/or live MIDI. Inspired by the Subsequence Python library — all algorithms reimplemented from mathematical descriptions (not ported code) to respect the AGPL-3.0 license.

**Tool name:** AlgoRhythm  
**Bundle ID:** `com.fluxrhythm.algorhythm`  
**Renoise version target:** 3.5+  
**Language:** Lua (Renoise scripting API)

---

## Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Output modes | Both phrase write + live MIDI in v1 | More versatile from day one |
| v1 scope | Rhythm only — all 6 algorithms + Evolve | Harmony engine (chord graphs, Markov melody) is complex; defer to v2 |
| Phrase engine | Direct phrase writing via `instrument.phrases[n]` API | Avoids `pattrns set_script` which has unconfirmed Tool-side API |
| Voice model | `{instrument, note, pitch_mode}` per lane | Multiple lanes can share same instrument (drum kit use case) |
| Max voices | 8 lanes UI cap; 12 lanes per instrument (phrase note column limit) | Practical ceiling; 12 = Renoise phrase max note columns |

---

## Voice Lane Model

Each lane has:
- **Instrument** — select any loaded Renoise instrument (VST or sampler)
- **Note** — MIDI note 0–119; e.g. C1 for kick, D1 for snare on same 808 VST
- **Pitch mode:**
  - `FIXED` — algorithm drives *when* the note fires (drums/perc)
  - `SCALE_WALK` — algorithm also drives *which* note fires each step (melody/bass)

**Phrase consolidation:** lanes sharing the same instrument → one phrase, one note column per lane. Lanes on different instruments → separate phrase per instrument.

---

## File Structure

```
algorhythm.xrnx/
├── manifest.xml
├── main.lua                       Entry point — menu, keybinding, timer registration
└── src/
    ├── algorithms/
    │   ├── euclidean.lua          Bjorklund, generate(params) → bool[]         [Phase 1]
    │   ├── bresenham.lua          Multi-voice interlocking                      [Phase 2]
    │   ├── cellular.lua           1D rules 30/90/110                            [Phase 2]
    │   ├── markov.lua             Weighted transition walk                      [Phase 2]
    │   ├── logistic.lua           Chaos source, r parameter                     [Phase 2]
    │   ├── perlin.lua             Smooth organic modulation                     [Phase 2]
    │   └── random_weighted.lua    Density-based weighted random                 [Phase 2]
    ├── output/
    │   ├── phrase_writer.lua      Step array → instrument.phrases[n]            [Phase 1]
    │   └── midi_output.lua        Real-time MIDI note on/off + NoteOff tracking [Phase 4]
    ├── state/
    │   ├── voice_state.lua        VoiceState: algorithm, params, output config  [Phase 1]
    │   ├── song_state.lua         Global: scale, root, seed, evolve, voices[]   [Phase 1]
    │   └── evolve.lua             tick() / randomize() / mutate()               [Phase 5]
    ├── ui/
    │   ├── main_panel.lua         Top-level dialog, single-voice layout         [Phase 1]
    │   ├── voice_lane.lua         Per-voice lane widget factory                 [Phase 3]
    │   ├── global_bar.lua         Scale/Root/Seed/Evolve controls               [Phase 3]
    │   └── output_bar.lua         Dual output routing controls                  [Phase 4]
    └── utils/
        ├── scales.lua             8 scale definitions, quantize(), note_name()  [Phase 1]
        └── midi_utils.lua         BPM math, MIDI message encoding               [Phase 1]
```

---

## Development Setup

1. Create a symlink (or copy) the `algorhythm.xrnx` folder to Renoise's Tools directory:
   ```
   ~/Library/Preferences/Renoise/V3.5.x/Scripts/Tools/
   ```
2. In Renoise: `Help → Reload All Tools` to pick up changes
3. Enable `_AUTO_RELOAD_DEBUG = true` in `main.lua` during development (hot-reload on save)
4. Access via `Main Menu → Tools → AlgoRhythm...`

To distribute: ZIP the folder contents, rename to `algorhythm.xrnx`.

---

## Phase Breakdown

### Phase 0 — Architecture Spike ✅ *confirmed via API research*
- `instrument.phrases[n]:line(i).note_columns[j].note_value` — confirmed (range 0–119, 120=off, 121=empty)
- `instrument:insert_phrase_at(index)` — confirmed
- `renoise.Midi.available_output_devices()` / `create_output_device()` — confirmed
- `renoise.tool():add_timer(fn, ms)` — confirmed (used for BPM-sync MIDI ticks)
- `renoise.song().transport.playback_pos` — confirmed (`.sequence`, `.line` fields)
- Phrase max note columns: **12** — confirmed (`MAX_NUMBER_OF_NOTE_COLUMNS = 12`)
- Phrase max lines: 512

### Phase 1 — Project Skeleton + Euclidean MVP 🔄 *in progress*
- [ ] `manifest.xml` + `main.lua` tool scaffold
- [ ] `voice_state.lua` + `song_state.lua` data structures
- [ ] `scales.lua` — 8 scale definitions, `quantize()`, `note_name()`
- [ ] `midi_utils.lua` — BPM math, message encoding
- [ ] `euclidean.lua` — Bjorklund algorithm, ~20 lines
- [ ] `phrase_writer.lua` — single voice, single note column
- [ ] `main_panel.lua` — single-voice UI: scale, root, seed, algorithm chooser, steps/pulses/offset, instrument/note pickers, 16-step grid, Render button

**Deliverable:** Load tool in Renoise, set euclidean 4/16, click Render, see pattern appear in instrument.phrases[1]

### Phase 2 — Full Algorithm Library
- [ ] `bresenham.lua` — multi-voice distribution, ~30 lines
- [ ] `cellular.lua` — 1D rules 30/90/110, ~40 lines  
- [ ] `logistic.lua` — chaos source, ~15 lines
- [ ] `perlin.lua` — smooth noise, ~50 lines
- [ ] `markov.lua` — weighted transition walk, ~40 lines
- [ ] `random_weighted.lua` — density-based, ~20 lines
- All algorithms expose: `generate(params) → bool[]` (uniform contract)

**Deliverable:** All 6 algorithms selectable in the chooser, each producing a correct pattern in the step grid

### Phase 3 — Multi-voice UI Panel
- [ ] Up to 8 voice lanes, dynamic add/remove
- [ ] Per-lane: algorithm pills, Steps/Pulses/Offset/Probability, note picker, pitch_mode toggle
- [ ] Step grid expands to show full `voice.steps` count (not just 16)
- [ ] Global bar: Scale, Root, Seed/Variation, Evolve (Off/Slow/Fast)
- [ ] Action bar: Randomize, Mutate, ▶ Playing, ⟳ Render
- [ ] Refactor into `voice_lane.lua` and `global_bar.lua` sub-modules

### Phase 4 — Dual Output Routing
- [ ] `midi_output.lua` — `renoise.Midi.create_output_device()`, note-on/off, NoteOff tracking
- [ ] `output_bar.lua` — per-voice output mode toggle (Phrase / MIDI), device + channel pickers
- [ ] Phrase consolidation: lanes on same instrument → one phrase with multiple note columns
- [ ] `SCALE_WALK` pitch mode: for melody lanes, algorithm drives which note fires
- [ ] **Critical:** NoteOff tracking — all sent note-ons must be resolved on Stop/Mutate/close (prevent hanging MIDI notes)
- [ ] BPM sync: `add_timer` tick rate derived from `song.transport.bpm`

**Deliverable:** Kick + Snare on same 808 VST, different notes, both write correctly to one phrase as two columns

### Phase 5 — Evolve System
- [ ] Bar-boundary detection via `transport.playback_pos.line` observer
- [ ] Per-algorithm natural mutation deltas:
  - Euclidean: ±1 pulse, ±1 offset rotation
  - Cellular: auto-step to next generation (inherently evolving)
  - Logistic: nudge `r` ±0.01 (stable → periodic → chaos)
  - Perlin: advance time offset (smooth continuous drift)
  - Markov: adjust transition weights ±5%
  - Bresenham: rotate weight vector
- [ ] Slow mode = mutate every 4 bars; Fast = every bar
- [ ] Randomize = full reseed; Mutate = ±10% delta from current state

### Phase 6 — Expression Details
- [ ] Swing: offset even-step timing via `note_columns[n].delay_value` (0–255)
- [ ] Velocity humanization: Van der Corput quasi-random distribution
- [ ] Note length variation per step

### Phase 7 — Presets + Polish
- [ ] Save/load state as JSON via `io.open()` in Renoise tool data folder
- [ ] 6–8 built-in starter grooves as presets
- [ ] Error handling: no instruments loaded, no MIDI device, transport-off edge cases
- [ ] In-tool help text

---

## v2 Roadmap (Harmony Engine)

Deferred from v1 — the features that make AlgoRhythm more than a rhythm tool:

- **Weighted chord transition graphs** — 11 styles (aeolian minor, dorian, lydian, functional major, etc.), each a Lua table of chord → weighted successors (~200 lines)
- **Narmour melody cognition** — Implication-Realization model: gap-fill, Process/Reversal/Closure rules applied to melody generation (~150 lines, optional)
- **Voice leading** — automatic chord inversion selection to minimize voice movement (~60 lines)
- **Form sections** — intro/verse/chorus state machine driven by bar count
- **Conductor signals** — LFO/ramp over global intensity (affects density/velocity across all voices)

---

## Algorithm Reference

| Algorithm | Params | Character |
|---|---|---|
| Euclidean | steps, pulses, offset | Even distribution of N pulses in M steps; classic techno/afrobeat feel |
| Bresenham | steps, weights[] | Multi-voice interlocking; no two voices hit simultaneously |
| Cellular | rule (30/90/110), generation | Evolves pattern each bar; complex emergent structures |
| Markov | transitions{}, seed | Weighted random walk; pattern has "memory" |
| Logistic | r (2.0–4.0), steps | Smooth near r=3, increasingly chaotic toward r=4 |
| Perlin | time_offset, threshold | Organic drift; smoothly morphing patterns |
| Random | density (0–1), seed | Weighted probability per step; controllable density |

---

## Key Risks

1. **Phrase write + playback timing** — phrase must be written before Renoise processes the next loop; use `looping = true` to ensure pattern loops correctly
2. **NoteOff on mutate** — when Evolve or Mutate fires mid-pattern, any in-flight MIDI notes must receive note-off first
3. **Instrument index drift** — if user adds/removes instruments, popup indices become stale; instrument picker needs a refresh mechanism (Phase 3)
