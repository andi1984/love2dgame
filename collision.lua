-- Car-to-car collision detection (Separating Axis Theorem on OBBs)
-- and physics resolution (impulse-based)
-- Pure logic – no Love2D dependency

local collision = {}

-- Return the 4 corners of a car's oriented bounding box
local function getCorners(car)
    local hw  = car.width  / 2
    local hh  = car.height / 2
    local cos = math.cos(car.angle)
    local sin = math.sin(car.angle)
    -- front-right, front-left, rear-left, rear-right (local frame)
    return {
        { x = car.x + cos * hw - sin * hh,  y = car.y + sin * hw + cos * hh  },
        { x = car.x + cos * hw + sin * hh,  y = car.y + sin * hw - cos * hh  },
        { x = car.x - cos * hw + sin * hh,  y = car.y - sin * hw - cos * hh  },
        { x = car.x - cos * hw - sin * hh,  y = car.y - sin * hw + cos * hh  },
    }
end

-- Project corners onto axis, return min/max extents
local function project(corners, ax, ay)
    local mn, mx = math.huge, -math.huge
    for _, c in ipairs(corners) do
        local d = c.x * ax + c.y * ay
        if d < mn then mn = d end
        if d > mx then mx = d end
    end
    return mn, mx
end

-- SAT overlap test; returns (overlap, axis) or nil on no collision
local function satTest(c1, c2)
    local corners1 = getCorners(c1)
    local corners2 = getCorners(c2)
    -- Two axes from each rectangle's orientation
    local axes = {
        { x =  math.cos(c1.angle), y =  math.sin(c1.angle) },
        { x = -math.sin(c1.angle), y =  math.cos(c1.angle) },
        { x =  math.cos(c2.angle), y =  math.sin(c2.angle) },
        { x = -math.sin(c2.angle), y =  math.cos(c2.angle) },
    }
    local minOverlap = math.huge
    local minAxis    = nil
    for _, axis in ipairs(axes) do
        local mn1, mx1 = project(corners1, axis.x, axis.y)
        local mn2, mx2 = project(corners2, axis.x, axis.y)
        if mn1 > mx2 or mn2 > mx1 then
            return nil  -- separating axis found → no collision
        end
        local ov = math.min(mx1, mx2) - math.max(mn1, mn2)
        if ov < minOverlap then
            minOverlap = ov
            minAxis    = axis
        end
    end
    return minOverlap, minAxis
end

-- ----------------------------------------------------------------
-- Check every pair of cars for OBB overlaps
-- Returns a list of collision events: { car1, car2, idx1, idx2,
--                                       overlap, axisX, axisY }
-- ----------------------------------------------------------------
function collision.checkAll(cars)
    local events = {}
    for i = 1, #cars do
        for j = i + 1, #cars do
            local c1, c2 = cars[i], cars[j]
            -- Quick circle pre-check (broad phase)
            local dx   = c2.x - c1.x
            local dy   = c2.y - c1.y
            local dist2 = dx * dx + dy * dy
            local rSum  = (c1.width + c2.width) * 0.65
            if dist2 < rSum * rSum then
                local overlap, axis = satTest(c1, c2)
                if overlap and axis then
                    table.insert(events, {
                        car1   = c1,   car2   = c2,
                        idx1   = i,    idx2   = j,
                        overlap = overlap,
                        axisX  = axis.x,
                        axisY  = axis.y,
                    })
                end
            end
        end
    end
    return events
end

-- ----------------------------------------------------------------
-- Resolve one collision event:
--   1. Positional correction (push cars apart)
--   2. Impulse-based velocity change
-- Returns the impact speed (for damage calculation)
-- ----------------------------------------------------------------
function collision.resolve(event)
    local c1      = event.car1
    local c2      = event.car2
    local overlap = event.overlap
    local ax, ay  = event.axisX, event.axisY

    -- Make sure axis points from c1 toward c2
    local dx = c2.x - c1.x
    local dy = c2.y - c1.y
    if dx * ax + dy * ay < 0 then
        ax, ay = -ax, -ay
    end

    -- Positional correction: push each car half the overlap
    local push = (overlap + 0.5) * 0.5
    c1.x = c1.x - ax * push
    c1.y = c1.y - ay * push
    c2.x = c2.x + ax * push
    c2.y = c2.y + ay * push

    -- World-space velocity vectors
    local v1x = math.cos(c1.angle) * c1.speed
    local v1y = math.sin(c1.angle) * c1.speed
    local v2x = math.cos(c2.angle) * c2.speed
    local v2y = math.sin(c2.angle) * c2.speed

    -- Relative velocity along the collision normal
    local relVel = (v1x - v2x) * ax + (v1y - v2y) * ay
    local impactSpeed = math.abs(relVel)

    if relVel > 0 then
        -- Impulse exchange (equal mass approximation, coefficient of restitution)
        local e       = 0.28
        local impulse = (1 + e) * relVel / 2

        -- Project impulse onto each car's heading
        local dot1 = ax * math.cos(c1.angle) + ay * math.sin(c1.angle)
        local dot2 = ax * math.cos(c2.angle) + ay * math.sin(c2.angle)
        c1.speed = c1.speed - dot1 * impulse
        c2.speed = c2.speed + dot2 * impulse

        -- Small angular deflection for realism (off-axis hits spin the car)
        local cross   = ax * dy - ay * dx
        local deflect = math.max(-0.18, math.min(0.18, cross * 0.007))
        c1.angle = c1.angle + deflect * 0.3
        c2.angle = c2.angle - deflect * 0.3
    end

    return impactSpeed
end

return collision
