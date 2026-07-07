//! In-race HUD: status panel, positions panel, countdown, win screen
//! (port of draw.hud / draw.positions / draw.countdown / draw.winScreen).

use bevy::prelude::*;

use super::shared::*;

#[derive(Component)]
pub struct HudRoot;

#[derive(Component)]
pub struct LapDot(pub u32);
#[derive(Component)]
pub struct SpeedFill;
#[derive(Component)]
pub struct SpeedText;
#[derive(Component)]
pub struct TimerText;
#[derive(Component)]
pub struct FuelFill;
#[derive(Component)]
pub struct FuelText;
#[derive(Component)]
pub struct TireText;
#[derive(Component)]
pub struct ZoneText;
#[derive(Component)]
pub struct TireDot(pub usize);
#[derive(Component)]
pub struct EngineFill;
#[derive(Component)]
pub struct BodyFill;
#[derive(Component)]
pub struct LapFractionText;
#[derive(Component)]
pub struct PositionRow(pub usize);
#[derive(Component)]
pub struct PositionDot(pub usize);
#[derive(Component)]
pub struct CountdownText;
#[derive(Component)]
pub struct WinUi;

pub fn health_color(h: f32) -> Color {
    if h > 0.60 {
        Color::srgb(0.2, 0.9, 0.2)
    } else if h > 0.25 {
        Color::srgb(0.95, 0.75, 0.1)
    } else {
        Color::srgb(0.95, 0.2, 0.1)
    }
}

fn label(text: &str, size: f32, alpha: f32) -> (Text, TextFont, TextColor) {
    (
        Text::new(text),
        TextFont {
            font_size: size,
            ..default()
        },
        TextColor(Color::srgba(1.0, 1.0, 1.0, alpha)),
    )
}

fn bar(width: f32, height: f32) -> (Node, BackgroundColor, BorderRadius) {
    (
        Node {
            width: Val::Px(width),
            height: Val::Px(height),
            ..default()
        },
        BackgroundColor(Color::srgba(1.0, 1.0, 1.0, 0.15)),
        BorderRadius::all(Val::Px(2.0)),
    )
}

fn bar_fill() -> (Node, BackgroundColor, BorderRadius) {
    (
        Node {
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            ..default()
        },
        BackgroundColor(Color::srgba(0.2, 0.9, 0.1, 0.85)),
        BorderRadius::all(Val::Px(2.0)),
    )
}

