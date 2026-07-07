//! Controls screen (port of draw.controlsScreen).

use bevy::prelude::*;

use super::audio_sys::{self, Sounds};
use super::shared::*;

#[derive(Component)]
pub struct ControlsUi;

#[derive(Component)]
pub struct BackButton;

pub fn spawn_controls(mut commands: Commands) {
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.8)),
            ControlsUi,
        ))
        .with_children(|root| {
            root.spawn((
                Node {
                    width: Val::Px(400.0),
                    height: Val::Px(400.0),
                    border: UiRect::all(Val::Px(2.0)),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    padding: UiRect::all(Val::Px(20.0)),
                    row_gap: Val::Px(8.0),
                    ..default()
                },
                BackgroundColor(Color::srgba(0.15, 0.15, 0.2, 0.95)),
                BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.3)),
                BorderRadius::all(Val::Px(10.0)),
            ))
            .with_children(|panel| {
                panel.spawn((
                    Text::new("CONTROLS"),
                    TextFont {
                        font_size: 42.0,
                        ..default()
                    },
                    TextColor(Color::srgb(1.0, 0.9, 0.2)),
                ));

                let controls = [
                    ("UP", "Accelerate"),
                    ("DOWN", "Brake / Reverse"),
                    ("LEFT / RIGHT", "Steer"),
                    ("R", "Restart Race"),
                    ("ESC", "Pause Menu"),
                    ("F1", "Dev Menu"),
                ];
                for (key, action) in controls {
                    panel
                        .spawn(Node {
                            width: Val::Percent(90.0),
                            justify_content: JustifyContent::SpaceBetween,
                            ..default()
                        })
                        .with_children(|row| {
                            row.spawn((
                                Text::new(key),
                                TextFont {
                                    font_size: 16.0,
                                    ..default()
                                },
                                TextColor(Color::srgb(0.3, 0.7, 1.0)),
                            ));
                            row.spawn((
                                Text::new(action),
                                TextFont {
                                    font_size: 16.0,
                                    ..default()
                                },
                                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.9)),
                            ));
                        });
                }

                panel
                    .spawn((
                        Node {
                            width: Val::Px(150.0),
                            height: Val::Px(40.0),
                            margin: UiRect::top(Val::Px(20.0)),
                            border: UiRect::all(Val::Px(2.0)),
                            justify_content: JustifyContent::Center,
                            align_items: AlignItems::Center,
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.3, 0.6, 0.9, 0.9)),
                        BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.8)),
                        BorderRadius::all(Val::Px(6.0)),
                        Button,
                        BackButton,
                    ))
                    .with_children(|btn| {
                        btn.spawn((
                            Text::new("BACK"),
                            TextFont {
                                font_size: 16.0,
                                ..default()
                            },
                            TextColor(Color::WHITE),
                        ));
                    });

                panel.spawn((
                    Text::new("Press ESC or Enter to go back"),
                    TextFont {
                        font_size: 12.0,
                        ..default()
                    },
                    TextColor(Color::srgba(1.0, 1.0, 1.0, 0.5)),
                ));
            });
        });
}

pub fn despawn_controls(mut commands: Commands, query: Query<Entity, With<ControlsUi>>) {
    for entity in query.iter() {
        commands.entity(entity).despawn();
    }
}

/// ESC / Enter / Space or the BACK button returns to wherever we came from.
pub fn controls_input(
    keys: Res<ButtonInput<KeyCode>>,
    interactions: Query<&Interaction, (Changed<Interaction>, With<BackButton>)>,
    mut commands: Commands,
    sounds: Res<Sounds>,
    return_to: Res<ControlsReturnTo>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    let key_back = keys.just_pressed(KeyCode::Escape)
        || keys.just_pressed(KeyCode::Enter)
        || keys.just_pressed(KeyCode::Space);
    let click_back = interactions
        .iter()
        .any(|i| matches!(i, Interaction::Pressed));

    if key_back || click_back {
        audio_sys::play_menu_blip(&mut commands, &sounds);
        next_state.set(return_to.0);
    }
}
