//! Race scene rendering: grass, track, curbs, finish line, trees, cars
//! (port of draw.lua's world rendering; HUD lives in hud.rs).

use bevy::asset::RenderAssetUsages;
use bevy::prelude::*;
use bevy::render::mesh::{Indices, PrimitiveTopology};
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat};
use racing_sim::car::Car;
use racing_sim::rng::Lcg;
use racing_sim::track::Track;

use super::shared::{srgb, to_world, to_world_rot, RaceScene, SCREEN_H, SCREEN_W};

// Draw layers (Love2D draw order → z)
pub const Z_GRASS: f32 = 0.0;
pub const Z_TRACK: f32 = 1.0;
pub const Z_ZONES: f32 = 1.5;
pub const Z_CURBS: f32 = 2.0;
pub const Z_CENTERLINE: f32 = 2.5;
pub const Z_FINISH: f32 = 2.6;
pub const Z_TREES: f32 = 3.0;
pub const Z_SHADOW: f32 = 4.0;
pub const Z_PARTICLES: f32 = 5.0;
pub const Z_CAR: f32 = 6.0;

#[derive(Component)]
pub struct CarSprite(pub usize);
#[derive(Component)]
pub struct CarShadow(pub usize);
#[derive(Component)]
pub struct CarBody;
#[derive(Component)]
pub struct CarStripe;
#[derive(Component)]
pub struct CarFlash;
/// Wheel index 0..4 = FL, FR, RL, RR.
#[derive(Component)]
pub struct CarWheel(pub usize);

/// Handle to the grass background texture, generated once at startup.
#[derive(Resource)]
pub struct GrassImage(pub Handle<Image>);

/// Procedural grass texture (port of draw.generateGrassCanvas).
pub fn setup_grass(mut commands: Commands, mut images: ResMut<Assets<Image>>) {
    let (w, h) = (SCREEN_W as usize, SCREEN_H as usize);
    let mut px = vec![0u8; w * h * 4];

    let put = |px: &mut Vec<u8>, x: usize, y: usize, c: [f32; 4]| {
        if x >= w || y >= h {
            return;
        }
        let i = (y * w + x) * 4;
        // alpha blend over existing
        let a = c[3];
        for ch in 0..3 {
            let old = px[i + ch] as f32 / 255.0;
            px[i + ch] = (((c[ch] * a) + old * (1.0 - a)) * 255.0) as u8;
        }
        px[i + 3] = 255;
    };

    // Base green
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) * 4;
            px[i] = (0.18 * 255.0) as u8;
            px[i + 1] = (0.55 * 255.0) as u8;
            px[i + 2] = (0.13 * 255.0) as u8;
            px[i + 3] = 255;
        }
    }

    // Speckle detail (fixed seed, like math.randomseed(42) in the Lua code)
    let mut rng = Lcg::new(42);
    for _ in 0..4000 {
        let x = rng.int(0, 799) as usize;
        let y = rng.int(0, 599) as usize;
        let shade = 0.14 + rng.next() as f32 * 0.12;
        let g = 0.45 + rng.next() as f32 * 0.25;
        for dy in 0..2 {
            for dx in 0..2 {
                put(&mut px, x + dx, y + dy, [shade, g, shade * 0.7, 0.6]);
            }
        }
    }
    for _ in 0..1500 {
        let x = rng.int(0, 799) as usize;
        let y = rng.int(0, 599) as usize;
        let shade = 0.1 + rng.next() as f32 * 0.15;
        let g = 0.5 + rng.next() as f32 * 0.2;
        let len = 3 + rng.int(0, 2) as usize;
        for dy in 0..len {
            put(&mut px, x, y + dy, [shade, g, shade * 0.6, 0.4]);
        }
    }

    let image = Image::new(
        Extent3d {
            width: w as u32,
            height: h as u32,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        px,
        TextureFormat::Rgba8UnormSrgb,
        RenderAssetUsages::RENDER_WORLD,
    );
    let handle = images.add(image);
    commands.insert_resource(GrassImage(handle));
}

