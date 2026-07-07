//! Dev menu with physics sliders (port of devmenu.lua + draw.devMenu).
//! Toggled with F1 while racing; sliders edit the player car's physics live.

use bevy::prelude::*;

use super::shared::{cursor_sim_pos, Cars};

pub const PANEL_X: f32 = 530.0;
pub const PANEL_Y: f32 = 10.0;
pub const PANEL_W: f32 = 260.0;
pub const SLIDER_H: f32 = 16.0;
pub const SLIDER_PAD: f32 = 22.0;
const SLIDER_X_OFF: f32 = 105.0;
const SLIDER_W: f32 = PANEL_W - 115.0;

pub struct SliderDef {
    pub label: &'static str,
    pub unit: &'static str,
    pub min: f64,
    pub max: f64,
    pub get: fn(&racing_sim::car::Physics) -> f64,
    pub set: fn(&mut racing_sim::car::Physics, f64),
}

pub const SLIDERS: [SliderDef; 10] = [
    SliderDef {
        label: "Car Mass",
        unit: "kg",
        min: 400.0,
        max: 1500.0,
        get: |p| p.mass,
        set: |p, v| p.mass = v,
    },
    SliderDef {
        label: "Fuel",
        unit: "kg",
        min: 0.0,
        max: 50.0,
        get: |p| p.fuel_mass,
        set: |p, v| p.fuel_mass = v,
    },
    SliderDef {
        label: "Fuel Rate",
        unit: "kg/s",
        min: 0.0,
        max: 5.0,
        get: |p| p.fuel_rate,
        set: |p, v| p.fuel_rate = v,
    },
    SliderDef {
        label: "Tire Pressure",
        unit: "bar",
        min: 1.5,
        max: 3.0,
        get: |p| p.tire_pressure,
        set: |p, v| p.tire_pressure = v,
    },
    SliderDef {
        label: "Engine Force",
        unit: "",
        min: 50000.0,
        max: 500000.0,
        get: |p| p.engine_force,
        set: |p, v| p.engine_force = v,
    },
    SliderDef {
        label: "Brake Force",
        unit: "",
        min: 50000.0,
        max: 400000.0,
        get: |p| p.brake_force,
        set: |p, v| p.brake_force = v,
    },
    SliderDef {
        label: "Drag Coeff",
        unit: "",
        min: 0.5,
        max: 10.0,
        get: |p| p.drag_coeff,
        set: |p, v| p.drag_coeff = v,
    },
    SliderDef {
        label: "Rolling Res.",
        unit: "",
        min: 0.005,
        max: 0.05,
        get: |p| p.rolling_resistance,
        set: |p, v| p.rolling_resistance = v,
    },
    SliderDef {
        label: "Grip Multi.",
        unit: "x",
        min: 0.1,
        max: 1.5,
        get: |p| p.grip_multiplier,
        set: |p, v| p.grip_multiplier = v,
    },
    SliderDef {
        label: "Bump Multi.",
        unit: "x",
        min: 0.0,
        max: 3.0,
        get: |p| p.bump_multiplier,
        set: |p, v| p.bump_multiplier = v,
    },
];

#[derive(Resource, Default)]
pub struct DevMenu {
    pub open: bool,
    pub active_slider: Option<usize>,
}

#[derive(Component)]
pub struct DevMenuUi;
#[derive(Component)]
pub struct DevSliderFill(pub usize);
#[derive(Component)]
pub struct DevSliderValue(pub usize);

/// Slider hit-test in sim/screen coordinates (identical to devmenu.lua).
fn slider_at(x: f64, y: f64) -> Option<usize> {
    for i in 0..SLIDERS.len() {
        let sy = (PANEL_Y + 30.0 + i as f32 * SLIDER_PAD) as f64;
        let sx = (PANEL_X + SLIDER_X_OFF) as f64;
        if x >= sx && x <= sx + SLIDER_W as f64 && y >= sy && y <= sy + SLIDER_H as f64 {
            return Some(i);
        }
    }
    None
}

fn apply_slider_at(x: f64, slider: &SliderDef, physics: &mut racing_sim::car::Physics) {
    let sx = (PANEL_X + SLIDER_X_OFF) as f64;
    let t = ((x - sx) / SLIDER_W as f64).clamp(0.0, 1.0);
    (slider.set)(physics, slider.min + t * (slider.max - slider.min));
}

