//! Catmull-Rom spline interpolation (port of spline.lua).

use crate::P;

pub fn catmull_rom(p0: P, p1: P, p2: P, p3: P, t: f64) -> P {
    let t2 = t * t;
    let t3 = t2 * t;
    let x = 0.5
        * ((2.0 * p1.x)
            + (-p0.x + p2.x) * t
            + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2
            + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);
    let y = 0.5
        * ((2.0 * p1.y)
            + (-p0.y + p2.y) * t
            + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2
            + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);
    P { x, y }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passes_through_p1_at_t0() {
        let p = catmull_rom(
            P::new(0.0, 0.0),
            P::new(1.0, 2.0),
            P::new(3.0, 4.0),
            P::new(5.0, 6.0),
            0.0,
        );
        assert!((p.x - 1.0).abs() < 1e-12);
        assert!((p.y - 2.0).abs() < 1e-12);
    }

    #[test]
    fn reaches_p2_at_t1() {
        let p = catmull_rom(
            P::new(0.0, 0.0),
            P::new(1.0, 2.0),
            P::new(3.0, 4.0),
            P::new(5.0, 6.0),
            1.0,
        );
        assert!((p.x - 3.0).abs() < 1e-9);
        assert!((p.y - 4.0).abs() < 1e-9);
    }
}
