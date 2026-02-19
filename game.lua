-- Game state: laps, timer, countdown (pure logic, no Love2D dependency)

local game = {}

function game.init()
    game.laps = 0
    game.maxLaps = 3
    game.timer = 0
    game.won = false
    game.lastSide = nil
    game.countdown = 3
    game.countdownPhase = 3
    game.started = false
end

function game.updateCountdown(dt)
    game.countdown = game.countdown - dt
    game.countdownPhase = math.ceil(game.countdown)
    if game.countdown <= 0 then
        game.started = true
    end
end

function game.checkFinishLine(track, prevX, prevY, newX, newY)
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

return game
