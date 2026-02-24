local evolution = require("evolution")
local nnet = require("nnet")
local track = require("track")
local Car = require("car")

describe("evolution", function()
    it("keeps improvement when fitness increases", function()
        math.randomseed(42)
        track.init()
        local car = Car.new(track, { isAI = true })
        car.brain = nnet.new({13, 16, 4})
        car.bestBrain = nnet.serialize(car.brain)
        car.bestFitness = 100
        car.currentFitness = 200
        car.generation = 0
        car.personality = { mutationRate = 0.15, mutationStrength = 0.3 }

        evolution.evolveAfterRace(car)

        expect_eq(car.bestFitness, 200)
        expect_eq(car.generation, 1)
    end)

    it("reverts to best when fitness decreases", function()
        math.randomseed(42)
        track.init()
        local car = Car.new(track, { isAI = true })
        car.brain = nnet.new({13, 16, 4})
        car.bestBrain = nnet.serialize(car.brain)
        car.bestFitness = 200
        car.currentFitness = 100
        car.generation = 5
        car.personality = { mutationRate = 0.15, mutationStrength = 0.3 }

        evolution.evolveAfterRace(car)

        -- bestFitness should remain 200, generation unchanged
        expect_eq(car.bestFitness, 200)
        expect_eq(car.generation, 5)
    end)

    it("calculates fitness from race metrics", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        car.avgSpeed = 100
        car.timeOffTrack = 0
        car.timeStationary = 0

        local fitness = evolution.calculateFitness(car, track, 30, 2)
        expect_true(fitness > 0)
    end)

    it("penalizes time off track", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        car.avgSpeed = 100
        car.timeOffTrack = 0
        car.timeStationary = 0
        local f1 = evolution.calculateFitness(car, track, 30, 1)

        car.timeOffTrack = 10
        local f2 = evolution.calculateFitness(car, track, 30, 1)

        expect_true(f2 < f1)
    end)

    it("rewards on-track ratio", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        car.avgSpeed = 100
        car.timeStationary = 0

        car.timeOffTrack = 0
        local f1 = evolution.calculateFitness(car, track, 30, 0)

        car.timeOffTrack = 15  -- half the race off track
        local f2 = evolution.calculateFitness(car, track, 30, 0)

        expect_true(f1 > f2, "fully on-track should have higher fitness")
    end)
end)
