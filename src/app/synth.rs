//! Procedural 8-bit sound synthesis (port of audio.lua's generators).
//! Each generator returns 16-bit mono PCM samples at 44.1 kHz which are
//! wrapped into an in-memory WAV so Bevy/rodio can decode them.

use bevy::audio::AudioSource;
use racing_sim::rng::GameRng;

pub const SAMPLE_RATE: u32 = 44100;

/// Wrap f64 samples in [-1, 1] into a 16-bit PCM WAV byte stream.
fn to_wav(samples: &[f64]) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let mut bytes = Vec::with_capacity(44 + data_len as usize);
    // RIFF header
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&(36 + data_len).to_le_bytes());
    bytes.extend_from_slice(b"WAVE");
    // fmt chunk (PCM, mono, 16 bit)
    bytes.extend_from_slice(b"fmt ");
    bytes.extend_from_slice(&16u32.to_le_bytes());
    bytes.extend_from_slice(&1u16.to_le_bytes()); // PCM
    bytes.extend_from_slice(&1u16.to_le_bytes()); // mono
    bytes.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    bytes.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes()); // byte rate
    bytes.extend_from_slice(&2u16.to_le_bytes()); // block align
    bytes.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
                                                   // data chunk
    bytes.extend_from_slice(b"data");
    bytes.extend_from_slice(&data_len.to_le_bytes());
    for &s in samples {
        let v = (s.clamp(-1.0, 1.0) * i16::MAX as f64) as i16;
        bytes.extend_from_slice(&v.to_le_bytes());
    }
    bytes
}

pub fn wav_source(samples: &[f64]) -> AudioSource {
    AudioSource {
        bytes: to_wav(samples).into(),
    }
}

const PI: f64 = std::f64::consts::PI;
const SR: f64 = SAMPLE_RATE as f64;

fn square_wave(frequency: f64, duration: f64, duty_cycle: f64) -> Vec<f64> {
    let samples = (duration * SR) as usize;
    let period = SR / frequency;
    let attack_end = samples as f64 * 0.05;
    let release_start = samples as f64 * 0.7;
    (0..samples)
        .map(|i| {
            let t = (i as f64 % period) / period;
            let val = if t < duty_cycle { 0.3 } else { -0.3 };
            let i = i as f64;
            let env = if i < attack_end {
                i / attack_end
            } else if i > release_start {
                1.0 - (i - release_start) / (samples as f64 - release_start)
            } else {
                1.0
            };
            val * env
        })
        .collect()
}

pub fn engine_loop(rng: &mut GameRng) -> Vec<f64> {
    let samples = (0.5 * SR) as usize;
    let base_freq = 80.0;
    (0..samples)
        .map(|i| {
            let t = i as f64 / SR;
            let mut val = (2.0 * PI * base_freq * t).sin() * 0.15;
            val += (2.0 * PI * base_freq * 2.0 * t).sin() * 0.10;
            val += (2.0 * PI * base_freq * 3.0 * t).sin() * 0.05;
            val += (rng.next_f64() * 2.0 - 1.0) * 0.03;
            let m = 0.8 + 0.2 * (2.0 * PI * 15.0 * t).sin();
            val * m
        })
        .collect()
}

pub fn grass_loop(rng: &mut GameRng) -> Vec<f64> {
    let samples = (0.3 * SR) as usize;
    let mut out = Vec::with_capacity(samples);
    let mut prev = 0.0;
    for _ in 0..samples {
        let mut val = (rng.next_f64() * 2.0 - 1.0) * 0.15;
        val = prev * 0.7 + val * 0.3;
        prev = val;
        out.push(val);
    }
    out
}

pub fn rusty_brake_loop(rng: &mut GameRng) -> Vec<f64> {
    let samples = (0.3 * SR) as usize;
    let base_freq = 2800.0;
    (0..samples)
        .map(|i| {
            let t = i as f64 / SR;
            let pitch_wobble = 1.0 + 0.02 * (2.0 * PI * 8.0 * t).sin();
            let squeal1 = (2.0 * PI * base_freq * pitch_wobble * t).sin();
            let squeal2 = (2.0 * PI * base_freq * 1.502 * pitch_wobble * t).sin();
            let squeal3 = (2.0 * PI * base_freq * 2.03 * pitch_wobble * t).sin();
            let mut val = squeal1 * 0.25 + squeal2 * 0.15 + squeal3 * 0.1;
            let mut pulse = 0.5 + 0.5 * (2.0 * PI * 15.0 * t).sin();
            pulse *= pulse;
            val *= 0.3 + 0.7 * pulse;
            if (2.0 * PI * 47.0 * t).sin() > 0.7 {
                val *= 0.3;
            }
            val += (rng.next_f64() * 2.0 - 1.0) * 0.02;
            val.clamp(-0.4, 0.4)
        })
        .collect()
}

