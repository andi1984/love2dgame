//! Main menu: track selection cards, "+" generate card, controls button
//! (port of draw.mainMenu + the menu branches of love.keypressed/mousepressed).

use bevy::prelude::*;
use racing_sim::menu::{MenuAction, MenuButton, MenuState};
use racing_sim::persistence;
use racing_sim::trackgen;

use super::audio_sys::{self, Sounds};
use super::shared::*;

#[derive(Component)]
pub struct MenuUi;

/// Card marker (index kept for debugging/inspection).
#[derive(Component)]
pub struct MenuCard(#[allow(dead_code)] pub usize);

#[derive(Component)]
pub struct ControlsButton;

pub fn spawn_menu(mut commands: Commands, menu: Res<Menu>, tracks: Res<Tracks>) {
    build_menu(&mut commands, &menu.0, &tracks);
}

pub fn despawn_menu(mut commands: Commands, query: Query<Entity, With<MenuUi>>) {
    for entity in query.iter() {
        commands.entity(entity).despawn();
    }
}

/// Rebuild the menu when selection or track list changes (simplest way to
/// keep highlights and the card grid current).
pub fn rebuild_menu_on_change(
    mut commands: Commands,
    menu: Res<Menu>,
    tracks: Res<Tracks>,
    existing: Query<Entity, With<MenuUi>>,
) {
    if !menu.is_changed() && !tracks.is_changed() {
        return;
    }
    for entity in existing.iter() {
        commands.entity(entity).despawn();
    }
    build_menu(&mut commands, &menu.0, &tracks);
}

fn build_menu(commands: &mut Commands, menu: &MenuState, tracks: &Tracks) {
    // Full-screen dark background (over the grass-green clear color)
    commands
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.7)),
            MenuUi,
        ))
        .with_children(|root| {
            // Title
            root.spawn((
                Text::new("RACING GAME"),
                TextFont {
                    font_size: 42.0,
                    ..default()
                },
                TextColor(Color::srgb(1.0, 0.9, 0.2)),
                Node {
                    position_type: PositionType::Absolute,
                    top: Val::Px(50.0),
                    width: Val::Percent(100.0),
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                TextLayout::new_with_justify(JustifyText::Center),
            ));
            root.spawn((
                Text::new("Select a track to begin"),
                TextFont {
                    font_size: 16.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.7)),
                Node {
                    position_type: PositionType::Absolute,
                    top: Val::Px(110.0),
                    width: Val::Percent(100.0),
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                TextLayout::new_with_justify(JustifyText::Center),
            ));

            // Track cards
            for i in 0..menu.display_count() {
                let (x, y, w, h) = menu.card_rect(i, SCREEN_W as f64);
                let selected =
                    i == menu.selected_track && menu.selected_button == MenuButton::Track;
                let is_add = i >= menu.track_count;

                let (bg, border) = match (is_add, selected) {
                    (false, true) => (
                        Color::srgba(0.3, 0.6, 0.9, 0.9),
                        Color::srgba(1.0, 1.0, 1.0, 0.9),
                    ),
                    (false, false) => (
                        Color::srgba(0.2, 0.2, 0.25, 0.85),
                        Color::srgba(1.0, 1.0, 1.0, 0.3),
                    ),
                    (true, true) => (
                        Color::srgba(0.2, 0.65, 0.35, 0.9),
                        Color::srgba(0.4, 1.0, 0.5, 0.9),
                    ),
                    (true, false) => (
                        Color::srgba(0.15, 0.3, 0.2, 0.85),
                        Color::srgba(0.3, 0.8, 0.4, 0.4),
                    ),
                };

                root.spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Px(x as f32),
                        top: Val::Px(y as f32),
                        width: Val::Px(w as f32),
                        height: Val::Px(h as f32),
                        border: UiRect::all(Val::Px(if selected { 3.0 } else { 1.0 })),
                        flex_direction: FlexDirection::Column,
                        align_items: AlignItems::Center,
                        padding: UiRect::top(Val::Px(10.0)),
                        ..default()
                    },
                    BackgroundColor(bg),
                    BorderColor(border),
                    BorderRadius::all(Val::Px(8.0)),
                    MenuCard(i),
                ))
                .with_children(|card| {
                    if is_add {
                        card.spawn((
                            Text::new("+"),
                            TextFont {
                                font_size: 42.0,
                                ..default()
                            },
                            TextColor(if selected {
                                Color::srgba(0.4, 1.0, 0.5, 1.0)
                            } else {
                                Color::srgba(0.3, 0.8, 0.4, 0.8)
                            }),
                        ));
                        card.spawn((
                            Text::new("Generate Track"),
                            TextFont {
                                font_size: 12.0,
                                ..default()
                            },
                            TextColor(Color::srgba(1.0, 1.0, 1.0, 0.7)),
                        ));
                    } else if let Some(info) = tracks.0.get_by_index(i) {
                        card.spawn((
                            Text::new(info.name.clone()),
                            TextFont {
                                font_size: 15.0,
                                ..default()
                            },
                            TextColor(Color::WHITE),
                        ));
                        card.spawn((
                            Text::new(info.description.clone()),
                            TextFont {
                                font_size: 12.0,
                                ..default()
                            },
                            TextColor(Color::srgba(1.0, 1.0, 1.0, 0.7)),
                            TextLayout::new_with_justify(JustifyText::Center),
                        ));
                    }
                });
            }

            // Controls button
            let controls_selected = menu.selected_button == MenuButton::Controls;
            root.spawn((
                Node {
                    position_type: PositionType::Absolute,
                    left: Val::Px((SCREEN_W - 200.0) / 2.0),
                    top: Val::Px(530.0),
                    width: Val::Px(200.0),
                    height: Val::Px(40.0),
                    border: UiRect::all(Val::Px(if controls_selected { 2.0 } else { 1.0 })),
                    justify_content: JustifyContent::Center,
                    align_items: AlignItems::Center,
                    ..default()
                },
                BackgroundColor(if controls_selected {
                    Color::srgba(0.3, 0.6, 0.9, 0.9)
                } else {
                    Color::srgba(0.2, 0.2, 0.25, 0.85)
                }),
                BorderColor(Color::srgba(
                    1.0,
                    1.0,
                    1.0,
                    if controls_selected { 0.9 } else { 0.3 },
                )),
                BorderRadius::all(Val::Px(6.0)),
                ControlsButton,
            ))
            .with_children(|btn| {
                btn.spawn((
                    Text::new("CONTROLS"),
                    TextFont {
                        font_size: 16.0,
                        ..default()
                    },
                    TextColor(Color::WHITE),
                ));
            });

            // Footer instructions
            root.spawn((
                Text::new("Arrow keys to navigate  |  Enter to select  |  Click on a track"),
                TextFont {
                    font_size: 12.0,
                    ..default()
                },
                TextColor(Color::srgba(1.0, 1.0, 1.0, 0.5)),
                Node {
                    position_type: PositionType::Absolute,
                    top: Val::Px(578.0),
                    width: Val::Percent(100.0),
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                TextLayout::new_with_justify(JustifyText::Center),
            ));
        });
}

