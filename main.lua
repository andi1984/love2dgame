-- Love2D Racing Game — Graphics Overhaul

local car = {}
local track = {}
local game = {}
local particles = {}
local trees = {}
local fonts = {}
local physics = {}
local surfaceZones = {}
local devMenu = {}

-- Pre-rendered canvases
local grassCanvas
local trackCanvas

function love.load()
    love.window.setTitle("Racing Game")
    love.window.setMode(800, 600)

    -- Fonts (create once)
    fonts.hud = love.graphics.newFont(14)
    fonts.hudBig = love.graphics.newFont(18)
    fonts.countdown = love.graphics.newFont(72)
    fonts.countdownSmall = love.graphics.newFont(36)
    fonts.win = love.graphics.newFont(48)
    fonts.winSub = love.graphics.newFont(20)

    -- Track: oval defined by center + inner/outer radii
    track.cx = 400
    track.cy = 300
    track.outerRx = 350
    track.outerRy = 250
    track.innerRx = 200
    track.innerRy = 120

    -- Mid-track radii (for center line)
    track.midRx = (track.outerRx + track.innerRx) / 2
    track.midRy = (track.outerRy + track.innerRy) / 2

    -- Finish line at top of track
    track.finishX = track.cx
    track.finishY1 = track.cy - track.innerRy
    track.finishY2 = track.cy - track.outerRy

    -- Car starts at top of track, facing right (clockwise)
    car.x = track.cx
    car.y = track.cy - (track.innerRy + track.outerRy) / 2
    car.angle = 0
    car.speed = 0
    car.width = 28
    car.height = 14
    car.prevSpeed = 0
    car.turning = false

    -- Physics
    physics.mass = 800           -- kg (car body without fuel)
    physics.fuelMass = 50        -- kg (current fuel)
    physics.maxFuel = 50         -- kg
    physics.fuelRate = 1.5       -- kg/s at full throttle
    physics.tirePressure = 2.2   -- bar
    physics.optimalPressure = 2.2
    physics.engineForce = 250000  -- game-scale force units
    physics.brakeForce = 200000   -- game-scale force units
    physics.dragCoeff = 3.0       -- quadratic drag
    physics.rollingResistance = 0.015
    physics.maxSpeed = 320
    physics.baseTurnSpeed = 3.0
    physics.gripMultiplier = 1.0  -- global grip multiplier (dev menu)
    physics.bumpMultiplier = 1.0  -- global bump multiplier (dev menu)

    -- Game state
    game.laps = 0
    game.maxLaps = 3
    game.timer = 0
    game.won = false
    game.lastSide = nil
    game.countdown = 3
    game.countdownPhase = 3 -- tracks which number we're on for animation
    game.started = false

    -- Particles
    particles = {}

    -- Pre-render grass canvas
    generateGrassCanvas()

    -- Pre-render track canvas (asphalt with speckle)
    generateTrackCanvas()

    -- Pre-calculate curb segments
    generateCurbs()

    -- Generate trees
    generateTrees()

    -- Generate surface zones around the track
    generateSurfaceZones()

    -- Dev menu
    initDevMenu()
end

-- ============================================================
-- PRE-RENDERING
-- ============================================================

function generateGrassCanvas()
    grassCanvas = love.graphics.newCanvas(800, 600)
    love.graphics.setCanvas(grassCanvas)
    -- Base green
    love.graphics.clear(0.18, 0.55, 0.13, 1)
    -- Random grass dots
    math.randomseed(42) -- consistent seed
    for _ = 1, 4000 do
        local x = math.random(0, 800)
        local y = math.random(0, 600)
        local shade = 0.14 + math.random() * 0.12
        local g = 0.45 + math.random() * 0.25
        love.graphics.setColor(shade, g, shade * 0.7, 0.6)
        love.graphics.rectangle("fill", x, y, 2, 2)
    end
    -- Some longer grass blades
    for _ = 1, 1500 do
        local x = math.random(0, 800)
        local y = math.random(0, 600)
        local shade = 0.1 + math.random() * 0.15
        local g = 0.5 + math.random() * 0.2
        love.graphics.setColor(shade, g, shade * 0.6, 0.4)
        love.graphics.rectangle("fill", x, y, 1, 3 + math.random(0, 2))
    end
    love.graphics.setCanvas()
    math.randomseed(os.time())
end

