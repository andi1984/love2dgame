//! Neuroevolution: (1+1) evolutionary strategy per NPC (port of evolution.lua).

use crate::car::Car;
use crate::nnet;
use crate::rng::GameRng;
use crate::track::Track;

/// Fitness score from race performance.
pub fn calculate_fitness(car: &Car, track: &Track, race_time: f64, laps_completed: u32) -> f64 {
    let mut fitness = 0.0;

    // Primary: progress along track (heavily weighted)
    let track_pct = track.get_track_percent(car.x, car.y);
    fitness += laps_completed as f64 * 2000.0 + track_pct * 2000.0;

    let (avg_speed, time_off_track, time_stationary) = car
        .npc
        .as_ref()
        .map(|n| (n.avg_speed, n.time_off_track, n.time_stationary))
        .unwrap_or((0.0, 0.0, 0.0));

    // Secondary: average speed reward
    fitness += avg_speed * 3.0;

    // Strong penalty: time off track (primary learning signal)
    fitness -= time_off_track * 100.0;

    // Penalty: time spent stationary
    fitness -= time_stationary * 40.0;

    // Bonus: on-track ratio
    if race_time > 0.0 {
        let on_track_ratio = 1.0 - (time_off_track / race_time).min(1.0);
        fitness += on_track_ratio * 500.0;
    }

    // Bonus: faster completion
    if laps_completed > 0 && race_time > 0.0 {
        fitness += (1000.0 / race_time) * laps_completed as f64;
    }

    fitness
}

/// Evolve an NPC after a race using (1+1)-ES.
pub fn evolve_after_race(car: &mut Car, rng: &mut GameRng) {
    let Some(npc) = car.npc.as_mut() else { return };

    if npc.current_fitness > npc.best_fitness {
        // Improvement: keep the current brain as the new best
        npc.best_brain = nnet::serialize(&npc.brain);
        npc.best_fitness = npc.current_fitness;
        npc.generation += 1;
        // Small mutation for next race (exploit)
        npc.brain = nnet::mutate(
            &nnet::deserialize(&npc.best_brain),
            npc.personality.mutation_rate,
            npc.personality.mutation_strength * 0.5,
            rng,
        );
    } else {
        // No improvement: revert to best and try a larger mutation (explore)
        npc.brain = nnet::mutate(
            &nnet::deserialize(&npc.best_brain),
            npc.personality.mutation_rate,
            npc.personality.mutation_strength,
            rng,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::car::{CarOverrides, NpcState};
    use crate::npc_profiles::Personality;

    fn ai_car_with_fitness(
        track: &Track,
        best_fitness: f64,
        current_fitness: f64,
        generation: u32,
    ) -> Car {
        let mut rng = GameRng::new(42);
        let brain = nnet::new(&[13, 16, 4], None, &mut rng);
        let best_brain = nnet::serialize(&brain);
        let mut car = Car::new(
            track,
            CarOverrides {
                is_ai: true,
                ..Default::default()
            },
        );
        car.npc = Some(NpcState {
            brain,
            personality: Personality {
                mutation_rate: 0.15,
                mutation_strength: 0.3,
                initial_bias: Default::default(),
                physics: Default::default(),
                errors: None,
            },
            best_brain,
            best_fitness,
            generation,
            current_fitness,
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
        car
    }

    #[test]
    fn keeps_improvement_when_fitness_increases() {
        let track = Track::default_oval();
        let mut car = ai_car_with_fitness(&track, 100.0, 200.0, 0);
        let mut rng = GameRng::new(42);
        evolve_after_race(&mut car, &mut rng);
        let npc = car.npc.as_ref().unwrap();
        assert_eq!(npc.best_fitness, 200.0);
        assert_eq!(npc.generation, 1);
    }

    #[test]
    fn reverts_to_best_when_fitness_decreases() {
        let track = Track::default_oval();
        let mut car = ai_car_with_fitness(&track, 200.0, 100.0, 5);
        let mut rng = GameRng::new(42);
        evolve_after_race(&mut car, &mut rng);
        let npc = car.npc.as_ref().unwrap();
        assert_eq!(npc.best_fitness, 200.0);
        assert_eq!(npc.generation, 5);
    }

    #[test]
    fn calculates_positive_fitness_from_race_metrics() {
        let track = Track::default_oval();
        let mut car = ai_car_with_fitness(&track, 0.0, 0.0, 0);
        car.npc.as_mut().unwrap().avg_speed = 100.0;
        let fitness = calculate_fitness(&car, &track, 30.0, 2);
        assert!(fitness > 0.0);
    }

    #[test]
    fn penalizes_time_off_track() {
        let track = Track::default_oval();
        let mut car = ai_car_with_fitness(&track, 0.0, 0.0, 0);
        car.npc.as_mut().unwrap().avg_speed = 100.0;
        let f1 = calculate_fitness(&car, &track, 30.0, 1);
        car.npc.as_mut().unwrap().time_off_track = 10.0;
        let f2 = calculate_fitness(&car, &track, 30.0, 1);
        assert!(f2 < f1);
    }

    #[test]
    fn rewards_on_track_ratio() {
        let track = Track::default_oval();
        let mut car = ai_car_with_fitness(&track, 0.0, 0.0, 0);
        car.npc.as_mut().unwrap().avg_speed = 100.0;
        let f1 = calculate_fitness(&car, &track, 30.0, 0);
        car.npc.as_mut().unwrap().time_off_track = 15.0;
        let f2 = calculate_fitness(&car, &track, 30.0, 0);
        assert!(f1 > f2, "fully on-track should have higher fitness");
    }
}
