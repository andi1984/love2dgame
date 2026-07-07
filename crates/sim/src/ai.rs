//! AI sensor system and driving bridge (port of ai.lua).

use crate::car::{Car, CarInput};
use crate::npc_profiles::ErrorProfile;
use crate::rng::GameRng;
use crate::track::Track;

const PI: f64 = std::f64::consts::PI;
const TWO_PI: f64 = 2.0 * PI;

fn normalize_angle(mut a: f64) -> f64 {
    while a > PI {
        a -= TWO_PI;
    }
    while a < -PI {
        a += TWO_PI;
    }
    a
}

/// Curvature of the track ahead (average angle change over a segment),
/// signed by the direction of the overall curve, normalized to [-1, 1].
fn calculate_curvature(track: &Track, pct: f64, look_ahead: f64) -> f64 {
    let steps = 5;
    let mut total_angle_change = 0.0;
    let mut prev_angle: Option<f64> = None;
    for i in 0..=steps {
        let sample_pct = (pct + look_ahead * i as f64 / steps as f64).rem_euclid(1.0);
        let p1 = track.get_point_at_percent(sample_pct);
        let p2 = track.get_point_at_percent((sample_pct + 0.005).rem_euclid(1.0));
        let angle = (p2.y - p1.y).atan2(p2.x - p1.x);
        if let Some(prev) = prev_angle {
            total_angle_change += normalize_angle(angle - prev).abs();
        }
        prev_angle = Some(angle);
    }

    let start_pt = track.get_point_at_percent(pct);
    let end_pt = track.get_point_at_percent((pct + look_ahead).rem_euclid(1.0));
    let start_next = track.get_point_at_percent((pct + 0.005).rem_euclid(1.0));
    let fwd = (start_next.y - start_pt.y).atan2(start_next.x - start_pt.x);
    let to_end = (end_pt.y - start_pt.y).atan2(end_pt.x - start_pt.x);
    let sign = if normalize_angle(to_end - fwd) > 0.0 {
        1.0
    } else {
        -1.0
    };

    let avg_change = total_angle_change / steps as f64;
    (avg_change / PI * sign).clamp(-1.0, 1.0)
}

/// Signed distance from car to the closest centerline point
/// (sign from the cross product with the track tangent).
fn signed_dist_to_center(car: &Car, track: &Track) -> f64 {
    let mut min_dist = f64::INFINITY;
    let mut best_idx = 0;
    for (i, p) in track.center_path.iter().enumerate() {
        let dx = car.x - p.x;
        let dy = car.y - p.y;
        let dist = dx * dx + dy * dy;
        if dist < min_dist {
            min_dist = dist;
            best_idx = i;
        }
    }
    let min_dist = min_dist.sqrt();

    let n = track.center_path.len();
    let prev = track.center_path[(best_idx + n - 1) % n];
    let next = track.center_path[(best_idx + 1) % n];
    let tx = next.x - prev.x;
    let ty = next.y - prev.y;
    let dx = car.x - track.center_path[best_idx].x;
    let dy = car.y - track.center_path[best_idx].y;
    let cross = tx * dy - ty * dx;
    let side = if cross > 0.0 { 1.0 } else { -1.0 };

    min_dist * side
}

/// Cast a ray from the car and find the normalized distance to the track edge.
/// 0 = at edge, 1 = far from edge (max range).
fn raycast_to_edge(car: &Car, track: &Track, angle_offset: f64) -> f64 {
    let max_dist = 120.0;
    let step = 4.0;
    let angle = car.angle + angle_offset;
    let cos_a = angle.cos();
    let sin_a = angle.sin();
    let half_width = track.width / 2.0;
    let half_width_sq = half_width * half_width;

    // Starting nearest center index for efficient local search
    let mut best_idx = 0;
    let mut min_d = f64::INFINITY;
    for (i, p) in track.center_path.iter().enumerate() {
        let dx = car.x - p.x;
        let dy = car.y - p.y;
        let d = dx * dx + dy * dy;
        if d < min_d {
            min_d = d;
            best_idx = i as i64;
        }
    }

    let n = track.center_path.len() as i64;
    let search_radius = 25i64;

    let mut dist = step;
    while dist <= max_dist {
        let px = car.x + cos_a * dist;
        let py = car.y + sin_a * dist;

        // Screen bounds count as edges
        if !(10.0..=790.0).contains(&px) || !(10.0..=590.0).contains(&py) {
            return dist / max_dist;
        }

        // Nearest center point near last known index
        let mut local_min = f64::INFINITY;
        let mut local_best = best_idx;
        for offset in -search_radius..=search_radius {
            let idx = (best_idx + offset).rem_euclid(n);
            let cp = track.center_path[idx as usize];
            let dx = px - cp.x;
            let dy = py - cp.y;
            let d = dx * dx + dy * dy;
            if d < local_min {
                local_min = d;
                local_best = idx;
            }
        }
        best_idx = local_best;

        if local_min > half_width_sq {
            return dist / max_dist;
        }
        dist += step;
    }

    1.0
}

