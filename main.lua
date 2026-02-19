-- Love2D Racing Game — Entry Point

local track = require("track")
local car = require("car")
local game = require("game")
local particles = require("particles")
local draw = require("draw")
local devmenu = require("devmenu")
local state = require("state")
local menu = require("menu")
local pause = require("pause")
local tracks = require("tracks")
local audio = require("audio")

function love.load()
    love.window.setTitle("Racing Game")
    love.window.setMode(800, 600)

    -- Initialize state machine and menus
    state.init()
    menu.init()
    pause.init()
    
    -- Initialize drawing (without track for now)
    draw.init(nil)
    
    -- Initialize particles
    particles.init()
    
    -- Initialize audio system
    audio.init()
end

-- Start a race with the selected track
local function startRace(trackConfig)
    track.initFromConfig(trackConfig)
    car.init(track)
    game.init()
    particles.init()
    draw.generateTrackCanvas(track)
    devmenu.init(car.physics)
    audio.reset()  -- Reset audio state for new race
    state.set("racing")
end

-- Return to main menu
local function returnToMenu()
    audio.returnToMenu()  -- Stop racing sounds and fade music back in
    state.set("menu")
    menu.init()
end

function love.update(dt)
    -- Always update audio for music fading
    audio.update(dt, car, game, track, state)
    
    if state.is("menu") then
        -- No other updates needed for menu
        return
    end
    
    if state.is("controls") then
        -- No other updates needed for controls screen
        return
    end
    
    if state.is("paused") then
        -- Game is paused, no other updates
        return
    end
    
    if state.is("racing") then
        if not game.started then
            game.updateCountdown(dt)
            audio.updateCountdown(game)  -- Play countdown beeps
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

        local prevLaps = game.laps
        local prevX, prevY = car.x, car.y
        car.update(dt, input, track)
        game.checkFinishLine(track, prevX, prevY, car.x, car.y)
        
        -- Play lap complete or race win sounds
        if game.laps > prevLaps then
            if game.won then
                audio.playRaceWin()
            else
                audio.playLapComplete()
            end
        end

        particles.update(dt)
        if car.shouldSpawnSmoke then
            particles.spawnSmoke(car)
        end
    end
end

function love.draw()
    if state.is("menu") then
        draw.mainMenu(menu)
        return
    end
    
    if state.is("controls") then
        draw.controlsScreen()
        return
    end
    
    if state.is("racing") or state.is("paused") then
        draw.all(car, track, game, particles, devmenu)
        
        if state.is("paused") then
            draw.pauseMenu(pause)
        end
    end
end

function love.keypressed(key)
    if state.is("menu") then
        if key == "escape" then
            love.event.quit()
        elseif key == "return" or key == "space" then
            audio.playMenuSelect()
            if menu.selectedButton == "track" then
                local selectedTrack = menu.getSelectedTrack()
                if selectedTrack then
                    startRace(selectedTrack)
                end
            elseif menu.selectedButton == "controls" then
                state.set("controls")
            end
        elseif key == "left" then
            menu.selectPrev()
            audio.playMenuBlip()
        elseif key == "right" then
            menu.selectNext()
            audio.playMenuBlip()
        elseif key == "up" then
            menu.moveUp()
            audio.playMenuBlip()
        elseif key == "down" then
            menu.moveDown()
            audio.playMenuBlip()
        end
        return
    end
    
    if state.is("controls") then
        if key == "escape" or key == "return" or key == "space" then
            audio.playMenuBlip()
            state.goBack()
        end
        return
    end
    
    if state.is("paused") then
        if key == "escape" then
            audio.playMenuBlip()
            state.set("racing")  -- Resume
        elseif key == "return" or key == "space" then
            audio.playMenuSelect()
            local selected = pause.getSelected()
            if selected == "Resume" then
                state.set("racing")
            elseif selected == "Controls" then
                state.set("controls")
            elseif selected == "Main Menu" then
                returnToMenu()
            end
        elseif key == "up" then
            pause.moveUp()
            audio.playMenuBlip()
        elseif key == "down" then
            pause.moveDown()
            audio.playMenuBlip()
        end
        return
    end
    
    if state.is("racing") then
        if key == "escape" then
            audio.stopAll()  -- Stop racing sounds when pausing
            pause.init()
            state.set("paused")
        elseif key == "r" then
            -- Restart current track
            local currentTrackConfig = track.config
            if currentTrackConfig then
                startRace(currentTrackConfig)
            end
        elseif key == "f1" then
            devmenu.open = not devmenu.open
        end
        return
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    
    if state.is("menu") then
        local action = menu.handleClick(x, y, 800, 600)
        if action == "start" then
            audio.playMenuSelect()
            local selectedTrack = menu.getSelectedTrack()
            if selectedTrack then
                startRace(selectedTrack)
            end
        elseif action == "controls" then
            audio.playMenuSelect()
            state.set("controls")
        end
        return
    end
    
    if state.is("controls") then
        -- Check if back button clicked
        local btnW = 150
        local btnH = 40
        local btnX = (800 - btnW) / 2
        local btnY = (600 - 400) / 2 + 400 - 60
        
        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            audio.playMenuBlip()
            state.goBack()
        end
        return
    end
    
    if state.is("paused") then
        local action = pause.handleClick(x, y, 800, 600)
        if action then
            audio.playMenuSelect()
        end
        if action == "resume" then
            state.set("racing")
        elseif action == "controls" then
            state.set("controls")
        elseif action == "mainmenu" then
            returnToMenu()
        end
        return
    end
    
    if state.is("racing") then
        devmenu.mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if state.is("racing") then
        devmenu.mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if state.is("racing") then
        devmenu.mousemoved(x, y)
    end
end
