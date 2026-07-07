//! Procedural track generation (port of trackgen.lua).
//! Generates racing circuits from a seed value; deterministic per seed.

use crate::rng::Lcg;
use crate::spline::catmull_rom;
use crate::track::{SurfaceZone, TrackConfig};
use crate::P;

fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

/// Check if two line segments (p1-p2) and (p3-p4) intersect.
#[allow(clippy::too_many_arguments)]
fn segments_intersect(
    p1x: f64,
    p1y: f64,
    p2x: f64,
    p2y: f64,
    p3x: f64,
    p3y: f64,
    p4x: f64,
    p4y: f64,
) -> bool {
    let (d1x, d1y) = (p2x - p1x, p2y - p1y);
    let (d2x, d2y) = (p4x - p3x, p4y - p3y);
    let cross = d1x * d2y - d1y * d2x;
    if cross.abs() < 1e-10 {
        return false;
    }
    let (dx, dy) = (p3x - p1x, p3y - p1y);
    let t = (dx * d2y - dy * d2x) / cross;
    let u = (dx * d1y - dy * d1x) / cross;
    t > 0.0 && t < 1.0 && u > 0.0 && u < 1.0
}

fn generate_spline(points: &[P], segs_per_curve: usize) -> Vec<P> {
    let n = points.len();
    let mut path = Vec::with_capacity(n * segs_per_curve);
    for i in 0..n {
        let p0 = points[(i + n - 1) % n];
        let p1 = points[i];
        let p2 = points[(i + 1) % n];
        let p3 = points[(i + 2) % n];
        for j in 0..segs_per_curve {
            path.push(catmull_rom(
                p0,
                p1,
                p2,
                p3,
                j as f64 / segs_per_curve as f64,
            ));
        }
    }
    path
}

/// Validate a control-point loop: reject self-intersecting centerline or outer edge.
pub fn validate_points(points: &[P], width: f64) -> bool {
    let path = generate_spline(points, 10);
    let n = path.len();
    let half_w = width / 2.0;

    let get_normal = |idx: usize| -> (f64, f64) {
        let prev = path[(idx + n - 1) % n];
        let next = path[(idx + 1) % n];
        let dx = next.x - prev.x;
        let dy = next.y - prev.y;
        let len = (dx * dx + dy * dy).sqrt();
        if len < 1e-8 {
            (0.0, -1.0)
        } else {
            (-dy / len, dx / len)
        }
    };

    let self_intersects = |pts: &[P]| -> bool {
        let skip = 3;
        for i in 0..n {
            let i2 = (i + 1) % n;
            for j in (i + skip)..n {
                let j2 = (j + 1) % n;
                // Skip if j2 wraps to near i (1-based Lua logic preserved via +1 offsets)
                let a = (j2 as i64 - i as i64).abs();
                let wrap_dist = a.min(n as i64 - a);
                if wrap_dist >= skip as i64
                    && segments_intersect(
                        pts[i].x, pts[i].y, pts[i2].x, pts[i2].y, pts[j].x, pts[j].y, pts[j2].x,
                        pts[j2].y,
                    )
                {
                    return true;
                }
            }
        }
        false
    };

    if self_intersects(&path) {
        return false;
    }

    let outer: Vec<P> = (0..n)
        .map(|i| {
            let (nx, ny) = get_normal(i);
            P {
                x: path[i].x + nx * half_w,
                y: path[i].y + ny * half_w,
            }
        })
        .collect();

    !self_intersects(&outer)
}

const ADJECTIVES: [&str; 20] = [
    "Alpine", "Coastal", "Grand", "Silver", "Thunder", "Golden", "Crystal", "Shadow", "Sunset",
    "Iron", "Royal", "Emerald", "Storm", "Crimson", "Sapphire", "Northern", "Southern", "Desert",
    "Misty", "Autumn",
];

const NOUNS: [&str; 10] = [
    "Circuit", "Speedway", "Ring", "Rally", "Raceway", "Loop", "Run", "Prix", "Course", "Track",
];

fn generate_name(rng: &mut Lcg) -> String {
    format!("{} {}", rng.pick(&ADJECTIVES), rng.pick(&NOUNS))
}

