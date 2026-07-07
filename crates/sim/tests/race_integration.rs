//! End-to-end race simulation without an engine: seeded AI brains drive
//! around a generated track; verifies the full sim pipeline (sensors →
//! network → input → physics → laps → evolution) holds together.

use racing_sim::car::{Car, CarOverrides, NpcState};
use racing_sim::game::RaceState;
use racing_sim::rng::GameRng;
use racing_sim::track::Track;
use racing_sim::{ai, collision, damage, evolution, nnet, npc_profiles, trackgen};

#[test]
fn seeded_ai_drives_a_race_without_breaking() {
    let config = trackgen::generate(42);
    let track = Track::from_config(&config);
    let mut rng = GameRng::new(0xBEEF);

    // Player stays parked; NPCs drive with seeded brains.
    let mut cars = vec![Car::new(&track, CarOverrides::default())];
    for (i, profile) in npc_profiles::list().into_iter().enumerate() {
        let idx = i + 1;
        let mut car = Car::new(
            &track,
            CarOverrides {
                name: Some(profile.name.into()),
                is_ai: true,
                physics: profile.personality.physics,
                start_offset: Some(-(idx as f64) * 0.04),
                lateral_offset: if idx % 2 == 1 { 12.0 } else { -12.0 },
                ..Default::default()
            },
        );
        let brain = nnet::create_seeded(&[13, 16, 4], &mut rng);
        let best_brain = nnet::serialize(&brain);
        car.npc = Some(NpcState {
            brain,
            personality: profile.personality.clone(),
            best_brain,
            best_fitness: 0.0,
            generation: 0,
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
        ai::init_metrics(&mut car);
        cars.push(car);
    }

    let mut race = RaceState::new(cars.len());
    race.started = true;

    let dt = 1.0 / 60.0;
    let steps = 60 * 60; // 60 simulated seconds
    let start_positions: Vec<(f64, f64)> = cars.iter().map(|c| (c.x, c.y)).collect();

    for step in 0..steps {
        let now = step as f64 * dt;
        race.timer += dt;

        for i in 0..cars.len() {
            let (prev_x, prev_y) = (cars[i].x, cars[i].y);
            let input = if cars[i].is_ai {
                let car = &mut cars[i];
                let input = if let Some(ov) = ai::get_stuck_override(car, &mut rng) {
                    ov
                } else {
                    let mut sensors = ai::get_sensor_inputs(car, &track);
                    let errors = car.npc.as_ref().and_then(|n| n.personality.errors);
                    ai::apply_sensor_noise(&mut sensors, errors.as_ref(), &mut rng);
                    let outputs = nnet::forward(&car.npc.as_ref().unwrap().brain, &sensors);
                    ai::apply_errors(car, ai::output_to_input(&outputs), dt, &mut rng)
                };
                ai::update_metrics(&mut cars[i], dt, &track);
                input
            } else {
                Default::default()
            };

            let car = &mut cars[i];
            car.update(dt, &input, &track, now, &mut rng);
            race.check_finish_line(&track, prev_x, prev_y, car.x, car.y, i);

            let (x, y, speed) = (car.x, car.y, car.speed);
            damage::update_environment(&mut car.damage, x, y, speed, &track, dt);

            // Invariants every step
            assert!(car.x.is_finite() && car.y.is_finite(), "position blew up");
            assert!(car.speed.is_finite(), "speed blew up");
            assert!((10.0..=790.0).contains(&car.x));
            assert!((10.0..=590.0).contains(&car.y));
        }

        if race.timer >= 2.0 {
            let events = collision::check_all(&cars);
            for ev in &events {
                let impact = collision::resolve(&mut cars, ev);
                let (i, j) = (ev.idx1, ev.idx2);
                let (head, tail) = cars.split_at_mut(j);
                let (c1, c2) = (&mut head[i], &mut tail[0]);
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
                    impact,
                );
            }
        }
    }

    // NPCs must actually have driven somewhere
    for (i, car) in cars.iter().enumerate().skip(1) {
        let (sx, sy) = start_positions[i];
        let dist = ((car.x - sx).powi(2) + (car.y - sy).powi(2)).sqrt();
        let npc = car.npc.as_ref().unwrap();
        assert!(
            npc.avg_speed > 10.0,
            "{} barely moved (avg speed {:.1})",
            car.name,
            npc.avg_speed
        );
        assert!(
            dist > 1.0 || npc.avg_speed > 10.0,
            "{} never left the grid",
            car.name
        );
    }

    // Evolution after the race must not corrupt brains
    let timer = race.timer;
    let laps = race.car_laps.clone();
    for (i, car) in cars.iter_mut().enumerate() {
        if car.is_ai {
            let fitness = evolution::calculate_fitness(car, &track, timer, laps[i]);
            assert!(fitness.is_finite());
            if let Some(npc) = car.npc.as_mut() {
                npc.current_fitness = fitness;
            }
            evolution::evolve_after_race(car, &mut rng);
            let npc = car.npc.as_ref().unwrap();
            let out = nnet::forward(&npc.brain, &[0.1; 13]);
            assert!(out.iter().all(|v| v.is_finite()));
        }
    }
}
