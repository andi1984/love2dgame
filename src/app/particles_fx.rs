//! Particle system (port of particles.lua) as ECS entities.

use bevy::prelude::*;
use racing_sim::car::Car;
use racing_sim::damage::Side;
use racing_sim::rng::GameRng;

use super::render::Z_PARTICLES;
use super::shared::{to_world, RaceScene};

#[derive(Component)]
pub struct Particle {
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub life: f64,
    pub max_life: f64,
    pub size: f64,
    pub color: [f32; 4],
}

fn spawn_particle(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    particle: Particle,
) {
    let color = particle.color;
    commands.spawn((
        Mesh2d(meshes.add(Circle::new(1.0))),
        MeshMaterial2d(materials.add(ColorMaterial::from_color(Color::srgba(
            color[0], color[1], color[2], color[3],
        )))),
        Transform {
            translation: to_world(particle.x, particle.y, Z_PARTICLES),
            scale: Vec3::splat(particle.size as f32),
            ..default()
        },
        particle,
        RaceScene,
    ));
}

/// White/grey tyre smoke (braking / sharp turns).
pub fn spawn_smoke(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    car: &Car,
    rng: &mut GameRng,
) {
    let rear_x = car.x - car.angle.cos() * car.width * 0.4;
    let rear_y = car.y - car.angle.sin() * car.height * 0.4;
    for _ in 0..2 {
        spawn_particle(
            commands,
            meshes,
            materials,
            Particle {
                x: rear_x + (rng.next_f64() - 0.5) * 8.0,
                y: rear_y + (rng.next_f64() - 0.5) * 8.0,
                life: 0.5,
                max_life: 0.5,
                size: 3.0 + rng.next_f64() * 3.0,
                vx: (rng.next_f64() - 0.5) * 20.0,
                vy: (rng.next_f64() - 0.5) * 20.0,
                color: [0.8, 0.8, 0.8, 1.0],
            },
        );
    }
}

/// Dark engine-damage smoke.
pub fn spawn_dark_smoke(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    car: &Car,
    rng: &mut GameRng,
) {
    let rear_x = car.x - car.angle.cos() * car.width * 0.45;
    let rear_y = car.y - car.angle.sin() * car.height * 0.45;
    spawn_particle(
        commands,
        meshes,
        materials,
        Particle {
            x: rear_x + (rng.next_f64() - 0.5) * 6.0,
            y: rear_y + (rng.next_f64() - 0.5) * 6.0,
            life: 1.2,
            max_life: 1.2,
            size: 5.0 + rng.next_f64() * 5.0,
            vx: (rng.next_f64() - 0.5) * 12.0,
            vy: (rng.next_f64() - 0.5) * 12.0 - 8.0, // drift upward
            color: [0.12, 0.10, 0.10, 1.0],
        },
    );
}

/// Yellow/orange collision sparks at the impacted side.
pub fn spawn_sparks(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<ColorMaterial>,
    car: &Car,
    side: Option<Side>,
    rng: &mut GameRng,
) {
    let (mut ox, mut oy) = (car.x, car.y);
    let hw = car.width / 2.0;
    let hh = car.height / 2.0;
    let (ca, sa) = (car.angle.cos(), car.angle.sin());

    match side {
        Some(Side::Front) => {
            ox = car.x + ca * hw;
            oy = car.y + sa * hw;
        }
        Some(Side::Rear) => {
            ox = car.x - ca * hw;
            oy = car.y - sa * hw;
        }
        Some(Side::Left) => {
            ox = car.x - sa * hh;
            oy = car.y + ca * hh;
        }
        Some(Side::Right) => {
            ox = car.x + sa * hh;
            oy = car.y - ca * hh;
        }
        None => {}
    }

    let num_sparks = 6 + rng.int1(5);
    for _ in 0..num_sparks {
        let angle = rng.next_f64() * std::f64::consts::TAU;
        let speed = 40.0 + rng.next_f64() * 120.0;
        let color = [
            1.0,
            0.5 + rng.next_f64() as f32 * 0.5,
            rng.next_f64() as f32 * 0.2,
            1.0,
        ];
        spawn_particle(
            commands,
            meshes,
            materials,
            Particle {
                x: ox + (rng.next_f64() - 0.5) * 6.0,
                y: oy + (rng.next_f64() - 0.5) * 6.0,
                life: 0.15 + rng.next_f64() * 0.25,
                max_life: 0.4,
                size: 1.5 + rng.next_f64() * 2.0,
                vx: angle.cos() * speed,
                vy: angle.sin() * speed,
                color,
            },
        );
    }
}

/// Move, shrink, fade, and expire particles (port of particles.update + draw).
pub fn update_particles(
    time: Res<Time>,
    mut commands: Commands,
    mut query: Query<(
        Entity,
        &mut Particle,
        &mut Transform,
        &MeshMaterial2d<ColorMaterial>,
    )>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    let dt = time.delta_secs_f64();
    for (entity, mut p, mut transform, material) in query.iter_mut() {
        p.life -= dt;
        if p.life <= 0.0 {
            commands.entity(entity).despawn();
            continue;
        }
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= 0.95;
        p.vy *= 0.95;

        let t = (p.life / p.max_life) as f32;
        transform.translation = to_world(p.x, p.y, Z_PARTICLES);
        transform.scale = Vec3::splat((p.size as f32 * t).max(0.01));
        if let Some(mat) = materials.get_mut(&material.0) {
            let alpha = t * 0.6 * p.color[3];
            mat.color = Color::srgba(p.color[0], p.color[1], p.color[2], alpha);
        }
    }
}