/// Build/tear down the panel when `open` changes; handle drag interaction.
#[allow(clippy::too_many_arguments)]
pub fn devmenu_system(
    mut devmenu: ResMut<DevMenu>,
    mut commands: Commands,
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    mut cars: ResMut<Cars>,
    existing: Query<Entity, With<DevMenuUi>>,
    mut fills: Query<(&DevSliderFill, &mut Node)>,
    mut values: Query<(&DevSliderValue, &mut Text)>,
) {
    if !devmenu.open {
        for entity in existing.iter() {
            commands.entity(entity).despawn();
        }
        devmenu.active_slider = None;
        return;
    }

    if existing.is_empty() {
        spawn_panel(&mut commands);
    }

    let Some(player) = cars.0.first_mut() else {
        return;
    };

    // Drag handling
    let cursor = windows.single().ok().and_then(cursor_sim_pos);
    if buttons.just_pressed(MouseButton::Left) {
        if let Some((x, y)) = cursor {
            if let Some(i) = slider_at(x, y) {
                devmenu.active_slider = Some(i);
                apply_slider_at(x, &SLIDERS[i], &mut player.physics);
            }
        }
    } else if buttons.pressed(MouseButton::Left) {
        if let (Some(i), Some((x, _))) = (devmenu.active_slider, cursor) {
            apply_slider_at(x, &SLIDERS[i], &mut player.physics);
        }
    } else {
        devmenu.active_slider = None;
    }

    // Refresh fills and value labels
    for (fill, mut node) in fills.iter_mut() {
        let s = &SLIDERS[fill.0];
        let t = ((s.get)(&player.physics) - s.min) / (s.max - s.min);
        node.width = Val::Percent((t.clamp(0.0, 1.0) * 100.0) as f32);
    }
    for (value, mut text) in values.iter_mut() {
        let s = &SLIDERS[value.0];
        let v = (s.get)(&player.physics);
        let val_str = if s.max - s.min < 1.0 {
            format!("{v:.3}")
        } else if s.max - s.min < 10.0 {
            format!("{v:.1}")
        } else {
            format!("{}", v as i64)
        };
        text.0 = format!("{} {}", val_str, s.unit);
    }
}

fn spawn_panel(commands: &mut Commands) {
    let panel_h = 35.0 + SLIDERS.len() as f32 * SLIDER_PAD + 10.0;
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Px(PANEL_X),
                top: Val::Px(PANEL_Y),
                width: Val::Px(PANEL_W),
                height: Val::Px(panel_h),
                border: UiRect::all(Val::Px(1.0)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.75)),
            BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.2)),
            BorderRadius::all(Val::Px(6.0)),
            DevMenuUi,
        ))
        .with_children(|panel| {
            panel.spawn((
                Text::new("DEV MENU (F1)"),
                TextFont {
                    font_size: 14.0,
                    ..default()
                },
                TextColor(Color::srgb(1.0, 0.9, 0.3)),
                Node {
                    position_type: PositionType::Absolute,
                    left: Val::Px(8.0),
                    top: Val::Px(6.0),
                    ..default()
                },
            ));

            for (i, s) in SLIDERS.iter().enumerate() {
                let sy = 30.0 + i as f32 * SLIDER_PAD;
                panel.spawn((
                    Text::new(s.label),
                    TextFont {
                        font_size: 11.0,
                        ..default()
                    },
                    TextColor(Color::srgba(1.0, 1.0, 1.0, 0.8)),
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Px(6.0),
                        top: Val::Px(sy + 1.0),
                        ..default()
                    },
                ));
                panel
                    .spawn((
                        Node {
                            position_type: PositionType::Absolute,
                            left: Val::Px(SLIDER_X_OFF),
                            top: Val::Px(sy + 2.0),
                            width: Val::Px(SLIDER_W),
                            height: Val::Px(SLIDER_H - 4.0),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(1.0, 1.0, 1.0, 0.15)),
                        BorderRadius::all(Val::Px(2.0)),
                    ))
                    .with_children(|track| {
                        track.spawn((
                            Node {
                                width: Val::Percent(50.0),
                                height: Val::Percent(100.0),
                                ..default()
                            },
                            BackgroundColor(Color::srgba(0.3, 0.7, 1.0, 0.7)),
                            BorderRadius::all(Val::Px(2.0)),
                            DevSliderFill(i),
                        ));
                    });
                panel.spawn((
                    Text::new(""),
                    TextFont {
                        font_size: 11.0,
                        ..default()
                    },
                    TextColor(Color::srgba(1.0, 1.0, 1.0, 0.6)),
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Px(SLIDER_X_OFF + SLIDER_W + 4.0),
                        top: Val::Px(sy + 1.0),
                        ..default()
                    },
                    DevSliderValue(i),
                ));
            }
        });
}
