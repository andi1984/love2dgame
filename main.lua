-- Love2D Racing Game — Entry Point

local track = require("track")
local Car = require("car")
local game = require("game")
local particles = require("particles")
local draw = require("draw")
local devmenu = require("devmenu")
local state = require("state")
local menu = require("menu")
local pause = require("pause")
local tracks = require("tracks")
local audio = require("audio")
local nnet = require("nnet")
local ai = require("ai")
local evolution = require("evolution")
local npcProfiles = require("npc_profiles")
local persistence = require("persistence")

local cars = {}
local savedNpcData = nil

-- Current network architecture
local NET_ARCH = {13, 16, 4}

-- Load or create a brain for an NPC profile
local function loadOrCreateBrain(profile)
    local data = savedNpcData and savedNpcData.npcs and savedNpcData.npcs[profile.name]
    if data and data.bestBrain then
        -- Check architecture compatibility
        local savedArch = data.bestBrain.layerSizes
        if savedArch and #savedArch == #NET_ARCH then
            local compatible = true
            for i = 1, #NET_ARCH do
                if savedArch[i] ~= NET_ARCH[i] then
                    compatible = false
                    break
                end
            end
            if compatible then
                return nnet.deserialize(data.bestBrain)
            end
        end
    end
    -- Create a seeded brain that can follow the track from the start
    return nnet.createSeeded(NET_ARCH)
end

-- Get saved metadata for an NPC
local function getSavedMeta(profile)
    local data = savedNpcData and savedNpcData.npcs and savedNpcData.npcs[profile.name]
    if data then
        return data.bestFitness or 0, data.generation or 0, data.bestBrain
    end
    return 0, 0, nil
end

-- Gather all NPC data for saving
local function gatherSaveData()
    local data = { version = 1, npcs = {} }
    for _, c in ipairs(cars) do
        if c.isAI then
            data.npcs[c.name] = {
                bestBrain = c.bestBrain,
                bestFitness = c.bestFitness,
                generation = c.generation,
            }
        end
    end
    return data
end

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

    -- Load saved NPC brain data
    savedNpcData = persistence.load()
end

-- Start a race with the selected track
local function startRace(trackConfig)
    track.initFromConfig(trackConfig)

    -- Create all cars
    cars = {}

    -- Player car (index 1)
    local playerCar = Car.new(track, {
        name = "Player",
        color = {0.85, 0.1, 0.1},
        isAI = false,
    })
    table.insert(cars, playerCar)

    -- NPC cars
    for i, profile in ipairs(npcProfiles.list) do
        local npcCar = Car.new(track, {
            name = profile.name,
            color = profile.color,
            isAI = true,
            physics = profile.personality.physics,
            startOffset = -i * 0.01,
        })

        -- Load or create brain
        npcCar.brain = loadOrCreateBrain(profile)
        npcCar.personality = profile.personality
        local bestFitness, generation, bestBrain = getSavedMeta(profile)
        npcCar.bestFitness = bestFitness
        npcCar.generation = generation
        npcCar.bestBrain = bestBrain or nnet.serialize(npcCar.brain)
        npcCar.currentFitness = 0

        -- Init AI metrics
        ai.initMetrics(npcCar)

        table.insert(cars, npcCar)
    end

    game.init(#cars)
    particles.init()
    draw.generateTrackCanvas(track)
    devmenu.init(cars[1].physics)
    audio.reset()
    state.set("racing")
end

-- Return to main menu
local function returnToMenu()
    -- Save NPC brains when leaving a race
    if #cars > 1 then
        persistence.save(gatherSaveData())
    end
    audio.returnToMenu()
    state.set("menu")
    menu.init()
end

-- Handle race end: evolve NPCs and save
local function onRaceEnd()
    for i, c in ipairs(cars) do
        if c.isAI then
            c.currentFitness = evolution.calculateFitness(
                c, track, game.timer, game.carLaps[i] or 0)
            evolution.evolveAfterRace(c)
        end
    end
    persistence.save(gatherSaveData())
end

function love.update(dt)
    -- Always update audio for music fading
    audio.update(dt, cars[1] or {speed = 0, prevSpeed = 0, physics = {maxSpeed = 320}}, game, track, state)

    if state.is("menu") then
        return
    end

    if state.is("controls") then
        return
    end

    if state.is("paused") then
        return
    end

    if state.is("racing") then
        if not game.started then
            game.updateCountdown(dt)
            audio.updateCountdown(game)
            return
        end

        if game.won then return end

        game.timer = game.timer + dt

        -- Player input
        local playerInput = {
            up = love.keyboard.isDown("up"),
            down = love.keyboard.isDown("down"),
            left = love.keyboard.isDown("left"),
            right = love.keyboard.isDown("right"),
        }

        local prevLaps = {}
        for i = 1, #cars do
            prevLaps[i] = game.carLaps[i] or 0
        end

        -- Update all cars
        for i, c in ipairs(cars) do
            local prevX, prevY = c.x, c.y
            local input

            if c.isAI then
                -- Check for stuck override first
                local override = ai.getStuckOverride(c)
                if override then
                    input = override
                else
                    local sensors = ai.getSensorInputs(c, track)
                    -- Apply sensor noise (imperfect perception)
                    sensors = ai.applySensorNoise(sensors, c.personality and c.personality.errors)
                    local outputs = nnet.forward(c.brain, sensors)
                    input = ai.outputToInput(outputs)
                    -- Apply driving errors (lapses, jitter, late braking)
                    input = ai.applyErrors(c, input, dt)
                end
                ai.updateMetrics(c, dt, track)
            else
                input = playerInput
            end

            c:update(dt, input, track)
            game.checkFinishLine(track, prevX, prevY, c.x, c.y, i)

            -- Particles for all cars
            if c.shouldSpawnSmoke then
                particles.spawnSmoke(c)
            end
        end

        -- Check for lap/win audio events
        for i, c in ipairs(cars) do
            if (game.carLaps[i] or 0) > prevLaps[i] then
                if i == 1 then -- Only play audio for player events
                    if game.won and game.winnerIndex == 1 then
                        audio.playRaceWin()
                    elseif game.won then
                        -- NPC won, still play a sound
                        audio.playLapComplete()
                    else
                        audio.playLapComplete()
                    end
                end
            end
        end

        -- Trigger evolution on race end
        if game.won and not game.evolutionDone then
            game.evolutionDone = true
            onRaceEnd()
        end

        particles.update(dt)
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
        draw.all(cars, track, game, particles, devmenu)

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
            state.set("racing")
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
            if game.won then
                returnToMenu()
            else
                audio.stopAll()
                pause.init()
                state.set("paused")
            end
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