/// Ring mesh between two closed paths (outer/inner), in world coordinates.
fn ring_mesh(
    outer: &[racing_sim::P],
    inner: &[racing_sim::P],
    range: std::ops::Range<usize>,
) -> Mesh {
    let n = outer.len();
    let mut positions: Vec<[f32; 3]> = Vec::new();
    let mut indices: Vec<u32> = Vec::new();
    for i in range {
        let j = (i + 1) % n;
        let base = positions.len() as u32;
        for p in [&outer[i], &outer[j], &inner[j], &inner[i]] {
            let v = to_world(p.x, p.y, 0.0);
            positions.push([v.x, v.y, 0.0]);
        }
        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }
    let count = positions.len();
    let mut mesh = Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::RENDER_WORLD,
    );
    mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, positions);
    mesh.insert_attribute(Mesh::ATTRIBUTE_NORMAL, vec![[0.0, 0.0, 1.0]; count]);
    mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, vec![[0.0, 0.0]; count]);
    mesh.insert_indices(Indices::U32(indices));
    mesh
}

/// Line strip rendered as thin quads (Bevy 2D has no line width control on meshes).
fn polyline_mesh(
    points: &[racing_sim::P],
    width: f32,
    closed: bool,
    dashes: Option<usize>,
) -> Mesh {
    let n = points.len();
    let mut positions: Vec<[f32; 3]> = Vec::new();
    let mut indices: Vec<u32> = Vec::new();
    let seg_count = if closed { n } else { n - 1 };
    let mut dash_count = 0usize;
    for i in 0..seg_count {
        // Dash pattern port: draw `dash` segments, skip `dash` segments
        if let Some(dash) = dashes {
            dash_count += 1;
            let draw = dash_count <= dash;
            if dash_count >= dash * 2 {
                dash_count = 0;
            }
            if !draw {
                continue;
            }
        }
        let a = points[i];
        let b = points[(i + 1) % n];
        let (dx, dy) = ((b.x - a.x) as f32, -(b.y - a.y) as f32); // world y flip
        let len = (dx * dx + dy * dy).sqrt().max(1e-6);
        let (nx, ny) = (-dy / len * width / 2.0, dx / len * width / 2.0);
        let av = to_world(a.x, a.y, 0.0);
        let bv = to_world(b.x, b.y, 0.0);
        let base = positions.len() as u32;
        positions.push([av.x + nx, av.y + ny, 0.0]);
        positions.push([bv.x + nx, bv.y + ny, 0.0]);
        positions.push([bv.x - nx, bv.y - ny, 0.0]);
        positions.push([av.x - nx, av.y - ny, 0.0]);
        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }
    let count = positions.len();
    let mut mesh = Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::RENDER_WORLD,
    );
    mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, positions);
    mesh.insert_attribute(Mesh::ATTRIBUTE_NORMAL, vec![[0.0, 0.0, 1.0]; count]);
    mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, vec![[0.0, 0.0]; count]);
    mesh.insert_indices(Indices::U32(indices));
    mesh
}