pub fn crash_impact(rng: &mut GameRng) -> Vec<f64> {
    let samples = (0.4 * SR) as usize;
    (0..samples)
        .map(|i| {
            let t = i as f64 / SR;
            let thud = (2.0 * PI * 55.0 * t).sin() * 0.45 * (-t * 18.0).exp();
            let clang = (2.0 * PI * 310.0 * t).sin() * 0.20 * (-t * 22.0).exp();
            let env = (-t * 14.0).exp();
            let noise = (rng.next_f64() * 2.0 - 1.0) * 0.55 * env;
            (thud + clang + noise).clamp(-0.75, 0.75)
        })
        .collect()
}

pub fn tire_blowout(rng: &mut GameRng) -> Vec<f64> {
    let samples = (0.5 * SR) as usize;
    (0..samples)
        .map(|i| {
            let t = i as f64 / SR;
            let pop = (rng.next_f64() * 2.0 - 1.0) * (-t * 60.0).exp() * 0.8;
            let hiss = (rng.next_f64() * 2.0 - 1.0) * 0.2 * (-t * 6.0).exp();
            (pop + hiss).clamp(-0.8, 0.8)
        })
        .collect()
}

pub fn flat_tire_loop(rng: &mut GameRng) -> Vec<f64> {
    let duration = 0.6;
    let samples = (duration * SR) as usize;
    (0..samples)
        .map(|i| {
            let t = i as f64 / SR;
            let phase = t / duration;
            let thump_env = (-phase * 18.0).exp();
            let thump = ((2.0 * PI * 38.0 * t).sin() + (rng.next_f64() * 2.0 - 1.0) * 0.25)
                * thump_env
                * 0.55;
            let rumble = (rng.next_f64() * 2.0 - 1.0) * 0.03;
            (thump + rumble).clamp(-0.5, 0.5)
        })
        .collect()
}

pub fn countdown_beep(is_go: bool) -> Vec<f64> {
    let freq = if is_go { 880.0 } else { 440.0 };
    let duration = if is_go { 0.3 } else { 0.15 };
    square_wave(freq, duration, 0.25)
}

pub fn lap_jingle() -> Vec<f64> {
    let note_length = 0.08;
    let notes = [523.0, 659.0, 784.0, 1047.0];
    jingle(&notes, note_length, |wave_t, note_t| {
        let val = if wave_t < 0.5 { 0.25 } else { -0.25 };
        let env = if note_t > 0.7 {
            1.0 - (note_t - 0.7) / 0.3
        } else {
            1.0
        };
        val * env
    })
}

pub fn win_fanfare() -> Vec<f64> {
    let note_length = 0.12;
    let notes = [523.0, 659.0, 784.0, 1047.0, 1319.0, 1568.0, 2093.0];
    jingle(&notes, note_length, |wave_t, note_t| {
        let val = (4.0 * (wave_t - 0.5).abs() - 1.0) * 0.3;
        let env = if note_t < 0.1 {
            note_t / 0.1
        } else if note_t > 0.6 {
            1.0 - (note_t - 0.6) / 0.4
        } else {
            1.0
        };
        val * env
    })
}

fn jingle(notes: &[f64], note_length: f64, wave: impl Fn(f64, f64) -> f64) -> Vec<f64> {
    let note_samples = (note_length * SR) as usize;
    let total = notes.len() * note_samples;
    (0..total)
        .map(|i| {
            let note_idx = (i / note_samples).min(notes.len() - 1);
            let freq = notes[note_idx];
            let note_t = (i % note_samples) as f64 / note_samples as f64;
            let period = SR / freq;
            let wave_t = (i as f64 % period) / period;
            wave(wave_t, note_t)
        })
        .collect()
}

pub fn menu_blip() -> Vec<f64> {
    square_wave(660.0, 0.05, 0.25)
}

pub fn menu_select() -> Vec<f64> {
    let duration = 0.1;
    let samples = (duration * SR) as usize;
    (0..samples)
        .map(|i| {
            let t = i as f64 / samples as f64;
            let freq = 440.0 + 440.0 * t;
            let period = SR / freq;
            let wave_t = (i as f64 % period) / period;
            let val = if wave_t < 0.5 { 0.25 } else { -0.25 };
            let env = if t > 0.7 { 1.0 - (t - 0.7) / 0.3 } else { 1.0 };
            val * env
        })
        .collect()
}

