-- Car state and physics (pure logic, no Love2D dependency)

local car = {}

function car.init(track)
    car.x = track.cx
    car.y = track.cy - (track.innerRy + track.outerRy) / 2
    car.angle = 0
    car.speed = 0
    car.width = 28
    car.height = 14
    car.prevSpeed = 0
    car.turning = false
    car.currentZone = nil
    car.shouldSpawnSmoke = false

    car.physics = {
        mass = 800,
        fuelMass = 50,
        maxFuel = 50,
        fuelRate = 1.5,
        tirePressure = 2.2,
        optimalPressure = 2.2,
        engineForce = 250000,
        brakeForce = 200000,
        dragCoeff = 3.0,
        rollingResistance = 0.015,
        maxSpeed = 320,
        baseTurnSpeed = 3.0,
        gripMultiplier = 1.0,
        bumpMultiplier = 1.0,
    }
end

function car.update(dt, input, track)
    local physics = car.physics
    local totalMass = physics.mass + physics.fuelMass

    local zone = track.getSurfaceAt(car.x, car.y)
    car.currentZone = zone
    local onTrack = track.isOnTrack(car.x, car.y)

    -- Tire pressure grip
    local pressureDev = math.abs(physics.tirePressure - physics.optimalPressure)
    local pressureGrip = math.max(0.3, 1.0 - pressureDev * 0.4)

    -- Effective grip
    local surfaceGrip = onTrack and zone.grip or 0.3
    local effectiveGrip = surfaceGrip * pressureGrip * physics.gripMultiplier
    effectiveGrip = math.min(1.0, math.max(0.1, effectiveGrip))

    -- Bumpiness
    local bumpiness = onTrack and (zone.bumpiness * physics.bumpMultiplier) or 0.0

    car.prevSpeed = car.speed

    -- Throttle / brake
    local throttle = 0
    if input.up and physics.fuelMass > 0 then
        throttle = 1
    end
    local braking = input.down

    local driveForce = throttle * physics.engineForce * effectiveGrip
    local brakeDecel = 0
    if braking then
        brakeDecel = physics.brakeForce * effectiveGrip
    end

    -- Drag
    local dragForce = physics.dragCoeff * car.speed * math.abs(car.speed)

    -- Rolling resistance
    local rollingForce = physics.rollingResistance * totalMass * 9.81

    -- Off-track grass drag
    local grassDrag = 0
    if not onTrack then
        grassDrag = math.abs(car.speed) * 3.0
    end

    -- Net force
    local netForce = driveForce - dragForce - rollingForce - grassDrag
    if braking then
        if car.speed > 0 then
            netForce = netForce - brakeDecel
        elseif car.speed < 0 then
            netForce = netForce + brakeDecel
        else
            netForce = netForce - brakeDecel * 0.3
        end
    end

    local accel = netForce / totalMass
    car.speed = car.speed + accel * dt

    -- Bumpiness perturbation
    if bumpiness > 0.01 and math.abs(car.speed) > 20 then
        local bumpMag = bumpiness * math.abs(car.speed) * 0.0003
        car.speed = car.speed + (math.random() - 0.5) * bumpMag * car.speed
        car.angle = car.angle + (math.random() - 0.5) * bumpiness * 0.005
    end

    -- Clamp speed
    car.speed = math.max(-100, math.min(physics.maxSpeed, car.speed))

    -- Stop drifting at low speeds
    if math.abs(car.speed) < 1 and throttle == 0 and not braking then
        car.speed = 0
    end

    -- Fuel consumption
    if throttle > 0 then
        physics.fuelMass = math.max(0, physics.fuelMass - physics.fuelRate * dt)
    end

    -- Turning
    local turnFactor = math.min(1, math.abs(car.speed) / 100) * effectiveGrip
    car.turning = false
    if input.left then
        car.angle = car.angle - physics.baseTurnSpeed * turnFactor * dt
        car.turning = true
    end
    if input.right then
        car.angle = car.angle + physics.baseTurnSpeed * turnFactor * dt
        car.turning = true
    end

    -- Move car
    car.x = car.x + math.cos(car.angle) * car.speed * dt
    car.y = car.y + math.sin(car.angle) * car.speed * dt

    -- Keep in bounds
    car.x = math.max(10, math.min(790, car.x))
    car.y = math.max(10, math.min(590, car.y))

    -- Determine if should spawn smoke
    local isBraking = input.down and car.speed > 50
    local isSharpTurn = car.turning and math.abs(car.speed) > 120
    car.shouldSpawnSmoke = isBraking or isSharpTurn
end

return car
