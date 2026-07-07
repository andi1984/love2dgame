//! Damage system (port of damage.lua).
//! Tracks structural damage per car and computes handling modifiers.

use crate::track::Track;

pub const FLAT_TIRE_THRESHOLD: f64 = 0.25;
const CURB_DAMAGE_PER_SEC: f64 = 0.05;
const OFFROAD_WEAR_PER_SEC: f64 = 0.008;

/// Wheel index: FL, FR, RL, RR.
pub const FL: usize = 0;
pub const FR: usize = 1;
pub const RL: usize = 2;
pub const RR: usize = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Front,
    Rear,
    Left,
    Right,
}

#[derive(Debug, Clone)]
pub struct DamageState {
    /// Tire health per wheel [0 = destroyed/flat, 1 = perfect], order FL FR RL RR.
    pub tires: [f64; 4],
    /// Cached flat-tire flag per wheel.
    pub flat_tires: [bool; 4],
    /// Body panel health: front, rear, left, right.
    pub body_front: f64,
    pub body_rear: f64,
    pub body_left: f64,
    pub body_right: f64,
    pub engine: f64,
    /// Suspension health per corner, order FL FR RL RR.
    pub suspension: [f64; 4],

    // Visual / audio event flags (reset each frame)
    pub new_flat: bool,
    pub new_impact: bool,
    pub impact_side: Option<Side>,
    pub impact_force: f64,
    pub impact_flash: f64,
}

impl Default for DamageState {
    fn default() -> Self {
        Self::new()
    }
}

impl DamageState {
    pub fn new() -> Self {
        Self {
            tires: [1.0; 4],
            flat_tires: [false; 4],
            body_front: 1.0,
            body_rear: 1.0,
            body_left: 1.0,
            body_right: 1.0,
            engine: 1.0,
            suspension: [1.0; 4],
            new_flat: false,
            new_impact: false,
            impact_side: None,
            impact_force: 0.0,
            impact_flash: 0.0,
        }
    }

    pub fn body(&self, side: Side) -> f64 {
        match side {
            Side::Front => self.body_front,
            Side::Rear => self.body_rear,
            Side::Left => self.body_left,
            Side::Right => self.body_right,
        }
    }

    fn body_mut(&mut self, side: Side) -> &mut f64 {
        match side {
            Side::Front => &mut self.body_front,
            Side::Rear => &mut self.body_rear,
            Side::Left => &mut self.body_left,
            Side::Right => &mut self.body_right,
        }
    }

    pub fn avg_tire_health(&self) -> f64 {
        self.tires.iter().sum::<f64>() / 4.0
    }

    pub fn avg_body_health(&self) -> f64 {
        (self.body_front + self.body_rear + self.body_left + self.body_right) / 4.0
    }

    fn refresh_flats(&mut self) {
        for i in 0..4 {
            let was_flat = self.flat_tires[i];
            self.flat_tires[i] = self.tires[i] < FLAT_TIRE_THRESHOLD;
            if self.flat_tires[i] && !was_flat {
                self.new_flat = true;
            }
        }
    }
}

/// Environment damage (curbs, off-road). Called each frame per car.
pub fn update_environment(
    dmg: &mut DamageState,
    car_x: f64,
    car_y: f64,
    car_speed: f64,
    track: &Track,
    dt: f64,
) {
    // Reset per-frame flags
    dmg.new_flat = false;
    dmg.new_impact = false;

    if dmg.impact_flash > 0.0 {
        dmg.impact_flash = (dmg.impact_flash - dt).max(0.0);
    }

    let speed = car_speed.abs();
    let on_track = track.is_on_track(car_x, car_y);
    let zone = track.get_surface_at(car_x, car_y);

    // Curb damage: on-track but low-grip zone
    let on_curb = on_track && zone.grip < 0.72 && zone.grip > 0.2;
    if on_curb && speed > 20.0 {
        let intensity = (speed / 200.0).min(1.0);
        let curb_dmg = CURB_DAMAGE_PER_SEC * intensity * dt;

        dmg.tires[FL] = (dmg.tires[FL] - curb_dmg * 0.9).max(0.0);
        dmg.tires[FR] = (dmg.tires[FR] - curb_dmg * 0.9).max(0.0);
        dmg.tires[RL] = (dmg.tires[RL] - curb_dmg * 0.5).max(0.0);
        dmg.tires[RR] = (dmg.tires[RR] - curb_dmg * 0.5).max(0.0);
        dmg.suspension[FL] = (dmg.suspension[FL] - curb_dmg * 0.4).max(0.0);
        dmg.suspension[FR] = (dmg.suspension[FR] - curb_dmg * 0.4).max(0.0);
    }

    // Off-road wear (very slow)
    if !on_track && speed > 30.0 {
        let wear = OFFROAD_WEAR_PER_SEC * (speed / 150.0).min(1.0) * dt;
        for t in dmg.tires.iter_mut() {
            *t = (*t - wear).max(0.0);
        }
    }

    dmg.refresh_flats();
}

