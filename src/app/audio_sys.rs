//! Audio playback systems (port of audio.lua's state machine).
//! Looping sounds (engine, grass, brake, flat tire, music) are persistent
//! entities whose `AudioSink` is retuned each frame; one-shots spawn
//! fire-and-forget `AudioPlayer` entities.

use bevy::audio::{AudioSink, AudioSinkPlayback, PlaybackMode, Volume};
use bevy::prelude::*;
use racing_sim::rng::GameRng;

use super::shared::{AppState, Cars, CurrentTrack, Race};
use super::synth;

pub const MASTER_VOLUME: f32 = 0.7;
pub const ENGINE_VOLUME: f32 = 0.3;
pub const EFFECTS_VOLUME: f32 = 0.5;
pub const UI_VOLUME: f32 = 0.4;

#[derive(Resource)]
pub struct Sounds {
    pub engine: Handle<AudioSource>,
    pub grass: Handle<AudioSource>,
    pub brake: Handle<AudioSource>,
    pub crash: Handle<AudioSource>,
    pub tire_blowout: Handle<AudioSource>,
    pub flat_tire: Handle<AudioSource>,
    pub countdown_beep: Handle<AudioSource>,
    pub countdown_go: Handle<AudioSource>,
    pub lap_complete: Handle<AudioSource>,
    pub race_win: Handle<AudioSource>,
    pub menu_blip: Handle<AudioSource>,
    pub menu_select: Handle<AudioSource>,
    pub music: Handle<AudioSource>,
}

/// Mutable audio state (fades, cooldowns, countdown edge detection).
#[derive(Resource)]
pub struct AudioState {
    pub music_volume: f32,
    pub music_target_volume: f32,
    pub music_fade_speed: f32,
    pub last_countdown_phase: Option<i32>,
    pub crash_cooldown: f32,
}

impl Default for AudioState {
    fn default() -> Self {
        Self {
            music_volume: 0.35,
            music_target_volume: 0.35,
            music_fade_speed: 0.5,
            last_countdown_phase: None,
            crash_cooldown: 0.0,
        }
    }
}

// Markers for the looping sound entities
#[derive(Component)]
pub struct MusicLoop;
#[derive(Component)]
pub struct EngineLoop;
#[derive(Component)]
pub struct GrassLoop;
#[derive(Component)]
pub struct BrakeLoop;
#[derive(Component)]
pub struct FlatTireLoop;

/// Generate all sounds procedurally and spawn the looping entities (paused).
pub fn setup_audio(mut commands: Commands, mut sources: ResMut<Assets<AudioSource>>) {
    let mut rng = GameRng::new(0xA0D10);

    let sounds = Sounds {
        engine: sources.add(synth::wav_source(&synth::engine_loop(&mut rng))),
        grass: sources.add(synth::wav_source(&synth::grass_loop(&mut rng))),
        brake: sources.add(synth::wav_source(&synth::rusty_brake_loop(&mut rng))),
        crash: sources.add(synth::wav_source(&synth::crash_impact(&mut rng))),
        tire_blowout: sources.add(synth::wav_source(&synth::tire_blowout(&mut rng))),
        flat_tire: sources.add(synth::wav_source(&synth::flat_tire_loop(&mut rng))),
        countdown_beep: sources.add(synth::wav_source(&synth::countdown_beep(false))),
        countdown_go: sources.add(synth::wav_source(&synth::countdown_beep(true))),
        lap_complete: sources.add(synth::wav_source(&synth::lap_jingle())),
        race_win: sources.add(synth::wav_source(&synth::win_fanfare())),
        menu_blip: sources.add(synth::wav_source(&synth::menu_blip())),
        menu_select: sources.add(synth::wav_source(&synth::menu_select())),
        music: sources.add(synth::wav_source(&synth::background_music(&mut rng))),
    };

    let looped = |volume: f32, paused: bool| PlaybackSettings {
        mode: PlaybackMode::Loop,
        volume: Volume::Linear(volume),
        paused,
        ..default()
    };

    // Music starts immediately; driving loops start paused.
    commands.spawn((
        AudioPlayer(sounds.music.clone()),
        looped(0.35 * MASTER_VOLUME, false),
        MusicLoop,
    ));
    commands.spawn((
        AudioPlayer(sounds.engine.clone()),
        looped(ENGINE_VOLUME * MASTER_VOLUME, true),
        EngineLoop,
    ));
    commands.spawn((
        AudioPlayer(sounds.grass.clone()),
        looped(EFFECTS_VOLUME * MASTER_VOLUME * 0.5, true),
        GrassLoop,
    ));
    commands.spawn((
        AudioPlayer(sounds.brake.clone()),
        looped(EFFECTS_VOLUME * MASTER_VOLUME * 0.6, true),
        BrakeLoop,
    ));
    commands.spawn((
        AudioPlayer(sounds.flat_tire.clone()),
        looped(EFFECTS_VOLUME * MASTER_VOLUME * 0.55, true),
        FlatTireLoop,
    ));

    commands.insert_resource(sounds);
    commands.insert_resource(AudioState::default());
}

