//! NPC personality profiles (port of npc_profiles.lua).

use crate::car::PhysicsOverrides;
use crate::nnet::InitialBias;

#[derive(Debug, Clone, Copy)]
pub struct ErrorProfile {
    /// Gaussian noise magnitude on sensor inputs (misreads the track).
    pub sensor_noise: f64,
    /// Chance per second of a concentration lapse.
    pub lapse_chance: f64,
    pub lapse_duration_min: f64,
    pub lapse_duration_max: f64,
    /// Random wobble added to the steer value.
    pub steer_jitter: f64,
    /// Chance per second of ignoring the brake signal.
    pub brake_late_chance: f64,
}

#[derive(Debug, Clone)]
pub struct Personality {
    pub mutation_rate: f64,
    pub mutation_strength: f64,
    pub initial_bias: InitialBias,
    pub physics: PhysicsOverrides,
    pub errors: Option<ErrorProfile>,
}

#[derive(Debug, Clone)]
pub struct Profile {
    pub name: &'static str,
    pub color: [f32; 3],
    pub stripe_color: [f32; 3],
    pub personality: Personality,
}

pub fn list() -> Vec<Profile> {
    vec![
        Profile {
            name: "Aggressive Axel",
            color: [0.2, 0.4, 0.9],
            stripe_color: [0.4, 0.6, 1.0],
            personality: Personality {
                mutation_rate: 0.15,
                mutation_strength: 0.3,
                initial_bias: InitialBias {
                    throttle: 0.3,
                    brake: -0.2,
                    steer_sensitivity: 0.1,
                },
                physics: PhysicsOverrides {
                    engine_force: Some(260_000.0),
                    brake_force: Some(180_000.0),
                    base_turn_speed: Some(2.8),
                    grip_multiplier: Some(0.95),
                    ..Default::default()
                },
                // Aggressive mistakes: pushes too hard, brakes late, but stays focused
                errors: Some(ErrorProfile {
                    sensor_noise: 0.10,
                    lapse_chance: 0.15,
                    lapse_duration_min: 0.15,
                    lapse_duration_max: 0.35,
                    steer_jitter: 0.04,
                    brake_late_chance: 0.30,
                }),
            },
        },
        Profile {
            name: "Cautious Clara",
            color: [0.9, 0.7, 0.1],
            stripe_color: [1.0, 0.85, 0.3],
            personality: Personality {
                mutation_rate: 0.10,
                mutation_strength: 0.2,
                initial_bias: InitialBias {
                    throttle: 0.0,
                    brake: 0.1,
                    steer_sensitivity: 0.2,
                },
                physics: PhysicsOverrides {
                    engine_force: Some(240_000.0),
                    brake_force: Some(220_000.0),
                    base_turn_speed: Some(3.2),
                    grip_multiplier: Some(1.05),
                    ..Default::default()
                },
                // Cautious mistakes: loses concentration, overcorrects
                errors: Some(ErrorProfile {
                    sensor_noise: 0.05,
                    lapse_chance: 0.30,
                    lapse_duration_min: 0.25,
                    lapse_duration_max: 0.60,
                    steer_jitter: 0.08,
                    brake_late_chance: 0.08,
                }),
            },
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_profiles_defined() {
        let profiles = list();
        assert_eq!(profiles.len(), 2);
        assert_eq!(profiles[0].name, "Aggressive Axel");
        assert_eq!(profiles[1].name, "Cautious Clara");
    }
}