/// Transform a collision normal into a car's local frame to determine impact side.
fn get_side(car_angle: f64, world_nx: f64, world_ny: f64) -> Side {
    let ca = (-car_angle).cos();
    let sa = (-car_angle).sin();
    let lx = world_nx * ca - world_ny * sa;
    let ly = world_nx * sa + world_ny * ca;
    if lx.abs() >= ly.abs() {
        if lx > 0.0 {
            Side::Front
        } else {
            Side::Rear
        }
    } else if ly > 0.0 {
        Side::Right
    } else {
        Side::Left
    }
}

fn apply_tire_dmg(dmg: &mut DamageState, side: Side, amt: f64) {
    let (wheels, factor): (&[usize], f64) = match side {
        Side::Front => (&[FL, FR], 0.45),
        Side::Rear => (&[RL, RR], 0.45),
        Side::Left => (&[FL, RL], 0.65),
        Side::Right => (&[FR, RR], 0.65),
    };
    for &w in wheels {
        dmg.tires[w] = (dmg.tires[w] - amt * factor).max(0.0);
    }
}

fn apply_susp_dmg(dmg: &mut DamageState, side: Side, amt: f64) {
    let (wheels, factor): (&[usize], f64) = match side {
        Side::Front => (&[FL, FR], 0.5),
        Side::Rear => (&[RL, RR], 0.5),
        Side::Left => (&[FL, RL], 0.55),
        Side::Right => (&[FR, RR], 0.55),
    };
    for &w in wheels {
        dmg.suspension[w] = (dmg.suspension[w] - amt * factor).max(0.0);
    }
}

/// Collision damage between two cars.
/// `impact_speed` is the magnitude of relative velocity along the collision axis.
#[allow(clippy::too_many_arguments)]
pub fn apply_collision(
    dmg1: &mut DamageState,
    car1_x: f64,
    car1_y: f64,
    car1_angle: f64,
    dmg2: &mut DamageState,
    car2_x: f64,
    car2_y: f64,
    car2_angle: f64,
    impact_speed: f64,
) {
    let dx = car2_x - car1_x;
    let dy = car2_y - car1_y;
    let dist = (dx * dx + dy * dy).sqrt();
    if dist < 0.01 {
        return;
    }
    let (nx, ny) = (dx / dist, dy / dist);

    let side1 = get_side(car1_angle, nx, ny);
    let side2 = get_side(car2_angle, -nx, -ny);

    // Damage scales quadratically with speed (severe at high speed)
    let force = ((impact_speed / 120.0).powi(2)).min(1.0);
    let linear_force = (impact_speed / 120.0).min(1.0);

    // Body panels
    *dmg1.body_mut(side1) = (dmg1.body(side1) - force * 0.75).max(0.0);
    *dmg2.body_mut(side2) = (dmg2.body(side2) - force * 0.75).max(0.0);

    apply_tire_dmg(dmg1, side1, linear_force);
    apply_tire_dmg(dmg2, side2, linear_force);

    // Engine damage on severe frontal / rear collisions
    if force > 0.35 {
        if side1 == Side::Front || side1 == Side::Rear {
            dmg1.engine = (dmg1.engine - force * 0.40).max(0.0);
        }
        if side2 == Side::Front || side2 == Side::Rear {
            dmg2.engine = (dmg2.engine - force * 0.40).max(0.0);
        }
    }

    apply_susp_dmg(dmg1, side1, linear_force);
    apply_susp_dmg(dmg2, side2, linear_force);

    dmg1.refresh_flats();
    dmg2.refresh_flats();

    dmg1.new_impact = true;
    dmg1.impact_flash = dmg1.impact_flash.max(0.4);
    dmg1.impact_side = Some(side1);
    dmg1.impact_force = force;

    dmg2.new_impact = true;
    dmg2.impact_flash = dmg2.impact_flash.max(0.4);
    dmg2.impact_side = Some(side2);
    dmg2.impact_force = force;
}

/// Handling modifiers consumed by `car::update`.
#[derive(Debug, Clone, Copy)]
pub struct HandlingModifiers {
    /// Positive = pull to the left, negative = pull to the right.
    pub tire_pull: f64,
    pub engine_mult: f64,
    pub drag_mult: f64,
    pub bump_mult: f64,
    pub max_speed_mult: f64,
    pub avg_tire_health: f64,
}

