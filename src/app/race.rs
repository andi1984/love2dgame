//! Race orchestration: setup, per-frame sim update, evolution, persistence
//! (port of main.lua's love.update and race lifecycle).

use bevy::prelude::*;
use racing_sim::car::{Car, CarInput, CarOverrides, NpcState};
use racing_sim::game::RaceState;
use racing_sim::persistence::{self, NpcSave, SaveData};
use racing_sim::track::Track;
use racing_sim::{ai, collision, damage, evolution, nnet, npc_profiles};
use std::path::Path;

use super::audio_sys::{self, AudioState, Sounds};
use super::particles_fx;
use super::render;
use super::shared::*;

/// Fixed network architecture (13 sensors, 16 hidden, 4 outputs).
pub const NET_ARCH: [usize; 3] = [13, 16, 4];

fn load_or_create_brain(
    saved: &Option<SaveData>,
    profile_name: &str,
    rng: &mut racing_sim::rng::GameRng,
) -> nnet::Net {
    if let Some(data) = saved {
        if let Some(npc) = data.npcs.get(profile_name) {
            if npc.best_brain.layer_sizes == NET_ARCH {
                return nnet::deserialize(&npc.best_brain);
            }
        }
    }
    // Seeded brain that can follow the track from the start
    nnet::create_seeded(&NET_ARCH, rng)
}

fn saved_meta(saved: &Option<SaveData>, profile_name: &str) -> (f64, u32, Option<nnet::NetData>) {
    if let Some(data) = saved {
        if let Some(npc) = data.npcs.get(profile_name) {
            return (
                npc.best_fitness,
                npc.generation,
                Some(npc.best_brain.clone()),
            );
        }
    }
    (0.0, 0, None)
}

fn gather_save_data(cars: &[Car]) -> SaveData {
    let mut data = SaveData::default();
    for car in cars {
        if let Some(npc) = &car.npc {
            data.npcs.insert(
                car.name.clone(),
                NpcSave {
                    best_brain: npc.best_brain.clone(),
                    best_fitness: npc.best_fitness,
                    generation: npc.generation,
                },
            );
        }
    }
    data
}

/// Handle StartRace events: build track + cars, spawn the scene, enter Racing.
#[allow(clippy::too_many_arguments)]
pub fn start_race(
    mut events: EventReader<StartRace>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
    grass: Res<render::GrassImage>,
    saved: Res<SavedNpcData>,
    mut rng: ResMut<SimRng>,
    mut current_track: ResMut<CurrentTrack>,
    mut cars_res: ResMut<Cars>,
    mut race: ResMut<Race>,
    mut audio_state: ResMut<AudioState>,
    scene: Query<Entity, With<RaceScene>>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    let Some(StartRace(config)) = events.read().last() else {
        return;
    };

    // Tear down any previous scene (restart case)
    for entity in scene.iter() {
        commands.entity(entity).despawn();
    }

    let track = Track::from_config(config);

    // Player car (index 0)
    let mut cars = vec![Car::new(
        &track,
        CarOverrides {
            name: Some("Player".into()),
            color: Some([0.85, 0.1, 0.1]),
            is_ai: false,
            ..Default::default()
        },
    )];

    // NPC cars, staggered behind the player
    for (i, profile) in npc_profiles::list().into_iter().enumerate() {
        let idx = i + 1;
        let mut npc_car = Car::new(
            &track,
            CarOverrides {
                name: Some(profile.name.into()),
                color: Some(profile.color),
                is_ai: true,
                physics: profile.personality.physics,
                start_offset: Some(-(idx as f64) * 0.04),
                lateral_offset: if idx % 2 == 1 { 12.0 } else { -12.0 },
            },
        );

        let brain = load_or_create_brain(&saved.0, profile.name, &mut rng.0);
        let (best_fitness, generation, best_brain) = saved_meta(&saved.0, profile.name);
        let best_brain = best_brain.unwrap_or_else(|| nnet::serialize(&brain));
        npc_car.npc = Some(NpcState {
            brain,
            personality: profile.personality.clone(),
            best_brain,
            best_fitness,
            generation,
            current_fitness: 0.0,
            time_off_track: 0.0,
            time_stationary: 0.0,
            avg_speed: 0.0,
            speed_samples: 0.0,
            stuck_timer: 0.0,
            stuck_override: 0.0,
            stuck_steer_dir: 1.0,
            lapse_timer: 0.0,
            last_input: None,
        });
        ai::init_metrics(&mut npc_car);
        cars.push(npc_car);
    }

    race.0 = RaceState::new(cars.len());

    // Spawn scene + car entities
    render::spawn_track_scene(&mut commands, &mut meshes, &mut materials, &grass, &track);
    for (i, car) in cars.iter().enumerate() {
        render::spawn_car(&mut commands, &mut meshes, &mut materials, i, car);
    }

    *current_track = CurrentTrack(Some(track));
    cars_res.0 = cars;

    // audio.reset(): countdown state cleared, music fades back in until GO
    audio_state.last_countdown_phase = None;
    audio_state.crash_cooldown = 0.0;
    audio_sys::fade_in_music(&mut audio_state);

    next_state.set(AppState::Racing);
}