/// Calculate all 13 sensor inputs for a car on a track.
/// Inputs 0-7: original sensors, inputs 8-12: raycast distances.
pub fn get_sensor_inputs(car: &Car, track: &Track) -> [f64; 13] {
    let mut inputs = [0.0; 13];
    let pct = track.get_track_percent(car.x, car.y);

    // 0: Angle error to waypoint ~3% ahead
    let target = track.get_point_at_percent((pct + 0.03).rem_euclid(1.0));
    let desired_angle = (target.y - car.y).atan2(target.x - car.x);
    inputs[0] = normalize_angle(desired_angle - car.angle) / PI;

    // 1: Signed distance to center line, normalized by half track width
    let signed_dist = signed_dist_to_center(car, track);
    let half_width = track.width / 2.0;
    inputs[1] = (signed_dist / half_width).clamp(-1.0, 1.0);

    // 2: Speed ratio
    inputs[2] = car.speed / car.physics.max_speed;

    // 3: Upcoming curvature (~10% ahead)
    inputs[3] = calculate_curvature(track, pct, 0.10);

    // 4: Near look-ahead angle (~5% ahead)
    let near = track.get_point_at_percent((pct + 0.05).rem_euclid(1.0));
    let near_angle = (near.y - car.y).atan2(near.x - car.x);
    inputs[4] = normalize_angle(near_angle - car.angle) / PI;

    // 5: Far look-ahead angle (~15% ahead)
    let far = track.get_point_at_percent((pct + 0.15).rem_euclid(1.0));
    let far_angle = (far.y - car.y).atan2(far.x - car.x);
    inputs[5] = normalize_angle(far_angle - car.angle) / PI;

    // 6: Surface grip ahead (~5%)
    inputs[6] = track.get_surface_at(near.x, near.y).grip;

    // 7: On-track flag
    inputs[7] = if track.is_on_track(car.x, car.y) {
        1.0
    } else {
        0.0
    };

    // 8-12: Raycast distances to track edge (normalized 0-1)
    // Left (-90°), Front-left (-45°), Front (0°), Front-right (+45°), Right (+90°)
    inputs[8] = raycast_to_edge(car, track, -PI / 2.0);
    inputs[9] = raycast_to_edge(car, track, -PI / 4.0);
    inputs[10] = raycast_to_edge(car, track, 0.0);
    inputs[11] = raycast_to_edge(car, track, PI / 4.0);
    inputs[12] = raycast_to_edge(car, track, PI / 2.0);

    inputs
}

/// Convert network outputs [0,1] to game input with continuous steering.
pub fn output_to_input(outputs: &[f64]) -> CarInput {
    // outputs[2] = left tendency, outputs[3] = right tendency
    let steer = ((outputs[3] - outputs[2]) * 2.0).clamp(-1.0, 1.0);
    CarInput {
        up: outputs[0] > 0.5,
        down: outputs[1] > 0.5,
        left: false,
        right: false,
        steer: Some(steer),
    }
}

/// Add Gaussian noise to sensor inputs based on the personality error config.
pub fn apply_sensor_noise(
    inputs: &mut [f64; 13],
    errors: Option<&ErrorProfile>,
    rng: &mut GameRng,
) {
    let Some(errors) = errors else { return };
    if errors.sensor_noise <= 0.0 {
        return;
    }
    for v in inputs.iter_mut() {
        *v += rng.gaussian() * errors.sensor_noise;
    }
}

