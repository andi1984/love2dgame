//! Simple feedforward neural network (port of nnet.lua).
//! Fixed activation scheme: tanh hidden layers, sigmoid output layer.

use crate::rng::GameRng;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct Layer {
    /// weights[output][input]
    pub weights: Vec<Vec<f64>>,
    pub biases: Vec<f64>,
    pub input_size: usize,
    pub output_size: usize,
}

#[derive(Debug, Clone)]
pub struct Net {
    pub layers: Vec<Layer>,
}

/// Flat serialized form, matches the Lua `{ layerSizes, weights }` layout so
/// the on-disk format stays conceptually identical.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetData {
    #[serde(rename = "layerSizes")]
    pub layer_sizes: Vec<usize>,
    pub weights: Vec<f64>,
}

/// Initial output-layer biases for personality differentiation.
#[derive(Debug, Clone, Copy, Default)]
pub struct InitialBias {
    pub throttle: f64,
    pub brake: f64,
    pub steer_sensitivity: f64,
}

fn empty_layer(input_size: usize, output_size: usize) -> Layer {
    Layer {
        weights: vec![vec![0.0; input_size]; output_size],
        biases: vec![0.0; output_size],
        input_size,
        output_size,
    }
}

/// Create a new network with Xavier-initialized weights.
pub fn new(layer_sizes: &[usize], initial_bias: Option<InitialBias>, rng: &mut GameRng) -> Net {
    let mut layers = Vec::new();
    for i in 1..layer_sizes.len() {
        let mut layer = empty_layer(layer_sizes[i - 1], layer_sizes[i]);
        let scale = (2.0 / (layer_sizes[i - 1] + layer_sizes[i]) as f64).sqrt();
        for o in 0..layer.output_size {
            for j in 0..layer.input_size {
                layer.weights[o][j] = (rng.next_f64() * 2.0 - 1.0) * scale;
            }
        }
        layers.push(layer);
    }
    let mut net = Net { layers };

    if let Some(bias) = initial_bias {
        let output = net.layers.last_mut().expect("net has layers");
        output.biases[0] += bias.throttle;
        output.biases[1] += bias.brake;
        output.biases[2] += bias.steer_sensitivity;
        output.biases[3] += bias.steer_sensitivity;
    }

    net
}

/// Forward pass. Hidden layers use tanh, the output layer sigmoid.
pub fn forward(net: &Net, inputs: &[f64]) -> Vec<f64> {
    let mut current: Vec<f64> = inputs.to_vec();
    let last = net.layers.len() - 1;
    for (li, layer) in net.layers.iter().enumerate() {
        let outputs: Vec<f64> = (0..layer.output_size)
            .map(|o| {
                let mut sum = layer.biases[o];
                for j in 0..layer.input_size {
                    sum += layer.weights[o][j] * current.get(j).copied().unwrap_or(0.0);
                }
                if li == last {
                    1.0 / (1.0 + (-sum).exp())
                } else {
                    sum.tanh()
                }
            })
            .collect();
        current = outputs;
    }
    current
}

/// Serialize to the flat data form.
pub fn serialize(net: &Net) -> NetData {
    let mut layer_sizes = vec![net.layers[0].input_size];
    for layer in &net.layers {
        layer_sizes.push(layer.output_size);
    }
    let mut weights = Vec::new();
    for layer in &net.layers {
        for o in 0..layer.output_size {
            for j in 0..layer.input_size {
                weights.push(layer.weights[o][j]);
            }
            weights.push(layer.biases[o]);
        }
    }
    NetData {
        layer_sizes,
        weights,
    }
}

/// Rebuild a network from flat data.
pub fn deserialize(data: &NetData) -> Net {
    let mut layers = Vec::new();
    for i in 1..data.layer_sizes.len() {
        layers.push(empty_layer(data.layer_sizes[i - 1], data.layer_sizes[i]));
    }
    let mut idx = 0;
    for layer in &mut layers {
        for o in 0..layer.output_size {
            for j in 0..layer.input_size {
                layer.weights[o][j] = data.weights[idx];
                idx += 1;
            }
            layer.biases[o] = data.weights[idx];
            idx += 1;
        }
    }
    Net { layers }
}

/// Return a mutated copy (Gaussian perturbation of a random weight subset).
pub fn mutate(net: &Net, mutation_rate: f64, mutation_strength: f64, rng: &mut GameRng) -> Net {
    let mut data = serialize(net);
    for w in data.weights.iter_mut() {
        if rng.next_f64() < mutation_rate {
            *w += rng.gaussian() * mutation_strength;
        }
    }
    deserialize(&data)
}