/// Handle ReturnToMenu: save brains, tear down, back to menu.
#[allow(clippy::too_many_arguments)]
pub fn return_to_menu(
    mut events: EventReader<ReturnToMenu>,
    mut commands: Commands,
    cars: Res<Cars>,
    mut menu: ResMut<Menu>,
    tracks: Res<Tracks>,
    mut audio_state: ResMut<AudioState>,
    scene: Query<Entity, With<RaceScene>>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if events.read().last().is_none() {
        return;
    }
    if cars.0.len() > 1 {
        let _ = persistence::save(
            &gather_save_data(&cars.0),
            Path::new(persistence::BRAINS_FILE),
        );
    }
    for entity in scene.iter() {
        commands.entity(entity).despawn();
    }
    audio_sys::fade_in_music(&mut audio_state);
    menu.0 = racing_sim::menu::MenuState::new(tracks.0.count());
    next_state.set(AppState::Menu);
}

/// Countdown phase before the race starts.
pub fn update_countdown(time: Res<Time>, mut race: ResMut<Race>) {
    if !race.0.started {
        race.0.update_countdown(time.delta_secs_f64());
    }
}

/// Main per-frame simulation step (port of the racing branch of love.update).
#[allow(clippy::too_many_arguments)]
pub fn race_update(
    time: Res<Time>,
    keys: Res<ButtonInput<KeyCode>>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
    mut cars: ResMut<Cars>,
    mut race: ResMut<Race>,
    track: Res<CurrentTrack>,
    mut rng: ResMut<SimRng>,
    sounds: Res<Sounds>,
    mut audio_state: ResMut<AudioState>,
) {
    let Some(track) = track.0.as_ref() else {
        return;
    };
    if !race.0.started || race.0.won {
        return;
    }

    let dt = time.delta_secs_f64();
    let now = time.elapsed_secs_f64();
    race.0.timer += dt;

    // Player input
    let player_input = CarInput {
        up: keys.pressed(KeyCode::ArrowUp),
        down: keys.pressed(KeyCode::ArrowDown),
        left: keys.pressed(KeyCode::ArrowLeft),
        right: keys.pressed(KeyCode::ArrowRight),
        steer: None,
    };

    let prev_laps: Vec<u32> = race.0.car_laps.clone();
    let rng = &mut rng.0;

    // Update all cars
    for i in 0..cars.0.len() {
        let (prev_x, prev_y) = (cars.0[i].x, cars.0[i].y);

        let input = if cars.0[i].is_ai {
            let car = &mut cars.0[i];
            let input = if let Some(override_input) = ai::get_stuck_override(car, rng) {
                override_input
            } else {
                let mut sensors = ai::get_sensor_inputs(car, track);
                let errors = car.npc.as_ref().and_then(|n| n.personality.errors);
                ai::apply_sensor_noise(&mut sensors, errors.as_ref(), rng);
                let outputs = nnet::forward(&car.npc.as_ref().unwrap().brain, &sensors);
                let input = ai::output_to_input(&outputs);
                ai::apply_errors(car, input, dt, rng)
            };
            ai::update_metrics(&mut cars.0[i], dt, track);
            input
        } else {
            player_input
        };

        let car = &mut cars.0[i];
        car.update(dt, &input, track, now, rng);
        race.0
            .check_finish_line(track, prev_x, prev_y, car.x, car.y, i);

        // Environment damage (curbs, off-road)
        let had_flat = car.damage.new_flat;
        let (cx, cy, cspeed) = (car.x, car.y, car.speed);
        damage::update_environment(&mut car.damage, cx, cy, cspeed, track, dt);
        if car.damage.new_flat && !had_flat && i == 0 {
            audio_sys::play_tire_blowout(&mut commands, &sounds);
        }

        // Particles
        if car.should_spawn_smoke {
            particles_fx::spawn_smoke(&mut commands, &mut meshes, &mut materials, car, rng);
        }
        if car.should_spawn_dark_smoke && rng.next_f64() < dt * 4.0 {
            particles_fx::spawn_dark_smoke(&mut commands, &mut meshes, &mut materials, car, rng);
        }
    }

    // Car-to-car collisions (skip for first 2 seconds so grid spacing settles)
    if race.0.timer >= 2.0 {
        let events = collision::check_all(&cars.0);
        for ev in &events {
            let impact_speed = collision::resolve(&mut cars.0, ev);

            // Structural damage to both cars
            let (i, j) = (ev.idx1, ev.idx2);
            let prev_flat1 = cars.0[i].damage.new_flat;
            let prev_flat2 = cars.0[j].damage.new_flat;
            {
                let (head, tail) = cars.0.split_at_mut(j);
                let c1 = &mut head[i];
                let c2 = &mut tail[0];
                let (x1, y1, a1) = (c1.x, c1.y, c1.angle);
                let (x2, y2, a2) = (c2.x, c2.y, c2.angle);
                damage::apply_collision(
                    &mut c1.damage,
                    x1,
                    y1,
                    a1,
                    &mut c2.damage,
                    x2,
                    y2,
                    a2,
                    impact_speed,
                );
            }

            // Blowout sound for the player
            if (i == 0 && cars.0[i].damage.new_flat && !prev_flat1)
                || (j == 0 && cars.0[j].damage.new_flat && !prev_flat2)
            {
                audio_sys::play_tire_blowout(&mut commands, &sounds);
            }

            // Sparks at impact points
            for idx in [i, j] {
                let side = cars.0[idx].damage.impact_side;
                let car = &cars.0[idx];
                particles_fx::spawn_sparks(
                    &mut commands,
                    &mut meshes,
                    &mut materials,
                    car,
                    side,
                    rng,
                );
            }

            // Crash audio for player-involved collisions
            let force = cars.0[i].damage.impact_force as f32;
            if i == 0 || j == 0 {
                audio_sys::play_crash(&mut commands, &sounds, &mut audio_state, force);
            }
        }
    }

    // Lap / win audio events (player only)
    if race.0.car_laps[0] > prev_laps[0] {
        if race.0.won && race.0.winner_index == Some(0) {
            audio_sys::play_race_win(&mut commands, &sounds);
            audio_sys::fade_in_music(&mut audio_state);
        } else {
            audio_sys::play_lap_complete(&mut commands, &sounds);
        }
    } else if race.0.won && race.0.winner_index != Some(0) && !race.0.evolution_done {
        // NPC won this frame
        audio_sys::play_lap_complete(&mut commands, &sounds);
    }

    // Evolution on race end
    if race.0.won && !race.0.evolution_done {
        race.0.evolution_done = true;
        let timer = race.0.timer;
        let laps = race.0.car_laps.clone();
        for (i, car) in cars.0.iter_mut().enumerate() {
            if car.is_ai {
                let fitness = evolution::calculate_fitness(car, track, timer, laps[i]);
                if let Some(npc) = car.npc.as_mut() {
                    npc.current_fitness = fitness;
                }
                evolution::evolve_after_race(car, rng);
            }
        }
        let _ = persistence::save(
            &gather_save_data(&cars.0),
            Path::new(persistence::BRAINS_FILE),
        );
    }
}

/// Keyboard shortcuts while racing: ESC pause/menu, R restart, F1 dev menu.
#[allow(clippy::too_many_arguments)]
pub fn racing_keys(
    keys: Res<ButtonInput<KeyCode>>,
    mut commands: Commands,
    race: Res<Race>,
    track: Res<CurrentTrack>,
    mut pause: ResMut<Pause>,
    sounds: Res<Sounds>,
    mut start_events: EventWriter<StartRace>,
    mut menu_events: EventWriter<ReturnToMenu>,
    mut devmenu: ResMut<super::devmenu_ui::DevMenu>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if keys.just_pressed(KeyCode::Escape) {
        if race.0.won {
            menu_events.write(ReturnToMenu);
        } else {
            audio_sys::play_menu_blip(&mut commands, &sounds);
            pause.0 = racing_sim::pause::PauseState::new();
            next_state.set(AppState::Paused);
        }
    } else if keys.just_pressed(KeyCode::KeyR) {
        if let Some(track) = track.0.as_ref() {
            start_events.write(StartRace(track.config.clone()));
        }
    } else if keys.just_pressed(KeyCode::F1) {
        devmenu.open = !devmenu.open;
    }
}
