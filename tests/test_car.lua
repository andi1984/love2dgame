local car = require("car")
local track = require("track")

describe("car", function()
    it("initializes at track start position", function()
        track.init()
        car.init(track)
        expect_eq(car.x, track.startX)
        expect_eq(car.y, track.startY)
        expect_eq(car.speed, 0)
        expect_eq(car.angle, track.startAngle)
    end)

    it("accelerates when throttle is pressed", function()
        track.init()
        car.init(track)
        local input = { up = true, down = false, left = false, right = false }
        car.update(0.016, input, track)
        expect_true(car.speed > 0)
    end)

    it("stays still with no input", function()
        track.init()
        car.init(track)
        local input = { up = false, down = false, left = false, right = false }
        car.update(0.016, input, track)
        expect_eq(car.speed, 0)
    end)

    it("turns left when left is pressed at speed", function()
        track.init()
        car.init(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, left = true, right = false }
        car.update(0.016, input, track)
        expect_true(car.angle < startAngle)
    end)

    it("turns right when right is pressed at speed", function()
        track.init()
        car.init(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, left = false, right = true }
        car.update(0.016, input, track)
        expect_true(car.angle > startAngle)
    end)

    it("decelerates when braking", function()
        track.init()
        car.init(track)
        car.speed = 200
        local input = { up = false, down = true, left = false, right = false }
        car.update(0.016, input, track)
        expect_true(car.speed < 200)
    end)

    it("consumes fuel when accelerating", function()
        track.init()
        car.init(track)
        local startFuel = car.physics.fuelMass
        local input = { up = true, down = false, left = false, right = false }
        car.update(0.016, input, track)
        expect_true(car.physics.fuelMass < startFuel)
    end)

    it("does not accelerate with no fuel", function()
        track.init()
        car.init(track)
        car.physics.fuelMass = 0
        local input = { up = true, down = false, left = false, right = false }
        car.update(0.016, input, track)
        -- With no fuel, throttle=0, so no drive force. Speed should be 0 or negative (rolling resistance).
        expect_true(car.speed <= 0)
    end)

    it("speed is clamped to maxSpeed", function()
        track.init()
        car.init(track)
        car.speed = car.physics.maxSpeed + 100
        local input = { up = false, down = false, left = false, right = false }
        car.update(0.016, input, track)
        expect_true(car.speed <= car.physics.maxSpeed)
    end)

    it("position stays within screen bounds", function()
        track.init()
        car.init(track)
        car.x = 5
        car.y = 5
        car.speed = -200
        car.angle = math.pi -- moving left
        local input = { up = false, down = false, left = false, right = false }
        car.update(0.1, input, track)
        expect_true(car.x >= 10)
        expect_true(car.y >= 10)
    end)
end)
