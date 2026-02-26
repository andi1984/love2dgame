-- Damage system (pure logic, no Love2D dependency)
-- Tracks structural damage per car and computes handling modifiers

local damage = {}

local FLAT_TIRE_THRESHOLD  = 0.25   -- below this = flat tire
local CURB_DAMAGE_PER_SEC  = 0.05   -- damage/sec at max speed on curbs
local OFFROAD_WEAR_PER_SEC = 0.008  -- very slow off-road tire wear

-- Create a fresh damage state for a car
function damage.create()
    return {
        -- Tire health [0 = destroyed / flat, 1 = perfect]
        tires = { FL = 1.0, FR = 1.0, RL = 1.0, RR = 1.0 },

        -- Cached flat-tire boolean per wheel (recomputed each frame)
        flatTires = { FL = false, FR = false, RL = false, RR = false },

        -- Body panel health [0 = destroyed, 1 = intact]
        body = { front = 1.0, rear = 1.0, left = 1.0, right = 1.0 },

        -- Engine health
        engine = 1.0,

        -- Suspension health per corner
        suspension = { FL = 1.0, FR = 1.0, RL = 1.0, RR = 1.0 },

        -- Visual / audio event flags (reset each frame)
        newFlat    = false,  -- a tire just went flat this frame
        newImpact  = false,  -- a collision was applied this frame
        impactSide = nil,    -- "front" | "rear" | "left" | "right"
        impactForce = 0,     -- 0..1

        -- Flash timer for impact visual
        impactFlash = 0,
    }
end

-- ----------------------------------------------------------------
-- Environment damage (curbs, off-road)
-- ----------------------------------------------------------------
function damage.updateEnvironment(dmg, car, track, dt)
    if not dmg then return end

    -- Reset per-frame flags
    dmg.newFlat   = false
    dmg.newImpact = false

    -- Decay impact flash
    if dmg.impactFlash > 0 then
        dmg.impactFlash = math.max(0, dmg.impactFlash - dt)
    end

    local speed   = math.abs(car.speed)
    local onTrack = track.isOnTrack(car.x, car.y)
    local zone    = track.getSurfaceAt(car.x, car.y)

    -- Curb damage: on-track but low-grip zone (curb tiles)
    local onCurb = onTrack and zone and zone.grip < 0.72 and zone.grip > 0.2
    if onCurb and speed > 20 then
        local intensity = math.min(1.0, speed / 200)
        local curbDmg   = CURB_DAMAGE_PER_SEC * intensity * dt

        -- Front tires and suspension take most of the hit
        dmg.tires.FL      = math.max(0, dmg.tires.FL      - curbDmg * 0.9)
        dmg.tires.FR      = math.max(0, dmg.tires.FR      - curbDmg * 0.9)
        dmg.tires.RL      = math.max(0, dmg.tires.RL      - curbDmg * 0.5)
        dmg.tires.RR      = math.max(0, dmg.tires.RR      - curbDmg * 0.5)
        dmg.suspension.FL = math.max(0, dmg.suspension.FL - curbDmg * 0.4)
        dmg.suspension.FR = math.max(0, dmg.suspension.FR - curbDmg * 0.4)
    end

    -- Off-road wear (very slow)
    if not onTrack and speed > 30 then
        local wear = OFFROAD_WEAR_PER_SEC * math.min(1.0, speed / 150) * dt
        dmg.tires.FL = math.max(0, dmg.tires.FL - wear)
        dmg.tires.FR = math.max(0, dmg.tires.FR - wear)
        dmg.tires.RL = math.max(0, dmg.tires.RL - wear)
        dmg.tires.RR = math.max(0, dmg.tires.RR - wear)
    end

    -- Update flat-tire state and flag new flats
    for _, pos in ipairs({"FL", "FR", "RL", "RR"}) do
        local wasFlat = dmg.flatTires[pos]
        dmg.flatTires[pos] = dmg.tires[pos] < FLAT_TIRE_THRESHOLD
        if dmg.flatTires[pos] and not wasFlat then
            dmg.newFlat = true
        end
    end