/// Spawn the whole static race scene for a track.
pub fn spawn_track_scene(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    grass: &GrassImage,
    track: &Track,
) {
    // Grass background
    commands.spawn((
        Sprite::from_image(grass.0.clone()),
        Transform::from_xyz(0.0, 0.0, Z_GRASS),
        RaceScene,
    ));

    // Track surface
    let surface = ring_mesh(
        &track.outer_path,
        &track.inner_path,
        0..track.outer_path.len(),
    );
    commands.spawn((
        Mesh2d(meshes.add(surface)),
        MeshMaterial2d(materials.add(ColorMaterial::from_color(Color::srgb(0.25, 0.25, 0.28)))),
        Transform::from_xyz(0.0, 0.0, Z_TRACK),
        RaceScene,
    ));

    // Surface zone tints
    let path_len = track.center_path.len();
    for zone in &track.surface_zones {
        if zone.color[3] <= 0.0 {
            continue;
        }
        let start = (zone.start_pct * path_len as f64).floor() as usize;
        let end = ((zone.end_pct * path_len as f64).floor() as usize).min(path_len);
        if end <= start {
            continue;
        }
        let mesh = ring_mesh(&track.outer_path, &track.inner_path, start..end);
        let c = zone.color;
        commands.spawn((
            Mesh2d(meshes.add(mesh)),
            MeshMaterial2d(materials.add(ColorMaterial::from_color(Color::srgba(
                c[0] as f32,
                c[1] as f32,
                c[2] as f32,
                c[3] as f32,
            )))),
            Transform::from_xyz(0.0, 0.0, Z_ZONES),
            RaceScene,
        ));
    }

    // Track edges (subtle white outline)
    for path in [&track.outer_path, &track.inner_path] {
        commands.spawn((
            Mesh2d(meshes.add(polyline_mesh(path, 2.0, true, None))),
            MeshMaterial2d(
                materials.add(ColorMaterial::from_color(Color::srgba(1.0, 1.0, 1.0, 0.15))),
            ),
            Transform::from_xyz(0.0, 0.0, Z_TRACK + 0.1),
            RaceScene,
        ));
    }

    // Center line dashes
    commands.spawn((
        Mesh2d(meshes.add(polyline_mesh(&track.center_path, 2.0, true, Some(3)))),
        MeshMaterial2d(materials.add(ColorMaterial::from_color(Color::srgba(1.0, 1.0, 1.0, 0.6)))),
        Transform::from_xyz(0.0, 0.0, Z_CENTERLINE),
        RaceScene,
    ));

    // Curbs: alternating red/white rectangles along both edges
    let red = materials.add(ColorMaterial::from_color(Color::srgba(0.9, 0.15, 0.1, 0.9)));
    let white = materials.add(ColorMaterial::from_color(Color::srgba(1.0, 1.0, 1.0, 0.9)));
    let curb_mesh = meshes.add(Rectangle::new(10.0, 5.0));
    for curb in track.outer_curbs.iter().chain(track.inner_curbs.iter()) {
        let material = if curb.index % 2 == 0 { &red } else { &white };
        commands.spawn((
            Mesh2d(curb_mesh.clone()),
            MeshMaterial2d(material.clone()),
            Transform {
                translation: to_world(curb.x, curb.y, Z_CURBS),
                rotation: to_world_rot(curb.angle + std::f64::consts::FRAC_PI_2),
                ..default()
            },
            RaceScene,
        ));
    }

    // Finish line: checkered strip perpendicular to the track direction
    spawn_finish_line(commands, meshes, materials, track);

    // Trees
    for tree in &track.trees {
        // Trunk
        commands.spawn((
            Sprite {
                color: Color::srgb(0.4, 0.25, 0.1),
                custom_size: Some(Vec2::new(4.0, tree.trunk_h as f32)),
                ..default()
            },
            Transform::from_translation(to_world(tree.x, tree.y - tree.trunk_h / 2.0, Z_TREES)),
            RaceScene,
        ));
        // Canopy: three overlapping circles
        let r = tree.canopy_r;
        let (g, s) = (tree.green as f32, tree.shade as f32);
        let canopy = [
            (0.0, -tree.trunk_h - r * 0.3, r, [s, g * 0.8, s * 0.5, 0.9]),
            (
                -r * 0.3,
                -tree.trunk_h - r * 0.6,
                r * 0.7,
                [s * 1.1, g, s * 0.4, 0.95],
            ),
            (
                r * 0.3,
                -tree.trunk_h - r * 0.5,
                r * 0.65,
                [s * 0.9, g * 1.1, s * 0.6, 0.85],
            ),
        ];
        for (i, (dx, dy, radius, c)) in canopy.iter().enumerate() {
            commands.spawn((
                Mesh2d(meshes.add(Circle::new(*radius as f32))),
                MeshMaterial2d(materials.add(ColorMaterial::from_color(Color::srgba(
                    c[0], c[1], c[2], c[3],
                )))),
                Transform::from_translation(to_world(
                    tree.x + dx,
                    tree.y + dy,
                    Z_TREES + 0.01 * (i as f32 + 1.0),
                )),
                RaceScene,
            ));
        }
    }
}