/// Build the static HUD structure when a race starts.
pub fn spawn_hud(mut commands: Commands, cars: Res<Cars>, race: Res<Race>) {
    // Left status panel
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Px(8.0),
                top: Val::Px(8.0),
                width: Val::Px(180.0),
                height: Val::Px(215.0),
                border: UiRect::all(Val::Px(1.0)),
                flex_direction: FlexDirection::Column,
                padding: UiRect::all(Val::Px(8.0)),
                row_gap: Val::Px(4.0),
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.55)),
            BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.15)),
            BorderRadius::all(Val::Px(6.0)),
            HudRoot,
            RaceScene,
        ))
        .with_children(|panel| {
            // LAP row with dots
            panel
                .spawn(Node {
                    column_gap: Val::Px(8.0),
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|row| {
                    row.spawn(label("LAP", 14.0, 0.9));
                    for i in 1..=race.0.max_laps {
                        row.spawn((
                            Node {
                                width: Val::Px(12.0),
                                height: Val::Px(12.0),
                                border: UiRect::all(Val::Px(1.0)),
                                ..default()
                            },
                            BackgroundColor(Color::NONE),
                            BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.3)),
                            BorderRadius::MAX,
                            LapDot(i),
                        ));
                    }
                });

            // SPD row
            panel
                .spawn(Node {
                    column_gap: Val::Px(8.0),
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|row| {
                    row.spawn(label("SPD", 14.0, 0.9));
                    row.spawn(bar(100.0, 10.0)).with_children(|b| {
                        b.spawn((bar_fill(), SpeedFill));
                    });
                    row.spawn((label("0", 14.0, 0.8), SpeedText));
                });

            // Timer
            panel.spawn((label("TIME  0:00.00", 14.0, 0.9), TimerText));

            // FUEL row
            panel
                .spawn(Node {
                    column_gap: Val::Px(8.0),
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|row| {
                    row.spawn(label("FUEL", 14.0, 0.9));
                    row.spawn(bar(100.0, 10.0)).with_children(|b| {
                        b.spawn((bar_fill(), FuelFill));
                    });
                    row.spawn((label("50", 14.0, 0.8), FuelText));
                });

            // Tire pressure
            panel.spawn((label("TIRE 2.2 bar", 14.0, 0.9), TireText));

            // Surface zone
            panel.spawn((label("", 13.0, 0.6), ZoneText));

            // DAMAGE section
            panel.spawn((
                Text::new("DAMAGE"),
                TextFont {
                    font_size: 14.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 0.75, 0.2, 0.9)),
            ));

            // Tires 2x2 grid + ENG/BODY bars
            panel
                .spawn(Node {
                    column_gap: Val::Px(10.0),
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|row| {
                    row.spawn(label("TIRES", 12.0, 0.55));
                    row.spawn(Node {
                        display: Display::Grid,
                        grid_template_columns: RepeatedGridTrack::px(2, 16.0),
                        grid_template_rows: RepeatedGridTrack::px(2, 16.0),
                        column_gap: Val::Px(6.0),
                        row_gap: Val::Px(3.0),
                        ..default()
                    })
                    .with_children(|grid| {
                        for i in 0..4 {
                            grid.spawn((
                                Node {
                                    width: Val::Px(11.0),
                                    height: Val::Px(11.0),
                                    ..default()
                                },
                                BackgroundColor(health_color(1.0)),
                                BorderRadius::MAX,
                                TireDot(i),
                            ));
                        }
                    });
                });

            for (name, marker) in [("ENG", true), ("BODY", false)] {
                panel
                    .spawn(Node {
                        column_gap: Val::Px(8.0),
                        align_items: AlignItems::Center,
                        ..default()
                    })
                    .with_children(|row| {
                        row.spawn(label(name, 12.0, 0.55));
                        let mut b = row.spawn(bar(100.0, 8.0));
                        b.with_children(|inner| {
                            if marker {
                                inner.spawn((bar_fill(), EngineFill));
                            } else {
                                inner.spawn((bar_fill(), BodyFill));
                            }
                        });
                    });
            }

            // Lap fraction bottom-right of panel
            panel.spawn((
                Text::new("1/3"),
                TextFont {
                    font_size: 18.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.7)),
                Node {
                    position_type: PositionType::Absolute,
                    right: Val::Px(10.0),
                    bottom: Val::Px(4.0),
                    ..default()
                },
                LapFractionText,
            ));
        });

    // Positions panel (top-right)
    let n = cars.0.len();
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Px(SCREEN_W - 140.0),
                top: Val::Px(8.0),
                width: Val::Px(130.0),
                height: Val::Px(15.0 + n as f32 * 20.0),
                border: UiRect::all(Val::Px(1.0)),
                flex_direction: FlexDirection::Column,
                padding: UiRect::all(Val::Px(6.0)),
                row_gap: Val::Px(4.0),
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.55)),
            BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.15)),
            BorderRadius::all(Val::Px(6.0)),
            HudRoot,
            RaceScene,
        ))
        .with_children(|panel| {
            for pos in 0..n {
                panel
                    .spawn(Node {
                        column_gap: Val::Px(6.0),
                        align_items: AlignItems::Center,
                        ..default()
                    })
                    .with_children(|row| {
                        row.spawn((
                            Node {
                                width: Val::Px(8.0),
                                height: Val::Px(8.0),
                                ..default()
                            },
                            BackgroundColor(Color::WHITE),
                            BorderRadius::MAX,
                            PositionDot(pos),
                        ));
                        row.spawn((label("", 11.0, 0.8), PositionRow(pos)));
                    });
            }
        });

    // Countdown overlay text
    commands.spawn((
        Text::new("3"),
        TextFont {
            font_size: 72.0,
            ..default()
        },
        TextColor(Color::srgb(0.9, 0.2, 0.15)),
        Node {
            position_type: PositionType::Absolute,
            width: Val::Percent(100.0),
            top: Val::Px(240.0),
            justify_content: JustifyContent::Center,
            ..default()
        },
        TextLayout::new_with_justify(JustifyText::Center),
        CountdownText,
        HudRoot,
        RaceScene,
    ));
}