/// Create a seeded network pre-wired for basic track following.
/// Architecture: 13 inputs, N hidden, 4 outputs (throttle, brake, left, right).
pub fn create_seeded(layer_sizes: &[usize], rng: &mut GameRng) -> Net {
    let num_inputs = layer_sizes[0];
    let num_hidden = layer_sizes[1];
    let num_outputs = layer_sizes[2];

    let mut hidden = empty_layer(num_inputs, num_hidden);

    // Passthrough neurons for key sensor inputs (0-based indices; Lua was 1-based)
    hidden.weights[0][0] = 3.0; // angle error to waypoint
    hidden.weights[1][1] = 2.5; // center distance
    hidden.weights[2][2] = 3.0; // speed ratio
    hidden.weights[3][3] = 3.0; // curvature ahead
    hidden.weights[4][4] = 2.5; // near look-ahead

    if num_inputs >= 13 {
        hidden.weights[5][8] = 3.0; // left ray
        hidden.weights[6][9] = 3.0; // front-left ray
        hidden.weights[7][10] = 3.0; // front ray
        hidden.weights[8][11] = 3.0; // front-right ray
        hidden.weights[9][12] = 3.0; // right ray
    }

    // Remaining neurons: small random noise for evolution to explore
    let scale = 0.15;
    for o in 10..num_hidden {
        for j in 0..num_inputs {
            hidden.weights[o][j] = (rng.next_f64() * 2.0 - 1.0) * scale;
        }
    }

    let mut output = empty_layer(num_hidden, num_outputs);

    // Output 0 (throttle): almost always on, reduce at high speed
    output.biases[0] = 2.0;
    output.weights[0][2] = -1.5; // hidden 2 = speed → less throttle when fast
    output.weights[0][7] = 0.5; // hidden 7 = front ray → more throttle when clear

    // Output 1 (brake): normally off, activate for high speed in curves
    output.biases[1] = -2.0;
    output.weights[1][2] = 1.5; // speed → brake when fast
    output.weights[1][3] = 2.0; // curvature → brake in curves

    // Output 2 (left steer): activate when angle error is negative
    output.weights[2][0] = -4.0; // angle error negative → left output high
    output.weights[2][1] = -1.5; // off-center right → steer left
    output.weights[2][4] = -2.0; // near look-ahead → steer left
    if num_inputs >= 13 {
        output.weights[2][9] = -2.0; // right ray close → steer left
        output.weights[2][5] = 1.5; // left ray close → don't steer left
    }

    // Output 3 (right steer): activate when angle error is positive
    output.weights[3][0] = 4.0;
    output.weights[3][1] = 1.5;
    output.weights[3][4] = 2.0;
    if num_inputs >= 13 {
        output.weights[3][5] = -2.0; // left ray close → steer right
        output.weights[3][9] = 1.5; // right ray close → don't steer right
    }

    Net {
        layers: vec![hidden, output],
    }
}