end

-- ----------------------------------------------------------------
-- Collision damage between two cars
-- impactSpeed: magnitude of relative velocity along collision axis
-- ----------------------------------------------------------------
function damage.applyCollision(dmg1, car1, dmg2, car2, impactSpeed)
    if not dmg1 or not dmg2 then return end

    -- Direction from car1 to car2 (world space)
    local dx   = car2.x - car1.x
    local dy   = car2.y - car1.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then return end
    local nx, ny = dx / dist, dy / dist

    -- Transform into each car's local frame to determine impact side
    local function getSide(car, worldNX, worldNY)
        local cos = math.cos(-car.angle)
        local sin = math.sin(-car.angle)
        local lx  = worldNX * cos - worldNY * sin
        local ly  = worldNX * sin + worldNY * cos
        if math.abs(lx) >= math.abs(ly) then
            return lx > 0 and "front" or "rear"
        else
            return ly > 0 and "right" or "left"
        end
    end

    local side1 = getSide(car1,  nx,  ny)
    local side2 = getSide(car2, -nx, -ny)

    -- Damage scales quadratically with speed (severe at high speed)
    local force       = math.min(1.0, (impactSpeed / 120) ^ 2)
    local linearForce = math.min(1.0,  impactSpeed / 120)

    -- Body panels
    dmg1.body[side1] = math.max(0, dmg1.body[side1] - force * 0.75)
    dmg2.body[side2] = math.max(0, dmg2.body[side2] - force * 0.75)

    -- Tire damage based on impact side
    local function applyTireDmg(dmg, side, amt)
        if side == "front" then
            dmg.tires.FL = math.max(0, dmg.tires.FL - amt * 0.45)
            dmg.tires.FR = math.max(0, dmg.tires.FR - amt * 0.45)
        elseif side == "rear" then
            dmg.tires.RL = math.max(0, dmg.tires.RL - amt * 0.45)
            dmg.tires.RR = math.max(0, dmg.tires.RR - amt * 0.45)
        elseif side == "left" then
            dmg.tires.FL = math.max(0, dmg.tires.FL - amt * 0.65)
            dmg.tires.RL = math.max(0, dmg.tires.RL - amt * 0.65)
        elseif side == "right" then
            dmg.tires.FR = math.max(0, dmg.tires.FR - amt * 0.65)
            dmg.tires.RR = math.max(0, dmg.tires.RR - amt * 0.65)
        end
    end
    applyTireDmg(dmg1, side1, linearForce)
    applyTireDmg(dmg2, side2, linearForce)

    -- Engine damage on severe frontal / rear collisions
    if force > 0.35 then
        if side1 == "front" or side1 == "rear" then
            dmg1.engine = math.max(0, dmg1.engine - force * 0.40)
        end
        if side2 == "front" or side2 == "rear" then
            dmg2.engine = math.max(0, dmg2.engine - force * 0.40)
        end
    end

    -- Suspension damage
    local function applySuspDmg(dmg, side, amt)
        if side == "front" then
            dmg.suspension.FL = math.max(0, dmg.suspension.FL - amt * 0.5)
            dmg.suspension.FR = math.max(0, dmg.suspension.FR - amt * 0.5)
        elseif side == "rear" then
            dmg.suspension.RL = math.max(0, dmg.suspension.RL - amt * 0.5)
            dmg.suspension.RR = math.max(0, dmg.suspension.RR - amt * 0.5)
        elseif side == "left" then
            dmg.suspension.FL = math.max(0, dmg.suspension.FL - amt * 0.55)
            dmg.suspension.RL = math.max(0, dmg.suspension.RL - amt * 0.55)
        elseif side == "right" then
            dmg.suspension.FR = math.max(0, dmg.suspension.FR - amt * 0.55)
            dmg.suspension.RR = math.max(0, dmg.suspension.RR - amt * 0.55)
        end
    end
    applySuspDmg(dmg1, side1, linearForce)
    applySuspDmg(dmg2, side2, linearForce)

    -- Update flat-tire state
    for _, pos in ipairs({"FL", "FR", "RL", "RR"}) do
        local wasFlat1 = dmg1.flatTires[pos]
        local wasFlat2 = dmg2.flatTires[pos]
        dmg1.flatTires[pos] = dmg1.tires[pos] < FLAT_TIRE_THRESHOLD
        dmg2.flatTires[pos] = dmg2.tires[pos] < FLAT_TIRE_THRESHOLD
        if dmg1.flatTires[pos] and not wasFlat1 then dmg1.newFlat = true end
        if dmg2.flatTires[pos] and not wasFlat2 then dmg2.newFlat = true end
    end

    -- Set collision event data (used by audio / visuals)
    dmg1.newImpact   = true
    dmg1.impactFlash = math.max(dmg1.impactFlash, 0.4)
    dmg1.impactSide  = side1
    dmg1.impactForce = force

    dmg2.newImpact   = true
    dmg2.impactFlash = math.max(dmg2.impactFlash, 0.4)
    dmg2.impactSide  = side2
    dmg2.impactForce = force