function generateTrackCanvas()
    trackCanvas = love.graphics.newCanvas(800, 600)
    love.graphics.setCanvas({trackCanvas, stencil=true})
    love.graphics.clear(0, 0, 0, 0)

    -- We'll use a stencil to mask drawing to the track area only
    love.graphics.stencil(function()
        -- Outer ellipse
        drawFilledEllipse(track.cx, track.cy, track.outerRx, track.outerRy)
    end, "replace", 1)

    love.graphics.stencil(function()
        -- Inner ellipse: subtract from stencil
        drawFilledEllipse(track.cx, track.cy, track.innerRx, track.innerRy)
    end, "replace", 0, true) -- keep existing, set inner to 0

    love.graphics.setStencilTest("greater", 0)

    -- Dark asphalt base
    love.graphics.setColor(0.25, 0.25, 0.28, 1)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    -- Speckle noise for asphalt texture
    math.randomseed(123)
    for _ = 1, 6000 do
        local x = math.random(0, 800)
        local y = math.random(0, 600)
        local v = 0.2 + math.random() * 0.15
        love.graphics.setColor(v, v, v + 0.02, 0.3)
        love.graphics.rectangle("fill", x, y, 1, 1)
    end
    -- Slightly larger lighter patches
    for _ = 1, 800 do
        local x = math.random(0, 800)
        local y = math.random(0, 600)
        local v = 0.3 + math.random() * 0.1
        love.graphics.setColor(v, v, v, 0.15)
        love.graphics.rectangle("fill", x, y, 2, 2)
    end

    love.graphics.setStencilTest()
    love.graphics.setCanvas()
    math.randomseed(os.time())
end

function generateCurbs()
    track.outerCurbs = {}
    track.innerCurbs = {}
    local numSegments = 80
    for i = 0, numSegments - 1 do
        local angle = (i / numSegments) * math.pi * 2
        local nextAngle = ((i + 1) / numSegments) * math.pi * 2
        local midAngle = (angle + nextAngle) / 2

        -- Outer curb
        local ox = track.cx + math.cos(midAngle) * track.outerRx
        local oy = track.cy + math.sin(midAngle) * track.outerRy
        table.insert(track.outerCurbs, {
            x = ox, y = oy, angle = midAngle, index = i
        })

        -- Inner curb
        local ix = track.cx + math.cos(midAngle) * track.innerRx
        local iy = track.cy + math.sin(midAngle) * track.innerRy
        table.insert(track.innerCurbs, {
            x = ix, y = iy, angle = midAngle, index = i
        })
    end
end

function generateTrees()
    trees = {}
    math.randomseed(77) -- consistent placement

    -- Infield trees (~15)
    for _ = 1, 15 do
        local attempts = 0
        while attempts < 50 do
            local angle = math.random() * math.pi * 2
            local rx = math.random() * (track.innerRx - 30)
            local ry = math.random() * (track.innerRy - 25)
            local x = track.cx + math.cos(angle) * rx
            local y = track.cy + math.sin(angle) * ry
            -- Make sure it's well inside the inner ellipse
            local dx = x - track.cx
            local dy = y - track.cy
            local dist = (dx / (track.innerRx - 20))^2 + (dy / (track.innerRy - 15))^2
            if dist < 0.85 then
                local trunkH = 6 + math.random() * 4
                local canopyR = 8 + math.random() * 7
                local green = 0.3 + math.random() * 0.3
                table.insert(trees, {
                    x = x, y = y,
                    trunkH = trunkH, canopyR = canopyR,
                    green = green, shade = 0.1 + math.random() * 0.1
                })
                break
            end
            attempts = attempts + 1
        end
    end

    -- Outside trees (~10)
    for _ = 1, 10 do
        local attempts = 0
        while attempts < 50 do
            local angle = math.random() * math.pi * 2
            -- Place outside the outer ellipse
            local factor = 1.08 + math.random() * 0.25
            local x = track.cx + math.cos(angle) * track.outerRx * factor
            local y = track.cy + math.sin(angle) * track.outerRy * factor
            -- Make sure it's on screen
            if x > 15 and x < 785 and y > 15 and y < 585 then
                local trunkH = 6 + math.random() * 5
                local canopyR = 8 + math.random() * 8
                local green = 0.3 + math.random() * 0.3
                table.insert(trees, {
                    x = x, y = y,
                    trunkH = trunkH, canopyR = canopyR,
                    green = green, shade = 0.1 + math.random() * 0.1
                })
                break
            end
            attempts = attempts + 1
        end
    end

    math.randomseed(os.time())
end

