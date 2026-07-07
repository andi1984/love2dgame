//! Racing Game — Bevy entry point (port of main.lua).
//! Pure game logic lives in the `racing-sim` crate; this binary wires it into
//! Bevy states, systems, rendering, UI, and audio.

mod app;

use bevy::prelude::*;
use racing_sim::menu::MenuState;
use racing_sim::persistence;
use racing_sim::tracks::TrackList;
use std::path::Path;

use app::shared::*;
use app::{audio_sys, controls_ui, devmenu_ui, hud, menu_ui, particles_fx, pause_ui, race, render};

fn main() {
    // Load persisted NPC brains and custom tracks; build the track list + menu.
    // Done before App construction so the resources exist when the initial
    // OnEnter(Menu) transition fires.
    let saved = persistence::load(Path::new(persistence::BRAINS_FILE));
    let mut tracks = TrackList::with_defaults();
    for config in persistence::load_tracks(Path::new(persistence::TRACKS_FILE)) {
        tracks.add(config);
    }
    let menu = MenuState::new(tracks.count());

    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "Racing Game".into(),
                resolution: (SCREEN_W, SCREEN_H).into(),
                resizable: false,
                ..default()
            }),
            ..default()
        }))
        .insert_resource(ClearColor(Color::srgb(0.18, 0.55, 0.13)))
        .init_state::<AppState>()
        // Resources
        .init_resource::<SimRng>()
        .init_resource::<CurrentTrack>()
        .init_resource::<Cars>()
        .init_resource::<Race>()
        .init_resource::<Pause>()
        .init_resource::<ControlsReturnTo>()
        .init_resource::<devmenu_ui::DevMenu>()
        .insert_resource(SavedNpcData(saved))
        .insert_resource(Tracks(tracks))
        .insert_resource(Menu(menu))
        .add_event::<StartRace>()
        .add_event::<ReturnToMenu>()
        // Startup
        .add_systems(
            Startup,
            (setup_camera, render::setup_grass, audio_sys::setup_audio),
        )
        // Menu
        .add_systems(OnEnter(AppState::Menu), menu_ui::spawn_menu)
        .add_systems(OnExit(AppState::Menu), menu_ui::despawn_menu)
        .add_systems(
            Update,
            (
                menu_ui::menu_keys,
                menu_ui::menu_mouse,
                menu_ui::rebuild_menu_on_change,
                menu_ui::draw_track_previews,
            )
                .chain()
                .run_if(in_state(AppState::Menu)),
        )
        // Controls screen
        .add_systems(OnEnter(AppState::Controls), controls_ui::spawn_controls)
        .add_systems(OnExit(AppState::Controls), controls_ui::despawn_controls)
        .add_systems(
            Update,
            controls_ui::controls_input.run_if(in_state(AppState::Controls)),
        )
        // Pause overlay
        .add_systems(OnEnter(AppState::Paused), pause_ui::spawn_pause)
        .add_systems(OnExit(AppState::Paused), pause_ui::despawn_pause)
        .add_systems(
            Update,
            (
                pause_ui::pause_keys,
                pause_ui::pause_mouse,
                pause_ui::rebuild_pause_on_change,
            )
                .chain()
                .run_if(in_state(AppState::Paused)),
        )
        // Racing
        .add_systems(OnEnter(AppState::Racing), spawn_hud_once)
        .add_systems(
            Update,
            (
                race::update_countdown,
                audio_sys::countdown_audio,
                race::race_update,
                render::sync_cars,
                particles_fx::update_particles,
                hud::update_hud,
                hud::update_countdown_text,
                hud::update_win_screen,
                devmenu_ui::devmenu_system,
                race::racing_keys,
            )
                .chain()
                .run_if(in_state(AppState::Racing)),
        )
        // Race lifecycle (must run in any state: StartRace can fire from Menu,
        // ReturnToMenu from Paused or Racing)
        .add_systems(Update, (race::start_race, race::return_to_menu))
        // Audio runs everywhere (music fades, loop management)
        .add_systems(Update, audio_sys::update_audio)
        .run();
}

fn setup_camera(
    mut commands: Commands,
    tracks: Res<Tracks>,
    mut start_events: EventWriter<StartRace>,
) {
    commands.spawn(Camera2d);

    // Debug/testing hook: AUTOSTART_RACE=<track index> jumps straight into a race.
    if let Ok(value) = std::env::var("AUTOSTART_RACE") {
        let idx: usize = value.parse().unwrap_or(0);
        if let Some(config) = tracks.0.get_by_index(idx) {
            start_events.write(StartRace(config.clone()));
        }
    }
}

/// HUD only exists while a race scene exists; spawn when entering Racing from
/// a fresh race (start_race despawns the old scene including the old HUD).
fn spawn_hud_once(
    commands: Commands,
    cars: Res<Cars>,
    race: Res<Race>,
    existing: Query<(), With<hud::HudRoot>>,
) {
    if existing.is_empty() && !cars.0.is_empty() {
        hud::spawn_hud(commands, cars, race);
    }
}
