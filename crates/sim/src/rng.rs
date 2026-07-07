//! Random number generators.
//!
//! `Lcg` is an exact port of the Lua MINSTD generator used by trackgen/track so
//! that a given seed produces the same track as the Love2D original.
//! `GameRng` replaces Lua's global `math.random` for gameplay noise
//! (bumpiness, sensor noise, mutation, particles).

/// Multiplicative congruential generator (MINSTD), identical to the Lua version.
pub struct Lcg {
    s: i64,
}

impl Lcg {
    pub fn new(seed: i64) -> Self {
        let mut s = seed % 2147483647;
        if s <= 0 {
            s += 2147483646;
        }
        Self { s }
    }

    /// Uniform float in [0, 1).
    #[allow(clippy::should_implement_trait)]
    pub fn next(&mut self) -> f64 {
        self.s = (self.s * 48271) % 2147483647;
        self.s as f64 / 2147483647.0
    }

    /// Uniform float in [lo, hi].
    pub fn range(&mut self, lo: f64, hi: f64) -> f64 {
        lo + self.next() * (hi - lo)
    }

    /// Integer in [lo, hi] (mirrors the Lua `floor(range(lo, hi + 0.999))`).
    pub fn int(&mut self, lo: i64, hi: i64) -> i64 {
        self.range(lo as f64, hi as f64 + 0.999).floor() as i64
    }

    /// Pick a random element from a slice.
    pub fn pick<'a, T>(&mut self, arr: &'a [T]) -> &'a T {
        let idx = self.int(1, arr.len() as i64) as usize - 1;
        &arr[idx.min(arr.len() - 1)]
    }
}

/// Fast gameplay RNG (xorshift64*). Not seed-compatible with Lua's
/// `math.random`, which is fine: gameplay noise was never deterministic.
pub struct GameRng {
    s: u64,
}

impl Default for GameRng {
    fn default() -> Self {
        Self::new(0x9E3779B97F4A7C15)
    }
}

impl GameRng {
    pub fn new(seed: u64) -> Self {
        Self {
            s: if seed == 0 { 0xDEADBEEF } else { seed },
        }
    }

    fn next_u64(&mut self) -> u64 {
        let mut x = self.s;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.s = x;
        x.wrapping_mul(0x2545F4914F6CDD1D)
    }

    /// Uniform float in [0, 1).
    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }

    /// Uniform float in [lo, hi).
    pub fn range(&mut self, lo: f64, hi: f64) -> f64 {
        lo + self.next_f64() * (hi - lo)
    }

    /// Integer in [1, n] (mirrors Lua `math.random(n)`).
    pub fn int1(&mut self, n: u64) -> u64 {
        (self.next_f64() * n as f64) as u64 + 1
    }

    /// Standard normal via Box-Muller, as in the Lua code.
    pub fn gaussian(&mut self) -> f64 {
        let u1 = self.next_f64().max(1e-10);
        let u2 = self.next_f64();
        (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lcg_is_deterministic() {
        let mut a = Lcg::new(42);
        let mut b = Lcg::new(42);
        for _ in 0..100 {
            assert_eq!(a.next(), b.next());
        }
    }

    #[test]
    fn lcg_range_bounds() {
        let mut rng = Lcg::new(7);
        for _ in 0..1000 {
            let v = rng.range(5.0, 10.0);
            assert!((5.0..=10.0).contains(&v));
            let i = rng.int(1, 3);
            assert!((1..=3).contains(&i));
        }
    }

    #[test]
    fn game_rng_uniform_bounds() {
        let mut rng = GameRng::new(1234);
        for _ in 0..1000 {
            let v = rng.next_f64();
            assert!((0.0..1.0).contains(&v));
        }
    }

    #[test]
    fn gaussian_is_roughly_centered() {
        let mut rng = GameRng::new(99);
        let mean: f64 = (0..10_000).map(|_| rng.gaussian()).sum::<f64>() / 10_000.0;
        assert!(mean.abs() < 0.1, "mean = {mean}");
    }
}