/// Spawn a one-shot sound with the given linear volume.
pub fn play_oneshot(commands: &mut Commands, handle: &Handle<AudioSource>, volume: f32) {
    commands.spawn((
        AudioPlayer(handle.clone()),
        PlaybackSettings {
            mode: PlaybackMode::Despawn,
            volume: Volume::Linear(volume),
            ..default()
        },
    ));
}

pub fn play_menu_blip(commands: &mut Commands, sounds: &Sounds) {
    play_oneshot(commands, &sounds.menu_blip, UI_VOLUME * MASTER_VOLUME);
}

pub fn play_menu_select(commands: &mut Commands, sounds: &Sounds) {
    play_oneshot(commands, &sounds.menu_select, UI_VOLUME * MASTER_VOLUME);
}

pub fn play_crash(commands: &mut Commands, sounds: &Sounds, state: &mut AudioState, force: f32) {
    if state.crash_cooldown > 0.0 {
        return;
    }
    play_oneshot(
        commands,
        &sounds.crash,
        EFFECTS_VOLUME * MASTER_VOLUME * force.max(0.3),
    );
    state.crash_cooldown = 0.18; // avoid overlapping crunches
}

pub fn play_tire_blowout(commands: &mut Commands, sounds: &Sounds) {
    play_oneshot(
        commands,
        &sounds.tire_blowout,
        EFFECTS_VOLUME * MASTER_VOLUME,
    );
}

pub fn play_lap_complete(commands: &mut Commands, sounds: &Sounds) {
    play_oneshot(
        commands,
        &sounds.lap_complete,
        EFFECTS_VOLUME * MASTER_VOLUME,
    );
}

pub fn play_race_win(commands: &mut Commands, sounds: &Sounds) {
    play_oneshot(commands, &sounds.race_win, EFFECTS_VOLUME * MASTER_VOLUME);
}

pub fn fade_out_music(state: &mut AudioState) {
    state.music_target_volume = 0.08;
}

pub fn fade_in_music(state: &mut AudioState) {
    state.music_target_volume = 0.35;
}

/// Countdown beeps (port of audio.updateCountdown).
pub fn countdown_audio(
    mut commands: Commands,
    sounds: Res<Sounds>,
    mut audio_state: ResMut<AudioState>,
    race: Res<Race>,
) {
    if race.0.started {
        return;
    }
    let phase = race.0.countdown_phase;
    if Some(phase) != audio_state.last_countdown_phase {
        if (1..=3).contains(&phase) {
            play_oneshot(
                &mut commands,
                &sounds.countdown_beep,
                EFFECTS_VOLUME * MASTER_VOLUME,
            );
        } else if phase <= 0 && audio_state.last_countdown_phase == Some(1) {
            play_oneshot(
                &mut commands,
                &sounds.countdown_go,
                EFFECTS_VOLUME * MASTER_VOLUME,
            );
            fade_out_music(&mut audio_state);
        }
        audio_state.last_countdown_phase = Some(phase);
    }
}