/// Refresh all dynamic HUD values each frame.
#[allow(clippy::type_complexity, clippy::too_many_arguments)]
pub fn update_hud(
    cars: Res<Cars>,
    race: Res<Race>,
    track: Res<CurrentTrack>,
    mut bgs: ParamSet<(
        Query<(&LapDot, &mut BackgroundColor, &mut BorderColor)>,
        Query<(&mut Node, &mut BackgroundColor), With<SpeedFill>>,
        Query<(&mut Node, &mut BackgroundColor), With<FuelFill>>,
        Query<(&mut Node, &mut BackgroundColor), With<EngineFill>>,
        Query<(&mut Node, &mut BackgroundColor), With<BodyFill>>,
        Query<(&TireDot, &mut BackgroundColor)>,
        Query<(&PositionDot, &mut BackgroundColor)>,
    )>,
    mut texts: ParamSet<(
        Query<&mut Text, With<SpeedText>>,
        Query<&mut Text, With<TimerText>>,
        Query<&mut Text, With<FuelText>>,
        Query<(&mut Text, &mut TextColor), With<TireText>>,
        Query<&mut Text, With<ZoneText>>,
        Query<&mut Text, With<LapFractionText>>,
        Query<(&PositionRow, &mut Text, &mut TextColor)>,
    )>,
) {
    let Some(car) = cars.0.first() else { return };
    let Some(track) = track.0.as_ref() else {
        return;
    };
    let laps = race.0.car_laps[0];

    // Lap dots
    for (dot, mut bg, mut border) in bgs.p0().iter_mut() {
        if dot.0 <= laps {
            bg.0 = Color::srgb(0.2, 0.9, 0.2);
            border.0 = Color::NONE;
        } else {
            bg.0 = Color::NONE;
            border.0 = Color::srgba(1.0, 1.0, 1.0, 0.3);
        }
    }

    // Speed bar
    let speed_pct = ((car.speed.abs() / car.physics.max_speed) as f32).min(1.0);
    for (mut node, mut bg) in bgs.p1().iter_mut() {
        node.width = Val::Percent(speed_pct * 100.0);
        bg.0 = Color::srgba(speed_pct, 1.0 - speed_pct * 0.7, 0.1, 0.85);
    }
    if let Ok(mut text) = texts.p0().single_mut() {
        text.0 = format!("{}", car.speed.abs() as i64);
    }

    // Timer
    if let Ok(mut text) = texts.p1().single_mut() {
        let mins = (race.0.timer / 60.0) as i64;
        let secs = race.0.timer % 60.0;
        text.0 = format!("TIME  {mins}:{secs:05.2}");
    }

    // Fuel bar
    let fuel_pct = (car.physics.fuel_mass / car.physics.max_fuel) as f32;
    for (mut node, mut bg) in bgs.p2().iter_mut() {
        node.width = Val::Percent(fuel_pct * 100.0);
        let (r, g) = if fuel_pct > 0.5 {
            (0.2, 0.9)
        } else if fuel_pct > 0.2 {
            (0.95, 0.85)
        } else {
            (0.95, 0.2)
        };
        bg.0 = Color::srgba(r, g, 0.1, 0.85);
    }
    if let Ok(mut text) = texts.p2().single_mut() {
        text.0 = format!("{:.0}", car.physics.fuel_mass);
    }

    // Tire pressure
    if let Ok((mut text, mut color)) = texts.p3().single_mut() {
        text.0 = format!("TIRE {:.1} bar", car.physics.tire_pressure);
        let dev = (car.physics.tire_pressure - car.physics.optimal_pressure).abs();
        color.0 = if dev < 0.2 {
            Color::srgba(0.2, 0.9, 0.2, 0.9)
        } else if dev < 0.5 {
            Color::srgba(0.95, 0.85, 0.1, 0.9)
        } else {
            Color::srgba(0.95, 0.2, 0.1, 0.9)
        };
    }

    // Zone name
    if let Ok(mut text) = texts.p4().single_mut() {
        text.0 = if track.is_on_track(car.x, car.y) {
            car.current_zone_name.clone()
        } else {
            "Off Track".into()
        };
    }

    // Damage: tire dots
    for (dot, mut bg) in bgs.p5().iter_mut() {
        bg.0 = health_color(car.damage.tires[dot.0] as f32);
    }

    // Engine / body bars
    for (mut node, mut bg) in bgs.p3().iter_mut() {
        node.width = Val::Percent(car.damage.engine as f32 * 100.0);
        bg.0 = health_color(car.damage.engine as f32).with_alpha(0.85);
    }
    let avg_body = car.damage.avg_body_health() as f32;
    for (mut node, mut bg) in bgs.p4().iter_mut() {
        node.width = Val::Percent(avg_body * 100.0);
        bg.0 = health_color(avg_body).with_alpha(0.85);
    }

    // Lap fraction
    if let Ok(mut text) = texts.p5().single_mut() {
        text.0 = format!("{}/{}", (laps + 1).min(race.0.max_laps), race.0.max_laps);
    }

    // Positions: sort by laps then track percent
    let mut sorted: Vec<(usize, u32, f64)> = cars
        .0
        .iter()
        .enumerate()
        .map(|(i, c)| (i, race.0.car_laps[i], track.get_track_percent(c.x, c.y)))
        .collect();
    sorted.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.partial_cmp(&a.2).unwrap()));

    for (row, mut text, mut color) in texts.p6().iter_mut() {
        if let Some(&(car_idx, _, _)) = sorted.get(row.0) {
            let mut name = cars.0[car_idx].name.clone();
            if name.len() > 12 {
                name.truncate(11);
                name.push('.');
            }
            text.0 = format!("{}. {}", row.0 + 1, name);
            color.0 = if car_idx == 0 {
                Color::WHITE
            } else {
                Color::srgba(1.0, 1.0, 1.0, 0.8)
            };
        }
    }
    for (dot, mut bg) in bgs.p6().iter_mut() {
        if let Some(&(car_idx, _, _)) = sorted.get(dot.0) {
            bg.0 = srgb(cars.0[car_idx].color);
        }
    }
}