function generateSurfaceZones()
    surfaceZones = {
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

function getSurfaceAt(x, y)
    local dx = x - track.cx
    local dy = y - track.cy
    local angle = math.atan2(dy, dx)
    if angle < 0 then angle = angle + math.pi * 2 end
    for _, zone in ipairs(surfaceZones) do
        if angle >= zone.angleStart and angle < zone.angleEnd then
            return zone
        end
    end
    return surfaceZones[1] -- fallback
end

function initDevMenu()
    devMenu.open = false
    devMenu.activeSlider = nil
    devMenu.panelX = 530
    devMenu.panelY = 10
    devMenu.panelW = 260
    devMenu.sliderH = 16
    devMenu.sliderPad = 22
    devMenu.sliders = {
        { label = "Car Mass",      unit = "kg",  min = 400,   max = 1500,  get = function() return physics.mass end,              set = function(v) physics.mass = v end },
        { label = "Fuel",          unit = "kg",  min = 0,     max = 50,    get = function() return physics.fuelMass end,           set = function(v) physics.fuelMass = v end },
        { label = "Fuel Rate",     unit = "kg/s",min = 0,     max = 5,     get = function() return physics.fuelRate end,           set = function(v) physics.fuelRate = v end },
        { label = "Tire Pressure", unit = "bar", min = 1.5,   max = 3.0,   get = function() return physics.tirePressure end,       set = function(v) physics.tirePressure = v end },
        { label = "Engine Force",  unit = "",    min = 50000, max = 500000,get = function() return physics.engineForce end,        set = function(v) physics.engineForce = v end },
        { label = "Brake Force",   unit = "",    min = 50000, max = 400000,get = function() return physics.brakeForce end,         set = function(v) physics.brakeForce = v end },
        { label = "Drag Coeff",    unit = "",    min = 0.5,   max = 10.0,  get = function() return physics.dragCoeff end,          set = function(v) physics.dragCoeff = v end },
        { label = "Rolling Res.",  unit = "",    min = 0.005,  max = 0.05, get = function() return physics.rollingResistance end,  set = function(v) physics.rollingResistance = v end },
        { label = "Grip Multi.",   unit = "x",   min = 0.1,   max = 1.5,   get = function() return physics.gripMultiplier end,     set = function(v) physics.gripMultiplier = v end },
        { label = "Bump Multi.",   unit = "x",   min = 0.0,   max = 3.0,   get = function() return physics.bumpMultiplier end,     set = function(v) physics.bumpMultiplier = v end },
    }
end

-- ============================================================
-- UPDATE
-- ============================================================

function love.update(dt)
    -- Countdown
    if not game.started then
        game.countdown = game.countdown - dt
        game.countdownPhase = math.ceil(game.countdown)
        if game.countdown <= 0 then
            game.started = true
        end
        return
    end

    if game.won then return end

    game.timer = game.timer + dt

    -- Physics-based movement
    local totalMass = physics.mass + physics.fuelMass

    -- Surface zone at car position
    local zone = getSurfaceAt(car.x, car.y)
    car.currentZone = zone
    local onTrack = isOnTrack(car.x, car.y)

    -- Tire pressure grip: deviation from optimal reduces grip
    local pressureDev = math.abs(physics.tirePressure - physics.optimalPressure)
    local pressureGrip = math.max(0.3, 1.0 - pressureDev * 0.4)

    -- Effective grip
    local surfaceGrip = onTrack and zone.grip or 0.3
    local effectiveGrip = surfaceGrip * pressureGrip * physics.gripMultiplier
    effectiveGrip = math.min(1.0, math.max(0.1, effectiveGrip))

    -- Bumpiness
    local bumpiness = onTrack and (zone.bumpiness * physics.bumpMultiplier) or 0.0

    car.prevSpeed = car.speed

    -- Throttle / brake forces
    local throttle = 0
    if love.keyboard.isDown("up") and physics.fuelMass > 0 then
        throttle = 1
    end
    local braking = love.keyboard.isDown("down")

    local driveForce = throttle * physics.engineForce * effectiveGrip
    local brakeDecel = 0
    if braking then
        brakeDecel = physics.brakeForce * effectiveGrip
    end

    -- Drag (quadratic)
    local dragForce = physics.dragCoeff * car.speed * math.abs(car.speed)

    -- Rolling resistance
    local rollingForce = physics.rollingResistance * totalMass * 9.81

    -- Off-track grass drag
    local grassDrag = 0
    if not onTrack then
        grassDrag = math.abs(car.speed) * 3.0
    end

    -- Net force and acceleration
    local netForce = driveForce - dragForce - rollingForce - grassDrag
    if braking then
        if car.speed > 0 then
            netForce = netForce - brakeDecel
        elseif car.speed < 0 then
            netForce = netForce + brakeDecel
        else
            netForce = netForce - brakeDecel * 0.3 -- allow slight reverse
        end
    end

    local accel = netForce / totalMass
    car.speed = car.speed + accel * dt

    -- Bumpiness: random speed perturbation and steering wobble
    if bumpiness > 0.01 and math.abs(car.speed) > 20 then
        local bumpMag = bumpiness * math.abs(car.speed) * 0.0003
        car.speed = car.speed + (math.random() - 0.5) * bumpMag * car.speed
        car.angle = car.angle + (math.random() - 0.5) * bumpiness * 0.005
    end

    -- Clamp speed
    car.speed = math.max(-100, math.min(physics.maxSpeed, car.speed))

    -- Stop drifting at very low speeds
    if math.abs(car.speed) < 1 and throttle == 0 and not braking then
        car.speed = 0
    end

    -- Fuel consumption
    if throttle > 0 then
        physics.fuelMass = math.max(0, physics.fuelMass - physics.fuelRate * dt)
    end

    -- Turning (grip affects turn response)
    local turnFactor = math.min(1, math.abs(car.speed) / 100) * effectiveGrip
    car.turning = false
    if love.keyboard.isDown("left") then
        car.angle = car.angle - physics.baseTurnSpeed * turnFactor * dt
        car.turning = true
    end
    if love.keyboard.isDown("right") then
        car.angle = car.angle + physics.baseTurnSpeed * turnFactor * dt
        car.turning = true
    end

    -- Move car
    local prevX, prevY = car.x, car.y
    car.x = car.x + math.cos(car.angle) * car.speed * dt
    car.y = car.y + math.sin(car.angle) * car.speed * dt

    -- Keep car in bounds (soft: allow off-track but with heavy penalty above)
    -- Hard boundary: don't let car leave screen
    car.x = math.max(10, math.min(790, car.x))
    car.y = math.max(10, math.min(590, car.y))

    -- Finish line detection
    checkFinishLine(prevX, prevY, car.x, car.y)

    -- Tire smoke particles
    updateParticles(dt)

    -- Spawn particles on hard braking or sharp turns at speed
    local isBraking = love.keyboard.isDown("down") and car.speed > 50
    local isSharpTurn = car.turning and math.abs(car.speed) > 120

    if isBraking or isSharpTurn then
        -- Spawn from rear of car
        local rearX = car.x - math.cos(car.angle) * car.width * 0.4
        local rearY = car.y - math.sin(car.angle) * car.height * 0.4
        for _ = 1, 2 do
            table.insert(particles, {
                x = rearX + (math.random() - 0.5) * 8,
                y = rearY + (math.random() - 0.5) * 8,
                life = 0.5,
                maxLife = 0.5,
                size = 3 + math.random() * 3,
                vx = (math.random() - 0.5) * 20,
                vy = (math.random() - 0.5) * 20,
            })
        end
    end
end

function updateParticles(dt)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * 0.95
        p.vy = p.vy * 0.95
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

-- ============================================================
-- GAME LOGIC
-- ============================================================

function isOnTrack(x, y)
    local dx = x - track.cx
    local dy = y - track.cy
    local outerDist = (dx / track.outerRx)^2 + (dy / track.outerRy)^2
    local innerDist = (dx / track.innerRx)^2 + (dy / track.innerRy)^2
    return outerDist <= 1 and innerDist >= 1
end

function checkFinishLine(prevX, prevY, newX, newY)
    local lineX = track.finishX

    if (prevX < lineX and newX >= lineX) or (prevX >= lineX and newX < lineX) then
        local t = (lineX - prevX) / (newX - prevX)
        local crossY = prevY + t * (newY - prevY)

        local minY = math.min(track.finishY1, track.finishY2)
        local maxY = math.max(track.finishY1, track.finishY2)
        if crossY >= minY and crossY <= maxY then
            if newX > prevX then
                game.laps = game.laps + 1
                if game.laps >= game.maxLaps then
                    game.won = true
                end
            end
        end
    end
end

-- ============================================================
-- DRAWING
-- ============================================================

function love.draw()
    drawGrass()
    drawTrack()
    drawSurfaceZones()
    drawCurbs()
    drawCenterLine()
    drawFinishLine()
    drawTrees()
    drawCarShadow()
    drawParticles()
    drawCar()
    drawHUD()

    if not game.started then
        drawCountdown()
    end

    if game.won then
        drawWinScreen()
    end

    if devMenu.open then
        drawDevMenu()
    end
end

function drawGrass()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(grassCanvas, 0, 0)
end

function drawTrack()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(trackCanvas, 0, 0)

    -- Subtle track border lines
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.setLineWidth(2)
    drawEllipseOutline(track.cx, track.cy, track.outerRx, track.outerRy)
    drawEllipseOutline(track.cx, track.cy, track.innerRx, track.innerRy)
end

function drawCurbs()
    local curbW = 10
    local curbH = 5

    -- Outer curbs
    for _, c in ipairs(track.outerCurbs) do
        if c.index % 2 == 0 then
            love.graphics.setColor(0.9, 0.15, 0.1, 0.9)
        else
            love.graphics.setColor(1, 1, 1, 0.9)
        end
        love.graphics.push()
        love.graphics.translate(c.x, c.y)
        love.graphics.rotate(c.angle + math.pi / 2)
        love.graphics.rectangle("fill", -curbW / 2, -curbH / 2, curbW, curbH)
        love.graphics.pop()
    end

    -- Inner curbs
    for _, c in ipairs(track.innerCurbs) do
        if c.index % 2 == 0 then
            love.graphics.setColor(0.9, 0.15, 0.1, 0.9)
        else
            love.graphics.setColor(1, 1, 1, 0.9)
        end
        love.graphics.push()
        love.graphics.translate(c.x, c.y)
        love.graphics.rotate(c.angle + math.pi / 2)
        love.graphics.rectangle("fill", -curbW / 2, -curbH / 2, curbW, curbH)
        love.graphics.pop()
    end
end

function drawCenterLine()
    love.graphics.setColor(1, 1, 1, 0.6)
    local segments = 120
    local dashLen = 3 -- draw every other segment
    for i = 0, segments - 1 do
        if i % (dashLen * 2) < dashLen then
            local a1 = (i / segments) * math.pi * 2
            local a2 = ((i + 1) / segments) * math.pi * 2
            local x1 = track.cx + math.cos(a1) * track.midRx
            local y1 = track.cy + math.sin(a1) * track.midRy
            local x2 = track.cx + math.cos(a2) * track.midRx
            local y2 = track.cy + math.sin(a2) * track.midRy
            love.graphics.setLineWidth(2)
            love.graphics.line(x1, y1, x2, y2)
        end
    end
end

function drawFinishLine()
    local lineX = track.finishX
    local y1 = track.finishY2 -- outer (top, smaller y)
    local y2 = track.finishY1 -- inner (bottom, larger y)
    local gridSize = 6
    local cols = 2
    local totalWidth = cols * gridSize

    -- Draw checkered grid
    local numRows = math.floor((y2 - y1) / gridSize)
    for row = 0, numRows - 1 do
        for col = 0, cols - 1 do
            if (row + col) % 2 == 0 then
                love.graphics.setColor(1, 1, 1, 1)
            else
                love.graphics.setColor(0.05, 0.05, 0.05, 1)
            end
            love.graphics.rectangle("fill",
                lineX - totalWidth / 2 + col * gridSize,
                y1 + row * gridSize,
                gridSize, gridSize)
        end
    end

    -- Flag poles on each end
    local poleColor = {0.5, 0.5, 0.5, 1}
    local poleHeight = 20
    local flagSize = 8

    -- Top pole (outer edge)
    love.graphics.setColor(poleColor)
    love.graphics.rectangle("fill", lineX - 1, y1 - poleHeight, 2, poleHeight)
    -- Mini checkered flag
    for fr = 0, 1 do
        for fc = 0, 1 do
            if (fr + fc) % 2 == 0 then
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0, 0, 0)
            end
            love.graphics.rectangle("fill",
                lineX + 1 + fc * (flagSize / 2),
                y1 - poleHeight + fr * (flagSize / 2),
                flagSize / 2, flagSize / 2)
        end
    end

    -- Bottom pole (inner edge)
    love.graphics.setColor(poleColor)
    love.graphics.rectangle("fill", lineX - 1, y2, 2, poleHeight)
    -- Mini checkered flag
    for fr = 0, 1 do
        for fc = 0, 1 do
            if (fr + fc) % 2 == 0 then
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0, 0, 0)
            end
            love.graphics.rectangle("fill",
                lineX + 1 + fc * (flagSize / 2),
                y2 + fr * (flagSize / 2),
                flagSize / 2, flagSize / 2)
        end
    end
