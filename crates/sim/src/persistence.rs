//! Save/load NPC brains and custom tracks (port of persistence.lua).
//! The Lua original wrote Lua source files; this port uses JSON
//! (`npc_brains.json`, `custom_tracks.json`) in the working directory.

use crate::nnet::NetData;
use crate::track::TrackConfig;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

pub const BRAINS_FILE: &str = "npc_brains.json";
pub const TRACKS_FILE: &str = "custom_tracks.json";

/// Number of built-in tracks; only tracks beyond these are persisted.
pub const NUM_DEFAULT_TRACKS: usize = 3;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NpcSave {
    #[serde(rename = "bestBrain")]
    pub best_brain: NetData,
    #[serde(rename = "bestFitness")]
    pub best_fitness: f64,
    pub generation: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SaveData {
    pub version: u32,
    pub npcs: HashMap<String, NpcSave>,
}

impl Default for SaveData {
    fn default() -> Self {
        Self {
            version: 1,
            npcs: HashMap::new(),
        }
    }
}

pub fn save(data: &SaveData, path: &Path) -> std::io::Result<()> {
    let json = serde_json::to_string_pretty(data).expect("SaveData serializes");
    std::fs::write(path, json)
}

pub fn load(path: &Path) -> Option<SaveData> {
    let text = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

/// Save user-generated tracks (index >= NUM_DEFAULT_TRACKS with the
/// `generated` flag, mirroring the Lua behavior).
pub fn save_tracks(track_list: &[TrackConfig], path: &Path) -> std::io::Result<()> {
    let to_save: Vec<&TrackConfig> = track_list
        .iter()
        .skip(NUM_DEFAULT_TRACKS)
        .filter(|t| t.generated)
        .collect();
    if to_save.is_empty() {
        return Ok(());
    }
    let json = serde_json::to_string_pretty(&to_save).expect("TrackConfig serializes");
    std::fs::write(path, json)
}

pub fn load_tracks(path: &Path) -> Vec<TrackConfig> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str(&text).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nnet;
    use crate::rng::GameRng;
    use crate::trackgen;

    fn temp_path(name: &str) -> std::path::PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!("racing_sim_test_{}_{name}", std::process::id()));
        p
    }

    #[test]
    fn save_load_roundtrip_preserves_brains() {
        let mut rng = GameRng::new(5);
        let net = nnet::new(&[13, 16, 4], None, &mut rng);
        let mut data = SaveData::default();
        data.npcs.insert(
            "Test NPC".into(),
            NpcSave {
                best_brain: nnet::serialize(&net),
                best_fitness: 123.5,
                generation: 7,
            },
        );

        let path = temp_path("brains.json");
        save(&data, &path).unwrap();
        let loaded = load(&path).expect("load should succeed");
        std::fs::remove_file(&path).ok();

        assert_eq!(loaded.version, 1);
        let npc = &loaded.npcs["Test NPC"];
        assert_eq!(npc.best_fitness, 123.5);
        assert_eq!(npc.generation, 7);
        assert_eq!(npc.best_brain.layer_sizes, vec![13, 16, 4]);

        // Restored brain produces identical outputs
        let restored = nnet::deserialize(&npc.best_brain);
        let inputs = [0.3; 13];
        let a = nnet::forward(&net, &inputs);
        let b = nnet::forward(&restored, &inputs);
        for i in 0..4 {
            assert!((a[i] - b[i]).abs() < 1e-12);
        }
    }

    #[test]
    fn load_missing_file_returns_none() {
        assert!(load(Path::new("/nonexistent/npc_brains.json")).is_none());
    }

    #[test]
    fn save_tracks_only_persists_generated_extras() {
        let defaults: Vec<TrackConfig> = [42, 137, 314]
            .iter()
            .map(|&s| trackgen::generate(s))
            .collect();
        let mut list = defaults.clone();
        list.push(trackgen::generate(5555));

        let path = temp_path("tracks.json");
        save_tracks(&list, &path).unwrap();
        let loaded = load_tracks(&path);
        std::fs::remove_file(&path).ok();

        assert_eq!(loaded.len(), 1);
        // Generation may retry with seed+1 on self-intersection, so only the prefix is stable
        assert!(loaded[0].id.starts_with("gen_555"));
        assert!(loaded[0].generated);
    }

    #[test]
    fn load_tracks_missing_file_returns_empty() {
        assert!(load_tracks(Path::new("/nonexistent/custom_tracks.json")).is_empty());
    }
}
