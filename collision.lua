-- Car-to-car collision detection (Separating Axis Theorem on OBBs)
-- and physics resolution (impulse-based)
-- Pure logic – no Love2D dependency

local collision = {}
local cos, sin, abs, min, max = math.cos, math.sin, math.abs, math.min, math.max
local huge = math.huge

-- Return the 4 corners of a car's OBB plus the two unit axes (forward, right)
local function getCornersAndAxes(car)
    local hw  = car.width  / 2
    local hh  = car.height / 2
    local ca  = cos(car.angle)
    local sa  = sin(car.angle)
    local corners = {
        { x = car.x + ca * hw - sa * hh,  y = car.y + sa * hw + ca * hh  },
        { x = car.x + ca * hw + sa * hh,  y = car.y + sa * hw - ca * hh  },
        { x = car.x - ca * hw + sa * hh,  y = car.y - sa * hw - ca * hh  },
        { x = car.x - ca * hw - sa * hh,  y = car.y - sa * hw + ca * hh  },
    }
    return corners, ca, sa
end

-- Project corners onto axis, return min/max extents
local function project(corners, ax, ay)
    local mn, mx = huge, -huge
    for _, c in ipairs(corners) do
        local d = c.x * ax + c.y * ay
        if d < mn then mn = d end
        if d > mx then mx = d end
    end
    return mn, mx
end

-- SAT overlap test; returns (overlap, axis) or nil on no collision
local function satTest(c1, c2)
    local corners1, ca1, sa1 = getCornersAndAxes(c1)
    local corners2, ca2, sa2 = getCornersAndAxes(c2)
    -- Two axes from each rectangle's orientation (reuse cos/sin from corners)
    local axes = {
        { x =  ca1, y =  sa1 },
        { x = -sa1, y =  ca1 },
        { x =  ca2, y =  sa2 },
        { x = -sa2, y =  ca2 },
    }
    local minOverlap = huge
    local minAxis    = nil
    for _, axis in ipairs(axes) do
        local mn1, mx1 = project(corners1, axis.x, axis.y)
        local mn2, mx2 = project(corners2, axis.x, axis.y)
        if mn1 > mx2 or mn2 > mx1 then
            return nil  -- separating axis found → no collision
        end
        local ov = min(mx1, mx2) - max(mn1, mn2)
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
    local v1x = cos(c1.angle) * c1.speed
    local v1y = sin(c1.angle) * c1.speed
    local v2x = cos(c2.angle) * c2.speed
    local v2y = sin(c2.angle) * c2.speed

    -- Relative velocity along the collision normal
    local relVel = (v1x - v2x) * ax + (v1y - v2y) * ay
    local impactSpeed = abs(relVel)

    if relVel > 0 then
        -- Impulse exchange (equal mass approximation, coefficient of restitution)
        local e       = 0.28
        local impulse = (1 + e) * relVel / 2

        -- Project impulse onto each car's heading
        local dot1 = ax * cos(c1.angle) + ay * sin(c1.angle)
        local dot2 = ax * cos(c2.angle) + ay * sin(c2.angle)
        c1.speed = c1.speed - dot1 * impulse
        c2.speed = c2.speed + dot2 * impulse

        -- Small angular deflection for realism (off-axis hits spin the car)
        local cross   = ax * dy - ay * dx
        local deflect = max(-0.18, min(0.18, cross * 0.007))
        c1.angle = c1.angle + deflect * 0.3
        c2.angle = c2.angle - deflect * 0.3
    end

    return impactSpeed
end

return collision
