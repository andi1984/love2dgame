local persistence = require("persistence")

describe("persistence", function()
    it("serializes simple table", function()
        local data = { a = 1, b = "hello" }
        local str = persistence.serialize(data)
        local chunk = load("return " .. str)
        local restored = chunk()
        expect_eq(restored.a, 1)
        expect_eq(restored.b, "hello")
    end)

    it("serializes nested tables", function()
        local data = {
            version = 1,
            npcs = {
                test = {
                    bestFitness = 123.45,
                    generation = 5,
                },
            },
        }
        local str = persistence.serialize(data)
        local chunk = load("return " .. str)
        local restored = chunk()
        expect_near(restored.npcs.test.bestFitness, 123.45, 0.01)
        expect_eq(restored.npcs.test.generation, 5)
    end)

    it("serializes arrays of numbers", function()
        local data = { weights = {1.5, -0.3, 0.7, 2.1} }
        local str = persistence.serialize(data)
        local chunk = load("return " .. str)
        local restored = chunk()
        expect_eq(#restored.weights, 4)
        expect_near(restored.weights[1], 1.5, 0.001)
        expect_near(restored.weights[2], -0.3, 0.001)
    end)

    it("handles booleans", function()
        local data = { yes = true, no = false }
        local str = persistence.serialize(data)
        local chunk = load("return " .. str)
        local restored = chunk()
        expect_true(restored.yes)
        expect_false(restored.no)
    end)

    it("round-trips neural network weight arrays", function()
        local weights = {}
        for i = 1, 160 do
            weights[i] = (math.random() * 2 - 1)
        end
        local data = { layerSizes = {8, 12, 4}, weights = weights }
        local str = persistence.serialize(data)
        local chunk = load("return " .. str)
        local restored = chunk()
        expect_eq(#restored.weights, 160)
        for i = 1, 160 do
            expect_near(restored.weights[i], weights[i], 1e-10)
        end
    end)
end)