end

function drawTrees()
    for _, t in ipairs(trees) do
        -- Trunk
        love.graphics.setColor(0.4, 0.25, 0.1, 1)
        love.graphics.rectangle("fill", t.x - 2, t.y - t.trunkH, 4, t.trunkH)

        -- Canopy layers (3 circles with slight variation)
        local r = t.canopyR
        love.graphics.setColor(t.shade, t.green * 0.8, t.shade * 0.5, 0.9)
        love.graphics.circle("fill", t.x, t.y - t.trunkH - r * 0.3, r * 1.0)
        love.graphics.setColor(t.shade * 1.1, t.green, t.shade * 0.4, 0.95)
        love.graphics.circle("fill", t.x - r * 0.3, t.y - t.trunkH - r * 0.6, r * 0.7)
        love.graphics.setColor(t.shade * 0.9, t.green * 1.1, t.shade * 0.6, 0.85)
        love.graphics.circle("fill", t.x + r * 0.3, t.y - t.trunkH - r * 0.5, r * 0.65)
    end
end

function drawCarShadow()
    love.graphics.push()
    love.graphics.translate(car.x + 3, car.y + 4)
    love.graphics.rotate(car.angle)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", 0, 0, car.width * 0.55, car.height * 0.5)
    love.graphics.pop()