/// Per-frame driving audio (port of audio.update).
#[allow(clippy::too_many_arguments, clippy::type_complexity)]
pub fn update_audio(
    time: Res<Time>,
    state: Res<State<AppState>>,
    race: Option<Res<Race>>,
    cars: Option<Res<Cars>>,
    track: Option<Res<CurrentTrack>>,
    mut audio_state: ResMut<AudioState>,
    mut music: Query<&mut AudioSink, With<MusicLoop>>,
    mut engine: Query<&mut AudioSink, (With<EngineLoop>, Without<MusicLoop>)>,
    mut grass: Query<&mut AudioSink, (With<GrassLoop>, Without<MusicLoop>, Without<EngineLoop>)>,
    mut brake: Query<
        &mut AudioSink,
        (
            With<BrakeLoop>,
            Without<MusicLoop>,
            Without<EngineLoop>,
            Without<GrassLoop>,
        ),
    >,
    mut flat: Query<
        &mut AudioSink,
        (
            With<FlatTireLoop>,
            Without<MusicLoop>,
            Without<EngineLoop>,
            Without<GrassLoop>,
            Without<BrakeLoop>,
        ),
    >,
) {
    let dt = time.delta_secs();

    // Music fade
    let diff = audio_state.music_target_volume - audio_state.music_volume;
    if diff.abs() > 0.001 {
        let change = audio_state.music_fade_speed * dt;
        audio_state.music_volume = if diff > 0.0 {
            (audio_state.music_volume + change).min(audio_state.music_target_volume)
        } else {
            (audio_state.music_volume - change).max(audio_state.music_target_volume)
        };
        if let Ok(mut sink) = music.single_mut() {
            sink.set_volume(Volume::Linear(audio_state.music_volume * MASTER_VOLUME));
        }
    }

    if audio_state.crash_cooldown > 0.0 {
        audio_state.crash_cooldown -= dt;
    }

    let driving = matches!(state.get(), AppState::Racing)
        && race.as_ref().is_some_and(|r| r.0.started && !r.0.won);

    let (Ok(mut engine), Ok(grass), Ok(mut brake), Ok(flat)) = (
        engine.single_mut(),
        grass.single_mut(),
        brake.single_mut(),
        flat.single_mut(),
    ) else {
        return;
    };

    if !driving {
        engine.pause();
        grass.pause();
        brake.pause();
        flat.pause();
        return;
    }

    let (Some(cars), Some(track)) = (cars, track) else {
        return;
    };
    let Some(car) = cars.0.first() else { return };
    let Some(track) = track.0.as_ref() else {
        return;
    };

    // Engine
    engine.play();
    let speed_ratio = (car.speed.abs() / car.physics.max_speed) as f32;
    let mut pitch = 0.7 + speed_ratio * 0.8;

    // Engine sputter when damaged
    let engine_health = car.damage.engine as f32;
    let mut engine_vol = ENGINE_VOLUME * MASTER_VOLUME;
    if engine_health < 0.6 {
        let t = time.elapsed_secs();
        let sputter = 0.5 + 0.5 * (t * 22.0).sin() * (t * 7.3).sin();
        let severity = 1.0 - engine_health;
        engine_vol *= 1.0 - severity * 0.7 * (1.0 - sputter);
        pitch *= 0.88 + engine_health * 0.12;
    }
    engine.set_speed(pitch);
    let throttle_boost = if car.speed > car.prev_speed { 1.0 } else { 0.5 };
    engine.set_volume(Volume::Linear(engine_vol * (0.5 + throttle_boost * 0.5)));

    // Grass / off-track
    let on_track = track.is_on_track(car.x, car.y);
    if !on_track && car.speed.abs() > 20.0 {
        grass.play();
        grass.set_speed(0.8 + speed_ratio * 0.4);
    } else {
        grass.pause();
    }

    // Brake squeal
    let is_braking = car.speed > 30.0 && car.speed < car.prev_speed - 5.0;
    if is_braking {
        brake.play();
        let brake_pitch = 0.6 + (car.speed / car.physics.max_speed) as f32 * 0.8;
        let brake_intensity = ((car.speed / 150.0) as f32).min(1.0);
        brake.set_speed(brake_pitch);
        brake.set_volume(Volume::Linear(
            EFFECTS_VOLUME * MASTER_VOLUME * 0.6 * brake_intensity,
        ));
    } else {
        brake.pause();
    }

    // Flat tyre thumping loop (player car only)
    let has_flat = car.damage.flat_tires.iter().any(|&f| f);
    if has_flat && car.speed.abs() > 15.0 {
        flat.play();
        flat.set_speed(0.5 + speed_ratio * 1.4);
    } else {
        flat.pause();
    }
}
