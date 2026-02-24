-- Simple feedforward neural network (pure Lua, no dependencies)

local nnet = {}

-- Create a new neural network with given layer sizes
-- e.g. nnet.new({8, 12, 4}) = 8 inputs, 12 hidden, 4 outputs
function nnet.new(layerSizes, initialBias)
    local net = { layers = {} }
    for i = 2, #layerSizes do
        local layer = {
            weights = {},
            biases = {},
            inputSize = layerSizes[i - 1],
            outputSize = layerSizes[i],
        }
        -- Xavier initialization
        local scale = math.sqrt(2.0 / (layerSizes[i - 1] + layerSizes[i]))
        for o = 1, layerSizes[i] do
            layer.weights[o] = {}
            for j = 1, layerSizes[i - 1] do
                layer.weights[o][j] = (math.random() * 2 - 1) * scale
            end
            layer.biases[o] = 0
        end
        net.layers[i - 1] = layer
    end

    -- Apply initial biases to output layer (for personality differentiation)
    if initialBias then
        local outputLayer = net.layers[#net.layers]
        if initialBias.throttle then
            outputLayer.biases[1] = outputLayer.biases[1] + initialBias.throttle
        end
        if initialBias.brake then
            outputLayer.biases[2] = outputLayer.biases[2] + initialBias.brake
        end
        if initialBias.steerSensitivity then
            outputLayer.biases[3] = outputLayer.biases[3] + initialBias.steerSensitivity
            outputLayer.biases[4] = outputLayer.biases[4] + initialBias.steerSensitivity
        end
    end

    return net
end

-- Forward pass through the network
function nnet.forward(net, inputs)
    local current = inputs
    for li, layer in ipairs(net.layers) do
        local next = {}
        local isOutput = (li == #net.layers)
        for o = 1, layer.outputSize do
            local sum = layer.biases[o]
            for j = 1, layer.inputSize do
                sum = sum + layer.weights[o][j] * (current[j] or 0)
            end
            if isOutput then
                -- Sigmoid for output layer: map to [0, 1]
                next[o] = 1.0 / (1.0 + math.exp(-sum))
            else
                -- Tanh for hidden layers
                next[o] = math.tanh(sum)
            end
        end
        current = next
    end
    return current
end

-- Serialize network to a flat data table
function nnet.serialize(net)
    local data = { layerSizes = {}, weights = {} }
    data.layerSizes[1] = net.layers[1].inputSize
    for i, layer in ipairs(net.layers) do
        data.layerSizes[i + 1] = layer.outputSize
    end
    for _, layer in ipairs(net.layers) do
        for o = 1, layer.outputSize do
            for j = 1, layer.inputSize do
                data.weights[#data.weights + 1] = layer.weights[o][j]
            end
            data.weights[#data.weights + 1] = layer.biases[o]
        end
    end
    return data
end

-- Deserialize network from flat data table
function nnet.deserialize(data)
    local net = { layers = {} }
    for i = 2, #data.layerSizes do
        local layer = {
            weights = {},
            biases = {},
            inputSize = data.layerSizes[i - 1],
            outputSize = data.layerSizes[i],
        }
        for o = 1, layer.outputSize do
            layer.weights[o] = {}
        end
        net.layers[i - 1] = layer
    end
    local idx = 1
    for _, layer in ipairs(net.layers) do
        for o = 1, layer.outputSize do
            for j = 1, layer.inputSize do
                layer.weights[o][j] = data.weights[idx]
                idx = idx + 1
            end
            layer.biases[o] = data.weights[idx]
            idx = idx + 1
        end
    end
    return net
end

-- Create a mutated copy of a network
function nnet.mutate(net, mutationRate, mutationStrength)
    mutationRate = mutationRate or 0.15
    mutationStrength = mutationStrength or 0.3
    local data = nnet.serialize(net)
    for i, w in ipairs(data.weights) do
        if math.random() < mutationRate then
            -- Box-Muller for Gaussian noise
            local u1 = math.random()
            local u2 = math.random()
            if u1 < 1e-10 then u1 = 1e-10 end
            local gaussian = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
            data.weights[i] = w + gaussian * mutationStrength
        end
    end
    return nnet.deserialize(data)
end

-- Create a seeded network with pre-wired weights for basic track following
-- Architecture: 13 inputs, N hidden, 4 outputs (throttle, brake, left, right)
-- The seeded brain can steer toward waypoints and avoid track edges immediately,
-- giving evolution a competent starting point to refine.
function nnet.createSeeded(layerSizes)
    local numInputs = layerSizes[1]
    local numHidden = layerSizes[2]
    local numOutputs = layerSizes[3]

    local net = { layers = {} }

    -- Hidden layer: mostly zeros with specific passthrough neurons
    local hidden = {
        weights = {},
        biases = {},
        inputSize = numInputs,
        outputSize = numHidden,
    }
    for o = 1, numHidden do
        hidden.weights[o] = {}
        for j = 1, numInputs do
            hidden.weights[o][j] = 0
        end
        hidden.biases[o] = 0
    end

    -- Wire passthrough neurons for key sensor inputs
    -- Neuron 1: angle error to waypoint (input 1)
    hidden.weights[1][1] = 3.0
    -- Neuron 2: center distance (input 2)
    hidden.weights[2][2] = 2.5
    -- Neuron 3: speed ratio (input 3)
    hidden.weights[3][3] = 3.0
    -- Neuron 4: curvature ahead (input 4)
    hidden.weights[4][4] = 3.0
    -- Neuron 5: near look-ahead (input 5)
    hidden.weights[5][5] = 2.5

    -- Neurons 6-10: raycast sensors (inputs 9-13) if available
    if numInputs >= 13 then
        hidden.weights[6][9]  = 3.0  -- left ray
        hidden.weights[7][10] = 3.0  -- front-left ray
        hidden.weights[8][11] = 3.0  -- front ray
        hidden.weights[9][12] = 3.0  -- front-right ray
        hidden.weights[10][13] = 3.0 -- right ray
    end

    -- Remaining neurons: small random noise for evolution to explore
    local scale = 0.15
    for o = 11, numHidden do
        for j = 1, numInputs do
            hidden.weights[o][j] = (math.random() * 2 - 1) * scale
        end
    end

    net.layers[1] = hidden

    -- Output layer: wire to produce sensible driving behavior
    local output = {
        weights = {},
        biases = {},
        inputSize = numHidden,
        outputSize = numOutputs,
    }
    for o = 1, numOutputs do
        output.weights[o] = {}
        for j = 1, numHidden do
            output.weights[o][j] = 0
        end
        output.biases[o] = 0
    end

    -- Output 1 (throttle): almost always on, reduce at high speed
    output.biases[1] = 2.0
    output.weights[1][3] = -1.5  -- hidden 3 = speed → less throttle when fast
    output.weights[1][8] = 0.5   -- hidden 8 = front ray → more throttle when clear

    -- Output 2 (brake): normally off, activate for high speed in curves
    output.biases[2] = -2.0
    output.weights[2][3] = 1.5   -- speed → brake when fast
    output.weights[2][4] = 2.0   -- curvature → brake in curves

    -- Output 3 (left steer): activate when angle error is negative (need left)
    -- hidden[1] = tanh(3 * angleError), negative when need to go left
    output.weights[3][1] = -4.0  -- angle error negative → left output high
    output.weights[3][2] = -1.5  -- off-center right → steer left
    output.weights[3][5] = -2.0  -- near look-ahead → steer left
    -- Raycasts: if right wall is close (low ray value → low hidden activation)
    if numInputs >= 13 then
        output.weights[3][10] = -2.0  -- right ray close → steer left
        output.weights[3][6]  = 1.5   -- left ray close → don't steer left
    end

    -- Output 4 (right steer): activate when angle error is positive (need right)
    output.weights[4][1] = 4.0   -- angle error positive → right output high
    output.weights[4][2] = 1.5   -- off-center left → steer right
    output.weights[4][5] = 2.0   -- near look-ahead → steer right
    -- Raycasts: if left wall is close
    if numInputs >= 13 then
        output.weights[4][6]  = -2.0  -- left ray close → steer right
        output.weights[4][10] = 1.5   -- right ray close → don't steer right
    end

    net.layers[2] = output

    return net
end

-- Crossover two networks (uniform weight crossover)
function nnet.crossover(net1, net2)
    local d1 = nnet.serialize(net1)
    local d2 = nnet.serialize(net2)
    local child = { layerSizes = d1.layerSizes, weights = {} }
    for i = 1, #d1.weights do
        child.weights[i] = math.random() < 0.5 and d1.weights[i] or d2.weights[i]
    end
    return nnet.deserialize(child)
end

return nnet
