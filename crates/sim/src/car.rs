//! Car factory and physics (port of car.lua).

use crate::damage::{self, DamageState};
use crate::nnet::{Net, NetData};
use crate::npc_profiles::Personality;
use crate::rng::GameRng;
use crate::track::Track;

#[derive(Debug, Clone, Copy)]
pub struct Physics {
    pub mass: f64,
    pub fuel_mass: f64,
    pub max_fuel: f64,
    pub fuel_rate: f64,
    pub tire_pressure: f64,
    pub optimal_pressure: f64,
    pub engine_force: f64,
    pub brake_force: f64,
    pub drag_coeff: f64,
    pub rolling_resistance: f64,
    pub max_speed: f64,
    pub base_turn_speed: f64,
    pub grip_multiplier: f64,
    pub bump_multiplier: f64,
}

impl Default for Physics {
    fn default() -> Self {
        Self {
            mass: 800.0,
            fuel_mass: 50.0,
            max_fuel: 50.0,
            fuel_rate: 1.5,
            tire_pressure: 2.2,
            optimal_pressure: 2.2,
            engine_force: 250_000.0,
            brake_force: 200_000.0,
            drag_coeff: 3.0,
            rolling_resistance: 0.015,
            max_speed: 320.0,
            base_turn_speed: 3.0,
            grip_multiplier: 1.0,
            bump_multiplier: 1.0,
        }
    }
}

/// Per-profile physics overrides (only the fields a profile customizes).
#[derive(Debug, Clone, Copy, Default)]
pub struct PhysicsOverrides {
    pub mass: Option<f64>,
    pub engine_force: Option<f64>,
    pub brake_force: Option<f64>,
    pub base_turn_speed: Option<f64>,
    pub grip_multiplier: Option<f64>,
    pub max_speed: Option<f64>,
}

impl PhysicsOverrides {
    pub fn apply_to(&self, p: &mut Physics) {
        if let Some(v) = self.mass {
            p.mass = v;
        }
        if let Some(v) = self.engine_force {
            p.engine_force = v;
        }
        if let Some(v) = self.brake_force {
            p.brake_force = v;
        }
        if let Some(v) = self.base_turn_speed {
            p.base_turn_speed = v;
        }
        if let Some(v) = self.grip_multiplier {
            p.grip_multiplier = v;
        }
        if let Some(v) = self.max_speed {
            p.max_speed = v;
        }
    }
}

/// Per-frame control input. `steer` (continuous, [-1, 1]) takes precedence
/// over the boolean left/right when set — same contract as the Lua code.
#[derive(Debug, Clone, Copy, Default)]
pub struct CarInput {
    pub up: bool,
    pub down: bool,
    pub left: bool,
    pub right: bool,
    pub steer: Option<f64>,
}

/// Evolution + driving-error state carried by AI cars.
#[derive(Debug, Clone)]
pub struct NpcState {
    pub brain: Net,
    pub personality: Personality,
    pub best_brain: NetData,
    pub best_fitness: f64,
    pub generation: u32,
    pub current_fitness: f64,

    // Per-race metrics (see ai::init_metrics)
    pub time_off_track: f64,
    pub time_stationary: f64,
    pub avg_speed: f64,
    pub speed_samples: f64,
    pub stuck_timer: f64,
    pub stuck_override: f64,
    pub stuck_steer_dir: f64,

    // Error state for imperfect driving
    pub lapse_timer: f64,
    pub last_input: Option<CarInput>,
}

#[derive(Debug, Clone, Default)]
pub struct CarOverrides {
    pub name: Option<String>,
    pub color: Option<[f32; 3]>,
    pub is_ai: bool,
    pub physics: PhysicsOverrides,
    /// Offset along the track (fraction of a lap, may be negative) for grid starts.
    pub start_offset: Option<f64>,
    /// Lateral offset perpendicular to the track direction.
    pub lateral_offset: f64,
}

#[derive(Debug, Clone)]
pub struct Car {
    pub x: f64,
    pub y: f64,
    pub angle: f64,
    pub speed: f64,
    pub width: f64,
    pub height: f64,
    pub prev_speed: f64,
    pub turning: bool,
    pub current_zone_name: String,
    pub should_spawn_smoke: bool,
    pub should_spawn_dark_smoke: bool,

    pub name: String,
    pub color: [f32; 3],
    pub is_ai: bool,

    pub physics: Physics,
    pub damage: DamageState,
    pub npc: Option<NpcState>,
}