/// Mini track shape previews drawn with gizmos over the cards.
pub fn draw_track_previews(menu: Res<Menu>, tracks: Res<Tracks>, mut gizmos: Gizmos) {
    for i in 0..menu.0.track_count {
        let Some(info) = tracks.0.get_by_index(i) else {
            continue;
        };
        let (card_x, card_y, card_w, _) = menu.0.card_rect(i, SCREEN_W as f64);
        let (cx, cy) = (card_x + card_w / 2.0, card_y + 80.0);
        let (scale_x, scale_y) = (50.0, 25.0);

        let points = &info.points;
        if points.len() < 3 {
            continue;
        }
        let (mut min_x, mut max_x) = (f64::INFINITY, f64::NEG_INFINITY);
        let (mut min_y, mut max_y) = (f64::INFINITY, f64::NEG_INFINITY);
        for p in points {
            min_x = min_x.min(p.x);
            max_x = max_x.max(p.x);
            min_y = min_y.min(p.y);
            max_y = max_y.max(p.y);
        }
        let scale = (scale_x * 2.0 / (max_x - min_x).max(1.0))
            .min(scale_y * 2.0 / (max_y - min_y).max(1.0))
            * 0.8;

        let to_screen = |p: &racing_sim::P| {
            let x = cx + (p.x - (min_x + max_x) / 2.0) * scale;
            let y = cy + (p.y - (min_y + max_y) / 2.0) * scale;
            to_world(x, y, 0.0).truncate()
        };

        let color = Color::srgba(0.5, 0.5, 0.55, 0.8);
        for w in 0..points.len() {
            let a = to_screen(&points[w]);
            let b = to_screen(&points[(w + 1) % points.len()]);
            gizmos.line_2d(a, b, color);
        }
        // Start marker
        gizmos.circle_2d(to_screen(&points[0]), 3.0, Color::srgb(0.2, 0.9, 0.2));
    }
}

