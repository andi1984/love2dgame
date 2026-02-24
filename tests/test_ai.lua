local ai = require("ai")
local Car = require("car")
local track = require("track")

describe("ai", function()
    it("returns 13 sensor values", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        local sensors = ai.getSensorInputs(car, track)
        expect_eq(#sensors, 13)
    end)

    it("all sensor values are in reasonable range", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        local sensors = ai.getSensorInputs(car, track)
        for i, v in ipairs(sensors) do
            expect_true(v >= -2 and v <= 2,
                "sensor " .. i .. " out of range: " .. v)
        end
    end)

    it("on-track sensor is 1.0 when car is on track", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        local sensors = ai.getSensorInputs(car, track)
        expect_eq(sensors[8], 1.0)
    end)

    it("on-track sensor is 0.0 when car is off track", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        car.x = 10
        car.y = 10
        local sensors = ai.getSensorInputs(car, track)
        expect_eq(sensors[8], 0.0)
    end)

    it("raycast sensors are in [0, 1] range", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        local sensors = ai.getSensorInputs(car, track)
        for i = 9, 13 do
            expect_true(sensors[i] >= 0 and sensors[i] <= 1,
                "raycast sensor " .. i .. " out of range: " .. sensors[i])
        end
    end)

    it("outputToInput converts to continuous steering", function()
        -- Strong left: left=0.9, right=0.1 → steer negative
        local input = ai.outputToInput({0.8, 0.2, 0.9, 0.1})
        expect_true(input.up)
        expect_false(input.down)
        expect_true(input.steer < -0.5)
    end)

    it("outputToInput produces right steering", function()
        -- Strong right: left=0.1, right=0.9 → steer positive
        local input = ai.outputToInput({0.8, 0.2, 0.1, 0.9})
        expect_true(input.steer > 0.5)
    end)

    it("outputToInput produces near-zero steering when balanced", function()
        local input = ai.outputToInput({0.5, 0.5, 0.5, 0.5})
        expect_true(math.abs(input.steer) < 0.01)
    end)

    it("initMetrics sets all fields to zero", function()
        local car = Car.new(track, { isAI = true })
        ai.initMetrics(car)
        expect_eq(car.timeOffTrack, 0)
        expect_eq(car.timeStationary, 0)
        expect_eq(car.avgSpeed, 0)
        expect_eq(car.speedSamples, 0)
        expect_eq(car.stuckTimer, 0)
    end)

    it("stuck override uses continuous steer", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        ai.initMetrics(car)
        car.stuckTimer = 3  -- trigger stuck
        local override = ai.getStuckOverride(car)
        expect_true(override ~= nil)
        expect_true(override.steer ~= nil)
        expect_true(override.steer == 1 or override.steer == -1)
    end)

    it("applySensorNoise adds noise to inputs", function()
        math.randomseed(42)
        local inputs = {0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5}
        local errors = { sensorNoise = 0.1 }
        local noisy = ai.applySensorNoise(inputs, errors)
        expect_eq(#noisy, 13)
        local anyDifferent = false
        for i = 1, 13 do
            if noisy[i] ~= 0.5 then anyDifferent = true break end
        end
        expect_true(anyDifferent, "expected noise to change at least one value")
    end)

    it("applySensorNoise returns original inputs when no errors config", function()
        local inputs = {0.5, 0.5, 0.5}
        local result = ai.applySensorNoise(inputs, nil)
        for i = 1, 3 do
            expect_eq(result[i], inputs[i])
        end
    end)

    it("applyErrors returns input unchanged when no personality errors", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        ai.initMetrics(car)
        car.personality = {}
        local input = { up = true, down = false, steer = 0.3 }
        local result = ai.applyErrors(car, input, 0.016)
        expect_eq(result.up, true)
        expect_eq(result.down, false)
        expect_eq(result.steer, 0.3)
    end)

    it("applyErrors lapse holds stale input", function()
        track.init()
        local car = Car.new(track, { isAI = true })
        ai.initMetrics(car)
        car.personality = { errors = {
            lapseChance = 0, steerJitter = 0, brakeLateChance = 0,
        }}
        -- Manually trigger a lapse
        car.lapseTimer = 0.5
        local staleInput = { up = true, down = false, steer = -0.8 }
        car.lastInput = staleInput
        local result = ai.applyErrors(car, { up = false, down = true, steer = 0.5 }, 0.016)
        -- During lapse: should return stale input, not the new one
        expect_eq(result.steer, -0.8)
        expect_eq(result.up, true)
    end)

    it("initMetrics initializes error state fields", function()
        local car = Car.new(track, { isAI = true })
        ai.initMetrics(car)
        expect_eq(car.lapseTimer, 0)
        expect_eq(car.lastInput, nil)
    end)
end)
