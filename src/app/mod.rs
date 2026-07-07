//! Bevy app layer: rendering, input, UI, audio.
//! All game logic lives in the `racing-sim` crate; this layer feeds it input,
//! steps it, and mirrors its state into ECS entities.

pub mod audio_sys;
pub mod controls_ui;
pub mod devmenu_ui;
pub mod hud;
pub mod menu_ui;
pub mod particles_fx;
pub mod pause_ui;
pub mod race;
pub mod render;
pub mod shared;
pub mod synth;
