//! Track list and configuration (port of tracks.lua).
//! Default tracks are procedurally generated from fixed seeds.

use crate::track::TrackConfig;
use crate::trackgen;

pub const DEFAULT_SEEDS: [i64; 3] = [42, 137, 314];

#[derive(Debug, Clone, Default)]
pub struct TrackList {
    pub list: Vec<TrackConfig>,
}

impl TrackList {
    /// The three default tracks generated from fixed seeds.
    pub fn with_defaults() -> Self {
        Self {
            list: DEFAULT_SEEDS
                .iter()
                .map(|&s| trackgen::generate(s))
                .collect(),
        }
    }

    pub fn get_by_id(&self, id: &str) -> Option<&TrackConfig> {
        self.list.iter().find(|t| t.id == id)
    }

    /// 0-based index (the Lua original was 1-based).
    pub fn get_by_index(&self, index: usize) -> Option<&TrackConfig> {
        self.list.get(index)
    }

    pub fn count(&self) -> usize {
        self.list.len()
    }

    pub fn add(&mut self, config: TrackConfig) {
        self.list.push(config);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn has_three_default_tracks() {
        let tracks = TrackList::with_defaults();
        assert_eq!(tracks.count(), 3);
    }

    #[test]
    fn get_by_id_finds_default_tracks() {
        let tracks = TrackList::with_defaults();
        assert!(tracks.get_by_id("gen_42").is_some());
        assert!(tracks.get_by_id("nonexistent").is_none());
    }

    #[test]
    fn get_by_index_within_bounds() {
        let tracks = TrackList::with_defaults();
        assert!(tracks.get_by_index(0).is_some());
        assert!(tracks.get_by_index(2).is_some());
        assert!(tracks.get_by_index(3).is_none());
    }

    #[test]
    fn add_appends_to_list() {
        let mut tracks = TrackList::with_defaults();
        let config = trackgen::generate(9999);
        tracks.add(config);
        assert_eq!(tracks.count(), 4);
    }

    #[test]
    fn default_tracks_have_distinct_ids() {
        let tracks = TrackList::with_defaults();
        let ids: Vec<&str> = tracks.list.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(ids.len(), 3);
        assert!(ids.windows(2).all(|w| w[0] != w[1]));
    }
}