end

-- ----------------------------------------------------------------
-- Compute handling modifiers from damage state
-- Returns a table consumed by car.lua's update()
-- ----------------------------------------------------------------
function damage.getHandlingModifiers(dmg)
    if not dmg then
        return {
            tirePull     = 0,
            engineMult   = 1.0,
            dragMult     = 1.0,
            bumpMult     = 1.0,
            maxSpeedMult = 1.0,
            avgTireHealth = 1.0,
        }
    end

    -- Tire pull: asymmetric health between left/right sides
    -- Positive = pull to the left  (need right steering to correct)
    -- Negative = pull to the right (need left  steering to correct)
    local leftHealth  = (dmg.tires.FL + dmg.tires.RL) / 2
    local rightHealth = (dmg.tires.FR + dmg.tires.RR) / 2
    local tirePull    = (rightHealth - leftHealth) * 0.85

    local avgTireHealth = (dmg.tires.FL + dmg.tires.FR +
                           dmg.tires.RL + dmg.tires.RR) / 4

    -- Engine damage reduces drive force
    local engineMult = 0.20 + dmg.engine * 0.80

    -- Body damage increases aerodynamic drag
    local avgBodyDmg = 1 - (dmg.body.front + dmg.body.rear +
                             dmg.body.left  + dmg.body.right) / 4
    local dragMult = 1.0 + avgBodyDmg * 0.55

    -- Suspension damage amplifies track bumpiness
    local avgSusp = (dmg.suspension.FL + dmg.suspension.FR +
                     dmg.suspension.RL + dmg.suspension.RR) / 4
    local bumpMult = 1.0 + (1 - avgSusp) * 4.5

    -- Flat tires and engine damage cap max speed
    local maxSpeedMult = (0.35 + avgTireHealth * 0.65) *
                         (0.45 + dmg.engine   * 0.55)

    return {
        tirePull      = tirePull,
        engineMult    = engineMult,
        dragMult      = dragMult,
        bumpMult      = bumpMult,
        maxSpeedMult  = maxSpeedMult,
        avgTireHealth = avgTireHealth,
    }
end

-- Overall damage severity 0 (none) → 1 (destroyed), for display
function damage.getSeverity(dmg)
    if not dmg then return 0 end
    local avgTire = (dmg.tires.FL + dmg.tires.FR +
                     dmg.tires.RL + dmg.tires.RR) / 4
    local avgBody = (dmg.body.front + dmg.body.rear +
                     dmg.body.left  + dmg.body.right) / 4
    return 1 - (avgTire * 0.5 + avgBody * 0.3 + dmg.engine * 0.2)
end

-- Count how many tires are flat
function damage.flatTireCount(dmg)
    if not dmg then return 0 end
    local n = 0
    for _, v in pairs(dmg.flatTires) do
        if v then n = n + 1 end
    end
    return n
end

return damage
