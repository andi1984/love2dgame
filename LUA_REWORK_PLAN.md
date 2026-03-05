# Lua Best Practices Rework Plan

## Context
Comprehensive audit of the Love2D racing game identified ~50+ Lua best practice violations across all modules. This plan applies the project's Lua skill guidelines: caching globals, eliminating hot-path allocations, fixing bugs, improving module patterns, and removing code duplication.

---

## Phase 1 — Bug Fix

### 1.1 Fix infinite recursion in `trackgen.lua` (~line 426)
- `if seed < (seed + 5)` is always true — causes infinite recursion on self-intersecting tracks
- Fix: introduce an `attempt` counter parameter, cap retries at 5
- **File:** `trackgen.lua`

---

## Phase 2 — Cache `math.*` Globals

Add `local abs, sqrt, min, max, cos, sin = math.abs, math.sqrt, ...` at the top of each file, then replace all `math.X(...)` calls with `X(...)`.

| File | Globals to cache |
|------|-----------------|
| `collision.lua` | cos, sin, huge, min, max, abs |
| `ai.lua` | atan2, abs, sqrt, max, min, cos, sin, log, random, pi + add `TWO_PI = 2 * pi` constant |
| `car.lua` | abs, min, max, cos, sin, sqrt, random, pi |
| `nnet.lua` | exp, tanh, sqrt, log, cos, random, pi |
| `track.lua` | sqrt, huge, floor, atan2, random, pi |
| `damage.lua` | abs, sqrt, max, min |
| `trackgen.lua` | floor, sqrt, abs, min, max, cos, sin, atan2, pi |
| `helpers.lua` | pi, cos, sin |
| `persistence.lua` | floor, abs |
| `draw.lua` | floor, min, max, abs, ceil, cos, sin, pi, random |
| `audio.lua` | floor, pi, sin, exp |
| `particles.lua` | cos, sin, random |

---

## Phase 3 — Hot-Path Allocation Fixes

### 3.1 `main.lua` — reuse per-frame tables
- `playerInput` table → module-level, mutate fields in update
- `prevLaps` table → module-level, reuse
- Fallback car `{speed=0,...}` → module-level `DUMMY_CAR` constant

### 3.2 `damage.lua` — module-level constant
- `{"FL","FR","RL","RR"}` literal created on every call (lines 83, 179) → `local WHEEL_POSITIONS`

### 3.3 `draw.lua` — module-level constants and hoisted closures
- `poleColor` → `POLE_COLOR` constant
- `tireLayout` → `TIRE_LAYOUT` constant
- `tireOrder` → reuse pre-allocated `_tireOrder` table, overwrite values per car
- `sorted` in `draw.positions` → reuse module-level table
- `healthColor` closure inside `draw.hud` → module-level local function

### 3.4 `ai.lua` — reuse stuck override table
- `getStuckOverride` returns new table every frame per stuck NPC → cache `car._stuckInput` table, reuse it

---

## Phase 4 — Algorithm Improvements

### 4.1 `ai.lua` line 121 — eliminate sqrt in raycast inner loop
- `math.sqrt(localMin) > halfWidth` → `localMin > halfWidthSq` (precompute `halfWidthSq = halfWidth * halfWidth`)
- Saves ~1500 sqrt calls per NPC per frame

### 4.2 `collision.lua` — deduplicate cos/sin in satTest
- `getCorners` computes cos/sin of car.angle, then `satTest` recomputes them for axes
- Combine into `getCornersAndAxes` that returns both, halving trig calls

### 4.3 `track.lua` — squared distance in isOnTrack/getTrackPercent
- Replace `sqrt(dx*dx+dy*dy)` with squared distance comparison
- Eliminates ~250 sqrt calls per isOnTrack call

---

## Phase 5 — Code Quality

### 5.1 `track.lua` — make internal functions local
- `track.generateCurbs`, `track.generateTrees`, `track.generateSurfaceZones` → `local function`
- Only called from within track.lua

### 5.2 `damage.lua` — promote closures to module-level locals
- `getSide`, `applyTireDmg`, `applySuspDmg` defined inside `applyCollision` → module-level `local function`
- They capture no upvalues, so this is a pure promotion

### 5.3 `helpers.lua` — DRY ellipse vertex builder
- `drawFilledEllipse` and `drawEllipseOutline` share identical vertex loop
- Extract `buildEllipseVertices` + `SEGMENTS` constant

### 5.4 Deduplicate `catmullRom`
- Identical function in `track.lua` and `trackgen.lua`
- Create `spline.lua` with shared implementation, require from both

### 5.5 `track.lua` — fix global RNG mutation
- `generateTrees` calls `math.randomseed(77)` / `math.randomseed(os.time())` corrupting global PRNG
- Use local `makeRng(77)` pattern (same as trackgen.lua already does)

### 5.6 `devmenu.lua` — DRY slider computation
- Duplicate slider value calc in `mousepressed` and `mousemoved` → extract `applySliderAt` helper

---

## Verification
After each phase, run `lua tests/run.lua` — all 135 tests must pass. Love2D modules (draw, audio, particles, helpers, devmenu, main) require manual `love .` verification.

## Files Modified (total: 16)
`trackgen.lua`, `collision.lua`, `ai.lua`, `car.lua`, `nnet.lua`, `track.lua`, `damage.lua`, `helpers.lua`, `persistence.lua`, `draw.lua`, `audio.lua`, `particles.lua`, `main.lua`, `devmenu.lua`, `spline.lua` (new), `game.lua` (minor)