/// Countdown display: 3 / 2 / 1 / GO! with color and a short GO! linger.
pub fn update_countdown_text(
    race: Res<Race>,
    mut query: Query<(&mut Text, &mut TextColor, &mut Visibility), With<CountdownText>>,
) {
    let Ok((mut text, mut color, mut visibility)) = query.single_mut() else {
        return;
    };
    // Show through the countdown and half a second of "GO!"
    if race.0.countdown < -0.7 {
        *visibility = Visibility::Hidden;
        return;
    }
    *visibility = Visibility::Visible;

    let num = race.0.countdown.ceil() as i32;
    let (t, c) = match num {
        n if n >= 3 => ("3", Color::srgb(0.9, 0.2, 0.15)),
        2 => ("2", Color::srgb(0.95, 0.85, 0.1)),
        1 => ("1", Color::srgb(0.2, 0.9, 0.2)),
        _ => ("GO!", Color::srgb(0.1, 1.0, 0.2)),
    };
    text.0 = t.into();
    color.0 = c;
}

/// Spawn / refresh the win overlay when the race has been won.
pub fn update_win_screen(
    mut commands: Commands,
    race: Res<Race>,
    cars: Res<Cars>,
    track: Res<CurrentTrack>,
    existing: Query<Entity, With<WinUi>>,
) {
    if !race.0.won {
        for entity in existing.iter() {
            commands.entity(entity).despawn();
        }
        return;
    }
    if !existing.is_empty() {
        return;
    }
    let Some(track) = track.0.as_ref() else {
        return;
    };

    let winner_index = race.0.winner_index.unwrap_or(0);
    let winner = &cars.0[winner_index];
    let (win_text, win_color) = if winner_index == 0 {
        ("YOU WIN!".to_string(), Color::srgb(1.0, 0.9, 0.1))
    } else {
        (format!("{} WINS!", winner.name), srgb(winner.color))
    };

    let mins = (race.0.timer / 60.0) as i64;
    let secs = race.0.timer % 60.0;
    let avg_speed = if race.0.timer > 0.0 {
        (race.0.max_laps as f64 * track.circumference()) / race.0.timer
    } else {
        0.0
    };

    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                flex_direction: FlexDirection::Column,
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                row_gap: Val::Px(16.0),
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.65)),
            WinUi,
            RaceScene,
        ))
        .with_children(|root| {
            // Checkered borders top and bottom
            for top in [Val::Px(0.0), Val::Px(SCREEN_H - 32.0)] {
                root.spawn(Node {
                    position_type: PositionType::Absolute,
                    top,
                    left: Val::Px(0.0),
                    width: Val::Percent(100.0),
                    height: Val::Px(32.0),
                    flex_wrap: FlexWrap::Wrap,
                    ..default()
                })
                .with_children(|strip| {
                    for i in 0..100 {
                        let row = i / 50;
                        let col = i % 50;
                        strip.spawn((
                            Node {
                                width: Val::Px(16.0),
                                height: Val::Px(16.0),
                                ..default()
                            },
                            BackgroundColor(if (row + col) % 2 == 0 {
                                Color::srgba(1.0, 1.0, 1.0, 0.8)
                            } else {
                                Color::srgba(0.1, 0.1, 0.1, 0.8)
                            }),
                        ));
                    }
                });
            }

            root.spawn((
                Text::new(win_text),
                TextFont {
                    font_size: 48.0,
                    ..default()
                },
                TextColor(win_color),
            ));
            root.spawn((
                Text::new(format!("Time: {mins}:{secs:05.2}")),
                TextFont {
                    font_size: 20.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.95)),
            ));
            root.spawn((
                Text::new(format!("Avg Speed: {}", avg_speed as i64)),
                TextFont {
                    font_size: 20.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.95)),
            ));
            root.spawn((
                Text::new("Press R to restart  |  ESC for menu"),
                TextFont {
                    font_size: 20.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.7)),
            ));
        });
}
