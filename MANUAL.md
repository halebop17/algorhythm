# AlgoRhythm — User Manual

AlgoRhythm is a Renoise tool that generates algorithmic rhythms and melodic phrases using mathematical pattern generators. It writes directly into Renoise native phrases, which you can then assign to instrument phrase maps and trigger from the pattern editor.

It was inspired by [Subsequence](https://github.com/halebop17/subsequence) — the goal was to have a simple way to use those same algorithms to create phrases directly inside Renoise.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Global Controls](#2-global-controls)
3. [Voice Lanes](#3-voice-lanes)
4. [Algorithms](#4-algorithms)
5. [Expression Lanes](#5-expression-lanes)
6. [Probability and Gate](#6-probability-and-gate)
7. [Pitch A / Pitch B / A/B Prob](#7-pitch-a--pitch-b--ab-prob)
8. [Ratchet](#8-ratchet)
9. [Delay](#9-delay)
10. [Presets](#10-presets)
11. [Render and Append](#11-render-and-append)
12. [Evolve and Mutate](#12-evolve-and-mutate)
13. [Audition](#13-audition)

---

## 1. Getting Started

Install the tool by placing the `algorhythm.xrnx` folder in your Renoise Tools directory:

```
~/Library/Preferences/Renoise/V3.5.x/Scripts/Tools/   (macOS)
%AppData%\Renoise\V3.5.x\Scripts\Tools\               (Windows)
```

Open via **Tools → AlgoRhythm** or the assigned keybinding.

The tool generates rhythm patterns and writes them as **Renoise phrases** into the instruments you select per voice. To hear the output, trigger those phrases from the pattern editor using phrase playback mode.

---

## 2. Global Controls

These settings affect all voices.

| Control | Description |
|---|---|
| **Scale** | Musical scale used to quantize pitch lanes (Chromatic = no quantization) |
| **Root Note** | Root of the selected scale (C, C#, D … B). Only affects pitch quantization — it has no effect on rhythm, step firing, or velocity. Has no effect at all when Scale is set to Chromatic |
| **Seed** | Starting seed for all random generators. Same seed + same settings = same pattern |
| **Evolve** | Off / Slow / Fast — automatically mutates pattern parameters over time as the song plays. Slow mutates every 4 bars, Fast every bar |
| **Phrase Length** | Total number of lines written to the phrase. **Auto (0)** uses each voice's own step count as the phrase length. Fixed values (16, 32, 64, 128, 256, 512) tile and mutate the pattern across multiple blocks to fill the full phrase — see [Section 13](#13-audition) for how this interacts with Audition playback |

---

## 3. Voice Lanes

Each voice lane is one rhythmic generator targeting one instrument. You can have up to 6 voices.

### Header Row

The collapsible header shows the instrument name, the step grid, and the algorithm name. Click the **v** button to expand/collapse the voice parameters.

### Parameters

| Control | Description |
|---|---|
| **Algorithm** | Which pattern generator to use (see Section 4) |
| **Steps** | Number of steps in the pattern (1–16) |
| **Instrument** | Which Renoise instrument this voice writes to |
| **Note** | MIDI note value (0–119). Used as the base note for each hit. C-4 = 48 |
| **Prob %** | Global fire probability. Each active step rolls this chance. 100% = always fires, 50% = fires half the time (see Section 6) |
| **Pulses** | Number of hits distributed across Steps (Euclidean and Bresenham only) |
| **Offset** | Rotates the pattern left or right by N steps |

### Step Grid

16 small squares showing the current pattern state:
- **Green** — active hit within voice.steps
- **Mid-gray** — silent step within voice.steps
- **Near-black** — beyond the current step count (inactive region)

### Removing a Voice

Click the **x** button in the header row to remove a voice.

---

## 4. Algorithms

Each algorithm generates a boolean step pattern (which steps fire, which don't).

### Euclidean

Distributes a number of pulses as evenly as possible across all steps using the Bresenham/Bjorklund algorithm. This produces the traditional off-beat African and Middle Eastern rhythmic patterns.

- **Pulses** — how many hits to place
- **Steps** — total steps in the cycle
- **Offset** — rotate the pattern

**Example patterns:**
- E(3, 8) → `■ □ □ ■ □ □ ■ □` — classic tresillo
- E(5, 16) → `■ □ □ ■ □ □ ■ □ □ ■ □ □ ■ □ □ □`
- E(8, 16) → perfectly even, every other step

The pattern becomes most interesting when pulses do not divide evenly into steps (e.g. 5 pulses in 16 steps, 7 in 16, 3 in 8).

### Bresenham

Similar to Euclidean but uses a weighted Bresenham line distribution. Designed to interlock with other voices — it tends to avoid simultaneous hits with adjacent Bresenham voices sharing the same step count.

- **Pulses**, **Steps**, **Offset** — same as Euclidean

### Cellular

Uses 1D cellular automaton rules (Rule 30, 90, or 110) to generate a step pattern. The initial row is seeded from the global seed and the pattern evolves each bar when Evolve is active.

- Rule 30 → chaotic, unpredictable
- Rule 90 → self-similar, fractal-like
- Rule 110 → complex, intermediate structure

### Markov

A weighted Markov chain walks between hit/rest states. Higher **self-loop weight** creates patterns with more momentum (long runs of notes or rests). Lower self-loop weight creates rapid alternation.

### Logistic

Uses the logistic map equation: `x(n+1) = r × x(n) × (1 − x(n))`

The **r** parameter controls behavior:
- r < 3.0 → stable, repeating pattern
- r ≈ 3.5 → period-2 / period-4 oscillation
- r > 3.8 → fully chaotic, dense unpredictable pattern

### Perlin

Generates smooth, organically-drifting patterns using Perlin-style noise. Steps near the noise threshold fire, steps far below it rest. Advancing the time offset (via Evolve) produces slowly morphing patterns that never feel sudden or jarring.

- **Density** — threshold that determines how many steps fire

### Random

Each step fires independently at the given **Density** probability. No mathematical relationship between steps — fully stochastic. Simple and immediate.

### Straight

Evenly-spaced hits at a fixed rhythmic division. No complexity — every Nth step fires.

- **Division** — 1/4 (quarter notes), 1/8 (eighth notes), 1/16 (sixteenth notes), or triplet

---

## 5. Expression Lanes

Expand the **Expr** panel inside any voice lane to access per-step expression control. Every voice has 5 expression lanes accessible from the **Lane** dropdown.

Each lane shows 16 vertical sliders — one per step — and a control row above them.

### Lane Controls

| Button | Description |
|---|---|
| **Rand** | Randomizes all active steps in the current lane |
| **Reset** | Resets all active steps to the default value for that lane |

### Lane Types

| Lane | Range | Description |
|---|---|---|
| **Velocity** | 1–127 | Per-step note velocity (volume of each hit) |
| **Gate %** | 1–100 | Per-step note length as a fraction of step duration (see Section 6) |
| **Pitch A** | 0–119 | Per-step note value for the primary pitch |
| **Pitch B** | 0–119 | Per-step note value for the alternate pitch |
| **A/B Prob** | 0–100 | Per-step probability of playing Pitch A vs Pitch B (see Section 7) |
| **Ratchet** | 1–4 | Per-step retrigger count — how many times the note fires within one step (see Section 8) |
| **Delay** | 0–255 | Per-step timing nudge — how many ticks late the note is triggered (see Section 9) |

### Octave Range (Pitch A and Pitch B only)

When Pitch A or Pitch B is selected, an **Octave Range** row appears showing two valueboxes (e.g. `3 to 5`). This range is used only by the **Rand** button when randomizing pitch values — notes are picked from within this octave range, respecting the active Scale and Root Note.

---

## 6. Probability and Gate

These two controls are independent — they control different aspects of each note.

### Prob % (Fire Probability)

**What it does:** Decides whether an active step fires at all.

When the pattern generator marks a step as active (a hit), Prob % rolls a random number. If the roll fails, the step is silenced for that render. This is a global per-voice control — it applies the same chance to every step equally.

- **100%** — every active step always fires (deterministic)
- **50%** — each active step has a 50% chance of firing
- **0%** — no steps ever fire (voice is effectively silent)

Prob % is set in the main voice parameters row, not inside the Expr panel.

### Gate % Lane (Note Length)

**What it does:** Controls how long each note rings before a NOTE_OFF is inserted.

Gate % is a per-step value (in the Expr panel) that controls the duration of the note as a fraction of the step's time slot.

- **100** — note sustains for the full step duration
- **50** — note plays for half the step, then cuts off
- **1** — very short stab, nearly percussive

**Important:** Gate % only has an audible effect when **Phrase Length is greater than Steps**. For example, with 128 phrase lines and 16 steps, each step occupies 8 lines — there is space for a NOTE_OFF to be inserted inside that window. With 16 steps and 16 phrase lines (1 line per step), there is no room between steps and gate has no effect. This is a Renoise phrase architecture constraint.

### Summary

| Control | Location | Per-step? | What it controls |
|---|---|---|---|
| Prob % | Voice params row | No (global) | Whether the step fires at all |
| Gate % | Expr lane | Yes | How long the note sustains |

---

## 7. Pitch A / Pitch B / A/B Prob

AlgoRhythm supports two pitch values per step, selected randomly on each render.

### Pitch A and Pitch B

Each step has two assignable MIDI notes — Pitch A and Pitch B. When the pattern fires a hit on a given step, it randomly chooses between the two pitches for that step. This creates melodic variation without full randomization.

Both pitch values are quantized to the active **Scale** and **Root Note** when Scale is set to anything other than Chromatic.

### A/B Prob Lane

The **A/B Prob** lane controls the per-step probability of playing Pitch A vs Pitch B.

| Slider value | Behavior |
|---|---|
| **100** | Always plays Pitch A on this step |
| **50** | Equal chance of Pitch A or Pitch B |
| **0** | Always plays Pitch B on this step |

Because A/B Prob is per-step, you can shape the melodic behavior differently for each position in the sequence — for example, always playing Pitch A on the downbeat (step 1) while mixing randomly on off-beats.

### The Note Field and Pitch Maps

The **Note** field (in the voice parameters row) is the *base pitch anchor*. Its relationship to the pitch lanes:

| Situation | What happens |
|---|---|
| Voice is created | All Pitch A and Pitch B steps initialize to the Note field value |
| You drag a pitch slider | That step becomes independent — manually set, no longer tracking Note |
| You click **Rand** on a pitch row | All active steps get random notes — fully decoupled from Note |
| You change the **Note** field | Any step still sitting on the *old* base note shifts to the new one; manually customized or randomized steps are left unchanged |
| You click **Reset** on Pitch A or Pitch B | All steps snap back to the current Note field value |

In short: Note is the "home pitch". The sliders are the actual per-step values. Changing Note and changing sliders do not silently overwrite each other — the Note field only moves steps that are still at the previous default.

### Rand for Pitch Lanes

When you click **Rand** on the Pitch A or Pitch B lane, notes are picked randomly from the **Octave Range** (always visible below the lane controls), respecting the active Scale and Root Note. If Scale is set to Chromatic, notes are picked freely within the octave range.

Clicking **Rand** on the A/B Prob lane assigns a random probability (0–100) to each step independently.

---

## 8. Ratchet

The **Ratchet** expression lane sets how many times a note retriggers within one step.

| Value | Behavior |
|---|---|
| **1** | Normal — note fires once (no ratchet) |
| **2** | Note fires twice, evenly spaced within the step |
| **3** | Note fires three times |
| **4** | Note fires four times (maximum) |

**Important:** Ratchet only works when **Phrase Length is greater than Steps**, giving each step multiple phrase lines to fill. With 1 line per step there is no space for sub-hits.

Example: 128 lines / 16 steps = 8 lines per step. A ratchet of 4 places notes at lines 1, 3, 5, and 7 of that step window.

Ratchet sub-hits use the same note and velocity as the main hit. Gate % is applied to the main hit only.

---

## 9. Delay

The **Delay** expression lane nudges each note later in time by a per-step amount.

- Range: **0–255** (Renoise delay ticks, same unit as the phrase `delay_value` column)
- **0** = no delay (note fires exactly on the step)
- **127** = roughly half a step late (depends on song BPM and lines-per-beat)
- **255** = nearly a full step late

Use small values (1–30) for subtle swing/shuffle feel on individual steps. Random delay across steps creates a humanized, slightly-off-the-grid feel.

Delay works at all Phrase Length settings including 1 line per step.

---

## 10. Presets

The **Preset bar** sits above the Global Controls and lets you save, load, and delete full snapshots of the current session state.

### Loading a Preset

1. Select a preset from the **Preset** dropdown.
2. Click **Load** to apply it.

Loaded presets overwrite all voice algorithm settings and expression maps. **Instrument assignments are always preserved** — the preset never changes which Renoise instrument a voice targets.

### Built-in Presets

AlgoRhythm ships with 8 ready-to-use groove templates marked with a ★ prefix:

| Preset | Description |
|---|---|
| **★ 4-on-the-Floor** | Straight quarter-note kick pattern |
| **★ Tresillo** | Classic 3-against-8 euclidean feel |
| **★ Clave 3-2** | Son clave as E(5,16) |
| **★ House Groove** | E(4,16) kick + E(2,16) snare offset |
| **★ Breakbeat** | E(5,16) with humanized velocity map |
| **★ Perlin Drift** | Organically shifting Perlin pattern |
| **★ Trap Hats** | Dense 16th-note hats with velocity dips and ratchets |
| **★ Acid Bassline** | E(9,16) with dual pitched notes and gate variation |

Built-in presets cannot be deleted.

### Saving a User Preset

1. Type a name in the **Save as** text field.
2. Click **Save**.

If a user preset with that name already exists it is overwritten. The preset captures:
- Global Scale, Root Note, and Phrase Length
- All voice algorithm, step, and expression map settings
- Instrument assignments are **not** captured

### Deleting a User Preset

Select the user preset from the dropdown, then click **Delete**. Built-in presets (★) cannot be deleted.

### Where Presets Are Stored

User presets are saved to a `user_presets.lua` file inside the tool's own bundle folder:

```
~/Library/Preferences/Renoise/V3.5.x/Scripts/Tools/com.algorhythm.xrnx/user_presets.lua   (macOS)
%AppData%\Renoise\V3.5.x\Scripts\Tools\com.algorhythm.xrnx\user_presets.lua               (Windows)
```

It is a plain text file you can open in any editor. **Note:** if you reinstall or replace the tool folder, this file will be overwritten — back it up separately if you have presets you want to keep.

---

## 11. Render and Append

### Render to Phrase

Writes the current pattern for all voices into the **currently selected phrase** of the instrument assigned to Voice 1. If the phrase does not exist yet, it is created.

The phrase slot targeted is whichever phrase is selected in Renoise's instrument/phrase editor at the time you click Render.

### Append Phrase

Adds a new phrase to the instrument's phrase list. The number of phrases to append is controlled by the valuebox next to the button (1–16).

When appending more than 1 phrase, each successive phrase is **mutated** before writing — pulses and offset are shifted slightly so consecutive phrases have natural variation. Voice parameters are restored after appending so your settings are not permanently changed.

---

## 12. Evolve and Mutate

### Mutate Button

Applies a small random change to each voice's pattern parameters (±1 on pulses and offset) and immediately re-renders to the current phrase. Use this to explore variations of your current pattern.

### Randomize Button

Fully re-randomizes all voice parameters from a new random seed and re-renders. A larger change than Mutate.

### Evolve (Global)

When set to **Slow** or **Fast**, AlgoRhythm automatically mutates voice parameters on each bar boundary while the song is playing.

- **Slow** — mutates every 4 bars
- **Fast** — mutates every bar

The mutation type depends on the algorithm:
- Euclidean / Bresenham — rotates the offset
- Cellular — advances the CA generation
- Logistic — nudges the r parameter toward chaos
- Perlin — advances the time offset for smooth drift

---

---

## 13. Audition

The Audition feature lets you preview patterns through your instruments in real time, without needing to render to a phrase or start Renoise's transport.

### Per-voice Audition (▶)

Each voice header has a **▶** button. Clicking it:

1. Bakes the voice's pattern (applying any Evolve mutations across blocks, just like Render/Append would).
2. Starts a step-sequencer timer that fires MIDI notes through the voice's assigned instrument at the current BPM and LPB.
3. The button turns green and shows **■** while active. Click **■** to stop.

### Audition All (▶ All)

The **▶ All** button in the action bar auditions every voice simultaneously. All voices are baked at once (same as collecting patterns for Render), so polyrhythm between voices is preserved.

Click **■ All** to stop all voices at once.

### Phrase Length and Audition

The Phrase Length setting directly controls how audition behaves:

| Phrase Length | Audition behavior |
|---|---|
| **Auto (0)** | Each voice loops its own pattern indefinitely (true polyrhythm — a 3-step voice and an 8-step voice drift against each other). Click ■ to stop manually. |
| **Fixed (e.g. 128)** | All voices receive a fully baked 128-step pattern with mutations embedded between blocks. Audition plays through exactly 128 steps, then auto-stops. The button resets automatically. |

With a fixed Phrase Length, different per-voice step counts produce natural variation: a voice set to 16 steps will loop 8 times through its base pattern (with mutations between each cycle) over 128 steps.

### Notes

- Audition uses `trigger_instrument_note_on/off` — it works regardless of whether Renoise's transport is running.
- Starting a new audition automatically stops any currently running audition.
- Audition reads the velocity map and pitch maps from each voice's expression lanes, wrapping them correctly for baked patterns.

---

*This manual is updated alongside the tool as new features are added.*