struct ZoneTemplate {
    grip: (f64, f64),
    bump: (f64, f64),
    names: [&'static str; 3],
    color: [f64; 4],
}

const SMOOTH: ZoneTemplate = ZoneTemplate {
    grip: (0.92, 0.98),
    bump: (0.02, 0.08),
    names: ["Smooth Tarmac", "Racing Line", "Fresh Asphalt"],
    color: [0.5, 0.5, 0.5, 0.0],
};
const WORN: ZoneTemplate = ZoneTemplate {
    grip: (0.78, 0.88),
    bump: (0.10, 0.25),
    names: ["Worn Patch", "Patched Road", "Aged Tarmac"],
    color: [0.55, 0.45, 0.35, 0.06],
};
const BUMPY: ZoneTemplate = ZoneTemplate {
    grip: (0.80, 0.90),
    bump: (0.30, 0.60),
    names: ["Bumpy Section", "Rough Road", "Cobblestone"],
    color: [0.4, 0.35, 0.3, 0.07],
};
const WET: ZoneTemplate = ZoneTemplate {
    grip: (0.55, 0.72),
    bump: (0.05, 0.15),
    names: ["Damp Corner", "Wet Section", "Puddle Zone"],
    color: [0.2, 0.3, 0.6, 0.08],
};
const GRAVEL: ZoneTemplate = ZoneTemplate {
    grip: (0.60, 0.75),
    bump: (0.20, 0.45),
    names: ["Gravel Patch", "Sandy Stretch", "Loose Surface"],
    color: [0.6, 0.5, 0.4, 0.09],
};

fn generate_surface_zones(rng: &mut Lcg, curvatures: &[f64]) -> Vec<SurfaceZone> {
    let num_zones = rng.int(4, 7) as usize;
    let mut zones = Vec::with_capacity(num_zones);

    for i in 1..=num_zones {
        let start_pct = (i - 1) as f64 / num_zones as f64;
        let end_pct = i as f64 / num_zones as f64;

        // Zone character from average curvature in this segment
        let mut avg_curv = 0.0;
        if !curvatures.is_empty() {
            let start_idx = ((start_pct * curvatures.len() as f64).floor() as usize).max(1) - 1;
            let end_idx =
                ((end_pct * curvatures.len() as f64).floor() as usize).min(curvatures.len());
            let mut samples = 0;
            for c in curvatures.iter().take(end_idx).skip(start_idx) {
                avg_curv += c;
                samples += 1;
            }
            if samples > 0 {
                avg_curv /= samples as f64;
            }
        }

        let roll = rng.next();
        let template = if avg_curv > 0.15 {
            if roll < 0.35 {
                &WET
            } else if roll < 0.60 {
                &BUMPY
            } else if roll < 0.80 {
                &WORN
            } else {
                &SMOOTH
            }
        } else if avg_curv > 0.06 {
            if roll < 0.15 {
                &WET
            } else if roll < 0.35 {
                &WORN
            } else if roll < 0.50 {
                &GRAVEL
            } else {
                &SMOOTH
            }
        } else if roll < 0.10 {
            &GRAVEL
        } else if roll < 0.25 {
            &WORN
        } else {
            &SMOOTH
        };

        let grip = rng.range(template.grip.0, template.grip.1);
        let bumpiness = rng.range(template.bump.0, template.bump.1);
        let name = *rng.pick(&template.names);

        zones.push(SurfaceZone {
            start_pct,
            end_pct,
            grip,
            bumpiness,
            name: name.into(),
            color: template.color,
        });
    }

    zones[0].start_pct = 0.0;
    zones.last_mut().unwrap().end_pct = 1.0;
    zones
}

fn compute_curvatures(path: &[P]) -> Vec<f64> {
    let n = path.len();
    let mut curvatures = Vec::with_capacity(n);
    for i in 0..n {
        let prev = path[(i + n - 1) % n];
        let curr = path[i];
        let next = path[(i + 1) % n];
        let a1 = (curr.y - prev.y).atan2(curr.x - prev.x);
        let a2 = (next.y - curr.y).atan2(next.x - curr.x);
        let mut diff = a2 - a1;
        while diff > std::f64::consts::PI {
            diff -= 2.0 * std::f64::consts::PI;
        }
        while diff < -std::f64::consts::PI {
            diff += 2.0 * std::f64::consts::PI;
        }
        curvatures.push(diff.abs());
    }
    curvatures
}

const STYLE_NAMES: [&str; 3] = ["power", "technical", "flowing"];

fn style_description(style: &str) -> &'static str {
    match style {
        "power" => "High-speed sweeping curves",
        "technical" => "Tight technical corners",
        "flowing" => "Smooth flowing layout",
        _ => "A generated circuit",
    }
}

/// Generate a track configuration from a seed. Retries with `seed + 1` (up to
/// 5 attempts) when the generated layout self-intersects, exactly like the Lua
/// original.
pub fn generate(seed: i64) -> TrackConfig {
    generate_attempt(seed, 1)
}