/// Uniform weight crossover of two networks.
pub fn crossover(net1: &Net, net2: &Net, rng: &mut GameRng) -> Net {
    let d1 = serialize(net1);
    let d2 = serialize(net2);
    let weights = d1
        .weights
        .iter()
        .zip(d2.weights.iter())
        .map(|(&a, &b)| if rng.next_f64() < 0.5 { a } else { b })
        .collect();
    deserialize(&NetData {
        layer_sizes: d1.layer_sizes,
        weights,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ARCH: [usize; 3] = [13, 16, 4];

    #[test]
    fn creates_network_with_correct_layer_sizes() {
        let mut rng = GameRng::new(1);
        let net = new(&ARCH, None, &mut rng);
        assert_eq!(net.layers.len(), 2);
        assert_eq!(net.layers[0].input_size, 13);
        assert_eq!(net.layers[0].output_size, 16);
        assert_eq!(net.layers[1].input_size, 16);
        assert_eq!(net.layers[1].output_size, 4);
    }

    #[test]
    fn forward_returns_correct_number_of_outputs() {
        let mut rng = GameRng::new(2);
        let net = new(&ARCH, None, &mut rng);
        let inputs = [
            0.5, -0.3, 0.8, 0.0, 0.1, -0.1, 0.9, 1.0, 0.5, 0.6, 0.7, 0.8, 0.4,
        ];
        assert_eq!(forward(&net, &inputs).len(), 4);
    }

    #[test]
    fn outputs_are_in_unit_range() {
        let mut rng = GameRng::new(42);
        let net = new(&ARCH, None, &mut rng);
        let cases: [[f64; 13]; 3] = [
            [1.0; 13],
            [
                -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            ],
            [0.0; 13],
        ];
        for inputs in &cases {
            for (i, v) in forward(&net, inputs).iter().enumerate() {
                assert!((0.0..=1.0).contains(v), "output {i} = {v} out of [0,1]");
            }
        }
    }

    #[test]
    fn serialize_roundtrip_preserves_outputs() {
        let mut rng = GameRng::new(123);
        let net = new(&ARCH, None, &mut rng);
        let inputs = [
            0.5, -0.3, 0.8, 0.0, 0.1, -0.1, 0.9, 1.0, 0.5, 0.6, 0.7, 0.8, 0.4,
        ];
        let orig = forward(&net, &inputs);
        let restored = deserialize(&serialize(&net));
        let after = forward(&restored, &inputs);
        for i in 0..4 {
            assert!((orig[i] - after[i]).abs() < 1e-4);
        }
    }

    #[test]
    fn json_roundtrip_preserves_outputs() {
        let mut rng = GameRng::new(321);
        let net = new(&ARCH, None, &mut rng);
        let data = serialize(&net);
        let json = serde_json::to_string(&data).unwrap();
        let back: NetData = serde_json::from_str(&json).unwrap();
        let inputs = [0.1; 13];
        let a = forward(&net, &inputs);
        let b = forward(&deserialize(&back), &inputs);
        for i in 0..4 {
            assert!((a[i] - b[i]).abs() < 1e-12);
        }
    }

    #[test]
    fn mutation_changes_some_weights() {
        let mut rng = GameRng::new(99);
        let net = new(&ARCH, None, &mut rng);
        let d1 = serialize(&net);
        let mutated = mutate(&net, 1.0, 0.5, &mut rng);
        let d2 = serialize(&mutated);
        assert!(d1
            .weights
            .iter()
            .zip(d2.weights.iter())
            .any(|(a, b)| a != b));
    }

    #[test]
    fn crossover_combines_two_networks() {
        let mut rng = GameRng::new(55);
        let net1 = new(&ARCH, None, &mut rng);
        let net2 = new(&ARCH, None, &mut rng);
        let child = crossover(&net1, &net2, &mut rng);
        let d1 = serialize(&net1);
        let d2 = serialize(&net2);
        let dc = serialize(&child);
        for i in 0..dc.weights.len() {
            assert!(
                dc.weights[i] == d1.weights[i] || dc.weights[i] == d2.weights[i],
                "weight {i} doesn't match either parent"
            );
        }
    }

    #[test]
    fn applies_initial_bias_to_output_layer() {
        let mut rng = GameRng::new(77);
        let net = new(
            &ARCH,
            Some(InitialBias {
                throttle: 0.5,
                brake: -0.3,
                steer_sensitivity: 0.2,
            }),
            &mut rng,
        );
        let output = net.layers.last().unwrap();
        assert!((output.biases[0] - 0.5).abs() < 1e-3);
        assert!((output.biases[1] + 0.3).abs() < 1e-3);
        assert!((output.biases[2] - 0.2).abs() < 1e-3);
        assert!((output.biases[3] - 0.2).abs() < 1e-3);
    }

    #[test]
    fn seeded_network_has_correct_dimensions() {
        let mut rng = GameRng::new(1);
        let net = create_seeded(&ARCH, &mut rng);
        assert_eq!(net.layers.len(), 2);
        assert_eq!(net.layers[0].input_size, 13);
        assert_eq!(net.layers[0].output_size, 16);
        assert_eq!(net.layers[1].input_size, 16);
        assert_eq!(net.layers[1].output_size, 4);
    }

    #[test]
    fn seeded_brain_steers_right_on_positive_angle_error() {
        let mut rng = GameRng::new(1);
        let net = create_seeded(&ARCH, &mut rng);
        let inputs = [
            0.3, 0.0, 0.3, 0.0, 0.3, 0.3, 0.9, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5,
        ];
        let out = forward(&net, &inputs);
        assert!(
            out[3] > out[2],
            "expected right > left, got right={} left={}",
            out[3],
            out[2]
        );
    }

    #[test]
    fn seeded_brain_steers_left_on_negative_angle_error() {
        let mut rng = GameRng::new(1);
        let net = create_seeded(&ARCH, &mut rng);
        let inputs = [
            -0.3, 0.0, 0.3, 0.0, -0.3, -0.3, 0.9, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5,
        ];
        let out = forward(&net, &inputs);
        assert!(out[2] > out[3]);
    }

    #[test]
    fn seeded_brain_throttles_by_default() {
        let mut rng = GameRng::new(1);
        let net = create_seeded(&ARCH, &mut rng);
        let inputs = [
            0.0, 0.0, 0.2, 0.0, 0.0, 0.0, 0.9, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5,
        ];
        let out = forward(&net, &inputs);
        assert!(out[0] > 0.5, "expected throttle > 0.5, got {}", out[0]);
    }
}
