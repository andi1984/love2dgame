-- Track geometry, surface zones, curbs, and trees (pure logic, no Love2D dependency)

local track = {}

function track.init()
    track.cx = 400
    track.cy = 300
    track.outerRx = 350
    track.outerRy = 250
    track.innerRx = 200
    track.innerRy = 120

    track.midRx = (track.outerRx + track.innerRx) / 2
    track.midRy = (track.outerRy + track.innerRy) / 2

    track.finishX = track.cx
    track.finishY1 = track.cy - track.innerRy
    track.finishY2 = track.cy - track.outerRy

    track.generateCurbs()
    track.generateTrees()
    track.generateSurfaceZones()
end

function track.isOnTrack(x, y)
    local dx = x - track.cx
    local dy = y - track.cy
    local outerDist = (dx / track.outerRx)^2 + (dy / track.outerRy)^2
    local innerDist = (dx / track.innerRx)^2 + (dy / track.innerRy)^2
    return outerDist <= 1 and innerDist >= 1
end

function track.getSurfaceAt(x, y)
    local dx = x - track.cx
    local dy = y - track.cy
    local angle = math.atan2(dy, dx)
    if angle < 0 then angle = angle + math.pi * 2 end
    for _, zone in ipairs(track.surfaceZones) do
        if angle >= zone.angleStart and angle < zone.angleEnd then
            return zone
        end
    end
    return track.surfaceZones[1]
end

function track.generateCurbs()
    track.outerCurbs = {}
    track.innerCurbs = {}
    local numSegments = 80
    for i = 0, numSegments - 1 do
        local angle = (i / numSegments) * math.pi * 2
        local nextAngle = ((i + 1) / numSegments) * math.pi * 2
        local midAngle = (angle + nextAngle) / 2

        local ox = track.cx + math.cos(midAngle) * track.outerRx
        local oy = track.cy + math.sin(midAngle) * track.outerRy
        table.insert(track.outerCurbs, { x = ox, y = oy, angle = midAngle, index = i })

        local ix = track.cx + math.cos(midAngle) * track.innerRx
        local iy = track.cy + math.sin(midAngle) * track.innerRy
        table.insert(track.innerCurbs, { x = ix, y = iy, angle = midAngle, index = i })
    end
end

function track.generateTrees()
    track.trees = {}
    math.randomseed(77)

    for _ = 1, 15 do
        local attempts = 0
        while attempts < 50 do
            local angle = math.random() * math.pi * 2
            local rx = math.random() * (track.innerRx - 30)
            local ry = math.random() * (track.innerRy - 25)
            local x = track.cx + math.cos(angle) * rx
            local y = track.cy + math.sin(angle) * ry
            local dx = x - track.cx
            local dy = y - track.cy
            local dist = (dx / (track.innerRx - 20))^2 + (dy / (track.innerRy - 15))^2
            if dist < 0.85 then
                table.insert(track.trees, {
                    x = x, y = y,
                    trunkH = 6 + math.random() * 4,
                    canopyR = 8 + math.random() * 7,
                    green = 0.3 + math.random() * 0.3,
                    shade = 0.1 + math.random() * 0.1
                })
                break
            end
            attempts = attempts + 1
        end
    end

    for _ = 1, 10 do
        local attempts = 0
        while attempts < 50 do
            local angle = math.random() * math.pi * 2
            local factor = 1.08 + math.random() * 0.25
            local x = track.cx + math.cos(angle) * track.outerRx * factor
            local y = track.cy + math.sin(angle) * track.outerRy * factor
            if x > 15 and x < 785 and y > 15 and y < 585 then
                table.insert(track.trees, {
                    x = x, y = y,
                    trunkH = 6 + math.random() * 5,
                    canopyR = 8 + math.random() * 8,
                    green = 0.3 + math.random() * 0.3,
                    shade = 0.1 + math.random() * 0.1
                })
                break
            end
            attempts = attempts + 1
        end
    end

    math.randomseed(os.time())
end

function track.generateSurfaceZones()
    track.surfaceZones = {
        { angleStart = 0,              angleEnd = math.pi * 0.3,  grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac",   color = {0.5, 0.5, 0.5, 0.0} },
        { angleStart = math.pi * 0.3,  angleEnd = math.pi * 0.55, grip = 0.7,  bumpiness = 0.3,  name = "Worn Patch",      color = {0.6, 0.4, 0.2, 0.08} },
        { angleStart = math.pi * 0.55, angleEnd = math.pi * 0.85, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac",   color = {0.5, 0.5, 0.5, 0.0} },
        { angleStart = math.pi * 0.85, angleEnd = math.pi * 1.1,  grip = 0.85, bumpiness = 0.6,  name = "Bumpy Section",   color = {0.4, 0.35, 0.3, 0.06} },
        { angleStart = math.pi * 1.1,  angleEnd = math.pi * 1.4,  grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac",   color = {0.5, 0.5, 0.5, 0.0} },
        { angleStart = math.pi * 1.4,  angleEnd = math.pi * 1.65, grip = 0.6,  bumpiness = 0.1,  name = "Damp Corner",     color = {0.2, 0.3, 0.7, 0.07} },
        { angleStart = math.pi * 1.65, angleEnd = math.pi * 1.9,  grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac",   color = {0.5, 0.5, 0.5, 0.0} },
        { angleStart = math.pi * 1.9,  angleEnd = math.pi * 2.0,  grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac",   color = {0.5, 0.5, 0.5, 0.0} },
    }
end

return track
