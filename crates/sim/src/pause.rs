//! Pause menu logic (port of pause.lua). Indices are 0-based.

pub const OPTIONS: [&str; 3] = ["Resume", "Controls", "Main Menu"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PauseAction {
    Resume,
    Controls,
    MainMenu,
}

#[derive(Debug, Clone, Default)]
pub struct PauseState {
    pub selected_index: usize,
}

impl PauseState {
    pub fn new() -> Self {
        Self { selected_index: 0 }
    }

    pub fn move_up(&mut self) {
        self.selected_index = (self.selected_index + OPTIONS.len() - 1) % OPTIONS.len();
    }

    pub fn move_down(&mut self) {
        self.selected_index = (self.selected_index + 1) % OPTIONS.len();
    }

    pub fn selected(&self) -> &'static str {
        OPTIONS[self.selected_index]
    }

    pub fn selected_action(&self) -> PauseAction {
        match self.selected_index {
            0 => PauseAction::Resume,
            1 => PauseAction::Controls,
            _ => PauseAction::MainMenu,
        }
    }

    /// Mouse click hit-test (mirrors pause.handleClick's 200x180 menu layout).
    pub fn handle_click(
        &mut self,
        x: f64,
        y: f64,
        screen_width: f64,
        screen_height: f64,
    ) -> Option<PauseAction> {
        let menu_w = 200.0;
        let menu_h = 180.0;
        let menu_x = (screen_width - menu_w) / 2.0;
        let menu_y = (screen_height - menu_h) / 2.0;

        let btn_h = 35.0;
        let btn_padding = 10.0;
        let start_y = menu_y + 50.0;

        for (i, _) in OPTIONS.iter().enumerate() {
            let btn_y = start_y + i as f64 * (btn_h + btn_padding);
            if x >= menu_x + 20.0 && x <= menu_x + menu_w - 20.0 && y >= btn_y && y <= btn_y + btn_h
            {
                self.selected_index = i;
                return Some(match i {
                    0 => PauseAction::Resume,
                    1 => PauseAction::Controls,
                    _ => PauseAction::MainMenu,
                });
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_at_first_option() {
        let pause = PauseState::new();
        assert_eq!(pause.selected(), "Resume");
    }

    #[test]
    fn move_up_wraps_to_last() {
        let mut pause = PauseState::new();
        pause.move_up();
        assert_eq!(pause.selected(), "Main Menu");
    }

    #[test]
    fn move_down_cycles_through_options() {
        let mut pause = PauseState::new();
        pause.move_down();
        assert_eq!(pause.selected(), "Controls");
        pause.move_down();
        assert_eq!(pause.selected(), "Main Menu");
        pause.move_down();
        assert_eq!(pause.selected(), "Resume");
    }

    #[test]
    fn click_on_first_button_resumes() {
        let mut pause = PauseState::new();
        // Menu centered on 800x600: menu_y = 210, first button at y 260..295
        let action = pause.handle_click(400.0, 270.0, 800.0, 600.0);
        assert_eq!(action, Some(PauseAction::Resume));
    }

    #[test]
    fn click_outside_returns_none() {
        let mut pause = PauseState::new();
        assert_eq!(pause.handle_click(10.0, 10.0, 800.0, 600.0), None);
    }
}
