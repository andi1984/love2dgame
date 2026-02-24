local Car = require("car")
local track = require("track")

describe("car", function()
    it("initializes at track start position", function()
        track.init()
        local car = Car.new(track)
        expect_eq(car.x, track.startX)
        expect_eq(car.y, track.startY)
        expect_eq(car.speed, 0)
        expect_eq(car.angle, track.startAngle)
    end)

    it("two car instances are independent", function()
        track.init()
        local c1 = Car.new(track)
        local c2 = Car.new(track)
        c1.speed = 100
        expect_eq(c2.speed, 0)
    end)

    it("accelerates when throttle is pressed", function()
        track.init()
        local car = Car.new(track)
        local input = { up = true, down = false, left = false, right = false }
        car:update(0.016, input, track)
        expect_true(car.speed > 0)
    end)

    it("stays still with no input", function()
        track.init()
        local car = Car.new(track)
        local input = { up = false, down = false, left = false, right = false }
        car:update(0.016, input, track)
        expect_eq(car.speed, 0)
    end)

    it("turns left when left is pressed at speed", function()
        track.init()
        local car = Car.new(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, left = true, right = false }
        car:update(0.016, input, track)
        expect_true(car.angle < startAngle)
    end)

    it("turns right when right is pressed at speed", function()
        track.init()
        local car = Car.new(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, left = false, right = true }
        car:update(0.016, input, track)
        expect_true(car.angle > startAngle)
    end)

    it("decelerates when braking", function()
        track.init()
        local car = Car.new(track)
        car.speed = 200
        local input = { up = false, down = true, left = false, right = false }
        car:update(0.016, input, track)
        expect_true(car.speed < 200)
    end)

    it("consumes fuel when accelerating", function()
        track.init()
        local car = Car.new(track)
        local startFuel = car.physics.fuelMass
        local input = { up = true, down = false, left = false, right = false }
        car:update(0.016, input, track)
        expect_true(car.physics.fuelMass < startFuel)
    end)

    it("does not accelerate with no fuel", function()
        track.init()
        local car = Car.new(track)
        car.physics.fuelMass = 0
        local input = { up = true, down = false, left = false, right = false }
        car:update(0.016, input, track)
        expect_true(car.speed <= 0)
    end)

    it("speed is clamped to maxSpeed", function()
        track.init()
        local car = Car.new(track)
        car.speed = car.physics.maxSpeed + 100
        local input = { up = false, down = false, left = false, right = false }
        car:update(0.016, input, track)
        expect_true(car.speed <= car.physics.maxSpeed)
    end)

    it("position stays within screen bounds", function()
        track.init()
        local car = Car.new(track)
        car.x = 5
        car.y = 5
        car.speed = -200
        car.angle = math.pi
        local input = { up = false, down = false, left = false, right = false }
        car:update(0.1, input, track)
        expect_true(car.x >= 10)
        expect_true(car.y >= 10)
    end)

    it("applies physics overrides", function()
        track.init()
        local car = Car.new(track, { physics = { engineForce = 300000 } })
        expect_eq(car.physics.engineForce, 300000)
        expect_eq(car.physics.mass, 800) -- other values unchanged
    end)

    it("turns left with continuous negative steer", function()
        track.init()
        local car = Car.new(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, steer = -0.5 }
        car:update(0.016, input, track)
        expect_true(car.angle < startAngle)
    end)

    it("turns right with continuous positive steer", function()
        track.init()
        local car = Car.new(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, steer = 0.5 }
        car:update(0.016, input, track)
        expect_true(car.angle > startAngle)
    end)

    it("does not turn intentionally with tiny steer value", function()
        track.init()
        local car = Car.new(track)
        car.speed = 100
        local startAngle = car.angle
        local input = { up = false, down = false, steer = 0.01 }
        car:update(0.016, input, track)
        -- Steer below deadzone (0.05) should not cause intentional turning
        -- (tiny angle change may occur from bumpiness perturbation)
        expect_near(car.angle, startAngle, 0.01)
    end)
end)