impl Car {
    pub fn new(track: &Track, overrides: CarOverrides) -> Self {
        let mut physics = Physics::default();
        overrides.physics.apply_to(&mut physics);

        let mut x = track.start_x;
        let mut y = track.start_y;
        let angle = track.start_angle;

        // Start offset along track
        if let Some(offset) = overrides.start_offset {
            let offset_pct = (1.0 + offset).rem_euclid(1.0);
            let pt = track.get_point_at_percent(offset_pct);
            x = pt.x;
            y = pt.y;
        }

        // Lateral offset perpendicular to track direction (for grid starts)
        if overrides.lateral_offset != 0.0 {
            let perp = angle + std::f64::consts::FRAC_PI_2;
            x += perp.cos() * overrides.lateral_offset;
            y += perp.sin() * overrides.lateral_offset;
        }

        Self {
            x,
            y,
            angle,
            speed: 0.0,
            width: 28.0,
            height: 14.0,
            prev_speed: 0.0,
            turning: false,
            current_zone_name: String::new(),
            should_spawn_smoke: false,
            should_spawn_dark_smoke: false,
            name: overrides.name.unwrap_or_else(|| "Player".into()),
            color: overrides.color.unwrap_or([0.85, 0.1, 0.1]),
            is_ai: overrides.is_ai,
            physics,
            damage: DamageState::new(),
            npc: None,
        }
    }

    /// Physics step. `time` is the global elapsed time (used for flat-tire thumping).
    pub fn update(
        &mut self,
        dt: f64,
        input: &CarInput,
        track: &Track,
        time: f64,
        rng: &mut GameRng,
    ) {
        let physics = self.physics;
        let total_mass = physics.mass + physics.fuel_mass;

        let zone = track.get_surface_at(self.x, self.y);
        let (zone_grip, zone_bumpiness, zone_name) = (zone.grip, zone.bumpiness, zone.name.clone());
        self.current_zone_name = zone_name;
        let on_track = track.is_on_track(self.x, self.y);

        // Damage modifiers
        let dmg_mods = damage::get_handling_modifiers(&self.damage);

        // Tire pressure grip
        let pressure_dev = (physics.tire_pressure - physics.optimal_pressure).abs();
        let pressure_grip = (1.0 - pressure_dev * 0.4).max(0.3);

        // Effective grip (also reduced by average tire health)
        let surface_grip = if on_track { zone_grip } else { 0.3 };
        let effective_grip =
            (surface_grip * pressure_grip * physics.grip_multiplier * dmg_mods.avg_tire_health)
                .clamp(0.1, 1.0);

        // Bumpiness: suspension damage amplifies it; flat tires add periodic thump
        let base_bump = if on_track {
            zone_bumpiness * physics.bump_multiplier
        } else {
            0.0
        };
        let mut bumpiness = base_bump * dmg_mods.bump_mult;

        let flat_count = damage::flat_tire_count(&self.damage);
        if flat_count > 0 && self.speed.abs() > 15.0 {
            // Thump frequency scales with speed (like wheel hitting rim each revolution)
            let thump_freq = self.speed.abs() / 60.0;
            let thump_phase = time * thump_freq;
            let thump = (thump_phase * 2.0 * std::f64::consts::PI).sin().max(0.0);
            bumpiness += thump * flat_count as f64 * 0.35;
        }

        self.prev_speed = self.speed;

        // Throttle / brake
        let throttle = if input.up && physics.fuel_mass > 0.0 {
            1.0
        } else {
            0.0
        };
        let braking = input.down;

        // Engine damage reduces drive force
        let drive_force = throttle * physics.engine_force * effective_grip * dmg_mods.engine_mult;
        let brake_decel = if braking {
            physics.brake_force * effective_grip
        } else {
            0.0
        };

        // Drag (body damage increases drag)
        let drag_force = physics.drag_coeff * self.speed * self.speed.abs() * dmg_mods.drag_mult;

        // Rolling resistance
        let rolling_force = physics.rolling_resistance * total_mass * 9.81;

        // Off-track grass drag
        let grass_drag = if !on_track {
            self.speed.abs() * 3.0
        } else {
            0.0
        };

        // Net force
        let mut net_force = drive_force - drag_force - rolling_force - grass_drag;
        if braking {
            if self.speed > 0.0 {
                net_force -= brake_decel;
            } else if self.speed < 0.0 {
                net_force += brake_decel;
            } else {
                net_force -= brake_decel * 0.3;
            }
        }

        let accel = net_force / total_mass;
        self.speed += accel * dt;

        // Bumpiness perturbation (suspension damage amplified)
        if bumpiness > 0.01 && self.speed.abs() > 20.0 {
            let bump_mag = bumpiness * self.speed.abs() * 0.0003;
            self.speed += (rng.next_f64() - 0.5) * bump_mag * self.speed;
            self.angle += (rng.next_f64() - 0.5) * bumpiness * 0.005;
        }

        // Clamp speed (max speed reduced by damage)
        let effective_max_speed = physics.max_speed * dmg_mods.max_speed_mult;
        self.speed = self.speed.clamp(-100.0, effective_max_speed);

        // Stop drifting at low speeds
        if self.speed.abs() < 1.0 && throttle == 0.0 && !braking {
            self.speed = 0.0;
        }

        // Fuel consumption
        if throttle > 0.0 {
            self.physics.fuel_mass = (self.physics.fuel_mass - physics.fuel_rate * dt).max(0.0);
        }

        // Turning (supports both boolean left/right and continuous steer)
        let turn_factor = (self.speed.abs() / 100.0).min(1.0) * effective_grip;
        self.turning = false;
        if let Some(steer) = input.steer {
            let steer_val = steer.clamp(-1.0, 1.0);
            if steer_val.abs() > 0.05 {
                self.angle += physics.base_turn_speed * steer_val * turn_factor * dt;
                self.turning = true;
            }
        } else {
            if input.left {
                self.angle -= physics.base_turn_speed * turn_factor * dt;
                self.turning = true;
            }
            if input.right {
                self.angle += physics.base_turn_speed * turn_factor * dt;
                self.turning = true;
            }
        }

        // Tire pull: asymmetric damage pulls the car to one side
        if dmg_mods.tire_pull.abs() > 0.01 && self.speed.abs() > 10.0 {
            let pull_turn = dmg_mods.tire_pull * physics.base_turn_speed * 0.35 * turn_factor;
            self.angle += pull_turn * dt;
        }

        // Move car
        self.x += self.angle.cos() * self.speed * dt;
        self.y += self.angle.sin() * self.speed * dt;

        // Keep in bounds
        self.x = self.x.clamp(10.0, 790.0);
        self.y = self.y.clamp(10.0, 590.0);

        // Smoke flags
        let is_braking = input.down && self.speed > 50.0;
        let is_sharp_turn = self.turning && self.speed.abs() > 120.0;
        self.should_spawn_smoke = is_braking || is_sharp_turn;
        self.should_spawn_dark_smoke = self.damage.engine < 0.55 && self.speed.abs() > 25.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn no_input() -> CarInput {
        CarInput::default()
    }

    fn setup() -> (Track, GameRng) {
        (Track::default_oval(), GameRng::new(42))
    }

    #[test]
    fn initializes_at_track_start_position() {
        let (track, _) = setup();
        let car = Car::new(&track, CarOverrides::default());
        assert_eq!(car.x, track.start_x);
        assert_eq!(car.y, track.start_y);
        assert_eq!(car.speed, 0.0);
        assert_eq!(car.angle, track.start_angle);
    }

    #[test]
    fn accelerates_when_throttle_pressed() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        let input = CarInput {
            up: true,
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.speed > 0.0);
    }