end

function drawCar()
    love.graphics.push()
    love.graphics.translate(car.x, car.y)
    love.graphics.rotate(car.angle)

    local w = car.width
    local h = car.height

    -- Wheels (4 black rectangles, slightly outside body)
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    local wheelW, wheelH = 6, 3
    -- Front-left
    love.graphics.rectangle("fill", w * 0.25 - wheelW / 2, -h / 2 - wheelH / 2, wheelW, wheelH)
    -- Front-right
    love.graphics.rectangle("fill", w * 0.25 - wheelW / 2, h / 2 - wheelH / 2, wheelW, wheelH)
    -- Rear-left
    love.graphics.rectangle("fill", -w * 0.3 - wheelW / 2, -h / 2 - wheelH / 2, wheelW, wheelH)
    -- Rear-right
    love.graphics.rectangle("fill", -w * 0.3 - wheelW / 2, h / 2 - wheelH / 2, wheelW, wheelH)

    -- Main body (rounded rectangle via rectangle + circles)
    love.graphics.setColor(0.85, 0.1, 0.1, 1)
    local bodyInset = 1
    love.graphics.rectangle("fill", -w / 2 + bodyInset, -h / 2 + bodyInset, w - bodyInset * 2, h - bodyInset * 2, 3, 3)

    -- Body highlight stripe
    love.graphics.setColor(1, 0.2, 0.15, 0.4)
    love.graphics.rectangle("fill", -w / 2 + 3, -1, w - 6, 2, 1, 1)

    -- Windshield (darker tinted area on rear half of car)
    love.graphics.setColor(0.15, 0.2, 0.35, 0.8)
    love.graphics.rectangle("fill", -w * 0.2, -h / 2 + 2, w * 0.3, h - 4, 2, 2)

    -- Headlights (front, yellow)
    love.graphics.setColor(1, 0.95, 0.3, 1)
    love.graphics.rectangle("fill", w / 2 - 3, -h / 2 + 2, 3, 3)
    love.graphics.rectangle("fill", w / 2 - 3, h / 2 - 5, 3, 3)

    -- Taillights (rear, red)
    love.graphics.setColor(1, 0, 0, 0.9)
    love.graphics.rectangle("fill", -w / 2, -h / 2 + 2, 3, 3)
    love.graphics.rectangle("fill", -w / 2, h / 2 - 5, 3, 3)

    love.graphics.pop()
