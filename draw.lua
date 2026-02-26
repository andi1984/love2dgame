-- All rendering code (requires Love2D)

local draw = {}
local fonts = {}
local grassCanvas
local trackCanvas
local currentTrackId = nil

function draw.init(track)
    fonts.hud = love.graphics.newFont(14)
    fonts.hudBig = love.graphics.newFont(18)
    fonts.countdown = love.graphics.newFont(72)
    fonts.countdownSmall = love.graphics.newFont(36)
    fonts.win = love.graphics.newFont(48)
    fonts.winSub = love.graphics.newFont(20)
    fonts.title = love.graphics.newFont(42)
    fonts.menu = love.graphics.newFont(16)
    fonts.menuSmall = love.graphics.newFont(12)
    fonts.position = love.graphics.newFont(11)

    draw.generateGrassCanvas()
    if track then
        draw.generateTrackCanvas(track)
    end
end

-- ============================================================
-- CANVAS GENERATION
-- ============================================================

function draw.generateGrassCanvas()
    grassCanvas = love.graphics.newCanvas(800, 600)
    love.graphics.setCanvas(grassCanvas)
    love.graphics.clear(0.18, 0.55, 0.13, 1)
    math.randomseed(42)
    for _ = 1, 4000 do
        local x = math.random(0, 800)
        local y = math.random(0, 600)
        local shade = 0.14 + math.random() * 0.12
        local g = 0.45 + math.random() * 0.25
        love.graphics.setColor(shade, g, shade * 0.7, 0.6)
        love.graphics.rectangle("fill", x, y, 2, 2)
    end
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

function draw.generateTrackCanvas(track)
    -- Skip regeneration if track hasn't changed
    local trackId = track.config and track.config.id or "default"
    if trackId == currentTrackId and trackCanvas then
        return
    end
    currentTrackId = trackId

    trackCanvas = love.graphics.newCanvas(800, 600)
    love.graphics.setCanvas({trackCanvas, stencil=true})
    love.graphics.clear(0, 0, 0, 0)

    -- Draw track surface using polygon from inner and outer paths
    if track.innerPath and track.outerPath then
        -- Create a polygon for the track surface
        love.graphics.stencil(function()
            -- Draw outer boundary
            local outerVerts = {}
            for _, p in ipairs(track.outerPath) do
                table.insert(outerVerts, p.x)
                table.insert(outerVerts, p.y)
            end
            if #outerVerts >= 6 then
                love.graphics.polygon("fill", outerVerts)
            end
        end, "replace", 1)

        love.graphics.stencil(function()
            -- Cut out inner area (not applicable for spline tracks, skip)
        end, "replace", 0, true)

        love.graphics.setStencilTest("greater", 0)

        -- Draw track color
        love.graphics.setColor(0.25, 0.25, 0.28, 1)
        love.graphics.rectangle("fill", 0, 0, 800, 600)

        -- Add texture
        math.randomseed(123)
        for _ = 1, 6000 do
            local x = math.random(0, 800)
            local y = math.random(0, 600)
            local v = 0.2 + math.random() * 0.15
            love.graphics.setColor(v, v, v + 0.02, 0.3)
            love.graphics.rectangle("fill", x, y, 1, 1)
        end
        for _ = 1, 800 do
            local x = math.random(0, 800)
            local y = math.random(0, 600)
            local v = 0.3 + math.random() * 0.1
            love.graphics.setColor(v, v, v, 0.15)
            love.graphics.rectangle("fill", x, y, 2, 2)
        end

        love.graphics.setStencilTest()
    end

    love.graphics.setCanvas()
    math.randomseed(os.time())
end

-- ============================================================
-- MAIN DRAW (for racing state)
-- ============================================================

function draw.all(cars, track, game, particles, devmenu)
    draw.grass()
    draw.trackSurface(track)
    draw.surfaceZones(track)
    draw.curbs(track)
    draw.centerLine(track)
    draw.finishLine(track)
    draw.trees(track)

    -- Draw all car shadows
    for _, c in ipairs(cars) do
        draw.carShadow(c)
    end

    draw.particles(particles)

    -- Draw all cars
    for _, c in ipairs(cars) do
        draw.car(c)
    end

    draw.hud(cars[1], game, track)
    draw.positions(cars, game, track)

    if not game.started then
        draw.countdown(game)
    end

    if game.won then
        draw.winScreen(game, cars, track)
    end

    if devmenu.open then
        draw.devMenu(devmenu)
    end
