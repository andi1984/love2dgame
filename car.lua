-- Car factory and physics (pure logic, no Love2D dependency)

local Car = {}
Car.__index = Car

function Car.new(track, overrides)
    local self = setmetatable({}, Car)
    overrides = overrides or {}

    -- Start position (with optional offset along track)
    self.x = track.startX or track.cx
    self.y = track.startY or (track.cy - 50)
    self.angle = track.startAngle or 0
    self.speed = 0
    self.width = 28
    self.height = 14
    self.prevSpeed = 0
    self.turning = false
    self.currentZone = nil
    self.shouldSpawnSmoke = false

    -- Identity
    self.name = overrides.name or "Player"
    self.color = overrides.color or {0.85, 0.1, 0.1}
    self.isAI = overrides.isAI or false

    self.physics = {
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

    -- Apply physics overrides
    if overrides.physics then
        for k, v in pairs(overrides.physics) do
            self.physics[k] = v
        end
    end

    -- Apply start offset along track if provided
    if overrides.startOffset and track.getPointAtPercent then
        local offsetPct = (1.0 + overrides.startOffset) % 1.0
        local pt = track.getPointAtPercent(offsetPct)
        if pt then
            self.x = pt.x
            self.y = pt.y
        end
    end

    return self
end

function Car:update(dt, input, track)
    local physics = self.physics
    local totalMass = physics.mass + physics.fuelMass

    local zone = track.getSurfaceAt(self.x, self.y)
    self.currentZone = zone
    local onTrack = track.isOnTrack(self.x, self.y)

    -- Tire pressure grip
    local pressureDev = math.abs(physics.tirePressure - physics.optimalPressure)
    local pressureGrip = math.max(0.3, 1.0 - pressureDev * 0.4)

    -- Effective grip
    local surfaceGrip = onTrack and zone.grip or 0.3
    local effectiveGrip = surfaceGrip * pressureGrip * physics.gripMultiplier
    effectiveGrip = math.min(1.0, math.max(0.1, effectiveGrip))

    -- Bumpiness
    local bumpiness = onTrack and (zone.bumpiness * physics.bumpMultiplier) or 0.0

    self.prevSpeed = self.speed

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
    local dragForce = physics.dragCoeff * self.speed * math.abs(self.speed)

    -- Rolling resistance
    local rollingForce = physics.rollingResistance * totalMass * 9.81

    -- Off-track grass drag
    local grassDrag = 0
    if not onTrack then
        grassDrag = math.abs(self.speed) * 3.0
    end

    -- Net force
    local netForce = driveForce - dragForce - rollingForce - grassDrag
    if braking then
        if self.speed > 0 then
            netForce = netForce - brakeDecel
        elseif self.speed < 0 then
            netForce = netForce + brakeDecel
        else
            netForce = netForce - brakeDecel * 0.3
        end
    end

    local accel = netForce / totalMass
    self.speed = self.speed + accel * dt

    -- Bumpiness perturbation
    if bumpiness > 0.01 and math.abs(self.speed) > 20 then
        local bumpMag = bumpiness * math.abs(self.speed) * 0.0003
        self.speed = self.speed + (math.random() - 0.5) * bumpMag * self.speed
        self.angle = self.angle + (math.random() - 0.5) * bumpiness * 0.005
    end

    -- Clamp speed
    self.speed = math.max(-100, math.min(physics.maxSpeed, self.speed))

    -- Stop drifting at low speeds
    if math.abs(self.speed) < 1 and throttle == 0 and not braking then
        self.speed = 0
    end

    -- Fuel consumption
    if throttle > 0 then
        physics.fuelMass = math.max(0, physics.fuelMass - physics.fuelRate * dt)
    end

    -- Turning (supports both boolean left/right and continuous steer)
    local turnFactor = math.min(1, math.abs(self.speed) / 100) * effectiveGrip
    self.turning = false
    if input.steer then
        -- Continuous steering: steer in [-1, 1]
        local steerVal = math.max(-1, math.min(1, input.steer))
        if math.abs(steerVal) > 0.05 then
            self.angle = self.angle + physics.baseTurnSpeed * steerVal * turnFactor * dt
            self.turning = true
        end
    else
        if input.left then
            self.angle = self.angle - physics.baseTurnSpeed * turnFactor * dt
            self.turning = true
        end
        if input.right then
            self.angle = self.angle + physics.baseTurnSpeed * turnFactor * dt
            self.turning = true
        end
    end

    -- Move car
    self.x = self.x + math.cos(self.angle) * self.speed * dt
    self.y = self.y + math.sin(self.angle) * self.speed * dt

    -- Keep in bounds
    self.x = math.max(10, math.min(790, self.x))
    self.y = math.max(10, math.min(590, self.y))

    -- Determine if should spawn smoke
    local isBraking = input.down and self.speed > 50
    local isSharpTurn = self.turning and math.abs(self.speed) > 120
    self.shouldSpawnSmoke = isBraking or isSharpTurn
end

return Car