end

function drawParticles()
    for _, p in ipairs(particles) do
        local t = p.life / p.maxLife
        local alpha = t * 0.6
        local size = p.size * t
        love.graphics.setColor(0.8, 0.8, 0.8, alpha)
        love.graphics.circle("fill", p.x, p.y, size)
    end
end

function drawHUD()
    love.graphics.setFont(fonts.hud)

    -- Panel background
    local panelX, panelY = 8, 8
    local panelW, panelH = 180, 160
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

    local x0 = panelX + 10
    local y0 = panelY + 8

    -- Lap counter with circles
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(fonts.hud)
    love.graphics.print("LAP", x0, y0)
    local circleY = y0 + 8
    for i = 1, game.maxLaps do
        local cx = x0 + 35 + (i - 1) * 18
        if i <= game.laps then
            love.graphics.setColor(0.2, 0.9, 0.2, 1)
            love.graphics.circle("fill", cx, circleY, 6)
        else
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.circle("line", cx, circleY, 6)
        end
    end

    -- Speed bar + number
    local speedY = y0 + 25
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("SPD", x0, speedY)
    local barX = x0 + 35
    local barW = 100
    local barH = 10
    -- Bar background
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.rectangle("fill", barX, speedY + 3, barW, barH, 2, 2)
    -- Bar fill
    local speedPct = math.min(1, math.abs(car.speed) / physics.maxSpeed)
    local r = speedPct
    local g = 1 - speedPct * 0.7
    love.graphics.setColor(r, g, 0.1, 0.85)
    love.graphics.rectangle("fill", barX, speedY + 3, barW * speedPct, barH, 2, 2)
    -- Speed number
    love.graphics.setColor(1, 1, 1, 0.8)
    local speedStr = tostring(math.floor(math.abs(car.speed)))
    love.graphics.print(speedStr, barX + barW + 5, speedY)

    -- Timer
    local timerY = speedY + 22
    love.graphics.setColor(1, 1, 1, 0.9)
    local mins = math.floor(game.timer / 60)
    local secs = game.timer % 60
    love.graphics.print(string.format("TIME  %d:%05.2f", mins, secs), x0, timerY)

    -- Fuel bar
    local fuelY = timerY + 18
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("FUEL", x0, fuelY)
    local fuelPct = physics.fuelMass / physics.maxFuel
    -- Bar background
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.rectangle("fill", barX, fuelY + 3, barW, barH, 2, 2)
    -- Bar fill (green->yellow->red)
    local fr, fg
    if fuelPct > 0.5 then
        fr, fg = 0.2, 0.9
    elseif fuelPct > 0.2 then
        fr, fg = 0.95, 0.85
    else
        fr, fg = 0.95, 0.2
    end
    love.graphics.setColor(fr, fg, 0.1, 0.85)
    love.graphics.rectangle("fill", barX, fuelY + 3, barW * fuelPct, barH, 2, 2)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print(string.format("%.0f", physics.fuelMass), barX + barW + 5, fuelY)

    -- Tire pressure
    local tireY = fuelY + 18
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("TIRE", x0, tireY)
    local pressureDev = math.abs(physics.tirePressure - physics.optimalPressure)
    if pressureDev < 0.2 then
        love.graphics.setColor(0.2, 0.9, 0.2, 0.9)
    elseif pressureDev < 0.5 then
        love.graphics.setColor(0.95, 0.85, 0.1, 0.9)
    else
        love.graphics.setColor(0.95, 0.2, 0.1, 0.9)
    end
    love.graphics.print(string.format("%.1f bar", physics.tirePressure), barX, tireY)

    -- Surface zone name
    local surfY = tireY + 18
    love.graphics.setColor(1, 1, 1, 0.6)
    local zoneName = car.currentZone and car.currentZone.name or "Off Track"
    if not isOnTrack(car.x, car.y) then zoneName = "Off Track" end
    love.graphics.print(zoneName, x0, surfY)

    -- Position indicator (top right of panel)
    love.graphics.setFont(fonts.hudBig)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf(string.format("%d/%d", math.min(game.laps + 1, game.maxLaps), game.maxLaps),
        panelX, panelY + panelH - 24, panelW - 10, "right")
