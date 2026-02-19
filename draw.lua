-- All rendering code (requires Love2D)

local helpers = require("helpers")

local draw = {}
local fonts = {}
local grassCanvas
local trackCanvas

function draw.init(track)
    fonts.hud = love.graphics.newFont(14)
    fonts.hudBig = love.graphics.newFont(18)
    fonts.countdown = love.graphics.newFont(72)
    fonts.countdownSmall = love.graphics.newFont(36)
    fonts.win = love.graphics.newFont(48)
    fonts.winSub = love.graphics.newFont(20)

    draw.generateGrassCanvas()
    draw.generateTrackCanvas(track)
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
    trackCanvas = love.graphics.newCanvas(800, 600)
    love.graphics.setCanvas({trackCanvas, stencil=true})
    love.graphics.clear(0, 0, 0, 0)

    love.graphics.stencil(function()
        helpers.drawFilledEllipse(track.cx, track.cy, track.outerRx, track.outerRy)
    end, "replace", 1)

    love.graphics.stencil(function()
        helpers.drawFilledEllipse(track.cx, track.cy, track.innerRx, track.innerRy)
    end, "replace", 0, true)

    love.graphics.setStencilTest("greater", 0)

    love.graphics.setColor(0.25, 0.25, 0.28, 1)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

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
    love.graphics.setCanvas()
    math.randomseed(os.time())
end

-- ============================================================
-- MAIN DRAW
-- ============================================================

function draw.all(car, track, game, particles, devmenu)
    draw.grass()
    draw.trackSurface(track)
    draw.surfaceZones(track)
    draw.curbs(track)
    draw.centerLine(track)
    draw.finishLine(track)
    draw.trees(track)
    draw.carShadow(car)
    draw.particles(particles)
    draw.car(car)
    draw.hud(car, game, track)

    if not game.started then
        draw.countdown(game)
    end

    if game.won then
        draw.winScreen(game, track)
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
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(trackCanvas, 0, 0)

    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.setLineWidth(2)
    helpers.drawEllipseOutline(track.cx, track.cy, track.outerRx, track.outerRy)
    helpers.drawEllipseOutline(track.cx, track.cy, track.innerRx, track.innerRy)
end

function draw.curbs(track)
    local curbW = 10
    local curbH = 5

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

function draw.centerLine(track)
    love.graphics.setColor(1, 1, 1, 0.6)
    local segments = 120
    local dashLen = 3
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

function draw.finishLine(track)
    local lineX = track.finishX
    local y1 = track.finishY2
    local y2 = track.finishY1
    local gridSize = 6
    local cols = 2
    local totalWidth = cols * gridSize

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

    local poleColor = {0.5, 0.5, 0.5, 1}
    local poleHeight = 20
    local flagSize = 8

    love.graphics.setColor(poleColor)
    love.graphics.rectangle("fill", lineX - 1, y1 - poleHeight, 2, poleHeight)
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

    love.graphics.setColor(poleColor)
    love.graphics.rectangle("fill", lineX - 1, y2, 2, poleHeight)
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

function draw.trees(track)
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

    -- Wheels
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    local wheelW, wheelH = 6, 3
    love.graphics.rectangle("fill", w * 0.25 - wheelW / 2, -h / 2 - wheelH / 2, wheelW, wheelH)
    love.graphics.rectangle("fill", w * 0.25 - wheelW / 2, h / 2 - wheelH / 2, wheelW, wheelH)
    love.graphics.rectangle("fill", -w * 0.3 - wheelW / 2, -h / 2 - wheelH / 2, wheelW, wheelH)
    love.graphics.rectangle("fill", -w * 0.3 - wheelW / 2, h / 2 - wheelH / 2, wheelW, wheelH)

    -- Body
    love.graphics.setColor(0.85, 0.1, 0.1, 1)
    local bodyInset = 1
    love.graphics.rectangle("fill", -w / 2 + bodyInset, -h / 2 + bodyInset, w - bodyInset * 2, h - bodyInset * 2, 3, 3)

    -- Highlight stripe
    love.graphics.setColor(1, 0.2, 0.15, 0.4)
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

    -- Lap counter
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
    love.graphics.printf(string.format("%d/%d", math.min(game.laps + 1, game.maxLaps), game.maxLaps),
        panelX, panelY + panelH - 24, panelW - 10, "right")
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

function draw.winScreen(game, track)
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

    love.graphics.setFont(fonts.win)
    local winText = "YOU WIN!"
    local winTW = fonts.win:getWidth(winText)

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(winText, 400 - winTW / 2 + 3, 213)

    love.graphics.setColor(1, 0.9, 0.1, 1)
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
        local approxCircumference = math.pi * (track.midRx + track.midRy)
        avgSpeed = (game.maxLaps * approxCircumference) / game.timer
    end
    local avgStr = string.format("Avg Speed: %d", math.floor(avgSpeed))
    local avgTW = fonts.winSub:getWidth(avgStr)
    love.graphics.print(avgStr, 400 - avgTW / 2, 305)

    love.graphics.setColor(1, 1, 1, 0.7)
    local restartText = "Press R to restart"
    local restartTW = fonts.winSub:getWidth(restartText)
    love.graphics.print(restartText, 400 - restartTW / 2, 350)
end

function draw.surfaceZones(track)
    local segments = 40
    for _, zone in ipairs(track.surfaceZones) do
        if zone.color[4] > 0 then
            love.graphics.setColor(zone.color[1], zone.color[2], zone.color[3], zone.color[4])
            local aRange = zone.angleEnd - zone.angleStart
            local nSegs = math.max(2, math.floor(segments * aRange / (math.pi * 2)))
            for i = 0, nSegs - 1 do
                local a1 = zone.angleStart + (i / nSegs) * aRange
                local a2 = zone.angleStart + ((i + 1) / nSegs) * aRange
                local ox1 = track.cx + math.cos(a1) * track.outerRx
                local oy1 = track.cy + math.sin(a1) * track.outerRy
                local ox2 = track.cx + math.cos(a2) * track.outerRx
                local oy2 = track.cy + math.sin(a2) * track.outerRy
                local ix1 = track.cx + math.cos(a1) * track.innerRx
                local iy1 = track.cy + math.sin(a1) * track.innerRy
                local ix2 = track.cx + math.cos(a2) * track.innerRx
                local iy2 = track.cy + math.sin(a2) * track.innerRy
                local ok, _ = pcall(love.graphics.polygon, "fill", ox1, oy1, ox2, oy2, ix2, iy2, ix1, iy1)
                if not ok then end
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

return draw
