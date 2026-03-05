-- Car factory and physics (pure logic, no Love2D dependency)

local damage = require("damage")

local Car = {}
Car.__index = Car
local abs, min, max, cos, sin = math.abs, math.min, math.max, math.cos, math.sin
local random, pi = math.random, math.pi

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
    self.shouldSpawnDarkSmoke = false  -- engine damage smoke

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

    -- Apply lateral offset (perpendicular to track direction) for grid starts
    if overrides.lateralOffset and overrides.lateralOffset ~= 0 then
        local perpAngle = self.angle + pi / 2
        self.x = self.x + cos(perpAngle) * overrides.lateralOffset
        self.y = self.y + sin(perpAngle) * overrides.lateralOffset
    end

    -- Damage state (always present)
    self.damage = damage.create()

    return self
end

function Car:update(dt, input, track)
    local physics   = self.physics
    local totalMass = physics.mass + physics.fuelMass

    local zone    = track.getSurfaceAt(self.x, self.y)
    self.currentZone = zone
    local onTrack = track.isOnTrack(self.x, self.y)

    -- ----------------------------------------------------------------
    -- Damage modifiers
    -- ----------------------------------------------------------------
    local dmgMods = damage.getHandlingModifiers(self.damage)

    -- Tire pressure grip
    local pressureDev  = abs(physics.tirePressure - physics.optimalPressure)
    local pressureGrip = max(0.3, 1.0 - pressureDev * 0.4)

    -- Effective grip (also reduced by average tire health)
    local surfaceGrip   = onTrack and zone.grip or 0.3
    local effectiveGrip = surfaceGrip * pressureGrip * physics.gripMultiplier
                        * dmgMods.avgTireHealth
    effectiveGrip = min(1.0, max(0.1, effectiveGrip))

    -- Bumpiness: suspension damage amplifies it; flat tires add periodic thump
    local baseBump = onTrack and (zone.bumpiness * physics.bumpMultiplier) or 0.0
    local bumpiness = baseBump * dmgMods.bumpMult

    -- Flat-tire periodic thumping: each flat wheel adds low-frequency perturbation
    local flatCount = damage.flatTireCount(self.damage)
    if flatCount > 0 and abs(self.speed) > 15 then
        -- Thump frequency scales with speed (like wheel hitting rim each revolution)
        local thumpFreq = abs(self.speed) / 60   -- ~1 thump/sec at speed 60
        local thumpPhase = (love and love.timer and love.timer.getTime() or 0) * thumpFreq
        local thump = max(0, sin(thumpPhase * 2 * pi))
        bumpiness = bumpiness + thump * flatCount * 0.35
    end

    self.prevSpeed = self.speed

    -- Throttle / brake
    local throttle = 0
    if input.up and physics.fuelMass > 0 then
        throttle = 1
    end
    local braking = input.down

    -- Engine damage reduces drive force
    local driveForce = throttle * physics.engineForce * effectiveGrip * dmgMods.engineMult
    local brakeDecel = 0
    if braking then
        brakeDecel = physics.brakeForce * effectiveGrip
    end

    -- Drag (body damage increases drag)
    local dragForce = physics.dragCoeff * self.speed * abs(self.speed) * dmgMods.dragMult

    -- Rolling resistance
    local rollingForce = physics.rollingResistance * totalMass * 9.81

    -- Off-track grass drag
    local grassDrag = 0
    if not onTrack then
        grassDrag = abs(self.speed) * 3.0
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
    self.speed  = self.speed + accel * dt

    -- Bumpiness perturbation (suspension damage amplified)
    if bumpiness > 0.01 and abs(self.speed) > 20 then
        local bumpMag = bumpiness * abs(self.speed) * 0.0003
        self.speed = self.speed + (random() - 0.5) * bumpMag * self.speed
        self.angle = self.angle + (random() - 0.5) * bumpiness * 0.005
    end

    -- Clamp speed (max speed reduced by damage)
    local effectiveMaxSpeed = physics.maxSpeed * dmgMods.maxSpeedMult
    self.speed = max(-100, min(effectiveMaxSpeed, self.speed))

    -- Stop drifting at low speeds
    if abs(self.speed) < 1 and throttle == 0 and not braking then
        self.speed = 0
    end

    -- Fuel consumption
    if throttle > 0 then
        physics.fuelMass = max(0, physics.fuelMass - physics.fuelRate * dt)
    end

    -- Turning (supports both boolean left/right and continuous steer)
    local turnFactor = min(1, abs(self.speed) / 100) * effectiveGrip
    self.turning = false
    if input.steer then
        local steerVal = max(-1, min(1, input.steer))
        if abs(steerVal) > 0.05 then
            self.angle   = self.angle + physics.baseTurnSpeed * steerVal * turnFactor * dt
            self.turning = true
        end
    else
        if input.left then
            self.angle   = self.angle - physics.baseTurnSpeed * turnFactor * dt
            self.turning = true
        end
        if input.right then
            self.angle   = self.angle + physics.baseTurnSpeed * turnFactor * dt
            self.turning = true
        end
    end

    -- Tire pull: asymmetric damage pulls the car to one side
    -- Player must compensate with steering (NPCs experience it through physics)
    if abs(dmgMods.tirePull) > 0.01 and abs(self.speed) > 10 then
        local pullTurn = dmgMods.tirePull * physics.baseTurnSpeed * 0.35 * turnFactor
        self.angle = self.angle + pullTurn * dt
    end

    -- Move car
    self.x = self.x + cos(self.angle) * self.speed * dt
    self.y = self.y + sin(self.angle) * self.speed * dt

    -- Keep in bounds
    self.x = max(10, min(790, self.x))
    self.y = max(10, min(590, self.y))

    -- Smoke flags
    local isBraking    = input.down and self.speed > 50
    local isSharpTurn  = self.turning and abs(self.speed) > 120
    self.shouldSpawnSmoke     = isBraking or isSharpTurn
    -- Dark engine-damage smoke when engine is hurt and car is moving
    self.shouldSpawnDarkSmoke = self.damage and self.damage.engine < 0.55
                                and abs(self.speed) > 25
end

return Car