/// Apply imperfections to the AI output: lapses, jitter, late braking.
/// Mutates the car's NPC error state.
pub fn apply_errors(car: &mut Car, input: CarInput, dt: f64, rng: &mut GameRng) -> CarInput {
    let Some(npc) = car.npc.as_mut() else {
        return input;
    };
    let Some(errors) = npc.personality.errors else {
        return input;
    };

    // Lapse system: occasionally hold stale input (driver loses focus)
    if npc.lapse_timer > 0.0 {
        npc.lapse_timer -= dt;
        if let Some(stale) = npc.last_input {
            return stale;
        }
    } else {
        let chance = errors.lapse_chance * dt;
        if rng.next_f64() < chance {
            npc.lapse_timer = errors.lapse_duration_min
                + rng.next_f64() * (errors.lapse_duration_max - errors.lapse_duration_min);
            npc.last_input = Some(input);
            return input; // start of lapse: use current input, then freeze it
        }
    }

    let mut input = input;

    // Brake-late: occasionally ignore the brake signal
    let brake_late = errors.brake_late_chance * dt;
    if input.down && rng.next_f64() < brake_late {
        input.down = false;
    }

    // Steering jitter: random wobble added to steer value
    if errors.steer_jitter > 0.0 {
        let steer = input.steer.unwrap_or(0.0);
        input.steer = Some((steer + rng.gaussian() * errors.steer_jitter).clamp(-1.0, 1.0));
    }

    npc.last_input = Some(input);
    input
}

/// Initialize per-race metrics on an AI car.
pub fn init_metrics(car: &mut Car) {
    if let Some(npc) = car.npc.as_mut() {
        npc.time_off_track = 0.0;
        npc.time_stationary = 0.0;
        npc.avg_speed = 0.0;
        npc.speed_samples = 0.0;
        npc.stuck_timer = 0.0;
        npc.stuck_override = 0.0;
        npc.stuck_steer_dir = 1.0;
        npc.lapse_timer = 0.0;
        npc.last_input = None;
    }
}

/// Update per-frame performance metrics and handle stuck detection.
pub fn update_metrics(car: &mut Car, dt: f64, track: &Track) {
    let off_track = !track.is_on_track(car.x, car.y);
    let speed = car.speed;
    let Some(npc) = car.npc.as_mut() else { return };

    if off_track {
        npc.time_off_track += dt;
    }
    if speed.abs() < 5.0 {
        npc.time_stationary += dt;
        npc.stuck_timer += dt;
    } else {
        npc.stuck_timer = 0.0;
    }
    npc.speed_samples += 1.0;
    npc.avg_speed += (speed.abs() - npc.avg_speed) / npc.speed_samples;

    if npc.stuck_override > 0.0 {
        npc.stuck_override -= dt;
    }
}

