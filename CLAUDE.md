# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the game (requires Love2D 11.5+)
love .

# Run all tests (pure Lua, no Love2D needed)
lua tests/run.lua

# Lint
luacheck . --config .luacheckrc
```

## Architecture

Love2D 2D racing game with neural network AI opponents. Modules split into two layers:

**Pure Lua (no Love2D dependency, independently testable):** car.lua, ai.lua, track.lua, trackgen.lua, nnet.lua, evolution.lua, game.lua, state.lua, collision.lua, damage.lua, helpers.lua, menu.lua, pause.lua, persistence.lua, npc_profiles.lua, tracks.lua

**Love2D-dependent:** main.lua (entry point/game loop), draw.lua (rendering), audio.lua (procedural 8-bit synthesis), particles.lua, devmenu.lua

### Data flow

`main.lua` orchestrates the game loop:
1. Player input from keyboard; NPC input from `ai.getSensorInputs()` → `nnet.forward()` → `ai.outputToInput()`
2. `Car:update()` applies physics with damage modifiers from `damage.lua`
3. `collision.checkAll()` runs SAT-based OBB detection + impulse resolution
4. `game.checkFinishLine()` tracks lap progress
5. On race end: `evolution.evolveAfterRace()` runs (1+1)-ES per NPC, then `persistence.save()` serializes brains

### NPC AI system

- Neural network: fixed {13, 16, 4} architecture (13 sensor inputs, 16 hidden tanh, 4 sigmoid outputs)
- 13 inputs: angle error, center distance, speed ratio, curvature, 2 look-ahead angles, grip, on-track flag, 5 raycasts
- 4 outputs: throttle, brake, left_steer, right_steer → converted to continuous `input.steer` in [-1, 1]
- `nnet.createSeeded()` pre-wires brains for immediate track-following ability
- Each NPC evolves independently after each race; brains saved to `npc_brains.lua` (gitignored)

### Track system

- `trackgen.lua` generates tracks procedurally from a seed using Catmull-Rom splines
- 3 default tracks (seeds 42, 137, 314) + user-generated tracks saved to `custom_tracks.lua` (gitignored)
- Surfaces: track, curbs, grass — each with grip/bumpiness values

## Testing

Tests live in `tests/` with a custom runner (`tests/run.lua`) providing `describe()`, `it()`, `expect_true/false/eq/near()`. Each pure Lua module has a corresponding `test_*.lua` file. Tests require only standard Lua (no Love2D).

## Code conventions

- Module pattern: `local M = {} ... return M`
- snake_case for variables/functions, PascalCase for class-like tables (Car)
- State machine via `state.current` ∈ {menu, racing, paused, controls}
- Linter: luacheck with `std="luajit"`, warnings 212/213/611/612/631 suppressed

## CI/CD

GitHub Actions pipeline (`.github/workflows/ci.yml`): lint → test → package (.love ZIP) → platform builds (Linux AppImage, Windows bundle, macOS .app) → GitHub Release on version tags (`v*.*.*`).