end

function drawCountdown()
    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    local num = math.ceil(game.countdown)
    if num < 1 then num = 0 end

    local text
    local r, g, b
    if num >= 3 then
        text = "3"
        r, g, b = 0.9, 0.2, 0.15
    elseif num == 2 then
        text = "2"
        r, g, b = 0.95, 0.85, 0.1
    elseif num == 1 then
        text = "1"
        r, g, b = 0.2, 0.9, 0.2
    else
        text = "GO!"
        r, g, b = 0.1, 1, 0.2
    end

    -- Bounce ease: scale from large to normal within each second
    local frac = game.countdown - math.floor(game.countdown) -- fractional part
    -- When frac is close to 1 (just appeared), scale is large; frac close to 0, scale is normal
    local scale = 1 + (1 - frac) * 0 + frac * 0.5 -- range 1.0 to 1.5
    -- Add a bounce overshoot
    if frac > 0.7 then
        scale = 1 + (frac - 0.7) * 2.5
    else
        scale = 1 + frac * 0.15
    end

    love.graphics.setFont(fonts.countdown)
    local tw = fonts.countdown:getWidth(text)
    local th = fonts.countdown:getHeight()

    love.graphics.push()
    love.graphics.translate(400, 280)
    love.graphics.scale(scale, scale)

    -- Text shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(text, -tw / 2 + 2, -th / 2 + 2)

    -- Text
    love.graphics.setColor(r, g, b, 1)
    love.graphics.print(text, -tw / 2, -th / 2)

    love.graphics.pop()
end

function drawWinScreen()
    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    -- Checkered flag border (top and bottom)
    local checkSize = 16
    local cols = math.ceil(800 / checkSize)
    for i = 0, cols - 1 do
        for row = 0, 1 do
            if (i + row) % 2 == 0 then
                love.graphics.setColor(1, 1, 1, 0.8)
            else
                love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
            end
            -- Top border
            love.graphics.rectangle("fill", i * checkSize, row * checkSize, checkSize, checkSize)
            -- Bottom border
            love.graphics.rectangle("fill", i * checkSize, 600 - (2 - row) * checkSize, checkSize, checkSize)
        end
    end

    -- "YOU WIN!" with shadow
    love.graphics.setFont(fonts.win)
    local winText = "YOU WIN!"
    local winTW = fonts.win:getWidth(winText)

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(winText, 400 - winTW / 2 + 3, 213)

    -- Main text
    love.graphics.setColor(1, 0.9, 0.1, 1)
    love.graphics.print(winText, 400 - winTW / 2, 210)

    -- Stats
    love.graphics.setFont(fonts.winSub)
    love.graphics.setColor(1, 1, 1, 0.95)
    local mins = math.floor(game.timer / 60)
    local secs = game.timer % 60
    local timeStr = string.format("Time: %d:%05.2f", mins, secs)
    local timeTW = fonts.winSub:getWidth(timeStr)
    love.graphics.print(timeStr, 400 - timeTW / 2, 275)

    -- Average speed
    local avgSpeed = 0
    if game.timer > 0 then
        -- Approximate: total laps * track circumference / time
        local approxCircumference = math.pi * (track.midRx + track.midRy) -- rough ellipse perimeter
        avgSpeed = (game.maxLaps * approxCircumference) / game.timer
    end
    local avgStr = string.format("Avg Speed: %d", math.floor(avgSpeed))
    local avgTW = fonts.winSub:getWidth(avgStr)
    love.graphics.print(avgStr, 400 - avgTW / 2, 305)

    -- Restart prompt
    love.graphics.setColor(1, 1, 1, 0.7)
    local restartText = "Press R to restart"
    local restartTW = fonts.winSub:getWidth(restartText)
    love.graphics.print(restartText, 400 - restartTW / 2, 350)
end

