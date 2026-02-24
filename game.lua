-- Game state: laps, timer, countdown (pure logic, no Love2D dependency)

local game = {}

function game.init(numCars)
    numCars = numCars or 1
    game.carLaps = {}
    game.carFinished = {}
    for i = 1, numCars do
        game.carLaps[i] = 0
        game.carFinished[i] = false
    end
    game.maxLaps = 3
    game.timer = 0
    game.won = false
    game.winnerIndex = nil
    game.evolutionDone = false
    game.lastSide = nil
    game.countdown = 3
    game.countdownPhase = 3
    game.started = false
end

-- Backward compatibility: game.laps returns player lap count
function game.getPlayerLaps()
    return game.carLaps[1] or 0
end

function game.updateCountdown(dt)
    game.countdown = game.countdown - dt
    game.countdownPhase = math.ceil(game.countdown)
    if game.countdown <= 0 then
        game.started = true
    end
end

function game.checkFinishLine(track, prevX, prevY, newX, newY, carIndex)
    carIndex = carIndex or 1

    -- 2D line segment intersection: car path vs finish line
    -- Segment A: car movement (prevX,prevY) → (newX,newY)
    -- Segment B: finish line finishP1 → finishP2
    local p1 = track.finishP1
    local p2 = track.finishP2

    local ax = newX - prevX
    local ay = newY - prevY
    local bx = p2.x - p1.x
    local by = p2.y - p1.y

    local denom = ax * by - ay * bx
    if math.abs(denom) < 1e-10 then return end  -- parallel, no crossing

    local t = ((p1.x - prevX) * by - (p1.y - prevY) * bx) / denom
    local u = ((p1.x - prevX) * ay - (p1.y - prevY) * ax) / denom

    -- t in [0,1] means car path crosses; u in [0,1] means within finish line width
    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
        -- Check that the car is moving in the track's forward direction
        local fwd = track.finishForward
        local forwardDot = ax * fwd.x + ay * fwd.y
        if forwardDot > 0 then
            game.carLaps[carIndex] = game.carLaps[carIndex] + 1
            if game.carLaps[carIndex] >= game.maxLaps and not game.won then
                game.won = true
                game.winnerIndex = carIndex
                game.carFinished[carIndex] = true
            end
        end
    end
end

return game
