//! Pause menu overlay (port of draw.pauseMenu + pause input handling).

use bevy::prelude::*;
use racing_sim::pause::{PauseAction, OPTIONS};

use super::audio_sys::{self, Sounds};
use super::shared::*;

#[derive(Component)]
pub struct PauseUi;

#[derive(Component)]
pub struct PauseOption(#[allow(dead_code)] pub usize);

pub fn spawn_pause(mut commands: Commands, pause: Res<Pause>) {
    build_pause(&mut commands, pause.0.selected_index);
}

pub fn despawn_pause(mut commands: Commands, query: Query<Entity, With<PauseUi>>) {
    for entity in query.iter() {
        commands.entity(entity).despawn();
    }
}

pub fn rebuild_pause_on_change(
    mut commands: Commands,
    pause: Res<Pause>,
    existing: Query<Entity, With<PauseUi>>,
) {
    if !pause.is_changed() {
        return;
    }
    for entity in existing.iter() {
        commands.entity(entity).despawn();
    }
    build_pause(&mut commands, pause.0.selected_index);
}

fn build_pause(commands: &mut Commands, selected: usize) {
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
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.7)),
            PauseUi,
        ))
        .with_children(|root| {
            root.spawn((
                Node {
                    width: Val::Px(220.0),
                    height: Val::Px(200.0),
                    border: UiRect::all(Val::Px(2.0)),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    padding: UiRect::all(Val::Px(15.0)),
                    row_gap: Val::Px(10.0),
                    ..default()
                },
                BackgroundColor(Color::srgba(0.15, 0.15, 0.2, 0.95)),
                BorderColor(Color::srgba(1.0, 1.0, 1.0, 0.3)),
                BorderRadius::all(Val::Px(10.0)),
            ))
            .with_children(|panel| {
                panel.spawn((
                    Text::new("PAUSED"),
                    TextFont {
                        font_size: 18.0,
                        ..default()
                    },
                    TextColor(Color::WHITE),
                ));

                for (i, option) in OPTIONS.iter().enumerate() {
                    let is_selected = i == selected;
                    panel
                        .spawn((
                            Node {
                                width: Val::Px(180.0),
                                height: Val::Px(35.0),
                                border: UiRect::all(Val::Px(if is_selected { 2.0 } else { 1.0 })),
                                justify_content: JustifyContent::Center,
                                align_items: AlignItems::Center,
                                ..default()
                            },
                            BackgroundColor(if is_selected {
                                Color::srgba(0.3, 0.6, 0.9, 0.9)
                            } else {
                                Color::srgba(0.25, 0.25, 0.3, 0.8)
                            }),
                            BorderColor(Color::srgba(
                                1.0,
                                1.0,
                                1.0,
                                if is_selected { 0.8 } else { 0.2 },
                            )),
                            BorderRadius::all(Val::Px(5.0)),
                            PauseOption(i),
                        ))
                        .with_children(|btn| {
                            btn.spawn((
                                Text::new(*option),
                                TextFont {
                                    font_size: 16.0,
                                    ..default()
                                },
                                TextColor(Color::WHITE),
                            ));
                        });
                }
            });
        });
}

fn execute_action(
    action: PauseAction,
    return_to: &mut ControlsReturnTo,
    next_state: &mut NextState<AppState>,
    menu_events: &mut EventWriter<ReturnToMenu>,
) {
    match action {
        PauseAction::Resume => next_state.set(AppState::Racing),
        PauseAction::Controls => {
            return_to.0 = AppState::Paused;
            next_state.set(AppState::Controls);
        }
        PauseAction::MainMenu => {
            menu_events.write(ReturnToMenu);
        }
    }
}

/// Keyboard handling in the pause menu.
#[allow(clippy::too_many_arguments)]
pub fn pause_keys(
    keys: Res<ButtonInput<KeyCode>>,
    mut commands: Commands,
    mut pause: ResMut<Pause>,
    sounds: Res<Sounds>,
    mut return_to: ResMut<ControlsReturnTo>,
    mut next_state: ResMut<NextState<AppState>>,
    mut menu_events: EventWriter<ReturnToMenu>,
) {
    if keys.just_pressed(KeyCode::Escape) {
        audio_sys::play_menu_blip(&mut commands, &sounds);
        next_state.set(AppState::Racing);
    } else if keys.just_pressed(KeyCode::Enter) || keys.just_pressed(KeyCode::Space) {
        audio_sys::play_menu_select(&mut commands, &sounds);
        execute_action(
            pause.0.selected_action(),
            &mut return_to,
            &mut next_state,
            &mut menu_events,
        );
    } else if keys.just_pressed(KeyCode::ArrowUp) {
        pause.0.move_up();
        audio_sys::play_menu_blip(&mut commands, &sounds);
    } else if keys.just_pressed(KeyCode::ArrowDown) {
        pause.0.move_down();
        audio_sys::play_menu_blip(&mut commands, &sounds);
    }
}

/// Mouse handling in the pause menu (uses the ported hit-test).
#[allow(clippy::too_many_arguments)]
pub fn pause_mouse(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    mut commands: Commands,
    mut pause: ResMut<Pause>,
    sounds: Res<Sounds>,
    mut return_to: ResMut<ControlsReturnTo>,
    mut next_state: ResMut<NextState<AppState>>,
    mut menu_events: EventWriter<ReturnToMenu>,
) {
    if !buttons.just_pressed(MouseButton::Left) {
        return;
    }
    let Ok(window) = windows.single() else { return };
    let Some((x, y)) = cursor_sim_pos(window) else {
        return;
    };
    if let Some(action) = pause.0.handle_click(x, y, SCREEN_W as f64, SCREEN_H as f64) {
        audio_sys::play_menu_select(&mut commands, &sounds);
        execute_action(action, &mut return_to, &mut next_state, &mut menu_events);
    }
}