/// Menu keyboard handling (port of the menu branch of love.keypressed).
#[allow(clippy::too_many_arguments)]
pub fn menu_keys(
    keys: Res<ButtonInput<KeyCode>>,
    mut commands: Commands,
    mut menu: ResMut<Menu>,
    mut tracks: ResMut<Tracks>,
    sounds: Res<Sounds>,
    mut rng: ResMut<SimRng>,
    mut start_events: EventWriter<StartRace>,
    mut return_to: ResMut<ControlsReturnTo>,
    mut next_state: ResMut<NextState<AppState>>,
    mut exit: EventWriter<AppExit>,
) {
    if keys.just_pressed(KeyCode::Escape) {
        exit.write(AppExit::Success);
        return;
    }

    if keys.just_pressed(KeyCode::Enter) || keys.just_pressed(KeyCode::Space) {
        audio_sys::play_menu_select(&mut commands, &sounds);
        match menu.0.selected_button {
            MenuButton::Track => {
                if menu.0.is_add_selected() {
                    generate_new_track(&mut menu, &mut tracks, &mut rng);
                } else if let Some(idx) = menu.0.selected_track_index() {
                    if let Some(config) = tracks.0.get_by_index(idx) {
                        start_events.write(StartRace(config.clone()));
                    }
                }
            }
            MenuButton::Controls => {
                return_to.0 = AppState::Menu;
                next_state.set(AppState::Controls);
            }
        }
        return;
    }

    let mut blip = false;
    if keys.just_pressed(KeyCode::ArrowLeft) {
        menu.0.select_prev();
        blip = true;
    }
    if keys.just_pressed(KeyCode::ArrowRight) {
        menu.0.select_next();
        blip = true;
    }
    if keys.just_pressed(KeyCode::ArrowUp) {
        menu.0.move_up();
        blip = true;
    }
    if keys.just_pressed(KeyCode::ArrowDown) {
        menu.0.move_down();
        blip = true;
    }
    if blip {
        audio_sys::play_menu_blip(&mut commands, &sounds);
    }
}

/// Menu mouse handling (port of the menu branch of love.mousepressed).
#[allow(clippy::too_many_arguments)]
pub fn menu_mouse(
    buttons: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    mut commands: Commands,
    mut menu: ResMut<Menu>,
    mut tracks: ResMut<Tracks>,
    sounds: Res<Sounds>,
    mut rng: ResMut<SimRng>,
    mut start_events: EventWriter<StartRace>,
    mut return_to: ResMut<ControlsReturnTo>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    if !buttons.just_pressed(MouseButton::Left) {
        return;
    }
    let Ok(window) = windows.single() else { return };
    let Some((x, y)) = cursor_sim_pos(window) else {
        return;
    };

    match menu.0.handle_click(x, y, SCREEN_W as f64, SCREEN_H as f64) {
        Some(MenuAction::Start) => {
            audio_sys::play_menu_select(&mut commands, &sounds);
            if let Some(idx) = menu.0.selected_track_index() {
                if let Some(config) = tracks.0.get_by_index(idx) {
                    start_events.write(StartRace(config.clone()));
                }
            }
        }
        Some(MenuAction::Generate) => {
            audio_sys::play_menu_select(&mut commands, &sounds);
            generate_new_track(&mut menu, &mut tracks, &mut rng);
        }
        Some(MenuAction::Controls) => {
            audio_sys::play_menu_select(&mut commands, &sounds);
            return_to.0 = AppState::Menu;
            next_state.set(AppState::Controls);
        }
        None => {}
    }
}

/// Generate a new random track, persist it, and select it.
fn generate_new_track(menu: &mut Menu, tracks: &mut Tracks, rng: &mut SimRng) {
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(1)
        + (rng.0.next_f64() * 10000.0) as i64;
    let config = trackgen::generate(seed);
    tracks.0.add(config);
    let _ = persistence::save_tracks(
        &tracks.0.list,
        std::path::Path::new(persistence::TRACKS_FILE),
    );
    menu.0 = MenuState::new(tracks.0.count());
    menu.0.selected_track = tracks.0.count() - 1; // select the new track
}
