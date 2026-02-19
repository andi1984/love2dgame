-- Love2D Racing Game — Entry Point

local track = require("track")
local car = require("car")
local game = require("game")
local particles = require("particles")
local draw = require("draw")
local devmenu = require("devmenu")

function love.load()
    love.window.setTitle("Racing Game")
    love.window.setMode(800, 600)

    track.init()
    car.init(track)
    game.init()
    particles.init()
    draw.init(track)
    devmenu.init(car.physics)
end

function love.update(dt)
    if not game.started then
        game.updateCountdown(dt)
        return
    end

    if game.won then return end

    game.timer = game.timer + dt

    local input = {
        up = love.keyboard.isDown("up"),
        down = love.keyboard.isDown("down"),
        left = love.keyboard.isDown("left"),
        right = love.keyboard.isDown("right"),
    }

    local prevX, prevY = car.x, car.y
    car.update(dt, input, track)
    game.checkFinishLine(track, prevX, prevY, car.x, car.y)

    particles.update(dt)
    if car.shouldSpawnSmoke then
        particles.spawnSmoke(car)
    end
end

function love.draw()
    draw.all(car, track, game, particles, devmenu)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
    if key == "r" then
        love.load()
    end
    if key == "f1" then
        devmenu.open = not devmenu.open
    end
end

function love.mousepressed(x, y, button)
    devmenu.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    devmenu.mousereleased(x, y, button)
end

function love.mousemoved(x, y, dx, dy)
    devmenu.mousemoved(x, y)
end
