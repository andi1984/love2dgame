//! Shared states, resources, events, and coordinate helpers.

use bevy::prelude::*;
use racing_sim::car::Car;
use racing_sim::game::RaceState;
use racing_sim::menu::MenuState;
use racing_sim::pause::PauseState;
use racing_sim::persistence::SaveData;
use racing_sim::rng::GameRng;
use racing_sim::track::{Track, TrackConfig};
use racing_sim::tracks::TrackList;

pub const SCREEN_W: f32 = 800.0;
pub const SCREEN_H: f32 = 600.0;

/// Game state machine (replaces state.lua; Bevy states are the state machine).
#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum AppState {
    #[default]
    Menu,
    Controls,
    Racing,
    Paused,
}

/// Where the Controls screen returns to (it is reachable from Menu and Paused).
#[derive(Resource, Debug, Clone, Copy)]
pub struct ControlsReturnTo(pub AppState);

impl Default for ControlsReturnTo {
    fn default() -> Self {
        Self(AppState::Menu)
    }
}

/// Gameplay RNG (replaces Lua's global math.random).
#[derive(Resource)]
pub struct SimRng(pub GameRng);

impl Default for SimRng {
    fn default() -> Self {
        // Seed from wall clock, like the Lua original's os.time()
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x1234_5678);
        Self(GameRng::new(seed))
    }
}

/// All known track configurations (defaults + user-generated).
#[derive(Resource)]
pub struct Tracks(pub TrackList);

/// The active track geometry during a race.
#[derive(Resource, Default)]
pub struct CurrentTrack(pub Option<Track>);

/// Sim cars; index 0 is the player. Entities mirror these each frame.
#[derive(Resource, Default)]
pub struct Cars(pub Vec<Car>);

/// Race progress (laps, timer, countdown).
#[derive(Resource)]
pub struct Race(pub RaceState);

impl Default for Race {
    fn default() -> Self {
        Self(RaceState::new(1))
    }
}

#[derive(Resource)]
pub struct Menu(pub MenuState);

#[derive(Resource, Default)]
pub struct Pause(pub PauseState);

/// NPC brains loaded from disk at startup.
#[derive(Resource, Default)]
pub struct SavedNpcData(pub Option<SaveData>);

/// Start (or restart) a race on the given track configuration.
#[derive(Event, Clone)]
pub struct StartRace(pub TrackConfig);

/// Return to the main menu (saves NPC brains first).
#[derive(Event)]
pub struct ReturnToMenu;

/// Marker: everything belonging to the race scene (despawned on menu return).
#[derive(Component)]
pub struct RaceScene;

/// Convert sim coordinates (origin top-left, y down, 800x600) to Bevy world
/// coordinates (origin center, y up). `z` picks the draw layer.
pub fn to_world(x: f64, y: f64, z: f32) -> Vec3 {
    Vec3::new(x as f32 - SCREEN_W / 2.0, SCREEN_H / 2.0 - y as f32, z)
}

/// Sim angle (y-down, clockwise-positive) to Bevy rotation.
pub fn to_world_rot(angle: f64) -> Quat {
    Quat::from_rotation_z(-angle as f32)
}

/// Cursor position in sim coordinates (top-left origin, y down) — identical to
/// Love2D mouse coordinates, so all ported hit-tests work unchanged.
pub fn cursor_sim_pos(window: &Window) -> Option<(f64, f64)> {
    window.cursor_position().map(|p| (p.x as f64, p.y as f64))
}

pub fn srgb(c: [f32; 3]) -> Color {
    Color::srgb(c[0], c[1], c[2])
}
