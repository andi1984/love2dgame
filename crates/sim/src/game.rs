//! Race state: laps, timer, countdown (port of game.lua).

use crate::track::Track;

#[derive(Debug, Clone)]
pub struct RaceState {
    pub car_laps: Vec<u32>,
    pub car_finished: Vec<bool>,
    pub max_laps: u32,
    pub timer: f64,
    pub won: bool,
    pub winner_index: Option<usize>,
    pub evolution_done: bool,
    pub countdown: f64,
    pub countdown_phase: i32,
    pub started: bool,
}

impl RaceState {
    pub fn new(num_cars: usize) -> Self {
        Self {
            car_laps: vec![0; num_cars],
            car_finished: vec![false; num_cars],
            max_laps: 3,
            timer: 0.0,
            won: false,
            winner_index: None,
            evolution_done: false,
            countdown: 3.0,
            countdown_phase: 3,
            started: false,
        }
    }

    pub fn player_laps(&self) -> u32 {
        self.car_laps.first().copied().unwrap_or(0)
    }

    pub fn update_countdown(&mut self, dt: f64) {
        self.countdown -= dt;
        self.countdown_phase = self.countdown.ceil() as i32;
        if self.countdown <= 0.0 {
            self.started = true;
        }
    }

    /// Segment-intersection lap detection: car path vs finish line, counting
    /// only crossings in the track's forward direction.
    pub fn check_finish_line(
        &mut self,
        track: &Track,
        prev_x: f64,
        prev_y: f64,
        new_x: f64,
        new_y: f64,
        car_index: usize,
    ) {
        let p1 = track.finish_p1;
        let p2 = track.finish_p2;

        let ax = new_x - prev_x;
        let ay = new_y - prev_y;
        let bx = p2.x - p1.x;
        let by = p2.y - p1.y;

        let denom = ax * by - ay * bx;
        if denom.abs() < 1e-10 {
            return; // parallel, no crossing
        }

        let t = ((p1.x - prev_x) * by - (p1.y - prev_y) * bx) / denom;
        let u = ((p1.x - prev_x) * ay - (p1.y - prev_y) * ax) / denom;

        // t in [0,1]: car path crosses; u in [0,1]: within finish line width
        if (0.0..=1.0).contains(&t) && (0.0..=1.0).contains(&u) {
            let fwd = track.finish_forward;
            let forward_dot = ax * fwd.x + ay * fwd.y;
            if forward_dot > 0.0 {
                self.car_laps[car_index] += 1;
                if self.car_laps[car_index] >= self.max_laps && !self.won {
                    self.won = true;
                    self.winner_index = Some(car_index);
                    self.car_finished[car_index] = true;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tracks::TrackList;

    #[test]
    fn initializes_with_correct_defaults() {
        let game = RaceState::new(1);
        assert_eq!(game.car_laps[0], 0);
        assert_eq!(game.max_laps, 3);
        assert_eq!(game.timer, 0.0);
        assert!(!game.won);
        assert!(!game.started);
        assert_eq!(game.countdown, 3.0);
        assert!(!game.evolution_done);
    }

    #[test]
    fn initializes_with_multiple_cars() {
        let game = RaceState::new(3);
        assert_eq!(game.car_laps.len(), 3);
        assert!(game.car_laps.iter().all(|&l| l == 0));
    }

    #[test]
    fn countdown_decreases_over_time() {
        let mut game = RaceState::new(1);
        game.update_countdown(1.0);
        assert!((game.countdown - 2.0).abs() < 1e-3);
        assert!(!game.started);
    }

    #[test]
    fn game_starts_when_countdown_reaches_zero() {
        let mut game = RaceState::new(1);
        game.update_countdown(3.5);
        assert!(game.started);
    }

    #[test]
    fn finish_line_increments_laps_on_forward_crossing() {
        let track = Track::default_oval();
        let mut game = RaceState::new(1);
        let y = (track.finish_y1 + track.finish_y2) / 2.0;
        game.check_finish_line(&track, track.finish_x - 5.0, y, track.finish_x + 5.0, y, 0);
        assert_eq!(game.car_laps[0], 1);
    }

    #[test]
    fn finish_line_rejects_backward_crossing() {
        let track = Track::default_oval();
        let mut game = RaceState::new(1);
        let y = (track.finish_y1 + track.finish_y2) / 2.0;
        game.check_finish_line(&track, track.finish_x + 5.0, y, track.finish_x - 5.0, y, 0);
        assert_eq!(game.car_laps[0], 0);
    }

    #[test]
    fn finish_line_ignores_crossing_outside_line_extent() {
        let track = Track::default_oval();
        let mut game = RaceState::new(1);
        game.check_finish_line(
            &track,
            track.finish_x - 5.0,
            10.0,
            track.finish_x + 5.0,
            10.0,
            0,
        );
        assert_eq!(game.car_laps[0], 0);
    }

    #[test]
    fn game_is_won_after_max_laps() {
        let track = Track::default_oval();
        let mut game = RaceState::new(1);
        let y = (track.finish_y1 + track.finish_y2) / 2.0;
        for _ in 0..game.max_laps {
            game.check_finish_line(&track, track.finish_x - 5.0, y, track.finish_x + 5.0, y, 0);
        }
        assert_eq!(game.car_laps[0], game.max_laps);
        assert!(game.won);
        assert_eq!(game.winner_index, Some(0));
    }

    #[test]
    fn tracks_laps_per_car_independently() {
        let track = Track::default_oval();
        let mut game = RaceState::new(3);
        let y = (track.finish_y1 + track.finish_y2) / 2.0;
        game.check_finish_line(&track, track.finish_x - 5.0, y, track.finish_x + 5.0, y, 1);
        assert_eq!(game.car_laps[0], 0);
        assert_eq!(game.car_laps[1], 1);
        assert_eq!(game.car_laps[2], 0);
    }

    #[test]
    fn npc_can_win_the_race() {
        let track = Track::default_oval();
        let mut game = RaceState::new(3);
        let y = (track.finish_y1 + track.finish_y2) / 2.0;
        for _ in 0..game.max_laps {
            game.check_finish_line(&track, track.finish_x - 5.0, y, track.finish_x + 5.0, y, 1);
        }
        assert!(game.won);
        assert_eq!(game.winner_index, Some(1));
    }

    #[test]
    fn first_winner_keeps_the_win() {
        let track = Track::default_oval();
        let mut game = RaceState::new(3);
        let y = (track.finish_y1 + track.finish_y2) / 2.0;
        for _ in 0..game.max_laps {
            game.check_finish_line(&track, track.finish_x - 5.0, y, track.finish_x + 5.0, y, 0);
        }
        assert_eq!(game.winner_index, Some(0));
        for _ in 0..game.max_laps {
            game.check_finish_line(&track, track.finish_x - 5.0, y, track.finish_x + 5.0, y, 1);
        }
        assert_eq!(game.winner_index, Some(0));
    }

    #[test]
    fn finish_line_works_on_all_default_tracks() {
        let list = TrackList::with_defaults();
        for cfg in &list.list {
            let track = Track::from_config(cfg);
            let mut game = RaceState::new(1);
            let fwd = track.finish_forward;
            let cx = track.finish_point.x;
            let cy = track.finish_point.y;
            game.check_finish_line(
                &track,
                cx - fwd.x * 5.0,
                cy - fwd.y * 5.0,
                cx + fwd.x * 5.0,
                cy + fwd.y * 5.0,
                0,
            );
            assert_eq!(
                game.car_laps[0], 1,
                "{}: lap should count when crossing finish forward",
                cfg.name
            );

            // Backward crossing must not count
            let mut game = RaceState::new(1);
            game.check_finish_line(
                &track,
                cx + fwd.x * 5.0,
                cy + fwd.y * 5.0,
                cx - fwd.x * 5.0,
                cy - fwd.y * 5.0,
                0,
            );
            assert_eq!(
                game.car_laps[0], 0,
                "{}: backward crossing counted",
                cfg.name
            );
        }
    }
}
