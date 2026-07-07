# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the game (Rust/Bevy)
cargo run

# Jump straight into a race (debug/testing hook; value = track index)
AUTOSTART_RACE=0 cargo run

# Run all tests (sim crate is pure logic, no Bevy needed)
cargo test --workspace

# Lint / format
cargo clippy --workspace
cargo fmt --all
```

Linux build dependency: ALSA dev headers (`sudo apt install libasound2-dev`).
Without them, `.cargo/config.toml` points pkg-config at a local `.alsa-shim/`
directory (gitignored); recreate it by extracting `libasound2-dev` there, or
just install the package system-wide.

## Architecture

2D racing game with neural network AI opponents, written in Rust on Bevy 0.16.
Migrated from Love2D/Lua — the original `.lua` files remain in the repo root as
reference until parity sign-off, but the Rust code is the game.

Two-crate workspace:

**`crates/sim` (racing-sim)** — pure game logic, no engine dependency, unit-tested:
`car.rs` (physics), `ai.rs` (sensors/driving errors), `nnet.rs`, `evolution.rs`,
`track.rs`, `trackgen.rs`, `spline.rs`, `collision.rs` (SAT OBB + impulses),
`damage.rs`, `game.rs` (race state), `menu.rs`/`pause.rs` (selection logic),
`npc_profiles.rs`, `persistence.rs` (JSON save/load), `tracks.rs`, `rng.rs`.

**Root binary (racing-game)** — Bevy layer in `src/app/`:
`race.rs` (game-loop orchestration, port of main.lua), `render.rs` (track meshes,
procedural grass image, car sprite trees), `hud.rs`, `menu_ui.rs`, `pause_ui.rs`,
`controls_ui.rs`, `devmenu_ui.rs` (F1 physics sliders), `particles_fx.rs`,
`synth.rs` (procedural 8-bit WAV synthesis), `audio_sys.rs` (sink management),
`shared.rs` (states/resources/coordinate conversion).

### Coordinate convention

The sim keeps Love2D coordinates (800x600, origin top-left, y down, angles
clockwise). `shared::to_world`/`to_world_rot` convert to Bevy world space at the
render boundary. Mouse hit-tests run directly in sim coordinates.

### Data flow

`app/race.rs::race_update` orchestrates each frame (mirrors old main.lua):
1. Player input from keyboard; NPC input from `ai::get_sensor_inputs` → `nnet::forward` → `ai::output_to_input` (+ sensor noise, lapses, stuck override)
2. `Car::update` applies physics with damage modifiers from `damage.rs`
3. `collision::check_all` runs SAT-based OBB detection, `collision::resolve` impulse resolution
4. `RaceState::check_finish_line` tracks lap progress (forward-crossing only)
5. On race end: `evolution::evolve_after_race` runs (1+1)-ES per NPC, then `persistence::save` writes brains

### NPC AI system

- Neural network: fixed {13, 16, 4} architecture (13 sensor inputs, 16 hidden tanh, 4 sigmoid outputs)
- 13 inputs: angle error, center distance, speed ratio, curvature, 2 look-ahead angles, grip, on-track flag, 5 raycasts
- 4 outputs: throttle, brake, left_steer, right_steer → continuous `steer` in [-1, 1]
- `nnet::create_seeded` pre-wires brains for immediate track-following ability
- Each NPC evolves independently after each race; brains saved to `npc_brains.json` (gitignored)

### Track system

- `trackgen.rs` generates tracks procedurally from a seed using Catmull-Rom splines; deterministic per seed via the MINSTD `Lcg` (same constants as the Lua original)
- 3 default tracks (seeds 42, 137, 314) + user-generated tracks saved to `custom_tracks.json` (gitignored)
- Surface zones (grip/bumpiness per track percentage), curbs, trees

## Testing

Unit tests live inline in each `crates/sim` module (`#[cfg(test)]`), mirroring
the old Lua test suite. `crates/sim/tests/race_integration.rs` runs a full 60s
AI race headless and checks invariants. Gameplay randomness goes through
`rng::GameRng` (seedable) — tests must not use global randomness.

## Code conventions

- Sim math is `f64` (matches Lua doubles); render layer converts to `f32`
- snake_case; sim modules expose free functions over a plain struct (mirrors the Lua module pattern)
- State machine: Bevy `States` enum `AppState` ∈ {Menu, Racing, Paused, Controls} in `shared.rs`
- rustfmt + clippy clean (`cargo clippy --workspace` has zero warnings)

## Legacy Love2D version

Original Lua implementation kept at repo root (`*.lua`, `tests/`): run with
`love .`, test with `lua tests/run.lua`, lint with `luacheck . --config .luacheckrc`.
Scheduled for removal once the Rust port has parity sign-off.

## CI/CD

`.github/workflows/ci.yml` still targets the legacy Lua pipeline; needs a
rewrite for Rust (fmt + clippy + test + release builds). Tracked in issues.