    #[test]
    fn stays_still_with_no_input() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.update(0.016, &no_input(), &track, 0.0, &mut rng);
        assert_eq!(car.speed, 0.0);
    }

    #[test]
    fn turns_left_when_left_pressed_at_speed() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = 100.0;
        let start_angle = car.angle;
        let input = CarInput {
            left: true,
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.angle < start_angle);
    }

    #[test]
    fn turns_right_when_right_pressed_at_speed() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = 100.0;
        let start_angle = car.angle;
        let input = CarInput {
            right: true,
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.angle > start_angle);
    }

    #[test]
    fn decelerates_when_braking() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = 200.0;
        let input = CarInput {
            down: true,
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.speed < 200.0);
    }

    #[test]
    fn consumes_fuel_when_accelerating() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        let start_fuel = car.physics.fuel_mass;
        let input = CarInput {
            up: true,
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.physics.fuel_mass < start_fuel);
    }

    #[test]
    fn does_not_accelerate_with_no_fuel() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.physics.fuel_mass = 0.0;
        let input = CarInput {
            up: true,
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.speed <= 0.0);
    }

    #[test]
    fn speed_is_clamped_to_max_speed() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = car.physics.max_speed + 100.0;
        car.update(0.016, &no_input(), &track, 0.0, &mut rng);
        assert!(car.speed <= car.physics.max_speed);
    }

    #[test]
    fn position_stays_within_screen_bounds() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.x = 5.0;
        car.y = 5.0;
        car.speed = -200.0;
        car.angle = std::f64::consts::PI;
        car.update(0.1, &no_input(), &track, 0.0, &mut rng);
        assert!(car.x >= 10.0);
        assert!(car.y >= 10.0);
    }

    #[test]
    fn applies_physics_overrides() {
        let (track, _) = setup();
        let car = Car::new(
            &track,
            CarOverrides {
                physics: PhysicsOverrides {
                    engine_force: Some(300_000.0),
                    ..Default::default()
                },
                ..Default::default()
            },
        );
        assert_eq!(car.physics.engine_force, 300_000.0);
        assert_eq!(car.physics.mass, 800.0); // other values unchanged
    }

    #[test]
    fn turns_left_with_continuous_negative_steer() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = 100.0;
        let start_angle = car.angle;
        let input = CarInput {
            steer: Some(-0.5),
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.angle < start_angle);
    }

    #[test]
    fn turns_right_with_continuous_positive_steer() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = 100.0;
        let start_angle = car.angle;
        let input = CarInput {
            steer: Some(0.5),
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        assert!(car.angle > start_angle);
    }

    #[test]
    fn ignores_tiny_steer_below_deadzone() {
        let (track, mut rng) = setup();
        let mut car = Car::new(&track, CarOverrides::default());
        car.speed = 100.0;
        let start_angle = car.angle;
        let input = CarInput {
            steer: Some(0.01),
            ..no_input()
        };
        car.update(0.016, &input, &track, 0.0, &mut rng);
        // Steer below deadzone (0.05) should not cause intentional turning
        // (tiny angle change may occur from bumpiness perturbation)
        assert!((car.angle - start_angle).abs() < 0.01);
    }
}