pub fn get_handling_modifiers(dmg: &DamageState) -> HandlingModifiers {
    let left_health = (dmg.tires[FL] + dmg.tires[RL]) / 2.0;
    let right_health = (dmg.tires[FR] + dmg.tires[RR]) / 2.0;
    let tire_pull = (right_health - left_health) * 0.85;

    let avg_tire_health = dmg.avg_tire_health();
    let engine_mult = 0.20 + dmg.engine * 0.80;

    let avg_body_dmg = 1.0 - dmg.avg_body_health();
    let drag_mult = 1.0 + avg_body_dmg * 0.55;

    let avg_susp = dmg.suspension.iter().sum::<f64>() / 4.0;
    let bump_mult = 1.0 + (1.0 - avg_susp) * 4.5;

    let max_speed_mult = (0.35 + avg_tire_health * 0.65) * (0.45 + dmg.engine * 0.55);

    HandlingModifiers {
        tire_pull,
        engine_mult,
        drag_mult,
        bump_mult,
        max_speed_mult,
        avg_tire_health,
    }
}

/// Overall damage severity 0 (none) → 1 (destroyed), for display.
pub fn get_severity(dmg: &DamageState) -> f64 {
    1.0 - (dmg.avg_tire_health() * 0.5 + dmg.avg_body_health() * 0.3 + dmg.engine * 0.2)
}

pub fn flat_tire_count(dmg: &DamageState) -> usize {
    dmg.flat_tires.iter().filter(|&&f| f).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_state_has_no_damage() {
        let dmg = DamageState::new();
        assert_eq!(dmg.avg_tire_health(), 1.0);
        assert_eq!(dmg.engine, 1.0);
        assert_eq!(flat_tire_count(&dmg), 0);
        assert!(get_severity(&dmg).abs() < 1e-12);
    }

    #[test]
    fn undamaged_modifiers_are_neutral() {
        let m = get_handling_modifiers(&DamageState::new());
        assert!((m.tire_pull).abs() < 1e-12);
        assert!((m.engine_mult - 1.0).abs() < 1e-12);
        assert!((m.drag_mult - 1.0).abs() < 1e-12);
        assert!((m.bump_mult - 1.0).abs() < 1e-12);
        assert!((m.max_speed_mult - 1.0).abs() < 1e-12);
    }

    #[test]
    fn head_on_collision_damages_front() {
        let mut d1 = DamageState::new();
        let mut d2 = DamageState::new();
        // car1 at origin facing +x, car2 ahead of it facing -x, high impact speed
        apply_collision(
            &mut d1,
            0.0,
            0.0,
            0.0,
            &mut d2,
            30.0,
            0.0,
            std::f64::consts::PI,
            120.0,
        );
        assert!(d1.body_front < 1.0);
        assert!(d2.body_front < 1.0);
        assert!(d1.engine < 1.0, "severe frontal impact damages engine");
        assert!(d1.new_impact && d2.new_impact);
        assert_eq!(d1.impact_side, Some(Side::Front));
        assert_eq!(d2.impact_side, Some(Side::Front));
    }

    #[test]
    fn side_collision_damages_side_tires() {
        let mut d1 = DamageState::new();
        let mut d2 = DamageState::new();
        // car2 to the right of car1 (both facing +x) → car1 hit on its right
        apply_collision(&mut d1, 0.0, 0.0, 0.0, &mut d2, 0.0, 20.0, 0.0, 120.0);
        assert_eq!(d1.impact_side, Some(Side::Right));
        assert!(d1.tires[FR] < 1.0);
        assert!(d1.tires[RR] < 1.0);
        assert!((d1.tires[FL] - 1.0).abs() < 1e-12);
    }

    #[test]
    fn asymmetric_tire_damage_causes_pull() {
        let mut dmg = DamageState::new();
        dmg.tires[FR] = 0.2;
        dmg.tires[RR] = 0.2;
        let m = get_handling_modifiers(&dmg);
        assert!(
            m.tire_pull < 0.0,
            "right-side damage pulls right (negative)"
        );
    }

    #[test]
    fn flat_tires_are_flagged() {
        let mut dmg = DamageState::new();
        dmg.tires[FL] = 0.1;
        dmg.refresh_flats();
        assert!(dmg.flat_tires[FL]);
        assert!(dmg.new_flat);
        assert_eq!(flat_tire_count(&dmg), 1);
    }
}
