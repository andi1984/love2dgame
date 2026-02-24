-- AI sensor system and driving bridge (pure logic, no Love2D dependency)

local ai = {}

-- Normalize angle to [-pi, pi]
local function normalizeAngle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

-- Calculate curvature of track ahead (average angle change over a segment)
local function calculateCurvature(track, pct, lookAhead)
    local steps = 5
    local totalAngleChange = 0
    local prevAngle = nil
    for i = 0, steps do
        local samplePct = (pct + lookAhead * i / steps) % 1.0
        local p1 = track.getPointAtPercent(samplePct)
        local nextPct = (samplePct + 0.005) % 1.0
        local p2 = track.getPointAtPercent(nextPct)
        if p1 and p2 then
            local angle = math.atan2(p2.y - p1.y, p2.x - p1.x)
            if prevAngle then
                totalAngleChange = totalAngleChange + math.abs(normalizeAngle(angle - prevAngle))
            end
            prevAngle = angle
        end
    end
    -- Normalize to [-1, 1] based on direction of the overall curve
    local startPt = track.getPointAtPercent(pct)
    local endPt = track.getPointAtPercent((pct + lookAhead) % 1.0)
    local sign = 1
    if startPt and endPt then
        local startNextPct = (pct + 0.005) % 1.0
        local startNext = track.getPointAtPercent(startNextPct)
        if startNext then
            local fwd = math.atan2(startNext.y - startPt.y, startNext.x - startPt.x)
            local toEnd = math.atan2(endPt.y - startPt.y, endPt.x - startPt.x)
            sign = normalizeAngle(toEnd - fwd) > 0 and 1 or -1
        end
    end
    local avgChange = totalAngleChange / math.max(1, steps)
    return math.max(-1, math.min(1, avgChange / math.pi * sign))
end

-- Find signed distance from car to closest center point
local function signedDistToCenter(car, track)
    local minDist = math.huge
    local bestIdx = 1
    for i, p in ipairs(track.centerPath) do
        local dx = car.x - p.x
        local dy = car.y - p.y
        local dist = dx * dx + dy * dy
        if dist < minDist then
            minDist = dist
            bestIdx = i
        end
    end
    minDist = math.sqrt(minDist)

    -- Determine side using cross product with track tangent
    local n = #track.centerPath
    local prev = track.centerPath[((bestIdx - 2) % n) + 1]
    local next = track.centerPath[(bestIdx % n) + 1]
    local tx = next.x - prev.x
    local ty = next.y - prev.y
    local dx = car.x - track.centerPath[bestIdx].x
    local dy = car.y - track.centerPath[bestIdx].y
    local cross = tx * dy - ty * dx
    local side = cross > 0 and 1 or -1

    return minDist * side
end

-- Cast a ray from the car in a given direction and find distance to track edge
-- Returns normalized distance: 0 = at edge, 1 = far from edge (max range)
local function raycastToEdge(car, track, angleOffset)
    local maxDist = 120
    local step = 4
    local angle = car.angle + angleOffset
    local cosA = math.cos(angle)
    local sinA = math.sin(angle)
    local halfWidth = (track.width or 75) / 2

    -- Find starting nearest center index for efficient local search
    local bestIdx = 1
    local minD = math.huge
    for i, p in ipairs(track.centerPath) do
        local dx = car.x - p.x
        local dy = car.y - p.y
        local d = dx * dx + dy * dy
        if d < minD then minD = d; bestIdx = i end
    end

    local n = #track.centerPath
    local searchRadius = 25

    for dist = step, maxDist, step do
        local px = car.x + cosA * dist
        local py = car.y + sinA * dist

        -- Check screen bounds
        if px < 10 or px > 790 or py < 10 or py > 590 then
            return dist / maxDist
        end

        -- Search for nearest center point near last known index
        local localMin = math.huge
        local localBest = bestIdx
        for offset = -searchRadius, searchRadius do
            local idx = ((bestIdx - 1 + offset) % n) + 1
            local cp = track.centerPath[idx]
            local dx = px - cp.x
            local dy = py - cp.y
            local d = dx * dx + dy * dy
            if d < localMin then localMin = d; localBest = idx end
        end
        bestIdx = localBest

        if math.sqrt(localMin) > halfWidth then
            return dist / maxDist
        end
    end

    return 1.0
end

