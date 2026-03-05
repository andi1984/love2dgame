-- Procedural track generation (pure Lua, no Love2D dependency)
-- Generates realistic racing circuits from a seed value

local trackgen = {}
local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local cos, sin, atan2 = math.cos, math.sin, math.atan2
local huge, pi = math.huge, math.pi

-- ============================================================
-- SEEDED PRNG (Multiplicative congruential, Lua 5.1 / LuaJIT safe)
-- ============================================================

local function makeRng(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local rng = {}
    function rng:next()
        s = (s * 48271) % 2147483647
        return s / 2147483647
    end
    -- Return float in [lo, hi]
    function rng:range(lo, hi)
        return lo + self:next() * (hi - lo)
    end
    -- Return integer in [lo, hi]
    function rng:int(lo, hi)
        return floor(self:range(lo, hi + 0.999))
    end
    -- Pick random element from array
    function rng:pick(arr)
        return arr[self:int(1, #arr)]
    end
    return rng
end

-- ============================================================
-- GEOMETRY HELPERS
-- ============================================================

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Check if two line segments (p1-p2) and (p3-p4) intersect
local function segmentsIntersect(p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
    local d1x, d1y = p2x - p1x, p2y - p1y
    local d2x, d2y = p4x - p3x, p4y - p3y
    local cross = d1x * d2y - d1y * d2x
    if abs(cross) < 1e-10 then return false end
    local dx, dy = p3x - p1x, p3y - p1y
    local t = (dx * d2y - dy * d2x) / cross
    local u = (dx * d1y - dy * d1x) / cross
    return t > 0 and t < 1 and u > 0 and u < 1
end

local spline = require("spline")
local catmullRom = spline.catmullRom

-- Generate a spline path from control points (low or high resolution)
local function generateSpline(points, segsPerCurve)
    local path = {}
    local n = #points
    for i = 1, n do
        local p0 = points[((i - 2) % n) + 1]
        local p1 = points[((i - 1) % n) + 1]
        local p2 = points[(i % n) + 1]
        local p3 = points[((i + 1) % n) + 1]
        for j = 0, segsPerCurve - 1 do
            local t = j / segsPerCurve
            table.insert(path, catmullRom(p0, p1, p2, p3, t))
        end
    end
    return path
end

-- ============================================================
-- SELF-INTERSECTION VALIDATION
-- ============================================================

function trackgen.validatePoints(points, width)
    -- Generate low-res spline and check for self-intersection
    local path = generateSpline(points, 10)
    local n = #path
    local halfW = (width or 60) / 2

    -- Build offset paths (inner/outer) for width-aware check
    local function getNormal(idx)
        local prev = path[((idx - 2) % n) + 1]
        local nextPt = path[(idx % n) + 1]
        local dx, dy = nextPt.x - prev.x, nextPt.y - prev.y
        local len = sqrt(dx * dx + dy * dy)
        if len < 1e-8 then return 0, -1 end
        return -dy / len, dx / len
    end

    -- Check centerline self-intersection (skip adjacent + near-adjacent segments)
    local skip = 3  -- skip this many neighbors to avoid false positives at curves
    for i = 1, n do
        local i2 = (i % n) + 1
        for j = i + skip, n do
            local j2 = (j % n) + 1
            -- Also skip if j2 wraps to near i
            local wrapDist = min(abs(j2 - i), n - abs(j2 - i))
            if wrapDist >= skip then
                if segmentsIntersect(
                    path[i].x, path[i].y, path[i2].x, path[i2].y,
                    path[j].x, path[j].y, path[j2].x, path[j2].y
                ) then
                    return false
                end
            end
        end
    end

    -- Also check that no two non-adjacent track edges overlap
    -- Build outer path and check for self-intersection
    local outer = {}
    for i = 1, n do
        local nx, ny = getNormal(i)
        outer[i] = {x = path[i].x + nx * halfW, y = path[i].y + ny * halfW}
    end
    for i = 1, n do
        local i2 = (i % n) + 1
        for j = i + skip, n do
            local j2 = (j % n) + 1
            local wrapDist = min(abs(j2 - i), n - abs(j2 - i))
            if wrapDist >= skip then
                if segmentsIntersect(
                    outer[i].x, outer[i].y, outer[i2].x, outer[i2].y,
                    outer[j].x, outer[j].y, outer[j2].x, outer[j2].y
                ) then
                    return false
                end
            end
        end
    end

    return true
end

-- ============================================================
-- NAME GENERATION
-- ============================================================

local ADJECTIVES = {
    "Alpine", "Coastal", "Grand", "Silver", "Thunder",
    "Golden", "Crystal", "Shadow", "Sunset", "Iron",
    "Royal", "Emerald", "Storm", "Crimson", "Sapphire",
    "Northern", "Southern", "Desert", "Misty", "Autumn",
}

local NOUNS = {
    "Circuit", "Speedway", "Ring", "Rally", "Raceway",
    "Loop", "Run", "Prix", "Course", "Track",
}

local function generateName(rng)
    return rng:pick(ADJECTIVES) .. " " .. rng:pick(NOUNS)
end

-- ============================================================
-- SURFACE ZONE GENERATION
-- ============================================================

local ZONE_TEMPLATES = {
    smooth = { grip = {0.92, 0.98}, bump = {0.02, 0.08}, names = {"Smooth Tarmac", "Racing Line", "Fresh Asphalt"}, color = {0.5, 0.5, 0.5, 0.0} },
    worn   = { grip = {0.78, 0.88}, bump = {0.10, 0.25}, names = {"Worn Patch", "Patched Road", "Aged Tarmac"}, color = {0.55, 0.45, 0.35, 0.06} },
    bumpy  = { grip = {0.80, 0.90}, bump = {0.30, 0.60}, names = {"Bumpy Section", "Rough Road", "Cobblestone"}, color = {0.4, 0.35, 0.3, 0.07} },
    wet    = { grip = {0.55, 0.72}, bump = {0.05, 0.15}, names = {"Damp Corner", "Wet Section", "Puddle Zone"}, color = {0.2, 0.3, 0.6, 0.08} },
    gravel = { grip = {0.60, 0.75}, bump = {0.20, 0.45}, names = {"Gravel Patch", "Sandy Stretch", "Loose Surface"}, color = {0.6, 0.5, 0.4, 0.09} },
}

local function generateSurfaceZones(rng, curvatures)
    local numZones = rng:int(4, 7)
    local zones = {}

    -- Divide track into zones
    for i = 1, numZones do
        local startPct = (i - 1) / numZones
        local endPct = i / numZones

        -- Determine zone character from average curvature in this segment
        local avgCurv = 0
        local samples = 0
        if curvatures then
            local startIdx = max(1, floor(startPct * #curvatures))
            local endIdx = min(#curvatures, floor(endPct * #curvatures))
            for j = startIdx, endIdx do
                avgCurv = avgCurv + (curvatures[j] or 0)
                samples = samples + 1
            end
            if samples > 0 then avgCurv = avgCurv / samples end
        end

        -- Pick zone template based on curvature + randomness
        local roll = rng:next()
        local template
        if avgCurv > 0.15 then
            -- High curvature: more likely wet/bumpy
            if roll < 0.35 then template = ZONE_TEMPLATES.wet
            elseif roll < 0.60 then template = ZONE_TEMPLATES.bumpy
            elseif roll < 0.80 then template = ZONE_TEMPLATES.worn
            else template = ZONE_TEMPLATES.smooth end
        elseif avgCurv > 0.06 then
            -- Medium curvature
            if roll < 0.15 then template = ZONE_TEMPLATES.wet
            elseif roll < 0.35 then template = ZONE_TEMPLATES.worn
            elseif roll < 0.50 then template = ZONE_TEMPLATES.gravel
            else template = ZONE_TEMPLATES.smooth end
        else
            -- Low curvature: smooth straights
            if roll < 0.10 then template = ZONE_TEMPLATES.gravel
            elseif roll < 0.25 then template = ZONE_TEMPLATES.worn
            else template = ZONE_TEMPLATES.smooth end
        end

        local grip = rng:range(template.grip[1], template.grip[2])
        local bumpiness = rng:range(template.bump[1], template.bump[2])
        local name = rng:pick(template.names)

        table.insert(zones, {
            startPct = startPct,
            endPct = endPct,
            grip = grip,
            bumpiness = bumpiness,
            name = name,
            color = {template.color[1], template.color[2], template.color[3], template.color[4]},
        })
    end

    -- Ensure first starts at 0 and last ends at 1
    zones[1].startPct = 0.0
    zones[#zones].endPct = 1.0

    return zones
end

-- ============================================================
-- CURVATURE ANALYSIS
-- ============================================================

local function computeCurvatures(path)
    local n = #path
    local curvatures = {}
    for i = 1, n do
        local prev = path[((i - 2) % n) + 1]
        local curr = path[i]
        local nextPt = path[(i % n) + 1]
        local dx1, dy1 = curr.x - prev.x, curr.y - prev.y
        local dx2, dy2 = nextPt.x - curr.x, nextPt.y - curr.y
        local a1 = atan2(dy1, dx1)
        local a2 = atan2(dy2, dx2)
        local diff = a2 - a1
        -- Normalize to [-pi, pi]
        while diff > pi do diff = diff - 2 * pi end
        while diff < -pi do diff = diff + 2 * pi end
        curvatures[i] = abs(diff)
    end
    return curvatures
end

-- ============================================================
-- TRACK GENERATION
-- ============================================================

local STYLE_NAMES = {"power", "technical", "flowing"}
local STYLE_DESCRIPTIONS = {
    power = "High-speed sweeping curves",
    technical = "Tight technical corners",
    flowing = "Smooth flowing layout",
}

function trackgen.generate(seed, attempt)
    seed = seed or os.time()
    attempt = attempt or 1
    local rng = makeRng(seed)

    -- 1b. Choose meta-parameters
    local numAnchors = rng:int(8, 14)
    local baseWidth = rng:range(55, 85)
    local style = rng:pick(STYLE_NAMES)

    -- 1c. Generate base polygon (deformed ellipse)
    local aspectRatio = rng:range(0.65, 1.0)
    local baseRadiusX = 280
    local baseRadiusY = baseRadiusX * aspectRatio

    local anchors = {}
    local angles = {}
    for i = 1, numAnchors do
        local baseAngle = (i - 1) / numAnchors * 2 * pi
        local jitter = rng:range(-0.3, 0.3) / numAnchors * 2 * pi
        angles[i] = baseAngle + jitter
    end
    -- Sort angles to maintain consistent winding
    table.sort(angles)

    for i = 1, numAnchors do
        local angle = angles[i]
        local radiusMult = rng:range(0.75, 1.25)
        local rx = baseRadiusX * radiusMult
        local ry = baseRadiusY * radiusMult
        anchors[i] = {
            x = cos(angle) * rx,
            y = sin(angle) * ry,
        }
    end

    -- 1d. Feature injection between anchor pairs
    local maxFeatures
    if style == "power" then maxFeatures = rng:int(0, 1)
    elseif style == "technical" then maxFeatures = rng:int(2, 4)
    else maxFeatures = rng:int(1, 2) end

    maxFeatures = min(maxFeatures, floor(numAnchors / 3))

    local featureSegments = {} -- set of indices where features are injected
    local points = {}

    -- Decide which segments get features (no two adjacent, skip first segment)
    local candidates = {}
    for i = 2, numAnchors do
        candidates[#candidates + 1] = i
    end
    -- Shuffle candidates
    for i = #candidates, 2, -1 do
        local j = rng:int(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local featureCount = 0
    for _, idx in ipairs(candidates) do
        if featureCount >= maxFeatures then break end
        -- Check no adjacent feature
        local adjacent = false
        for seg in pairs(featureSegments) do
            if abs(seg - idx) <= 1 then adjacent = true; break end
        end
        if not adjacent then
            featureSegments[idx] = true
            featureCount = featureCount + 1
        end
    end

    -- Build final point list with features inserted
    for i = 1, numAnchors do
        table.insert(points, {x = anchors[i].x, y = anchors[i].y})

        if featureSegments[i] then
            local nextIdx = (i % numAnchors) + 1
            local ax, ay = anchors[i].x, anchors[i].y
            local bx, by = anchors[nextIdx].x, anchors[nextIdx].y
            local mx, my = (ax + bx) / 2, (ay + by) / 2
            -- Perpendicular direction
            local dx, dy = bx - ax, by - ay
            local len = sqrt(dx * dx + dy * dy)
            if len < 1e-6 then len = 1 end
            local nx, ny = -dy / len, dx / len

            local featureType = rng:int(1, 3)
            local offset = rng:range(30, 80)

            if featureType == 1 then
                -- Chicane: 2 points with opposite offsets (S-bend)
                local t1, t2 = 0.33, 0.67
                local p1x = lerp(ax, bx, t1) + nx * offset
                local p1y = lerp(ay, by, t1) + ny * offset
                local p2x = lerp(ax, bx, t2) - nx * offset
                local p2y = lerp(ay, by, t2) - ny * offset
                table.insert(points, {x = p1x, y = p1y})
                table.insert(points, {x = p2x, y = p2y})
            elseif featureType == 2 then
                -- Hairpin: 1 point pulled toward center
                local pullX = mx + nx * offset * rng:range(0.5, 1.5)
                local pullY = my + ny * offset * rng:range(0.5, 1.5)
                table.insert(points, {x = pullX, y = pullY})
            else
                -- Esses: 3 points with alternating offsets
                local t1, t2, t3 = 0.25, 0.50, 0.75
                local scale = offset * 0.6
                table.insert(points, {x = lerp(ax, bx, t1) + nx * scale, y = lerp(ay, by, t1) + ny * scale})
                table.insert(points, {x = lerp(ax, bx, t2) - nx * scale, y = lerp(ay, by, t2) - ny * scale})
                table.insert(points, {x = lerp(ax, bx, t3) + nx * scale * 0.7, y = lerp(ay, by, t3) + ny * scale * 0.7})
            end
        end
    end

    -- 1e. Fit to viewport (800x600 with margin)
    local margin = baseWidth / 2 + 25
    local minX, maxX, minY, maxY = huge, -huge, huge, -huge
    for _, p in ipairs(points) do
        if p.x < minX then minX = p.x end
        if p.x > maxX then maxX = p.x end
        if p.y < minY then minY = p.y end
        if p.y > maxY then maxY = p.y end
    end

    local rangeX = maxX - minX
    local rangeY = maxY - minY
    if rangeX < 1 then rangeX = 1 end
    if rangeY < 1 then rangeY = 1 end

    local scaleX = (800 - 2 * margin) / rangeX
    local scaleY = (600 - 2 * margin) / rangeY
    local scale = min(scaleX, scaleY)

    local cx = (minX + maxX) / 2
    local cy = (minY + maxY) / 2

    for _, p in ipairs(points) do
        p.x = 400 + (p.x - cx) * scale
        p.y = 300 + (p.y - cy) * scale
    end

    -- 1f. Self-intersection validation
    if not trackgen.validatePoints(points, baseWidth) then
        -- Retry with next seed (up to 5 attempts)
        if attempt < 5 then
            return trackgen.generate(seed + 1, attempt + 1)
        end
    end

    -- 1g. Compute startAngle from tangent at first control point
    local n = #points
    local prevP = points[n]
    local nextP = points[2]
    local tdx = nextP.x - prevP.x
    local tdy = nextP.y - prevP.y
    local startAngle = atan2(tdy, tdx)

    -- 1h. Compute curvatures for surface zone generation
    local splinePath = generateSpline(points, 10)
    local curvatures = computeCurvatures(splinePath)

    -- Generate surface zones
    local surfaceZones = generateSurfaceZones(rng, curvatures)

    -- 1i. Generate track name
    local name = generateName(rng)

    -- Generate description
    local description = STYLE_DESCRIPTIONS[style] or "A generated circuit"

    -- Generate a unique-ish ID from seed
    local id = "gen_" .. seed

    return {
        id = id,
        name = name,
        description = description,
        width = floor(baseWidth),
        points = points,
        startAngle = startAngle,
        surfaceZones = surfaceZones,
        seed = seed,
        generated = true,
    }
end

return trackgen