/// If the car is stuck, return an override input (reverse + random steer).
pub fn get_stuck_override(car: &mut Car, rng: &mut GameRng) -> Option<CarInput> {
    let npc = car.npc.as_mut()?;
    if npc.stuck_timer > 2.0 {
        npc.stuck_timer = 0.0;
        npc.stuck_override = 0.5;
        npc.stuck_steer_dir = if rng.next_f64() < 0.5 { -1.0 } else { 1.0 };
    }
    if npc.stuck_override > 0.0 {
        Some(CarInput {
            up: false,
            down: true,
            left: false,
            right: false,
            steer: Some(npc.stuck_steer_dir),
        })
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::car::{CarOverrides, NpcState};
    use crate::nnet;
    use crate::npc_profiles::Personality;
    use crate::track::Track;

    fn make_npc_state(errors: Option<ErrorProfile>) -> NpcState {
        let mut rng = GameRng::new(7);
        let brain = nnet::create_seeded(&[13, 16, 4], &mut rng);
        let best_brain = nnet::serialize(&brain);
        NpcState {
            brain,
            personality: Personality {
                mutation_rate: 0.15,
                mutation_strength: 0.3,
                initial_bias: Default::default(),
                physics: Default::default(),
                errors,
            },
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
        }
    }

    fn ai_car(track: &Track) -> Car {
        let mut car = Car::new(
            track,
            CarOverrides {
                is_ai: true,
                ..Default::default()
            },
        );
        car.npc = Some(make_npc_state(None));
        car
    }

    #[test]
    fn sensor_values_are_in_reasonable_range() {
        let track = Track::default_oval();
        let car = ai_car(&track);
        let sensors = get_sensor_inputs(&car, &track);
        for (i, v) in sensors.iter().enumerate() {
            assert!((-2.0..=2.0).contains(v), "sensor {i} out of range: {v}");
        }
    }

    #[test]
    fn on_track_sensor_is_one_when_on_track() {
        let track = Track::default_oval();
        let car = ai_car(&track);
        assert_eq!(get_sensor_inputs(&car, &track)[7], 1.0);
    }

    #[test]
    fn on_track_sensor_is_zero_when_off_track() {
        let track = Track::default_oval();
        let mut car = ai_car(&track);
        car.x = 10.0;
        car.y = 10.0;
        assert_eq!(get_sensor_inputs(&car, &track)[7], 0.0);
    }

    #[test]
    fn raycast_sensors_are_in_unit_range() {
        let track = Track::default_oval();
        let car = ai_car(&track);
        let sensors = get_sensor_inputs(&car, &track);
        for (i, v) in sensors.iter().enumerate().skip(8) {
            assert!(
                (0.0..=1.0).contains(v),
                "raycast sensor {i} out of range: {v}"
            );
        }
    }

    #[test]
    fn output_to_input_converts_to_continuous_steering() {
        let input = output_to_input(&[0.8, 0.2, 0.9, 0.1]);
        assert!(input.up);
        assert!(!input.down);
        assert!(input.steer.unwrap() < -0.5);
    }

    #[test]
    fn output_to_input_produces_right_steering() {
        let input = output_to_input(&[0.8, 0.2, 0.1, 0.9]);
        assert!(input.steer.unwrap() > 0.5);
    }

    #[test]
    fn output_to_input_balanced_steering_is_near_zero() {
        let input = output_to_input(&[0.5, 0.5, 0.5, 0.5]);
        assert!(input.steer.unwrap().abs() < 0.01);
    }

    #[test]
    fn init_metrics_zeroes_all_fields() {
        let track = Track::default_oval();
        let mut car = ai_car(&track);
        init_metrics(&mut car);
        let npc = car.npc.as_ref().unwrap();
        assert_eq!(npc.time_off_track, 0.0);
        assert_eq!(npc.time_stationary, 0.0);
        assert_eq!(npc.avg_speed, 0.0);
        assert_eq!(npc.speed_samples, 0.0);
        assert_eq!(npc.stuck_timer, 0.0);
        assert_eq!(npc.lapse_timer, 0.0);
        assert!(npc.last_input.is_none());
    }

    #[test]
    fn stuck_override_uses_continuous_steer() {
        let track = Track::default_oval();
        let mut car = ai_car(&track);
        let mut rng = GameRng::new(3);
        init_metrics(&mut car);
        car.npc.as_mut().unwrap().stuck_timer = 3.0;
        let ov = get_stuck_override(&mut car, &mut rng).expect("stuck override expected");
        let steer = ov.steer.unwrap();
        assert!(steer == 1.0 || steer == -1.0);
        assert!(ov.down);
    }

    #[test]
    fn sensor_noise_changes_inputs() {
        let mut rng = GameRng::new(42);
        let mut inputs = [0.5; 13];
        let errors = ErrorProfile {
            sensor_noise: 0.1,
            lapse_chance: 0.0,
            lapse_duration_min: 0.0,
            lapse_duration_max: 0.0,
            steer_jitter: 0.0,
            brake_late_chance: 0.0,
        };
        apply_sensor_noise(&mut inputs, Some(&errors), &mut rng);
        assert!(inputs.iter().any(|&v| v != 0.5));
    }

    #[test]
    fn sensor_noise_noop_without_error_config() {
        let mut rng = GameRng::new(42);
        let mut inputs = [0.5; 13];
        apply_sensor_noise(&mut inputs, None, &mut rng);
        assert!(inputs.iter().all(|&v| v == 0.5));
    }

    #[test]
    fn apply_errors_passthrough_without_error_config() {
        let track = Track::default_oval();
        let mut car = ai_car(&track);
        let mut rng = GameRng::new(1);
        init_metrics(&mut car);
        let input = CarInput {
            up: true,
            down: false,
            steer: Some(0.3),
            ..Default::default()
        };
        let result = apply_errors(&mut car, input, 0.016, &mut rng);
        assert!(result.up);
        assert!(!result.down);
        assert_eq!(result.steer, Some(0.3));
    }

    #[test]
    fn lapse_holds_stale_input() {
        let track = Track::default_oval();
        let mut car = ai_car(&track);
        let mut rng = GameRng::new(1);
        car.npc.as_mut().unwrap().personality.errors = Some(ErrorProfile {
            sensor_noise: 0.0,
            lapse_chance: 0.0,
            lapse_duration_min: 0.0,
            lapse_duration_max: 0.0,
            steer_jitter: 0.0,
            brake_late_chance: 0.0,
        });
        init_metrics(&mut car);
        let stale = CarInput {
            up: true,
            down: false,
            steer: Some(-0.8),
            ..Default::default()
        };
        {
            let npc = car.npc.as_mut().unwrap();
            npc.lapse_timer = 0.5;
            npc.last_input = Some(stale);
        }
        let fresh = CarInput {
            up: false,
            down: true,
            steer: Some(0.5),
            ..Default::default()
        };
        let result = apply_errors(&mut car, fresh, 0.016, &mut rng);
        assert_eq!(result.steer, Some(-0.8));
        assert!(result.up);
    }
}