/// 8-bar chiptune loop: square-wave melody, triangle bass, kick/snare/hat.
pub fn background_music(rng: &mut GameRng) -> Vec<f64> {
    let bpm = 140.0;
    let beat_length = 60.0 / bpm;
    let bar_length = beat_length * 4.0;
    let total_bars = 8.0;
    let duration = total_bars * bar_length;
    let samples = (duration * SR) as usize;

    let note_freq = |name: &str| -> f64 {
        match name {
            "A3" => 220.0,
            "C4" => 262.0,
            "D4" => 294.0,
            "E4" => 330.0,
            "G4" => 392.0,
            "A4" => 440.0,
            "C5" => 523.0,
            "D5" => 587.0,
            "E5" => 659.0,
            "G5" => 784.0,
            "A5" => 880.0,
            _ => 0.0,
        }
    };

    const X: &str = ""; // rest
    let melody: [&str; 64] = [
        "A4", X, "C5", X, "D5", X, "E5", X, "D5", X, "C5", X, "A4", X, "G4", X, "A4", X, "C5", X,
        "E5", X, "G5", X, "E5", X, "D5", X, "C5", X, X, X, "A4", X, "A4", "C5", "D5", X, "E5", X,
        "G5", X, "E5", X, "D5", X, "C5", X, "A4", X, "C5", X, "D5", X, "E5", "D5", "C5", X, "A4",
        X, X, X, X, X,
    ];
    let bass: [&str; 32] = [
        "A3", "A3", "C4", "C4", "A3", "A3", "G4", "G4", "A3", "A3", "C4", "C4", "D4", "D4", "E4",
        "E4", "A3", "A3", "C4", "C4", "A3", "A3", "G4", "G4", "A3", "A3", "D4", "D4", "C4", "C4",
        "A3", "A3",
    ];

    let eighth_note_samples = ((beat_length / 2.0) * SR) as usize;
    let quarter_note_samples = (beat_length * SR) as usize;

    let mut out = Vec::with_capacity(samples);
    for i in 0..samples {
        let t = i as f64 / SR;
        let eighth_note = (i / eighth_note_samples) % 64;
        let quarter_note = (i / quarter_note_samples) % 32;
        let beat_in_bar = (i / quarter_note_samples) % 4;
        let eighth_pos = (i % eighth_note_samples) as f64 / eighth_note_samples as f64;
        let quarter_pos = (i % quarter_note_samples) as f64 / quarter_note_samples as f64;
        let mut val = 0.0;

        // Melody (square wave)
        let m_freq = note_freq(melody[eighth_note]);
        if m_freq > 0.0 {
            let period = SR / m_freq;
            let wave_t = (i as f64 % period) / period;
            let sq = if wave_t < 0.5 { 1.0 } else { -1.0 };
            let env = if eighth_pos < 0.05 {
                eighth_pos / 0.05
            } else if eighth_pos > 0.7 {
                1.0 - (eighth_pos - 0.7) / 0.3
            } else {
                1.0
            };
            val += sq * 0.12 * env;
        }

        // Bass (triangle wave)
        let b_freq = note_freq(bass[quarter_note]);
        if b_freq > 0.0 {
            let period = SR / b_freq;
            let wave_t = (i as f64 % period) / period;
            let tri = 4.0 * (wave_t - 0.5).abs() - 1.0;
            let env = if quarter_pos < 0.02 {
                quarter_pos / 0.02
            } else if quarter_pos > 0.6 {
                1.0 - (quarter_pos - 0.6) / 0.4
            } else {
                1.0
            };
            val += tri * 0.15 * env;
        }

        // Drums
        let beat_pos = (i % quarter_note_samples) as f64 / quarter_note_samples as f64;
        if (beat_in_bar == 0 || beat_in_bar == 2) && beat_pos < 0.15 {
            let kick_env = 1.0 - beat_pos / 0.15;
            let kick_freq = 60.0 * (1.0 + (1.0 - beat_pos / 0.15) * 2.0);
            val += (2.0 * PI * kick_freq * t).sin() * kick_env * 0.2;
        }
        if (beat_in_bar == 1 || beat_in_bar == 3) && beat_pos < 0.1 {
            val += (rng.next_f64() * 2.0 - 1.0) * (1.0 - beat_pos / 0.1) * 0.12;
        }
        if eighth_pos < 0.05 {
            val += (rng.next_f64() * 2.0 - 1.0) * (1.0 - eighth_pos / 0.05) * 0.04;
        }

        out.push(val.clamp(-0.5, 0.5));
    }
    out
}
