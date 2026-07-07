//! Track geometry, surface zones, curbs, and trees (port of track.lua).

use crate::rng::Lcg;
use crate::spline::catmull_rom;
use crate::P;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SurfaceZone {
    #[serde(rename = "startPct")]
    pub start_pct: f64,
    #[serde(rename = "endPct")]
    pub end_pct: f64,
    pub grip: f64,
    pub bumpiness: f64,
    pub name: String,
    /// RGBA overlay tint; alpha 0 = invisible.
    #[serde(default = "default_zone_color")]
    pub color: [f64; 4],
}

fn default_zone_color() -> [f64; 4] {
    [0.5, 0.5, 0.5, 0.0]
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackConfig {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    pub width: f64,
    pub points: Vec<P>,
    #[serde(rename = "startAngle", default)]
    pub start_angle: f64,
    #[serde(rename = "surfaceZones", default)]
    pub surface_zones: Vec<SurfaceZone>,
    #[serde(default)]
    pub seed: i64,
    #[serde(default)]
    pub generated: bool,
}

#[derive(Debug, Clone)]
pub struct Curb {
    pub x: f64,
    pub y: f64,
    pub angle: f64,
    pub index: usize,
}

#[derive(Debug, Clone)]
pub struct Tree {
    pub x: f64,
    pub y: f64,
    pub trunk_h: f64,
    pub canopy_r: f64,
    pub green: f64,
    pub shade: f64,
}

#[derive(Debug, Clone)]
pub struct Track {
    pub config: TrackConfig,
    pub name: String,
    pub width: f64,
    pub center_path: Vec<P>,
    pub path_length: f64,
    pub cumulative: Vec<f64>,
    pub inner_path: Vec<P>,
    pub outer_path: Vec<P>,
    pub finish_x: f64,
    pub finish_y1: f64,
    pub finish_y2: f64,
    pub finish_angle: f64,
    pub finish_point: P,
    /// Track tangent at the finish line = forward direction.
    pub finish_forward: P,
    pub finish_p1: P,
    pub finish_p2: P,
    /// Approximate center of the layout (for trees / legacy behavior).
    pub cx: f64,
    pub cy: f64,
    pub outer_curbs: Vec<Curb>,
    pub inner_curbs: Vec<Curb>,
    pub trees: Vec<Tree>,
    pub surface_zones: Vec<SurfaceZone>,
    pub start_x: f64,
    pub start_y: f64,
    pub start_angle: f64,
}

/// Generate a smooth closed path from control points using Catmull-Rom splines.
pub fn generate_spline_path(control_points: &[P], segments_per_curve: usize) -> Vec<P> {
    let n = control_points.len();
    let mut path = Vec::with_capacity(n * segments_per_curve);
    for i in 0..n {
        let p0 = control_points[(i + n - 1) % n];
        let p1 = control_points[i];
        let p2 = control_points[(i + 1) % n];
        let p3 = control_points[(i + 2) % n];
        for j in 0..segments_per_curve {
            let t = j as f64 / segments_per_curve as f64;
            path.push(catmull_rom(p0, p1, p2, p3, t));
        }
    }
    path
}

fn calculate_path_metrics(path: &[P]) -> (f64, Vec<f64>) {
    let mut total = 0.0;
    let mut cumulative = vec![0.0; path.len()];
    for i in 1..path.len() {
        let dx = path[i].x - path[i - 1].x;
        let dy = path[i].y - path[i - 1].y;
        total += (dx * dx + dy * dy).sqrt();
        cumulative[i] = total;
    }
    // Close the loop
    let dx = path[0].x - path[path.len() - 1].x;
    let dy = path[0].y - path[path.len() - 1].y;
    total += (dx * dx + dy * dy).sqrt();
    (total, cumulative)
}

fn point_at_percent(path: &[P], cumulative: &[f64], total_length: f64, pct: f64) -> P {
    let target = pct * total_length;
    for i in 1..path.len() {
        if cumulative[i] >= target {
            let prev = cumulative[i - 1];
            let seg = cumulative[i] - prev;
            let t = if seg > 0.0 {
                (target - prev) / seg
            } else {
                0.0
            };
            return P {
                x: path[i - 1].x + t * (path[i].x - path[i - 1].x),
                y: path[i - 1].y + t * (path[i].y - path[i - 1].y),
            };
        }
    }
    path[path.len() - 1]
}

/// Unit tangent at a path index (central difference over neighbors).
pub fn tangent_at(path: &[P], index: usize) -> (f64, f64) {
    let n = path.len();
    let prev = path[(index + n - 1) % n];
    let next = path[(index + 1) % n];
    let dx = next.x - prev.x;
    let dy = next.y - prev.y;
    let len = (dx * dx + dy * dy).sqrt();
    if len > 0.0 {
        (dx / len, dy / len)
    } else {
        (1.0, 0.0)
    }
}

impl Track {
    pub fn from_config(config: &TrackConfig) -> Self {
        let center_path = generate_spline_path(&config.points, 25);
        let (path_length, cumulative) = calculate_path_metrics(&center_path);

        let half_width = config.width / 2.0;
        let mut inner_path = Vec::with_capacity(center_path.len());
        let mut outer_path = Vec::with_capacity(center_path.len());
        for (i, p) in center_path.iter().enumerate() {
            let (tx, ty) = tangent_at(&center_path, i);
            let (nx, ny) = (-ty, tx);
            inner_path.push(P {
                x: p.x + nx * half_width,
                y: p.y + ny * half_width,
            });
            outer_path.push(P {
                x: p.x - nx * half_width,
                y: p.y - ny * half_width,
            });
        }

        // Finish line at the start of the track
        let start_point = center_path[0];
        let (tx, ty) = tangent_at(&center_path, 0);
        let (nx, ny) = (-ty, tx);

        let finish_angle = ty.atan2(tx);
        let finish_p1 = P {
            x: start_point.x + nx * half_width,
            y: start_point.y + ny * half_width,
        };
        let finish_p2 = P {
            x: start_point.x - nx * half_width,
            y: start_point.y - ny * half_width,
        };

        // Approximate center for trees
        let (sum_x, sum_y) = config
            .points
            .iter()
            .fold((0.0, 0.0), |(sx, sy), p| (sx + p.x, sy + p.y));
        let cx = sum_x / config.points.len() as f64;
        let cy = sum_y / config.points.len() as f64;

        let surface_zones = if config.surface_zones.is_empty() {
            vec![SurfaceZone {
                start_pct: 0.0,
                end_pct: 1.0,
                grip: 0.95,
                bumpiness: 0.05,
                name: "Smooth Tarmac".into(),
                color: default_zone_color(),
            }]
        } else {
            config.surface_zones.clone()
        };

        let mut track = Track {
            config: config.clone(),
            name: config.name.clone(),
            width: config.width,
            center_path,
            path_length,
            cumulative,
            inner_path,
            outer_path,
            finish_x: start_point.x,
            finish_y1: finish_p1.y,
            finish_y2: finish_p2.y,
            finish_angle,
            finish_point: start_point,
            finish_forward: P { x: tx, y: ty },
            finish_p1,
            finish_p2,
            cx,
            cy,
            outer_curbs: Vec::new(),
            inner_curbs: Vec::new(),
            trees: Vec::new(),
            surface_zones,
            start_x: start_point.x,
            start_y: start_point.y,
            start_angle: if config.start_angle != 0.0 {
                config.start_angle
            } else {
                finish_angle
            },
        };
        track.generate_curbs();
        track.generate_trees();
        track
    }

    /// Legacy oval track (port of track.init()).
    pub fn default_oval() -> Self {
        let mk_zone =
            |start: f64, end: f64, grip: f64, bump: f64, name: &str, color: [f64; 4]| SurfaceZone {
                start_pct: start,
                end_pct: end,
                grip,
                bumpiness: bump,
                name: name.into(),
                color,
            };
        let config = TrackConfig {
            id: "default".into(),
            name: "Classic Oval".into(),
            description: "The classic".into(),
            width: 75.0,
            points: vec![
                P::new(400.0, 50.0),
                P::new(700.0, 150.0),
                P::new(750.0, 300.0),
                P::new(700.0, 450.0),
                P::new(400.0, 550.0),
                P::new(100.0, 450.0),
                P::new(50.0, 300.0),
                P::new(100.0, 150.0),
            ],
            start_angle: 0.0,
            surface_zones: vec![
                mk_zone(0.0, 0.15, 0.95, 0.05, "Smooth Tarmac", [0.5, 0.5, 0.5, 0.0]),
                mk_zone(0.15, 0.30, 0.7, 0.3, "Worn Patch", [0.6, 0.4, 0.2, 0.08]),
                mk_zone(
                    0.30,
                    0.50,
                    0.95,
                    0.05,
                    "Smooth Tarmac",
                    [0.5, 0.5, 0.5, 0.0],
                ),
                mk_zone(
                    0.50,
                    0.65,
                    0.85,
                    0.6,
                    "Bumpy Section",
                    [0.4, 0.35, 0.3, 0.06],
                ),
                mk_zone(
                    0.65,
                    0.80,
                    0.95,
                    0.05,
                    "Smooth Tarmac",
                    [0.5, 0.5, 0.5, 0.0],
                ),
                mk_zone(0.80, 1.0, 0.6, 0.1, "Damp Corner", [0.2, 0.3, 0.7, 0.07]),
            ],
            seed: 0,
            generated: false,
        };
        Self::from_config(&config)
    }

    fn generate_curbs(&mut self) {
        self.outer_curbs.clear();
        self.inner_curbs.clear();
        let step = (self.center_path.len() / 80).max(1);
        let mut index = 0;
        let mut i = 0;
        while i < self.center_path.len() {
            let outer = self.outer_path[i];
            let inner = self.inner_path[i];
            let (tx, ty) = tangent_at(&self.center_path, i);
            let angle = ty.atan2(tx);
            self.outer_curbs.push(Curb {
                x: outer.x,
                y: outer.y,
                angle,
                index,
            });
            self.inner_curbs.push(Curb {
                x: inner.x,
                y: inner.y,
                angle,
                index,
            });
            index += 1;
            i += step;
        }
    }

    fn generate_trees(&mut self) {
        self.trees.clear();
        let mut rng = Lcg::new(77);
        for _ in 0..25 {
            for _attempt in 0..50 {
                let x = rng.int(20, 780) as f64;
                let y = rng.int(20, 580) as f64;
                let mut min_dist = f64::INFINITY;
                for p in &self.center_path {
                    let dx = x - p.x;
                    let dy = y - p.y;
                    min_dist = min_dist.min((dx * dx + dy * dy).sqrt());
                }
                if min_dist > self.width / 2.0 + 15.0 {
                    self.trees.push(Tree {
                        x,
                        y,
                        trunk_h: 6.0 + rng.next() * 4.0,
                        canopy_r: 8.0 + rng.next() * 7.0,
                        green: 0.3 + rng.next() * 0.3,
                        shade: 0.1 + rng.next() * 0.1,
                    });
                    break;
                }
            }
        }
    }

    /// Whether a point is on the track surface.
    pub fn is_on_track(&self, x: f64, y: f64) -> bool {
        let mut min_dist_sq = f64::INFINITY;
        for p in &self.center_path {
            let dx = x - p.x;
            let dy = y - p.y;
            min_dist_sq = min_dist_sq.min(dx * dx + dy * dy);
        }
        let half = self.width / 2.0;
        min_dist_sq <= half * half
    }

    /// Percentage along the track for a given position.
    pub fn get_track_percent(&self, x: f64, y: f64) -> f64 {
        let mut min_dist_sq = f64::INFINITY;
        let mut best = 0;
        for (i, p) in self.center_path.iter().enumerate() {
            let dx = x - p.x;
            let dy = y - p.y;
            let d = dx * dx + dy * dy;
            if d < min_dist_sq {
                min_dist_sq = d;
                best = i;
            }
        }
        self.cumulative[best] / self.path_length
    }

    pub fn get_surface_at(&self, x: f64, y: f64) -> &SurfaceZone {
        let pct = self.get_track_percent(x, y);
        self.surface_zones
            .iter()
            .find(|z| pct >= z.start_pct && pct < z.end_pct)
            .unwrap_or(&self.surface_zones[0])
    }

    pub fn get_point_at_percent(&self, pct: f64) -> P {
        point_at_percent(&self.center_path, &self.cumulative, self.path_length, pct)
    }

    pub fn circumference(&self) -> f64 {
        self.path_length
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tracks::TrackList;

    #[test]
    fn is_on_track_at_start_position() {
        let t = Track::default_oval();
        assert!(t.is_on_track(t.start_x, t.start_y));
    }

    #[test]
    fn infield_is_off_track() {
        let t = Track::default_oval();
        assert!(!t.is_on_track(t.cx, t.cy));
    }

    #[test]
    fn origin_is_off_track() {
        let t = Track::default_oval();
        assert!(!t.is_on_track(0.0, 0.0));
    }

    #[test]
    fn point_along_center_path_is_on_track() {
        let t = Track::default_oval();
        let p = t.center_path[9];
        assert!(t.is_on_track(p.x, p.y));
    }

    #[test]
    fn surface_zone_has_valid_properties() {
        let t = Track::default_oval();
        let zone = t.get_surface_at(t.start_x, t.start_y);
        assert!(zone.grip > 0.0);
        assert!(!zone.name.is_empty());
    }

    #[test]
    fn generates_curbs_and_trees() {
        let t = Track::default_oval();
        assert!(!t.outer_curbs.is_empty());
        assert!(!t.inner_curbs.is_empty());
        assert!(!t.trees.is_empty());
    }

    #[test]
    fn surface_zones_cover_zero_to_one() {
        let t = Track::default_oval();
        assert!(t.surface_zones[0].start_pct.abs() < 1e-3);
        assert!((t.surface_zones.last().unwrap().end_pct - 1.0).abs() < 1e-3);
    }

    #[test]
    fn inner_and_outer_paths_match_center_length() {
        let list = TrackList::with_defaults();
        let t = Track::from_config(list.get_by_index(0).unwrap());
        assert_eq!(t.inner_path.len(), t.center_path.len());
        assert_eq!(t.outer_path.len(), t.center_path.len());
        assert!(!t.center_path.is_empty());
    }

    #[test]
    fn track_percent_is_in_unit_range() {
        let list = TrackList::with_defaults();
        let t = Track::from_config(list.get_by_index(0).unwrap());
        let pct = t.get_track_percent(t.start_x, t.start_y);
        assert!((0.0..=1.0).contains(&pct));
    }

    #[test]
    fn circumference_is_positive() {
        let list = TrackList::with_defaults();
        let t = Track::from_config(list.get_by_index(0).unwrap());
        assert!(t.circumference() > 0.0);
    }

    #[test]
    fn all_default_tracks_initialize_with_start_on_track() {
        let list = TrackList::with_defaults();
        for cfg in &list.list {
            let t = Track::from_config(cfg);
            assert!(!t.center_path.is_empty(), "{} has no path", cfg.name);
            assert!(
                t.is_on_track(t.start_x, t.start_y),
                "{} start pos not on track",
                cfg.name
            );
        }
    }

    #[test]
    fn get_point_at_percent_walks_the_loop() {
        let t = Track::default_oval();
        let p0 = t.get_point_at_percent(0.0);
        let p50 = t.get_point_at_percent(0.5);
        let dx = p50.x - p0.x;
        let dy = p50.y - p0.y;
        assert!(
            (dx * dx + dy * dy).sqrt() > t.width,
            "halfway point should be far from start"
        );
    }
}
