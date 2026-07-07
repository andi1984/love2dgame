//! Pure game logic: physics, AI, track generation, race state.
//! No engine dependency — everything here is unit-testable with `cargo test`.

pub mod ai;
pub mod car;
pub mod collision;
pub mod damage;
pub mod evolution;
pub mod game;
pub mod menu;
pub mod nnet;
pub mod npc_profiles;
pub mod pause;
pub mod persistence;
pub mod rng;
pub mod spline;
pub mod track;
pub mod trackgen;
pub mod tracks;

/// 2D point in track/screen space (Love2D-style coordinates: origin top-left, y down).
#[derive(Debug, Clone, Copy, PartialEq, Default, serde::Serialize, serde::Deserialize)]
pub struct P {
    pub x: f64,
    pub y: f64,
}

impl P {
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
}