fn generate_attempt(seed: i64, attempt: u32) -> TrackConfig {
    let mut rng = Lcg::new(seed);
    let pi = std::f64::consts::PI;

    // Meta-parameters
    let num_anchors = rng.int(8, 14) as usize;
    let base_width = rng.range(55.0, 85.0);
    let style = *rng.pick(&STYLE_NAMES);

    // Base polygon (deformed ellipse)
    let aspect_ratio = rng.range(0.65, 1.0);
    let base_radius_x = 280.0;
    let base_radius_y = base_radius_x * aspect_ratio;

    let mut angles: Vec<f64> = (0..num_anchors)
        .map(|i| {
            let base_angle = i as f64 / num_anchors as f64 * 2.0 * pi;
            let jitter = rng.range(-0.3, 0.3) / num_anchors as f64 * 2.0 * pi;
            base_angle + jitter
        })
        .collect();
    angles.sort_by(|a, b| a.partial_cmp(b).unwrap());

    let anchors: Vec<P> = angles
        .iter()
        .map(|&angle| {
            let radius_mult = rng.range(0.75, 1.25);
            P {
                x: angle.cos() * base_radius_x * radius_mult,
                y: angle.sin() * base_radius_y * radius_mult,
            }
        })
        .collect();

    // Feature injection between anchor pairs
    let mut max_features = match style {
        "power" => rng.int(0, 1),
        "technical" => rng.int(2, 4),
        _ => rng.int(1, 2),
    } as usize;
    max_features = max_features.min(num_anchors / 3);

    // Candidate segments (2..=num_anchors in Lua's 1-based indexing → anchor
    // indices 1..num_anchors here), shuffled with the same Fisher-Yates order.
    let mut candidates: Vec<usize> = (2..=num_anchors).collect();
    let clen = candidates.len();
    for i in (1..clen).rev() {
        let j = rng.int(1, (i + 1) as i64) as usize - 1;
        candidates.swap(i, j);
    }

    let mut feature_segments: Vec<usize> = Vec::new();
    for &idx in &candidates {
        if feature_segments.len() >= max_features {
            break;
        }
        let adjacent = feature_segments
            .iter()
            .any(|&seg| (seg as i64 - idx as i64).abs() <= 1);
        if !adjacent {
            feature_segments.push(idx);
        }
    }

    // Build final point list with features inserted (i is the Lua 1-based anchor index)
    let mut points: Vec<P> = Vec::new();
    for i in 1..=num_anchors {
        let a = anchors[i - 1];
        points.push(a);

        if feature_segments.contains(&i) {
            let next = anchors[i % num_anchors];
            let (ax, ay) = (a.x, a.y);
            let (bx, by) = (next.x, next.y);
            let (mx, my) = ((ax + bx) / 2.0, (ay + by) / 2.0);
            let (dx, dy) = (bx - ax, by - ay);
            let mut len = (dx * dx + dy * dy).sqrt();
            if len < 1e-6 {
                len = 1.0;
            }
            let (nx, ny) = (-dy / len, dx / len);

            let feature_type = rng.int(1, 3);
            let offset = rng.range(30.0, 80.0);

            match feature_type {
                1 => {
                    // Chicane: 2 points with opposite offsets (S-bend)
                    let (t1, t2) = (0.33, 0.67);
                    points.push(P {
                        x: lerp(ax, bx, t1) + nx * offset,
                        y: lerp(ay, by, t1) + ny * offset,
                    });
                    points.push(P {
                        x: lerp(ax, bx, t2) - nx * offset,
                        y: lerp(ay, by, t2) - ny * offset,
                    });
                }
                2 => {
                    // Hairpin: 1 point pulled toward center
                    points.push(P {
                        x: mx + nx * offset * rng.range(0.5, 1.5),
                        y: my + ny * offset * rng.range(0.5, 1.5),
                    });
                }
                _ => {
                    // Esses: 3 points with alternating offsets
                    let (t1, t2, t3) = (0.25, 0.50, 0.75);
                    let scale = offset * 0.6;
                    points.push(P {
                        x: lerp(ax, bx, t1) + nx * scale,
                        y: lerp(ay, by, t1) + ny * scale,
                    });
                    points.push(P {
                        x: lerp(ax, bx, t2) - nx * scale,
                        y: lerp(ay, by, t2) - ny * scale,
                    });
                    points.push(P {
                        x: lerp(ax, bx, t3) + nx * scale * 0.7,
                        y: lerp(ay, by, t3) + ny * scale * 0.7,
                    });
                }
            }
        }
    }

    // Fit to viewport (800x600 with margin)
    let margin = base_width / 2.0 + 25.0;
    let (mut min_x, mut max_x) = (f64::INFINITY, f64::NEG_INFINITY);
    let (mut min_y, mut max_y) = (f64::INFINITY, f64::NEG_INFINITY);
    for p in &points {
        min_x = min_x.min(p.x);
        max_x = max_x.max(p.x);
        min_y = min_y.min(p.y);
        max_y = max_y.max(p.y);
    }
    let range_x = (max_x - min_x).max(1.0);
    let range_y = (max_y - min_y).max(1.0);
    let scale = ((800.0 - 2.0 * margin) / range_x).min((600.0 - 2.0 * margin) / range_y);
    let cx = (min_x + max_x) / 2.0;
    let cy = (min_y + max_y) / 2.0;
    for p in points.iter_mut() {
        p.x = 400.0 + (p.x - cx) * scale;
        p.y = 300.0 + (p.y - cy) * scale;
    }

    // Self-intersection validation with retry
    if !validate_points(&points, base_width) && attempt < 5 {
        return generate_attempt(seed + 1, attempt + 1);
    }

    // Start angle from tangent at first control point
    let n = points.len();
    let prev_p = points[n - 1];
    let next_p = points[1];
    let start_angle = (next_p.y - prev_p.y).atan2(next_p.x - prev_p.x);

    // Curvatures for surface zone generation
    let spline_path = generate_spline(&points, 10);
    let curvatures = compute_curvatures(&spline_path);
    let surface_zones = generate_surface_zones(&mut rng, &curvatures);

    let name = generate_name(&mut rng);

    TrackConfig {
        id: format!("gen_{seed}"),
        name,
        description: style_description(style).into(),
        width: base_width.floor(),
        points,
        start_angle,
        surface_zones,
        seed,
        generated: true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::track::Track;

    #[test]
    fn generates_a_track_config_from_a_seed() {
        let config = generate(42);
        assert!(!config.name.is_empty());
        assert!(!config.description.is_empty());
        assert!(config.width > 0.0);
        assert!(!config.points.is_empty());
        assert!(!config.surface_zones.is_empty());
        assert!(config.generated);
        assert_eq!(config.id, "gen_42");
    }

    #[test]
    fn is_deterministic() {
        let a = generate(999);
        let b = generate(999);
        assert_eq!(a.name, b.name);
        assert_eq!(a.points.len(), b.points.len());
        assert_eq!(a.width, b.width);
        for i in 0..a.points.len() {
            assert!((a.points[i].x - b.points[i].x).abs() < 1e-3);
            assert!((a.points[i].y - b.points[i].y).abs() < 1e-3);
        }
    }

    #[test]
    fn different_seeds_differ() {
        let a = generate(42);
        let b = generate(137);
        let differ = a.name != b.name
            || a.points.len() != b.points.len()
            || a.points
                .iter()
                .zip(b.points.iter())
                .any(|(p, q)| (p.x - q.x).abs() > 1.0);
        assert!(differ, "seeds 42 and 137 should produce different tracks");
    }

    #[test]
    fn points_fit_viewport() {
        for seed in [42, 137, 314, 1000, 2024] {
            let config = generate(seed);
            for (j, p) in config.points.iter().enumerate() {
                assert!(
                    (0.0..=800.0).contains(&p.x),
                    "seed {seed} point {j} x={} out of bounds",
                    p.x
                );
                assert!(
                    (0.0..=600.0).contains(&p.y),
                    "seed {seed} point {j} y={} out of bounds",
                    p.y
                );
            }
        }
    }

    #[test]
    fn has_at_least_six_control_points() {
        assert!(generate(42).points.len() >= 6);
    }

    #[test]
    fn surface_zones_cover_zero_to_one() {
        let config = generate(42);
        let zones = &config.surface_zones;
        assert!(zones.len() >= 4);
        assert!(zones[0].start_pct.abs() < 1e-3);
        assert!((zones.last().unwrap().end_pct - 1.0).abs() < 1e-3);
        for z in zones {
            assert!(z.grip > 0.0);
            assert!(z.bumpiness >= 0.0);
            assert!(!z.name.is_empty());
        }
    }

    #[test]
    fn compatible_with_track_from_config() {
        let config = generate(42);
        let track = Track::from_config(&config);
        assert!(!track.center_path.is_empty());
        assert!(
            track.is_on_track(track.start_x, track.start_y),
            "start position should be on track"
        );
    }

    #[test]
    fn validate_points_rejects_figure_eight() {
        let bad = vec![
            P::new(100.0, 100.0),
            P::new(700.0, 500.0),
            P::new(700.0, 100.0),
            P::new(100.0, 500.0),
        ];
        assert!(!validate_points(&bad, 60.0));
    }

    #[test]
    fn works_with_many_seeds() {
        for seed in 1..=20 {
            let config = generate(seed * 73);
            assert!(
                config.points.len() >= 6,
                "seed {} produced too few points",
                seed * 73
            );
        }
    }
}
