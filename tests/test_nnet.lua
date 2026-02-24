local nnet = require("nnet")

describe("nnet", function()
    it("creates network with correct layer sizes", function()
        local net = nnet.new({13, 16, 4})
        expect_eq(#net.layers, 2)
        expect_eq(net.layers[1].inputSize, 13)
        expect_eq(net.layers[1].outputSize, 16)
        expect_eq(net.layers[2].inputSize, 16)
        expect_eq(net.layers[2].outputSize, 4)
    end)

    it("forward pass returns correct number of outputs", function()
        local net = nnet.new({13, 16, 4})
        local inputs = {0.5, -0.3, 0.8, 0.0, 0.1, -0.1, 0.9, 1.0, 0.5, 0.6, 0.7, 0.8, 0.4}
        local outputs = nnet.forward(net, inputs)
        expect_eq(#outputs, 4)
    end)

    it("outputs are in [0, 1] range", function()
        math.randomseed(42)
        local net = nnet.new({13, 16, 4})
        -- Test with extreme inputs
        local testInputs = {
            {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
            {-1, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 0},
            {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        }
        for _, inputs in ipairs(testInputs) do
            local outputs = nnet.forward(net, inputs)
            for i, v in ipairs(outputs) do
                expect_true(v >= 0 and v <= 1,
                    "output " .. i .. " = " .. v .. " is out of [0,1] range")
            end
        end
    end)

    it("serialize then deserialize produces same outputs", function()
        math.randomseed(123)
        local net = nnet.new({13, 16, 4})
        local inputs = {0.5, -0.3, 0.8, 0.0, 0.1, -0.1, 0.9, 1.0, 0.5, 0.6, 0.7, 0.8, 0.4}
        local orig = nnet.forward(net, inputs)

        local data = nnet.serialize(net)
        local restored = nnet.deserialize(data)
        local after = nnet.forward(restored, inputs)

        for i = 1, 4 do
            expect_near(orig[i], after[i], 0.0001)
        end
    end)

    it("mutation changes at least some weights", function()
        math.randomseed(99)
        local net = nnet.new({13, 16, 4})
        local d1 = nnet.serialize(net)
        local mutated = nnet.mutate(net, 1.0, 0.5) -- 100% mutation rate
        local d2 = nnet.serialize(mutated)

        local changed = false
        for i = 1, #d1.weights do
            if d1.weights[i] ~= d2.weights[i] then
                changed = true
                break
            end
        end
        expect_true(changed)
    end)

    it("crossover combines two networks", function()
        math.randomseed(55)
        local net1 = nnet.new({13, 16, 4})
        local net2 = nnet.new({13, 16, 4})
        local child = nnet.crossover(net1, net2)

        local d1 = nnet.serialize(net1)
        local d2 = nnet.serialize(net2)
        local dc = nnet.serialize(child)

        -- Each weight should come from either parent
        for i = 1, #dc.weights do
            local fromP1 = dc.weights[i] == d1.weights[i]
            local fromP2 = dc.weights[i] == d2.weights[i]
            expect_true(fromP1 or fromP2,
                "weight " .. i .. " doesn't match either parent")
        end
    end)

    it("applies initial bias to output layer", function()
        math.randomseed(77)
        local net = nnet.new({13, 16, 4}, {
            throttle = 0.5,
            brake = -0.3,
            steerSensitivity = 0.2,
        })
        local outputLayer = net.layers[#net.layers]
        expect_near(outputLayer.biases[1], 0.5, 0.001) -- throttle
        expect_near(outputLayer.biases[2], -0.3, 0.001) -- brake
        expect_near(outputLayer.biases[3], 0.2, 0.001) -- left steer
        expect_near(outputLayer.biases[4], 0.2, 0.001) -- right steer
    end)

    it("createSeeded produces a network with correct dimensions", function()
        local net = nnet.createSeeded({13, 16, 4})
        expect_eq(#net.layers, 2)
        expect_eq(net.layers[1].inputSize, 13)
        expect_eq(net.layers[1].outputSize, 16)
        expect_eq(net.layers[2].inputSize, 16)
        expect_eq(net.layers[2].outputSize, 4)
    end)

    it("createSeeded brain steers right when angle error is positive", function()
        local net = nnet.createSeeded({13, 16, 4})
        -- Positive angle error (need to steer right), on track, moderate speed
        local inputs = {0.3, 0, 0.3, 0, 0.3, 0.3, 0.9, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5}
        local outputs = nnet.forward(net, inputs)
        -- Right output should be higher than left output
        expect_true(outputs[4] > outputs[3],
            "expected right > left, got right=" .. outputs[4] .. " left=" .. outputs[3])
    end)

    it("createSeeded brain steers left when angle error is negative", function()
        local net = nnet.createSeeded({13, 16, 4})
        -- Negative angle error (need to steer left), on track, moderate speed
        local inputs = {-0.3, 0, 0.3, 0, -0.3, -0.3, 0.9, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5}
        local outputs = nnet.forward(net, inputs)
        -- Left output should be higher than right output
        expect_true(outputs[3] > outputs[4],
            "expected left > right, got left=" .. outputs[3] .. " right=" .. outputs[4])
    end)

    it("createSeeded brain throttles by default", function()
        local net = nnet.createSeeded({13, 16, 4})
        -- Neutral inputs, on track
        local inputs = {0, 0, 0.2, 0, 0, 0, 0.9, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5}
        local outputs = nnet.forward(net, inputs)
        expect_true(outputs[1] > 0.5,
            "expected throttle > 0.5, got " .. outputs[1])
    end)
end)
