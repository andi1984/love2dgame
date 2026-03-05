-- Track geometry, surface zones, curbs, and trees (pure logic, no Love2D dependency)
-- Now supports spline-based tracks from configuration

local track = {}
local sqrt, floor, atan2, max = math.sqrt, math.floor, math.atan2, math.max
local huge, pi = math.huge, math.pi

-- Local seeded PRNG to avoid corrupting global math.random state
local function makeRng(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local rng = {}
    function rng:next()
        s = (s * 48271) % 2147483647
        return s / 2147483647
    end
    function rng:range(lo, hi)
        return lo + self:next() * (hi - lo)
    end
    function rng:int(lo, hi)
        return floor(self:range(lo, hi + 0.999))
    end
    return rng
end

local spline = require("spline")
local catmullRom = spline.catmullRom

-- Generate smooth path from control points using Catmull-Rom spline
local function generateSplinePath(controlPoints, segmentsPerCurve)
    segmentsPerCurve = segmentsPerCurve or 20
    local path = {}
    local n = #controlPoints
    
    for i = 1, n do
        local p0 = controlPoints[((i - 2) % n) + 1]
        local p1 = controlPoints[((i - 1) % n) + 1]
        local p2 = controlPoints[(i % n) + 1]
        local p3 = controlPoints[((i + 1) % n) + 1]
        
        for j = 0, segmentsPerCurve - 1 do
            local t = j / segmentsPerCurve
            local point = catmullRom(p0, p1, p2, p3, t)
            table.insert(path, point)
        end
    end
    
    return path
end

-- Calculate path length and cumulative distances
local function calculatePathMetrics(path)
    local totalLength = 0
    local cumulative = {0}
    
    for i = 2, #path do
        local dx = path[i].x - path[i-1].x
        local dy = path[i].y - path[i-1].y
        totalLength = totalLength + sqrt(dx * dx + dy * dy)
        cumulative[i] = totalLength
    end
    
    -- Close the loop
    local dx = path[1].x - path[#path].x
    local dy = path[1].y - path[#path].y
    totalLength = totalLength + sqrt(dx * dx + dy * dy)
    
    return totalLength, cumulative
end

-- Get point at a specific percentage along the path
local function getPointAtPercent(path, cumulative, totalLength, pct)
    local targetDist = pct * totalLength
    
    for i = 2, #path do
        if cumulative[i] >= targetDist then
            local prevDist = cumulative[i-1]
            local segmentLength = cumulative[i] - prevDist
            local t = (targetDist - prevDist) / segmentLength
            
            return {
                x = path[i-1].x + t * (path[i].x - path[i-1].x),
                y = path[i-1].y + t * (path[i].y - path[i-1].y)
            }
        end
    end
    
    return path[#path]
end

-- Get tangent direction at a path index
local function getTangent(path, index)
    local n = #path
    local prev = path[((index - 2) % n) + 1]
    local nextPt = path[(index % n) + 1]

    local dx = nextPt.x - prev.x
    local dy = nextPt.y - prev.y
    local len = sqrt(dx * dx + dy * dy)
    
    if len > 0 then
        return dx / len, dy / len
    end
    return 1, 0
end

local function generateCurbs()
    track.outerCurbs = {}
    track.innerCurbs = {}

    local step = max(1, floor(#track.centerPath / 80))
    local index = 0

    for i = 1, #track.centerPath, step do
        local outer = track.outerPath[i]
        local inner = track.innerPath[i]
        local tx, ty = getTangent(track.centerPath, i)
        local angle = atan2(ty, tx)

        table.insert(track.outerCurbs, { x = outer.x, y = outer.y, angle = angle, index = index })
        table.insert(track.innerCurbs, { x = inner.x, y = inner.y, angle = angle, index = index })
        index = index + 1
    end
end

local function generateTrees()
    track.trees = {}
    local rng = makeRng(77)

    -- Generate trees around the track
    for _ = 1, 25 do
        local attempts = 0
        while attempts < 50 do
            local x = rng:int(20, 780)
            local y = rng:int(20, 580)

            -- Check if far enough from track
            local minDist = huge
            for _, p in ipairs(track.centerPath) do
                local dx = x - p.x
                local dy = y - p.y
                local dist = sqrt(dx * dx + dy * dy)
                if dist < minDist then
                    minDist = dist
                end
            end

            -- Place tree if it's off the track
            if minDist > track.width / 2 + 15 then
                table.insert(track.trees, {
                    x = x, y = y,
                    trunkH = 6 + rng:next() * 4,
                    canopyR = 8 + rng:next() * 7,
                    green = 0.3 + rng:next() * 0.3,
                    shade = 0.1 + rng:next() * 0.1
                })
                break
            end
            attempts = attempts + 1
        end
    end
end

local function generateSurfaceZones(zoneConfigs)
    track.surfaceZones = {}

    if zoneConfigs then
        for _, z in ipairs(zoneConfigs) do
            table.insert(track.surfaceZones, {
                startPct = z.startPct,
                endPct = z.endPct,
                grip = z.grip,
                bumpiness = z.bumpiness,
                name = z.name,
                color = z.color or {0.5, 0.5, 0.5, 0.0}
            })
        end
    else
        -- Default zones
        table.insert(track.surfaceZones, {
            startPct = 0.0, endPct = 1.0,
            grip = 0.95, bumpiness = 0.05,
            name = "Smooth Tarmac",
            color = {0.5, 0.5, 0.5, 0.0}
        })
    end
end

-- Initialize track from a configuration
function track.initFromConfig(config)
    track.config = config
    track.name = config.name
    track.width = config.width
    
    -- Generate the center line path
    track.centerPath = generateSplinePath(config.points, 25)
    track.pathLength, track.cumulative = calculatePathMetrics(track.centerPath)
    
    -- Generate inner and outer boundaries
    track.innerPath = {}
    track.outerPath = {}
    local halfWidth = config.width / 2
    
    for i, p in ipairs(track.centerPath) do
        local tx, ty = getTangent(track.centerPath, i)
        -- Normal is perpendicular to tangent
        local nx, ny = -ty, tx
        
        table.insert(track.innerPath, {
            x = p.x + nx * halfWidth,
            y = p.y + ny * halfWidth
        })
        table.insert(track.outerPath, {
            x = p.x - nx * halfWidth,
            y = p.y - ny * halfWidth
        })
    end
    
    -- Set up finish line at the start of the track
    local startPoint = track.centerPath[1]
    local tx, ty = getTangent(track.centerPath, 1)
    local nx, ny = -ty, tx
    
    track.finishX = startPoint.x
    track.finishY1 = startPoint.y + ny * halfWidth
    track.finishY2 = startPoint.y - ny * halfWidth
    track.finishAngle = atan2(ty, tx)

    -- Finish line as proper 2D geometry for direction-independent crossing detection
    track.finishPoint = { x = startPoint.x, y = startPoint.y }
    track.finishForward = { x = tx, y = ty }  -- track tangent = forward direction
    track.finishP1 = { x = startPoint.x + nx * halfWidth, y = startPoint.y + ny * halfWidth }
    track.finishP2 = { x = startPoint.x - nx * halfWidth, y = startPoint.y - ny * halfWidth }
    
    -- For compatibility: approximate center for trees
    local sumX, sumY = 0, 0
    for _, p in ipairs(config.points) do
        sumX = sumX + p.x
        sumY = sumY + p.y
    end
    track.cx = sumX / #config.points
    track.cy = sumY / #config.points
    
    -- Generate curbs, trees, and surface zones
    generateCurbs()
    generateTrees()
    generateSurfaceZones(config.surfaceZones)
    
    -- Store start position and angle for car init
    track.startX = startPoint.x
    track.startY = startPoint.y
    track.startAngle = config.startAngle or track.finishAngle
end

-- Legacy init for backward compatibility (creates oval track)
function track.init()
    local defaultConfig = {
        name = "Classic Oval",
        width = 75,
        points = {
            {x = 400, y = 50},
            {x = 700, y = 150},
            {x = 750, y = 300},
            {x = 700, y = 450},
            {x = 400, y = 550},
            {x = 100, y = 450},
            {x = 50, y = 300},
            {x = 100, y = 150},
        },
        startAngle = 0,
        surfaceZones = {
            { startPct = 0.0,  endPct = 0.15, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.15, endPct = 0.30, grip = 0.7,  bumpiness = 0.3,  name = "Worn Patch",    color = {0.6, 0.4, 0.2, 0.08} },
            { startPct = 0.30, endPct = 0.50, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.50, endPct = 0.65, grip = 0.85, bumpiness = 0.6,  name = "Bumpy Section", color = {0.4, 0.35, 0.3, 0.06} },
            { startPct = 0.65, endPct = 0.80, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.80, endPct = 1.0,  grip = 0.6,  bumpiness = 0.1,  name = "Damp Corner",   color = {0.2, 0.3, 0.7, 0.07} },
        },
    }
    track.initFromConfig(defaultConfig)
end

-- Check if a point is on the track (squared distance comparison, no sqrt)
function track.isOnTrack(x, y)
    local minDistSq = huge

    for _, p in ipairs(track.centerPath) do
        local dx = x - p.x
        local dy = y - p.y
        local distSq = dx * dx + dy * dy
        if distSq < minDistSq then
            minDistSq = distSq
        end
    end

    local halfWidth = track.width / 2
    return minDistSq <= halfWidth * halfWidth
end

-- Get the percentage along the track for a given position (squared distance, no sqrt)
function track.getTrackPercent(x, y)
    local minDistSq = huge
    local bestIndex = 1

    for i, p in ipairs(track.centerPath) do
        local dx = x - p.x
        local dy = y - p.y
        local distSq = dx * dx + dy * dy
        if distSq < minDistSq then
            minDistSq = distSq
            bestIndex = i
        end
    end

    return track.cumulative[bestIndex] / track.pathLength
end

function track.getSurfaceAt(x, y)
    local pct = track.getTrackPercent(x, y)
    
    for _, zone in ipairs(track.surfaceZones) do
        if pct >= zone.startPct and pct < zone.endPct then
            return zone
        end
    end
    
    return track.surfaceZones[1]
end

-- Get a point at a specific percentage along the track (0.0 to 1.0)
function track.getPointAtPercent(pct)
    return getPointAtPercent(track.centerPath, track.cumulative, track.pathLength, pct)
end

-- Get approximate track circumference (for stats)
function track.getCircumference()
    return track.pathLength
end

return track