end

-- ============================================================
-- INDIVIDUAL DRAW FUNCTIONS
-- ============================================================

function draw.grass()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(grassCanvas, 0, 0)
end

function draw.trackSurface(track)
    if trackCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(trackCanvas, 0, 0)
    end

    -- Draw track outline
    if track.outerPath and track.innerPath then
        love.graphics.setColor(1, 1, 1, 0.15)
        love.graphics.setLineWidth(2)

        -- Outer edge
        for i = 1, #track.outerPath do
            local p1 = track.outerPath[i]
            local p2 = track.outerPath[(i % #track.outerPath) + 1]
            love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end

        -- Inner edge
        for i = 1, #track.innerPath do
            local p1 = track.innerPath[i]
            local p2 = track.innerPath[(i % #track.innerPath) + 1]
            love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end
    end
end

function draw.curbs(track)
    local curbW = 10
    local curbH = 5

    if track.outerCurbs then
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
    end

    if track.innerCurbs then
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
end

function draw.centerLine(track)
    if not track.centerPath then return end

    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(2)

    local dashLength = 3
    local dashCount = 0

    for i = 1, #track.centerPath do
        dashCount = dashCount + 1
        if dashCount <= dashLength then
            local p1 = track.centerPath[i]
            local p2 = track.centerPath[(i % #track.centerPath) + 1]
            love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end
        if dashCount >= dashLength * 2 then
            dashCount = 0
        end
    end
end

function draw.finishLine(track)
    local lineX = track.finishX
    local y1 = track.finishY2
    local y2 = track.finishY1

    -- Handle both horizontal and vertical finish lines based on track angle
    local angle = track.finishAngle or 0
    local isVertical = math.abs(math.cos(angle)) > math.abs(math.sin(angle))

    local gridSize = 6
    local cols = 2
    local totalWidth = cols * gridSize

    if isVertical then
        local numRows = math.floor(math.abs(y2 - y1) / gridSize)
        local minY = math.min(y1, y2)
        for row = 0, numRows - 1 do
            for col = 0, cols - 1 do
                if (row + col) % 2 == 0 then
                    love.graphics.setColor(1, 1, 1, 1)
                else
                    love.graphics.setColor(0.05, 0.05, 0.05, 1)
                end
                love.graphics.rectangle("fill",
                    lineX - totalWidth / 2 + col * gridSize,
                    minY + row * gridSize,
                    gridSize, gridSize)
            end
        end
    else
        love.graphics.push()
        love.graphics.translate(lineX, (y1 + y2) / 2)
        love.graphics.rotate(angle + math.pi / 2)

        local halfLen = math.abs(y2 - y1) / 2
        local numRows = math.floor(halfLen * 2 / gridSize)

        for row = 0, numRows - 1 do
            for col = 0, cols - 1 do
                if (row + col) % 2 == 0 then
                    love.graphics.setColor(1, 1, 1, 1)
                else
                    love.graphics.setColor(0.05, 0.05, 0.05, 1)
                end
                love.graphics.rectangle("fill",
                    -totalWidth / 2 + col * gridSize,
                    -halfLen + row * gridSize,
                    gridSize, gridSize)
            end
        end
        love.graphics.pop()
    end

    -- Draw flags at finish line ends
    local poleColor = {0.5, 0.5, 0.5, 1}
    local poleHeight = 20
    local flagSize = 8

    love.graphics.setColor(poleColor)
    love.graphics.rectangle("fill", lineX - 1, math.min(y1, y2) - poleHeight, 2, poleHeight)
    for fr = 0, 1 do
        for fc = 0, 1 do
            if (fr + fc) % 2 == 0 then
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0, 0, 0)
            end
            love.graphics.rectangle("fill",
                lineX + 1 + fc * (flagSize / 2),
                math.min(y1, y2) - poleHeight + fr * (flagSize / 2),
                flagSize / 2, flagSize / 2)
        end
    end

    love.graphics.setColor(poleColor)
    love.graphics.rectangle("fill", lineX - 1, math.max(y1, y2), 2, poleHeight)
    for fr = 0, 1 do
        for fc = 0, 1 do
            if (fr + fc) % 2 == 0 then
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0, 0, 0)
            end
            love.graphics.rectangle("fill",
                lineX + 1 + fc * (flagSize / 2),
                math.max(y1, y2) + fr * (flagSize / 2),
                flagSize / 2, flagSize / 2)
        end
    end
end

function draw.trees(track)
    if not track.trees then return end

    for _, t in ipairs(track.trees) do
        love.graphics.setColor(0.4, 0.25, 0.1, 1)
        love.graphics.rectangle("fill", t.x - 2, t.y - t.trunkH, 4, t.trunkH)

        local r = t.canopyR
        love.graphics.setColor(t.shade, t.green * 0.8, t.shade * 0.5, 0.9)
        love.graphics.circle("fill", t.x, t.y - t.trunkH - r * 0.3, r * 1.0)
        love.graphics.setColor(t.shade * 1.1, t.green, t.shade * 0.4, 0.95)
        love.graphics.circle("fill", t.x - r * 0.3, t.y - t.trunkH - r * 0.6, r * 0.7)
        love.graphics.setColor(t.shade * 0.9, t.green * 1.1, t.shade * 0.6, 0.85)
        love.graphics.circle("fill", t.x + r * 0.3, t.y - t.trunkH - r * 0.5, r * 0.65)
    end
end

function draw.carShadow(car)
    love.graphics.push()
    love.graphics.translate(car.x + 3, car.y + 4)
    love.graphics.rotate(car.angle)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", 0, 0, car.width * 0.55, car.height * 0.5)
    love.graphics.pop()
end

function draw.car(car)
    love.graphics.push()
    love.graphics.translate(car.x, car.y)
    love.graphics.rotate(car.angle)

    local w = car.width
    local h = car.height
    local color = car.color or {0.85, 0.1, 0.1}

    -- Wheels
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    local wheelW, wheelH = 6, 3
    love.graphics.rectangle("fill", w * 0.25 - wheelW / 2, -h / 2 - wheelH / 2, wheelW, wheelH)
    love.graphics.rectangle("fill", w * 0.25 - wheelW / 2, h / 2 - wheelH / 2, wheelW, wheelH)
    love.graphics.rectangle("fill", -w * 0.3 - wheelW / 2, -h / 2 - wheelH / 2, wheelW, wheelH)
    love.graphics.rectangle("fill", -w * 0.3 - wheelW / 2, h / 2 - wheelH / 2, wheelW, wheelH)

    -- Body — use car's color
    love.graphics.setColor(color[1], color[2], color[3], 1)
    local bodyInset = 1
    love.graphics.rectangle("fill", -w / 2 + bodyInset, -h / 2 + bodyInset, w - bodyInset * 2, h - bodyInset * 2, 3, 3)

    -- Highlight stripe — lighter version of car color
    love.graphics.setColor(
        math.min(1, color[1] + 0.15),
        math.min(1, color[2] + 0.1),
        math.min(1, color[3] + 0.05),
        0.4)
    love.graphics.rectangle("fill", -w / 2 + 3, -1, w - 6, 2, 1, 1)

    -- Windshield
    love.graphics.setColor(0.15, 0.2, 0.35, 0.8)
    love.graphics.rectangle("fill", -w * 0.2, -h / 2 + 2, w * 0.3, h - 4, 2, 2)

    -- Headlights
    love.graphics.setColor(1, 0.95, 0.3, 1)
    love.graphics.rectangle("fill", w / 2 - 3, -h / 2 + 2, 3, 3)
    love.graphics.rectangle("fill", w / 2 - 3, h / 2 - 5, 3, 3)

    -- Taillights
    love.graphics.setColor(1, 0, 0, 0.9)
    love.graphics.rectangle("fill", -w / 2, -h / 2 + 2, 3, 3)
    love.graphics.rectangle("fill", -w / 2, h / 2 - 5, 3, 3)

    love.graphics.pop()
end

function draw.particles(particles)
    for _, p in ipairs(particles.list) do
        local t = p.life / p.maxLife
        local alpha = t * 0.6
        local size = p.size * t
        love.graphics.setColor(0.8, 0.8, 0.8, alpha)
        love.graphics.circle("fill", p.x, p.y, size)
    end
end

function draw.hud(car, game, track)
    love.graphics.setFont(fonts.hud)

    local panelX, panelY = 8, 8
    local panelW, panelH = 180, 160
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

    local x0 = panelX + 10
    local y0 = panelY + 8
    local laps = game.carLaps[1] or 0

    -- Lap counter
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(fonts.hud)
    love.graphics.print("LAP", x0, y0)
    local circleY = y0 + 8
    for i = 1, game.maxLaps do
        local cx = x0 + 35 + (i - 1) * 18
        if i <= laps then
            love.graphics.setColor(0.2, 0.9, 0.2, 1)
            love.graphics.circle("fill", cx, circleY, 6)
        else
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.circle("line", cx, circleY, 6)
        end
    end

    -- Speed bar
    local speedY = y0 + 25
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("SPD", x0, speedY)
    local barX = x0 + 35
    local barW = 100
    local barH = 10
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.rectangle("fill", barX, speedY + 3, barW, barH, 2, 2)
    local speedPct = math.min(1, math.abs(car.speed) / car.physics.maxSpeed)
    local r = speedPct
    local g = 1 - speedPct * 0.7
    love.graphics.setColor(r, g, 0.1, 0.85)
    love.graphics.rectangle("fill", barX, speedY + 3, barW * speedPct, barH, 2, 2)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print(tostring(math.floor(math.abs(car.speed))), barX + barW + 5, speedY)

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
    local fuelPct = car.physics.fuelMass / car.physics.maxFuel
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.rectangle("fill", barX, fuelY + 3, barW, barH, 2, 2)
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
    love.graphics.print(string.format("%.0f", car.physics.fuelMass), barX + barW + 5, fuelY)

    -- Tire pressure
    local tireY = fuelY + 18
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("TIRE", x0, tireY)
    local pressureDev = math.abs(car.physics.tirePressure - car.physics.optimalPressure)
    if pressureDev < 0.2 then
        love.graphics.setColor(0.2, 0.9, 0.2, 0.9)
    elseif pressureDev < 0.5 then
        love.graphics.setColor(0.95, 0.85, 0.1, 0.9)
    else
        love.graphics.setColor(0.95, 0.2, 0.1, 0.9)
    end
    love.graphics.print(string.format("%.1f bar", car.physics.tirePressure), barX, tireY)

    -- Surface zone
    local surfY = tireY + 18
    love.graphics.setColor(1, 1, 1, 0.6)
    local zoneName = car.currentZone and car.currentZone.name or "Off Track"
    if not track.isOnTrack(car.x, car.y) then zoneName = "Off Track" end
    love.graphics.print(zoneName, x0, surfY)

    -- Lap position
    love.graphics.setFont(fonts.hudBig)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf(string.format("%d/%d", math.min(laps + 1, game.maxLaps), game.maxLaps),
        panelX, panelY + panelH - 24, panelW - 10, "right")
end

-- Race positions panel (top-right)
function draw.positions(cars, game, track)
    -- Sort cars by lap count then track percentage
    local sorted = {}
    for i, c in ipairs(cars) do
        table.insert(sorted, {
            index = i,
            name = c.name,
            laps = game.carLaps[i] or 0,
            pct = track.getTrackPercent(c.x, c.y),
            color = c.color,
        })
    end
    table.sort(sorted, function(a, b)
        if a.laps ~= b.laps then return a.laps > b.laps end
        return a.pct > b.pct
    end)

    local panelX = 800 - 140
    local panelY = 8
    local panelW = 130
    local lineH = 20
    local panelH = 10 + #sorted * lineH + 5

    -- Panel background
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

    love.graphics.setFont(fonts.position)
    for pos, entry in ipairs(sorted) do
        local y = panelY + 6 + (pos - 1) * lineH

        -- Position number
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.print(pos .. ".", panelX + 6, y)

        -- Color dot
        love.graphics.setColor(entry.color[1], entry.color[2], entry.color[3], 1)
        love.graphics.circle("fill", panelX + 26, y + 7, 4)

        -- Name (truncated)
        local displayName = entry.name
        if #displayName > 12 then
            displayName = displayName:sub(1, 11) .. "."
        end
        if entry.index == 1 then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(1, 1, 1, 0.8)
        end
        love.graphics.print(displayName, panelX + 35, y)
    end
end

function draw.countdown(game)
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

    local frac = game.countdown - math.floor(game.countdown)
    local scale
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

    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(text, -tw / 2 + 2, -th / 2 + 2)

    love.graphics.setColor(r, g, b, 1)
    love.graphics.print(text, -tw / 2, -th / 2)

    love.graphics.pop()
end

function draw.winScreen(game, cars, track)
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    local checkSize = 16
    local cols = math.ceil(800 / checkSize)
    for i = 0, cols - 1 do
        for row = 0, 1 do
            if (i + row) % 2 == 0 then
                love.graphics.setColor(1, 1, 1, 0.8)
            else
                love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
            end
            love.graphics.rectangle("fill", i * checkSize, row * checkSize, checkSize, checkSize)
            love.graphics.rectangle("fill", i * checkSize, 600 - (2 - row) * checkSize, checkSize, checkSize)
        end
    end

    -- Determine winner text
    local winnerIndex = game.winnerIndex or 1
    local winnerCar = cars[winnerIndex]
    local winText
    if winnerIndex == 1 then
        winText = "YOU WIN!"
    else
        winText = winnerCar.name .. " WINS!"
    end

    love.graphics.setFont(fonts.win)
    local winTW = fonts.win:getWidth(winText)

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(winText, 400 - winTW / 2 + 3, 213)

    -- Winner text color: use winner's car color or gold for player
    if winnerIndex == 1 then
        love.graphics.setColor(1, 0.9, 0.1, 1)
    else
        love.graphics.setColor(winnerCar.color[1], winnerCar.color[2], winnerCar.color[3], 1)
    end
    love.graphics.print(winText, 400 - winTW / 2, 210)

    love.graphics.setFont(fonts.winSub)
    love.graphics.setColor(1, 1, 1, 0.95)
    local mins = math.floor(game.timer / 60)
    local secs = game.timer % 60
    local timeStr = string.format("Time: %d:%05.2f", mins, secs)
    local timeTW = fonts.winSub:getWidth(timeStr)
    love.graphics.print(timeStr, 400 - timeTW / 2, 275)

    local avgSpeed = 0
    if game.timer > 0 then
        local circumference = track.getCircumference and track.getCircumference() or 1500
        avgSpeed = (game.maxLaps * circumference) / game.timer
    end
    local avgStr = string.format("Avg Speed: %d", math.floor(avgSpeed))
    local avgTW = fonts.winSub:getWidth(avgStr)
    love.graphics.print(avgStr, 400 - avgTW / 2, 305)

    love.graphics.setColor(1, 1, 1, 0.7)
    local restartText = "Press R to restart  |  ESC for menu"
    local restartTW = fonts.winSub:getWidth(restartText)
    love.graphics.print(restartText, 400 - restartTW / 2, 350)
end

function draw.surfaceZones(track)
    if not track.surfaceZones or not track.centerPath then return end

    -- For spline tracks, draw zones along the path segments
    local pathLen = #track.centerPath

    for _, zone in ipairs(track.surfaceZones) do
        if zone.color and zone.color[4] > 0 then
            love.graphics.setColor(zone.color[1], zone.color[2], zone.color[3], zone.color[4])

            local startIdx = math.floor(zone.startPct * pathLen) + 1
            local endIdx = math.floor(zone.endPct * pathLen)

            for i = startIdx, endIdx do
                if track.innerPath[i] and track.outerPath[i] then
                    local nextI = (i % pathLen) + 1
                    if track.innerPath[nextI] and track.outerPath[nextI] then
                        pcall(love.graphics.polygon, "fill",
                            track.outerPath[i].x, track.outerPath[i].y,
                            track.outerPath[nextI].x, track.outerPath[nextI].y,
                            track.innerPath[nextI].x, track.innerPath[nextI].y,
                            track.innerPath[i].x, track.innerPath[i].y)
                    end
                end
            end
        end
    end
end

function draw.devMenu(devmenu)
    local px, py = devmenu.panelX, devmenu.panelY
    local pw = devmenu.panelW
    local numSliders = #devmenu.sliders
    local ph = 35 + numSliders * devmenu.sliderPad + 10

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px, py, pw, ph, 6, 6)

    love.graphics.setFont(fonts.hud)
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.print("DEV MENU (F1)", px + 8, py + 6)

    for i, s in ipairs(devmenu.sliders) do
        local sy = py + 30 + (i - 1) * devmenu.sliderPad
        local sx = px + 105
        local sw = pw - 115
        local val = s.get()
        local t = (val - s.min) / (s.max - s.min)

        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print(s.label, px + 6, sy + 1)

        love.graphics.setColor(1, 1, 1, 0.15)
        love.graphics.rectangle("fill", sx, sy + 2, sw, devmenu.sliderH - 4, 2, 2)

        love.graphics.setColor(0.3, 0.7, 1.0, 0.7)
        love.graphics.rectangle("fill", sx, sy + 2, sw * t, devmenu.sliderH - 4, 2, 2)

        local hx = sx + sw * t
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", hx, sy + devmenu.sliderH / 2, 5)

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
-- MENU DRAWING
-- ============================================================

function draw.mainMenu(menu)
    -- Background
    draw.grass()

    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    -- Title
    love.graphics.setFont(fonts.title)
    local title = "RACING GAME"
    local titleW = fonts.title:getWidth(title)

    -- Title shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(title, 400 - titleW / 2 + 3, 53)

    -- Title text
    love.graphics.setColor(1, 0.9, 0.2, 1)
    love.graphics.print(title, 400 - titleW / 2, 50)

    -- Subtitle
    love.graphics.setFont(fonts.menu)
    love.graphics.setColor(1, 1, 1, 0.7)
    local subtitle = "Select a track to begin"
    local subtitleW = fonts.menu:getWidth(subtitle)
    love.graphics.print(subtitle, 400 - subtitleW / 2, 110)

    -- Track cards
    local trackList = menu.getTrackList()
    local startY = 160
    local cardW = 160
    local cardH = 120
    local padding = 20
    local cols = 3

    local totalW = cols * cardW + (cols - 1) * padding
    local startX = (800 - totalW) / 2

    for i, trackInfo in ipairs(trackList) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cardX = startX + col * (cardW + padding)
        local cardY = startY + row * (cardH + padding)

        local isSelected = (i == menu.selectedTrack) and (menu.selectedButton == "track")

        -- Card background
        if isSelected then
            love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 0.85)
        end
        love.graphics.rectangle("fill", cardX, cardY, cardW, cardH, 8, 8)

        -- Card border
        if isSelected then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setLineWidth(3)
        else
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", cardX, cardY, cardW, cardH, 8, 8)

        -- Track name
        love.graphics.setFont(fonts.menu)
        love.graphics.setColor(1, 1, 1, 1)
        local nameW = fonts.menu:getWidth(trackInfo.name)
        love.graphics.print(trackInfo.name, cardX + (cardW - nameW) / 2, cardY + 10)

        -- Track description
        love.graphics.setFont(fonts.menuSmall)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.printf(trackInfo.description, cardX + 8, cardY + 35, cardW - 16, "center")

        -- Mini track preview
        draw.miniTrackPreview(trackInfo, cardX + cardW / 2, cardY + 80, 50, 25)
    end

    -- Controls button
    local btnW = 200
    local btnH = 40
    local btnX = (800 - btnW) / 2
    local btnY = 530

    local isControlsSelected = (menu.selectedButton == "controls")

    if isControlsSelected then
        love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
    else
        love.graphics.setColor(0.2, 0.2, 0.25, 0.85)
    end
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

    if isControlsSelected then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)

    love.graphics.setFont(fonts.menu)
    love.graphics.setColor(1, 1, 1, 1)
    local ctrlText = "CONTROLS"
    local ctrlW = fonts.menu:getWidth(ctrlText)
    love.graphics.print(ctrlText, btnX + (btnW - ctrlW) / 2, btnY + 10)

    -- Instructions
    love.graphics.setFont(fonts.menuSmall)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Arrow keys to navigate  |  Enter to select  |  Click on a track", 0, 580, 800, "center")
end

function draw.miniTrackPreview(trackInfo, cx, cy, scaleX, scaleY)
    -- Draw a small preview of the track shape
    local points = trackInfo.points
    if not points or #points < 3 then return end

    -- Find bounds
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(points) do
        minX = math.min(minX, p.x)
        maxX = math.max(maxX, p.x)
        minY = math.min(minY, p.y)
        maxY = math.max(maxY, p.y)
    end

    local rangeX = maxX - minX
    local rangeY = maxY - minY

    -- Scale to fit preview area
    local scale = math.min(scaleX * 2 / rangeX, scaleY * 2 / rangeY) * 0.8

    -- Draw track outline
    love.graphics.setColor(0.5, 0.5, 0.55, 0.8)
    love.graphics.setLineWidth(4)

    local verts = {}
    for _, p in ipairs(points) do
        local x = cx + (p.x - (minX + maxX) / 2) * scale
        local y = cy + (p.y - (minY + maxY) / 2) * scale
        table.insert(verts, x)
        table.insert(verts, y)
    end

    -- Close the loop and draw
    if #verts >= 6 then
        table.insert(verts, verts[1])
        table.insert(verts, verts[2])
        love.graphics.line(verts)
    end

    -- Draw start position marker
    if #verts >= 2 then
        love.graphics.setColor(0.2, 0.9, 0.2, 1)
        love.graphics.circle("fill", verts[1], verts[2], 3)
    end
end

-- ============================================================
-- PAUSE MENU DRAWING
-- ============================================================

function draw.pauseMenu(pause)
    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    -- Menu panel
    local menuW = 220
    local menuH = 200
    local menuX = (800 - menuW) / 2
    local menuY = (600 - menuH) / 2

    love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
    love.graphics.rectangle("fill", menuX, menuY, menuW, menuH, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", menuX, menuY, menuW, menuH, 10, 10)

    -- Title
    love.graphics.setFont(fonts.hudBig)
    love.graphics.setColor(1, 1, 1, 1)
    local pauseTitle = "PAUSED"
    local titleW = fonts.hudBig:getWidth(pauseTitle)
    love.graphics.print(pauseTitle, menuX + (menuW - titleW) / 2, menuY + 15)

    -- Options
    local options = pause.getOptions()
    local btnH = 35
    local btnPadding = 10
    local startY = menuY + 55

    for i, option in ipairs(options) do
        local btnY = startY + (i - 1) * (btnH + btnPadding)
        local isSelected = (i == pause.getSelectedIndex())

        -- Button background
        if isSelected then
            love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
        else
            love.graphics.setColor(0.25, 0.25, 0.3, 0.8)
        end
        love.graphics.rectangle("fill", menuX + 20, btnY, menuW - 40, btnH, 5, 5)

        -- Button border
        if isSelected then
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(1, 1, 1, 0.2)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", menuX + 20, btnY, menuW - 40, btnH, 5, 5)

        -- Button text
        love.graphics.setFont(fonts.menu)
        love.graphics.setColor(1, 1, 1, 1)
        local optW = fonts.menu:getWidth(option)
        love.graphics.print(option, menuX + (menuW - optW) / 2, btnY + 8)
    end
end

-- ============================================================
-- CONTROLS SCREEN DRAWING
-- ============================================================

function draw.controlsScreen()
    -- Background
    draw.grass()

    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    -- Panel
    local panelW = 400
    local panelH = 400
    local panelX = (800 - panelW) / 2
    local panelY = (600 - panelH) / 2

    love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 10, 10)

    -- Title
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(1, 0.9, 0.2, 1)
    local title = "CONTROLS"
    local titleW = fonts.title:getWidth(title)
    love.graphics.print(title, 400 - titleW / 2, panelY + 20)

    -- Controls list
    local controls = {
        {"UP", "Accelerate"},
        {"DOWN", "Brake / Reverse"},
        {"LEFT / RIGHT", "Steer"},
        {"R", "Restart Race"},
        {"ESC", "Pause Menu"},
        {"F1", "Dev Menu"},
    }

    local startY = panelY + 90
    local lineH = 40

    for i, ctrl in ipairs(controls) do
        local y = startY + (i - 1) * lineH

        -- Key
        love.graphics.setFont(fonts.menu)
        love.graphics.setColor(0.3, 0.7, 1, 1)
        love.graphics.print(ctrl[1], panelX + 40, y)

        -- Action
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(ctrl[2], panelX + 180, y)
    end

    -- Back button
    local btnW = 150
    local btnH = 40
    local btnX = (800 - btnW) / 2
    local btnY = panelY + panelH - 60

    love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)

    love.graphics.setFont(fonts.menu)
    love.graphics.setColor(1, 1, 1, 1)
    local backText = "BACK"
    local backW = fonts.menu:getWidth(backText)
    love.graphics.print(backText, btnX + (btnW - backW) / 2, btnY + 10)

    -- Instructions
    love.graphics.setFont(fonts.menuSmall)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Press ESC or Enter to go back", 0, 560, 800, "center")
end

return draw
