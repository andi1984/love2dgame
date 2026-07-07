//! Car-to-car collision detection (SAT on OBBs) and impulse resolution
//! (port of collision.lua).

use crate::car::Car;

#[derive(Debug, Clone, Copy)]
pub struct CollisionEvent {
    pub idx1: usize,
    pub idx2: usize,
    pub overlap: f64,
    pub axis_x: f64,
    pub axis_y: f64,
}

struct Obb {
    corners: [(f64, f64); 4],
    ca: f64,
    sa: f64,
}

fn get_corners_and_axes(car: &Car) -> Obb {
    let hw = car.width / 2.0;
    let hh = car.height / 2.0;
    let ca = car.angle.cos();
    let sa = car.angle.sin();
    Obb {
        corners: [
            (car.x + ca * hw - sa * hh, car.y + sa * hw + ca * hh),
            (car.x + ca * hw + sa * hh, car.y + sa * hw - ca * hh),
            (car.x - ca * hw + sa * hh, car.y - sa * hw - ca * hh),
            (car.x - ca * hw - sa * hh, car.y - sa * hw + ca * hh),
        ],
        ca,
        sa,
    }
}

fn project(corners: &[(f64, f64); 4], ax: f64, ay: f64) -> (f64, f64) {
    let mut mn = f64::INFINITY;
    let mut mx = f64::NEG_INFINITY;
    for &(cx, cy) in corners {
        let d = cx * ax + cy * ay;
        mn = mn.min(d);
        mx = mx.max(d);
    }
    (mn, mx)
}

/// SAT overlap test; returns (overlap, axis) or None when separated.
fn sat_test(c1: &Car, c2: &Car) -> Option<(f64, (f64, f64))> {
    let o1 = get_corners_and_axes(c1);
    let o2 = get_corners_and_axes(c2);
    let axes = [
        (o1.ca, o1.sa),
        (-o1.sa, o1.ca),
        (o2.ca, o2.sa),
        (-o2.sa, o2.ca),
    ];
    let mut min_overlap = f64::INFINITY;
    let mut min_axis = axes[0];
    for &axis in &axes {
        let (mn1, mx1) = project(&o1.corners, axis.0, axis.1);
        let (mn2, mx2) = project(&o2.corners, axis.0, axis.1);
        if mn1 > mx2 || mn2 > mx1 {
            return None; // separating axis found
        }
        let ov = mx1.min(mx2) - mn1.max(mn2);
        if ov < min_overlap {
            min_overlap = ov;
            min_axis = axis;
        }
    }
    Some((min_overlap, min_axis))
}

/// Check every pair of cars for OBB overlaps.
pub fn check_all(cars: &[Car]) -> Vec<CollisionEvent> {
    let mut events = Vec::new();
    for i in 0..cars.len() {
        for j in (i + 1)..cars.len() {
            let (c1, c2) = (&cars[i], &cars[j]);
            // Quick circle pre-check (broad phase)
            let dx = c2.x - c1.x;
            let dy = c2.y - c1.y;
            let dist2 = dx * dx + dy * dy;
            let r_sum = (c1.width + c2.width) * 0.65;
            if dist2 < r_sum * r_sum {
                if let Some((overlap, axis)) = sat_test(c1, c2) {
                    events.push(CollisionEvent {
                        idx1: i,
                        idx2: j,
                        overlap,
                        axis_x: axis.0,
                        axis_y: axis.1,
                    });
                }
            }
        }
    }
    events
}

/// Resolve one collision event: positional correction + impulse exchange.
/// Returns the impact speed (for damage calculation).
pub fn resolve(cars: &mut [Car], event: &CollisionEvent) -> f64 {
    let (i, j) = (event.idx1, event.idx2);
    debug_assert!(i < j);
    let (head, tail) = cars.split_at_mut(j);
    let c1 = &mut head[i];
    let c2 = &mut tail[0];

    let overlap = event.overlap;
    let (mut ax, mut ay) = (event.axis_x, event.axis_y);

    // Make sure axis points from c1 toward c2
    let dx = c2.x - c1.x;
    let dy = c2.y - c1.y;
    if dx * ax + dy * ay < 0.0 {
        ax = -ax;
        ay = -ay;
    }

    // Positional correction: push each car half the overlap
    let push = (overlap + 0.5) * 0.5;
    c1.x -= ax * push;
    c1.y -= ay * push;
    c2.x += ax * push;
    c2.y += ay * push;

    // World-space velocity vectors
    let v1x = c1.angle.cos() * c1.speed;
    let v1y = c1.angle.sin() * c1.speed;
    let v2x = c2.angle.cos() * c2.speed;
    let v2y = c2.angle.sin() * c2.speed;

    // Relative velocity along the collision normal
    let rel_vel = (v1x - v2x) * ax + (v1y - v2y) * ay;
    let impact_speed = rel_vel.abs();

    if rel_vel > 0.0 {
        // Impulse exchange (equal mass approximation, coefficient of restitution)
        let e = 0.28;
        let impulse = (1.0 + e) * rel_vel / 2.0;

        let dot1 = ax * c1.angle.cos() + ay * c1.angle.sin();
        let dot2 = ax * c2.angle.cos() + ay * c2.angle.sin();
        c1.speed -= dot1 * impulse;
        c2.speed += dot2 * impulse;

        // Small angular deflection for realism
        let cross = ax * dy - ay * dx;
        let deflect = (cross * 0.007).clamp(-0.18, 0.18);
        c1.angle += deflect * 0.3;
        c2.angle -= deflect * 0.3;
    }

    impact_speed
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::car::{Car, CarOverrides};
    use crate::track::Track;

    fn two_cars(track: &Track) -> Vec<Car> {
        vec![
            Car::new(track, CarOverrides::default()),
            Car::new(track, CarOverrides::default()),
        ]
    }

    #[test]
    fn overlapping_cars_collide() {
        let track = Track::default_oval();
        let mut cars = two_cars(&track);
        cars[0].x = 100.0;
        cars[0].y = 100.0;
        cars[0].angle = 0.0;
        cars[1].x = 110.0;
        cars[1].y = 100.0;
        cars[1].angle = 0.0;
        let events = check_all(&cars);
        assert_eq!(events.len(), 1);
        assert!(events[0].overlap > 0.0);
    }

    #[test]
    fn distant_cars_do_not_collide() {
        let track = Track::default_oval();
        let mut cars = two_cars(&track);
        cars[0].x = 100.0;
        cars[0].y = 100.0;
        cars[1].x = 300.0;
        cars[1].y = 300.0;
        assert!(check_all(&cars).is_empty());
    }

    #[test]
    fn resolve_separates_cars_and_returns_impact_speed() {
        let track = Track::default_oval();
        let mut cars = two_cars(&track);
        cars[0].x = 100.0;
        cars[0].y = 100.0;
        cars[0].angle = 0.0;
        cars[0].speed = 100.0; // driving toward car 1
        cars[1].x = 115.0;
        cars[1].y = 100.0;
        cars[1].angle = 0.0;
        cars[1].speed = 0.0;

        let events = check_all(&cars);
        assert_eq!(events.len(), 1);
        let dist_before = (cars[1].x - cars[0].x).abs();
        let impact = resolve(&mut cars, &events[0]);
        let dist_after = (cars[1].x - cars[0].x).abs();

        assert!(impact > 0.0, "closing speed should register as impact");
        assert!(dist_after > dist_before, "cars should be pushed apart");
        assert!(cars[0].speed < 100.0, "collider slows down");
        assert!(cars[1].speed > 0.0, "hit car gets pushed forward");
    }
}