function drawSurfaceZones()
    -- Draw subtle colored overlays for non-smooth zones
    local segments = 40
    for _, zone in ipairs(surfaceZones) do
        if zone.color[4] > 0 then
            love.graphics.setColor(zone.color[1], zone.color[2], zone.color[3], zone.color[4])
            local aRange = zone.angleEnd - zone.angleStart
            local nSegs = math.max(2, math.floor(segments * aRange / (math.pi * 2)))
            for i = 0, nSegs - 1 do
                local a1 = zone.angleStart + (i / nSegs) * aRange
                local a2 = zone.angleStart + ((i + 1) / nSegs) * aRange
                -- Draw a quad from inner to outer edge
                local ox1 = track.cx + math.cos(a1) * track.outerRx
                local oy1 = track.cy + math.sin(a1) * track.outerRy
                local ox2 = track.cx + math.cos(a2) * track.outerRx
                local oy2 = track.cy + math.sin(a2) * track.outerRy
                local ix1 = track.cx + math.cos(a1) * track.innerRx
                local iy1 = track.cy + math.sin(a1) * track.innerRy
                local ix2 = track.cx + math.cos(a2) * track.innerRx
                local iy2 = track.cy + math.sin(a2) * track.innerRy
                local ok, _ = pcall(love.graphics.polygon, "fill", ox1, oy1, ox2, oy2, ix2, iy2, ix1, iy1)
                if not ok then end -- skip degenerate polys
            end
        end
    end
end

function drawDevMenu()
    local px, py = devMenu.panelX, devMenu.panelY
    local pw = devMenu.panelW
    local numSliders = #devMenu.sliders
    local ph = 35 + numSliders * devMenu.sliderPad + 10

    -- Panel background
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px, py, pw, ph, 6, 6)

    -- Title
    love.graphics.setFont(fonts.hud)
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.print("DEV MENU (F1)", px + 8, py + 6)

    -- Sliders
    for i, s in ipairs(devMenu.sliders) do
        local sy = py + 30 + (i - 1) * devMenu.sliderPad
        local sx = px + 105
        local sw = pw - 115
        local val = s.get()
        local t = (val - s.min) / (s.max - s.min)

        -- Label
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print(s.label, px + 6, sy + 1)

        -- Bar bg
        love.graphics.setColor(1, 1, 1, 0.15)
        love.graphics.rectangle("fill", sx, sy + 2, sw, devMenu.sliderH - 4, 2, 2)

        -- Bar fill
        love.graphics.setColor(0.3, 0.7, 1.0, 0.7)
        love.graphics.rectangle("fill", sx, sy + 2, sw * t, devMenu.sliderH - 4, 2, 2)

        -- Handle
        local hx = sx + sw * t
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", hx, sy + devMenu.sliderH / 2, 5)

        -- Value text
        local valStr
        if s.max - s.min < 1 then
            valStr = string.format("%.3f", val)
        elseif s.max - s.min < 10 then
            valStr = string.format("%.1f", val)
        else
            valStr = string.format("%d", math.floor(val))
        end
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.print(valStr .. " " .. s.unit, sx + sw + 4, sy + 1)
    end
end

-- ============================================================
-- INPUT
-- ============================================================

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
    if key == "r" then
        love.load()
    end
    if key == "f1" then
        devMenu.open = not devMenu.open
    end
end

function love.mousepressed(x, y, button)
    if not devMenu.open or button ~= 1 then return end
    for i, s in ipairs(devMenu.sliders) do
        local sy = devMenu.panelY + 30 + (i - 1) * devMenu.sliderPad
        local sx = devMenu.panelX + 105
        local sw = devMenu.panelW - 115
        if x >= sx and x <= sx + sw and y >= sy and y <= sy + devMenu.sliderH then
            devMenu.activeSlider = i
            local t = math.max(0, math.min(1, (x - sx) / sw))
            s.set(s.min + t * (s.max - s.min))
        end
    end
end

function love.mousereleased(x, y, button)
    if button == 1 then
        devMenu.activeSlider = nil
    end
end

function love.mousemoved(x, y, dx, dy)
    if not devMenu.open or not devMenu.activeSlider then return end
    local s = devMenu.sliders[devMenu.activeSlider]
    local sx = devMenu.panelX + 105
    local sw = devMenu.panelW - 115
    local t = math.max(0, math.min(1, (x - sx) / sw))
    s.set(s.min + t * (s.max - s.min))
end

-- ============================================================
-- HELPERS
-- ============================================================

function drawFilledEllipse(cx, cy, rx, ry)
    local segments = 64
    local vertices = {}
    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2
        table.insert(vertices, cx + math.cos(angle) * rx)
        table.insert(vertices, cy + math.sin(angle) * ry)
    end
    love.graphics.polygon("fill", vertices)
end

function drawEllipseOutline(cx, cy, rx, ry)
    local segments = 64
    local vertices = {}
    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2
        table.insert(vertices, cx + math.cos(angle) * rx)
        table.insert(vertices, cy + math.sin(angle) * ry)
    end
    love.graphics.polygon("line", vertices)
end
