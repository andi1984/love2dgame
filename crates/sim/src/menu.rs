//! Main menu with track selection (port of menu.lua).
//! Pure selection logic; rendering and input mapping live in the app layer.
//! Indices are 0-based (the Lua original was 1-based).

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuButton {
    Track,
    Controls,
}

/// Result of a mouse click on the menu.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuAction {
    Start,
    Controls,
    Generate,
}

#[derive(Debug, Clone)]
pub struct MenuState {
    /// Selected card, 0-based. Index == track_count selects the "+" card.
    pub selected_track: usize,
    pub selected_button: MenuButton,
    pub track_count: usize,
}

// Layout constants shared with the app layer for hit-testing and rendering.
pub const CARD_START_Y: f64 = 160.0;
pub const CARD_W: f64 = 160.0;
pub const CARD_H: f64 = 120.0;
pub const CARD_PADDING: f64 = 20.0;
pub const CARD_COLS: usize = 3;
pub const CONTROLS_BTN_W: f64 = 200.0;
pub const CONTROLS_BTN_H: f64 = 40.0;

impl MenuState {
    pub fn new(track_count: usize) -> Self {
        Self {
            selected_track: 0,
            selected_button: MenuButton::Track,
            track_count,
        }
    }

    /// Display count includes the "+" generate card.
    pub fn display_count(&self) -> usize {
        self.track_count + 1
    }

    pub fn select_next(&mut self) {
        if self.selected_button == MenuButton::Track {
            self.selected_track = (self.selected_track + 1) % self.display_count();
        }
    }

    pub fn select_prev(&mut self) {
        if self.selected_button == MenuButton::Track {
            let n = self.display_count();
            self.selected_track = (self.selected_track + n - 1) % n;
        }
    }

    pub fn move_up(&mut self) {
        if self.selected_button == MenuButton::Controls {
            self.selected_button = MenuButton::Track;
        }
    }

    pub fn move_down(&mut self) {
        if self.selected_button == MenuButton::Track {
            self.selected_button = MenuButton::Controls;
        }
    }

    /// True when the "+" generate card is selected.
    pub fn is_add_selected(&self) -> bool {
        self.selected_button == MenuButton::Track && self.selected_track >= self.track_count
    }

    /// Index of the selected track, or None when the "+" card is selected.
    pub fn selected_track_index(&self) -> Option<usize> {
        if self.is_add_selected() {
            None
        } else {
            Some(self.selected_track)
        }
    }

    /// Card rectangle (x, y, w, h) for a 0-based card index, on an 800x600 screen.
    pub fn card_rect(&self, i: usize, screen_width: f64) -> (f64, f64, f64, f64) {
        let total_w = CARD_COLS as f64 * CARD_W + (CARD_COLS - 1) as f64 * CARD_PADDING;
        let start_x = (screen_width - total_w) / 2.0;
        let col = i % CARD_COLS;
        let row = i / CARD_COLS;
        (
            start_x + col as f64 * (CARD_W + CARD_PADDING),
            CARD_START_Y + row as f64 * (CARD_H + CARD_PADDING),
            CARD_W,
            CARD_H,
        )
    }

    /// Mouse click hit-test (mirrors menu.handleClick).
    pub fn handle_click(
        &mut self,
        x: f64,
        y: f64,
        screen_width: f64,
        screen_height: f64,
    ) -> Option<MenuAction> {
        for i in 0..self.display_count() {
            let (cx, cy, cw, ch) = self.card_rect(i, screen_width);
            if x >= cx && x <= cx + cw && y >= cy && y <= cy + ch {
                self.selected_track = i;
                self.selected_button = MenuButton::Track;
                return if i >= self.track_count {
                    Some(MenuAction::Generate)
                } else {
                    Some(MenuAction::Start)
                };
            }
        }

        // Controls button
        let btn_x = (screen_width - CONTROLS_BTN_W) / 2.0;
        let btn_y = screen_height - 80.0;
        if x >= btn_x && x <= btn_x + CONTROLS_BTN_W && y >= btn_y && y <= btn_y + CONTROLS_BTN_H {
            return Some(MenuAction::Controls);
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initializes_with_first_track_selected() {
        let menu = MenuState::new(3);
        assert_eq!(menu.selected_track, 0);
        assert_eq!(menu.selected_button, MenuButton::Track);
        assert_eq!(menu.display_count(), 4);
    }

    #[test]
    fn select_next_wraps_around_including_plus_card() {
        let mut menu = MenuState::new(3);
        for _ in 0..4 {
            menu.select_next();
        }
        assert_eq!(menu.selected_track, 0);
    }

    #[test]
    fn select_prev_wraps_to_plus_card() {
        let mut menu = MenuState::new(3);
        menu.select_prev();
        assert_eq!(menu.selected_track, 3);
        assert!(menu.is_add_selected());
    }

    #[test]
    fn selected_track_index_is_none_on_plus_card() {
        let mut menu = MenuState::new(3);
        menu.selected_track = 3;
        assert!(menu.selected_track_index().is_none());
        menu.selected_track = 1;
        assert_eq!(menu.selected_track_index(), Some(1));
    }

    #[test]
    fn move_down_and_up_toggle_controls_focus() {
        let mut menu = MenuState::new(3);
        menu.move_down();
        assert_eq!(menu.selected_button, MenuButton::Controls);
        menu.move_up();
        assert_eq!(menu.selected_button, MenuButton::Track);
    }

    #[test]
    fn click_on_first_card_starts_race() {
        let mut menu = MenuState::new(3);
        let (cx, cy, _, _) = menu.card_rect(0, 800.0);
        let action = menu.handle_click(cx + 5.0, cy + 5.0, 800.0, 600.0);
        assert_eq!(action, Some(MenuAction::Start));
        assert_eq!(menu.selected_track, 0);
    }

    #[test]
    fn click_on_plus_card_generates() {
        let mut menu = MenuState::new(3);
        let (cx, cy, _, _) = menu.card_rect(3, 800.0);
        let action = menu.handle_click(cx + 5.0, cy + 5.0, 800.0, 600.0);
        assert_eq!(action, Some(MenuAction::Generate));
    }

    #[test]
    fn click_on_controls_button() {
        let mut menu = MenuState::new(3);
        let action = menu.handle_click(400.0, 530.0, 800.0, 600.0);
        assert_eq!(action, Some(MenuAction::Controls));
    }

    #[test]
    fn click_on_empty_space_does_nothing() {
        let mut menu = MenuState::new(3);
        assert_eq!(menu.handle_click(5.0, 5.0, 800.0, 600.0), None);
    }
}