fn spawn_finish_line(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    track: &Track,
) {
    let grid = 6.0_f32;
    let cols = 2;
    let total_width = cols as f32 * grid;
    let half_len = ((track.finish_p2.x - track.finish_p1.x).powi(2)
        + (track.finish_p2.y - track.finish_p1.y).powi(2))
    .sqrt() as f32
        / 2.0;
    let num_rows = (half_len * 2.0 / grid) as i32;

    let mid_x = (track.finish_p1.x + track.finish_p2.x) / 2.0;
    let mid_y = (track.finish_p1.y + track.finish_p2.y) / 2.0;

    let white = materials.add(ColorMaterial::from_color(Color::srgb(1.0, 1.0, 1.0)));
    let black = materials.add(ColorMaterial::from_color(Color::srgb(0.05, 0.05, 0.05)));
    let square = meshes.add(Rectangle::new(grid, grid));

    // Parent oriented along the finish line (perpendicular to track direction)
    let parent = commands
        .spawn((
            Transform {
                translation: to_world(mid_x, mid_y, Z_FINISH),
                rotation: to_world_rot(track.finish_angle + std::f64::consts::FRAC_PI_2),
                ..default()
            },
            Visibility::default(),
            RaceScene,
        ))
        .id();

    for row in 0..num_rows {
        for col in 0..cols {
            let material = if (row + col) % 2 == 0 { &white } else { &black };
            // Local coords: x across the line width, y along its length (y up in world)
            let lx = -total_width / 2.0 + col as f32 * grid + grid / 2.0;
            let ly = half_len - row as f32 * grid - grid / 2.0;
            let child = commands
                .spawn((
                    Mesh2d(square.clone()),
                    MeshMaterial2d(material.clone()),
                    Transform::from_xyz(lx, ly, 0.0),
                ))
                .id();
            commands.entity(parent).add_child(child);
        }
    }

    // Flag poles at both ends (axis-aligned, like the original)
    let y_min = track.finish_y1.min(track.finish_y2);
    let y_max = track.finish_y1.max(track.finish_y2);
    let pole_h = 20.0;
    for (base_y, _flag_top) in [(y_min, true), (y_max, false)] {
        let pole_y = if base_y == y_min {
            base_y - pole_h as f64 / 2.0
        } else {
            base_y + pole_h as f64 / 2.0
        };
        commands.spawn((
            Sprite {
                color: Color::srgb(0.5, 0.5, 0.5),
                custom_size: Some(Vec2::new(2.0, pole_h)),
                ..default()
            },
            Transform::from_translation(to_world(track.finish_x, pole_y, Z_FINISH + 0.01)),
            RaceScene,
        ));
        // Mini checkered flag: 2x2 squares
        let flag = 8.0_f32;
        let flag_base_y = if base_y == y_min {
            base_y - pole_h as f64
        } else {
            base_y
        };
        for fr in 0..2 {
            for fc in 0..2 {
                let color = if (fr + fc) % 2 == 0 {
                    Color::srgb(1.0, 1.0, 1.0)
                } else {
                    Color::srgb(0.0, 0.0, 0.0)
                };
                commands.spawn((
                    Sprite {
                        color,
                        custom_size: Some(Vec2::splat(flag / 2.0)),
                        ..default()
                    },
                    Transform::from_translation(to_world(
                        track.finish_x + 1.0 + fc as f64 * (flag as f64 / 2.0) + flag as f64 / 4.0,
                        flag_base_y + fr as f64 * (flag as f64 / 2.0) + flag as f64 / 4.0,
                        Z_FINISH + 0.02,
                    )),
                    RaceScene,
                ));
            }
        }
    }
}

/// Spawn a car entity tree: shadow + body/stripe/windshield/lights/wheels/flash.
pub fn spawn_car(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    index: usize,
    car: &Car,
) {
    let w = car.width as f32;
    let h = car.height as f32;

    // Shadow (separate entity: fixed world offset, not rotated with the car)
    commands.spawn((
        Mesh2d(meshes.add(Ellipse::new(w * 0.55, h * 0.5))),
        MeshMaterial2d(materials.add(ColorMaterial::from_color(Color::srgba(0.0, 0.0, 0.0, 0.3)))),
        Transform::from_translation(to_world(car.x + 3.0, car.y + 4.0, Z_SHADOW)),
        CarShadow(index),
        RaceScene,
    ));

    let color = srgb(car.color);

    commands
        .spawn((
            Transform::from_translation(to_world(car.x, car.y, Z_CAR + index as f32 * 0.1)),
            Visibility::default(),
            CarSprite(index),
            RaceScene,
        ))
        .with_children(|parent| {
            // Wheels (behind body): FL, FR, RL, RR — local x forward, y left/right
            let (wheel_w, wheel_h) = (6.0, 3.0);
            let front_x = w * 0.25;
            let rear_x = -w * 0.3;
            let half_h = h / 2.0;
            // Sim local y-down → world child y flipped
            let wheel_pos = [
                (front_x, half_h),  // FL (sim -halfH → world +)
                (front_x, -half_h), // FR
                (rear_x, half_h),   // RL
                (rear_x, -half_h),  // RR
            ];
            for (i, (wx, wy)) in wheel_pos.iter().enumerate() {
                parent.spawn((
                    Sprite {
                        color: Color::srgb(0.1, 0.1, 0.1),
                        custom_size: Some(Vec2::new(wheel_w, wheel_h)),
                        ..default()
                    },
                    Transform::from_xyz(*wx, *wy, -0.01),
                    CarWheel(i),
                ));
            }

            // Body
            parent.spawn((
                Sprite {
                    color,
                    custom_size: Some(Vec2::new(w - 2.0, h - 2.0)),
                    ..default()
                },
                Transform::from_xyz(0.0, 0.0, 0.0),
                CarBody,
            ));

            // Highlight stripe
            parent.spawn((
                Sprite {
                    color: Color::srgba(
                        (car.color[0] + 0.15).min(1.0),
                        (car.color[1] + 0.10).min(1.0),
                        (car.color[2] + 0.05).min(1.0),
                        0.4,
                    ),
                    custom_size: Some(Vec2::new(w - 6.0, 2.0)),
                    ..default()
                },
                Transform::from_xyz(0.0, 0.0, 0.01),
                CarStripe,
            ));

            // Windshield
            parent.spawn((
                Sprite {
                    color: Color::srgba(0.15, 0.2, 0.35, 0.8),
                    custom_size: Some(Vec2::new(w * 0.3, h - 4.0)),
                    ..default()
                },
                Transform::from_xyz(-w * 0.05, 0.0, 0.02),
            ));

            // Headlights (front = +x)
            for y in [h / 2.0 - 3.5, -(h / 2.0 - 3.5)] {
                parent.spawn((
                    Sprite {
                        color: Color::srgb(1.0, 0.95, 0.3),
                        custom_size: Some(Vec2::new(3.0, 3.0)),
                        ..default()
                    },
                    Transform::from_xyz(w / 2.0 - 1.5, y, 0.03),
                ));
            }

            // Taillights (rear = -x)
            for y in [h / 2.0 - 3.5, -(h / 2.0 - 3.5)] {
                parent.spawn((
                    Sprite {
                        color: Color::srgba(1.0, 0.0, 0.0, 0.9),
                        custom_size: Some(Vec2::new(3.0, 3.0)),
                        ..default()
                    },
                    Transform::from_xyz(-w / 2.0 + 1.5, y, 0.03),
                ));
            }

            // Impact flash overlay (alpha driven by damage.impact_flash)
            parent.spawn((
                Sprite {
                    color: Color::srgba(1.0, 1.0, 1.0, 0.0),
                    custom_size: Some(Vec2::new(w - 2.0, h - 2.0)),
                    ..default()
                },
                Transform::from_xyz(0.0, 0.0, 0.04),
                CarFlash,
            ));
        });
}