-- Calculate all 13 sensor inputs for a car on a track
-- Inputs 1-8: original sensors, inputs 9-13: raycast distances
function ai.getSensorInputs(car, track)
    local inputs = {}
    local pct = track.getTrackPercent(car.x, car.y)

    -- 1: Angle error to waypoint ~3% ahead
    local targetPct = (pct + 0.03) % 1.0
    local target = track.getPointAtPercent(targetPct)
    if target then
        local desiredAngle = math.atan2(target.y - car.y, target.x - car.x)
        inputs[1] = normalizeAngle(desiredAngle - car.angle) / math.pi
    else
        inputs[1] = 0
    end

    -- 2: Signed distance to center line, normalized by half track width
    local signedDist = signedDistToCenter(car, track)
    local halfWidth = (track.width or 75) / 2
    inputs[2] = math.max(-1, math.min(1, signedDist / halfWidth))

    -- 3: Speed ratio
    inputs[3] = car.speed / car.physics.maxSpeed

    -- 4: Upcoming curvature (~10% ahead)
    inputs[4] = calculateCurvature(track, pct, 0.10)

    -- 5: Near look-ahead angle (~5% ahead)
    local nearPct = (pct + 0.05) % 1.0
    local near = track.getPointAtPercent(nearPct)
    if near then
        local nearAngle = math.atan2(near.y - car.y, near.x - car.x)
        inputs[5] = normalizeAngle(nearAngle - car.angle) / math.pi
    else
        inputs[5] = 0
    end

    -- 6: Far look-ahead angle (~15% ahead)
    local farPct = (pct + 0.15) % 1.0
    local far = track.getPointAtPercent(farPct)
    if far then
        local farAngle = math.atan2(far.y - car.y, far.x - car.x)
        inputs[6] = normalizeAngle(farAngle - car.angle) / math.pi
    else
        inputs[6] = 0
    end

    -- 7: Surface grip ahead (~5%)
    local aheadZone = track.getSurfaceAt(near and near.x or car.x, near and near.y or car.y)
    inputs[7] = aheadZone and aheadZone.grip or 0.5

    -- 8: On-track flag
    inputs[8] = track.isOnTrack(car.x, car.y) and 1.0 or 0.0

    -- 9-13: Raycast distances to track edge (normalized 0-1)
    -- Left (-90°), Front-left (-45°), Front (0°), Front-right (+45°), Right (+90°)
    inputs[9]  = raycastToEdge(car, track, -math.pi / 2)
    inputs[10] = raycastToEdge(car, track, -math.pi / 4)
    inputs[11] = raycastToEdge(car, track, 0)
    inputs[12] = raycastToEdge(car, track, math.pi / 4)
    inputs[13] = raycastToEdge(car, track, math.pi / 2)

    return inputs
end

-- Convert network outputs [0,1] to game input with continuous steering
function ai.outputToInput(outputs)
    -- Continuous steering: difference between right and left outputs
    -- outputs[3] = left tendency, outputs[4] = right tendency
    local steer = (outputs[4] - outputs[3]) * 2  -- range [-2, 2], clamped in car
    steer = math.max(-1, math.min(1, steer))

    return {
        up = outputs[1] > 0.5,
        down = outputs[2] > 0.5,
        steer = steer,
    }
end

-- Add noise to sensor inputs based on personality error config
function ai.applySensorNoise(inputs, errors)
    if not errors or not errors.sensorNoise or errors.sensorNoise <= 0 then
        return inputs
    end
    local noisy = {}
    local mag = errors.sensorNoise
    for i, v in ipairs(inputs) do
        -- Box-Muller gaussian noise
        local u1 = math.max(1e-10, math.random())
        local u2 = math.random()
        local gaussian = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        noisy[i] = v + gaussian * mag
    end
    return noisy
end

-- Apply imperfections to the AI output: lapses, jitter, late braking
-- Returns the (possibly modified) input and updates car error state
function ai.applyErrors(car, input, dt)
    local errors = car.personality and car.personality.errors
    if not errors then return input end

    -- Lapse system: occasionally hold stale input (driver loses focus)
    if car.lapseTimer > 0 then
        car.lapseTimer = car.lapseTimer - dt
        if car.lastInput then
            return car.lastInput
        end
    else
        -- Roll for a new lapse
        local chance = (errors.lapseChance or 0) * dt
        if math.random() < chance then
            local minDur = errors.lapseDurationMin or 0.2
            local maxDur = errors.lapseDurationMax or 0.5
            car.lapseTimer = minDur + math.random() * (maxDur - minDur)
            car.lastInput = input
            return input  -- start of lapse: use current input, then freeze it
        end
    end

    -- Brake-late: occasionally ignore the brake signal
    local brakeLate = (errors.brakeLateChance or 0) * dt
    if input.down and math.random() < brakeLate then
        input = {
            up = input.up,
            down = false,
            steer = input.steer,
        }
    end

    -- Steering jitter: random wobble added to steer value
    local jitter = errors.steerJitter or 0
    if jitter > 0 then
        local u1 = math.max(1e-10, math.random())
        local u2 = math.random()
        local gaussian = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        input = {
            up = input.up,
            down = input.down,
            steer = math.max(-1, math.min(1, input.steer + gaussian * jitter)),
        }
    end

    -- Cache input for potential future lapse
    car.lastInput = input
    return input
end

-- Initialize per-race metrics on a car
function ai.initMetrics(car)
    car.timeOffTrack = 0
    car.timeStationary = 0
    car.avgSpeed = 0
    car.speedSamples = 0
    car.stuckTimer = 0
    car.stuckOverride = 0
    car.stuckSteerDir = 1

    -- Error state for imperfect driving
    car.lapseTimer = 0         -- countdown while in a lapse
    car.lastInput = nil        -- cached input from before the lapse
end

-- Update per-frame performance metrics and handle stuck detection
function ai.updateMetrics(car, dt, track)
    if not track.isOnTrack(car.x, car.y) then
        car.timeOffTrack = car.timeOffTrack + dt
    end
    if math.abs(car.speed) < 5 then
        car.timeStationary = car.timeStationary + dt
        car.stuckTimer = car.stuckTimer + dt
    else
        car.stuckTimer = 0
    end
    car.speedSamples = car.speedSamples + 1
    car.avgSpeed = car.avgSpeed + (math.abs(car.speed) - car.avgSpeed) / car.speedSamples

    -- Stuck override countdown
    if car.stuckOverride > 0 then
        car.stuckOverride = car.stuckOverride - dt
    end
end

-- Check if car is stuck and needs override input
function ai.getStuckOverride(car)
    if car.stuckTimer > 2 then
        car.stuckTimer = 0
        car.stuckOverride = 0.5
        car.stuckSteerDir = math.random() < 0.5 and -1 or 1
    end
    if car.stuckOverride > 0 then
        return {
            up = false,
            down = true,
            steer = car.stuckSteerDir,
        }
    end
    return nil
end

return ai