/// Mirror sim car state into transforms and damage-driven sprite colors.
#[allow(clippy::type_complexity)]
pub fn sync_cars(
    cars: Res<super::shared::Cars>,
    mut roots: Query<(&CarSprite, &mut Transform, &Children)>,
    mut shadows: Query<(&CarShadow, &mut Transform), Without<CarSprite>>,
    mut wheels: Query<(&CarWheel, &mut Sprite), (Without<CarBody>, Without<CarFlash>)>,
    mut bodies: Query<&mut Sprite, (With<CarBody>, Without<CarWheel>, Without<CarFlash>)>,
    mut flashes: Query<&mut Sprite, (With<CarFlash>, Without<CarBody>, Without<CarWheel>)>,
) {
    for (marker, mut transform, children) in roots.iter_mut() {
        let Some(car) = cars.0.get(marker.0) else {
            continue;
        };
        transform.translation = to_world(car.x, car.y, Z_CAR + marker.0 as f32 * 0.1);
        transform.rotation = to_world_rot(car.angle);

        let dmg = &car.damage;
        let avg_body = dmg.avg_body_health() as f32;
        let flash_alpha = (dmg.impact_flash * 0.7) as f32;

        for child in children.iter() {
            if let Ok((wheel, mut sprite)) = wheels.get_mut(child) {
                let health = dmg.tires[wheel.0] as f32;
                if dmg.flat_tires[wheel.0] {
                    sprite.color = Color::srgb(0.35, 0.30, 0.20); // dusty rim
                    sprite.custom_size = Some(Vec2::new(8.0, 2.0));
                } else {
                    let shade = 0.1 + (1.0 - health) * 0.25;
                    sprite.color = Color::srgb(shade, shade, shade);
                    sprite.custom_size = Some(Vec2::new(6.0, 3.0));
                }
            } else if let Ok(mut sprite) = bodies.get_mut(child) {
                let f = 0.55 + avg_body * 0.45;
                sprite.color = Color::srgb(car.color[0] * f, car.color[1] * f, car.color[2] * f);
            } else if let Ok(mut sprite) = flashes.get_mut(child) {
                sprite.color = Color::srgba(1.0, 1.0, 1.0, flash_alpha);
            }
        }
    }

    for (marker, mut transform) in shadows.iter_mut() {
        let Some(car) = cars.0.get(marker.0) else {
            continue;
        };
        transform.translation = to_world(car.x + 3.0, car.y + 4.0, Z_SHADOW);
        transform.rotation = to_world_rot(car.angle);
    }
}
