-- 8-bit Audio System for Racing Game
-- Generates retro-style sounds procedurally using Love2D's SoundData

local audio = {}

-- Sound sources
audio.sounds = {}
audio.engineSource  = nil
audio.enginePlaying = false
audio.grassSource   = nil
audio.grassPlaying  = false
audio.brakeSource   = nil
audio.brakePlaying  = false
audio.flatTirePlaying = false

-- Music state
audio.musicSource        = nil
audio.musicPlaying       = false
audio.musicVolume        = 0.35
audio.musicTargetVolume  = 0.35
audio.musicFadeSpeed     = 0.5
audio.musicFadedForRace  = false

-- State tracking
audio.lastCountdownPhase = nil
audio.wasOnTrack         = true
audio.wasBraking         = false
audio.wasSkidding        = false
audio.crashCooldown      = 0    -- prevent overlapping crash sounds

-- Volume settings
audio.masterVolume  = 0.7
audio.engineVolume  = 0.3
audio.effectsVolume = 0.5
audio.uiVolume      = 0.4

-- ----------------------------------------------------------------
-- Sound generation helpers
-- ----------------------------------------------------------------

local function generateSquareWave(frequency, duration, sampleRate, dutyCycle)
    sampleRate = sampleRate or 44100
    dutyCycle  = dutyCycle  or 0.5
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    local period = sampleRate / frequency
    for i = 0, samples - 1 do
        local t   = (i % period) / period
        local val = t < dutyCycle and 0.3 or -0.3
        local env = 1.0
        local attackEnd    = samples * 0.05
        local releaseStart = samples * 0.7
        if i < attackEnd then
            env = i / attackEnd
        elseif i > releaseStart then
            env = 1.0 - (i - releaseStart) / (samples - releaseStart)
        end
        soundData:setSample(i, val * env)
    end
    return soundData
end

local function generateEngineLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration  = 0.5
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    local baseFreq  = 80
    for i = 0, samples - 1 do
        local t   = i / sampleRate
        local val = 0
        val = val + math.sin(2 * math.pi * baseFreq     * t) * 0.15
        val = val + math.sin(2 * math.pi * baseFreq * 2 * t) * 0.10
        val = val + math.sin(2 * math.pi * baseFreq * 3 * t) * 0.05
        val = val + (math.random() * 2 - 1) * 0.03
        local mod = 0.8 + 0.2 * math.sin(2 * math.pi * 15 * t)
        soundData:setSample(i, val * mod)
    end
    return soundData
end

local function generateGrassLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration  = 0.3
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local val = (math.random() * 2 - 1) * 0.15
        if i > 0 then
            val = soundData:getSample(i - 1) * 0.7 + val * 0.3
        end
        soundData:setSample(i, val)
    end
    return soundData
end

local function generateRustyBrakeLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration  = 0.3
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    local baseFreq  = 2800
    for i = 0, samples - 1 do
        local t           = i / sampleRate
        local pitchWobble = 1 + 0.02 * math.sin(2 * math.pi * 8 * t)
        local squeal1 = math.sin(2 * math.pi * baseFreq          * pitchWobble * t)
        local squeal2 = math.sin(2 * math.pi * baseFreq * 1.502  * pitchWobble * t)
        local squeal3 = math.sin(2 * math.pi * baseFreq * 2.03   * pitchWobble * t)
        local val     = squeal1 * 0.25 + squeal2 * 0.15 + squeal3 * 0.1
        local pulse   = 0.5 + 0.5 * math.sin(2 * math.pi * 15 * t)
        pulse  = pulse * pulse
        val    = val * (0.3 + 0.7 * pulse)
        if math.sin(2 * math.pi * 47 * t) > 0.7 then val = val * 0.3 end
        val = val + (math.random() * 2 - 1) * 0.02
        soundData:setSample(i, math.max(-0.4, math.min(0.4, val)))
    end
    return soundData
end

-- Crash / impact: metallic thud + crunch noise
local function generateCrashImpact(sampleRate)
    sampleRate = sampleRate or 44100
    local duration  = 0.4
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t   = i / sampleRate
        -- Low "thud" boom
        local thud  = math.sin(2 * math.pi * 55 * t) * 0.45 * math.exp(-t * 18)
        -- Metallic clang (higher mid)
        local clang = math.sin(2 * math.pi * 310 * t) * 0.20 * math.exp(-t * 22)
        -- Crunch noise burst
        local env   = math.exp(-t * 14)
        local noise = (math.random() * 2 - 1) * 0.55 * env
        local val   = thud + clang + noise
        soundData:setSample(i, math.max(-0.75, math.min(0.75, val)))
    end
    return soundData
end

-- Tyre blowout: sharp POP then hissing air
local function generateTireBlowout(sampleRate)
    sampleRate = sampleRate or 44100
    local duration  = 0.5
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t   = i / sampleRate
        -- Sharp pop at t=0
        local pop = (math.random() * 2 - 1) * math.exp(-t * 60) * 0.8
        -- Hissing air (filtered noise decay)
        local hiss = (math.random() * 2 - 1) * 0.2 * math.exp(-t * 6)
        local val  = pop + hiss
        soundData:setSample(i, math.max(-0.8, math.min(0.8, val)))
    end
    return soundData
end

-- Flat-tyre thump loop: rhythmic low bump (wheel hitting rim)
local function generateFlatTireLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration  = 0.6   -- one "revolution" at low speed; pitch shifted at high speed
    local samples   = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t        = i / sampleRate
        local phase    = t / duration   -- 0..1 across one loop
        -- One sharp thump near start of each revolution
        local thumpEnv = math.exp(-phase * 18)
        local thump    = (math.sin(2 * math.pi * 38 * t) + (math.random() * 2 - 1) * 0.25)
                       * thumpEnv * 0.55
        -- Light rolling rumble underneath
        local rumble   = (math.random() * 2 - 1) * 0.03
        local val      = thump + rumble
        soundData:setSample(i, math.max(-0.5, math.min(0.5, val)))
    end
    return soundData
end

local function generateCountdownBeep(isGo)
    local freq     = isGo and 880 or 440
    local duration = isGo and 0.3  or 0.15
    return generateSquareWave(freq, duration, 44100, 0.25)
end

local function generateLapJingle()
    local sampleRate = 44100
    local noteLength = 0.08
    local notes      = {523, 659, 784, 1047}
    local totalSamples = math.floor(#notes * noteLength * sampleRate)
    local soundData  = love.sound.newSoundData(totalSamples, sampleRate, 16, 1)
    for i = 0, totalSamples - 1 do
        local noteIdx = math.min(math.floor(i / (noteLength * sampleRate)) + 1, #notes)
        local freq    = notes[noteIdx]
        local noteT   = (i % math.floor(noteLength * sampleRate)) / (noteLength * sampleRate)
        local period  = sampleRate / freq
        local waveT   = (i % period) / period
        local val     = waveT < 0.5 and 0.25 or -0.25
        local env     = noteT > 0.7 and (1.0 - (noteT - 0.7) / 0.3) or 1.0
        soundData:setSample(i, val * env)
    end
    return soundData
end

local function generateWinFanfare()
    local sampleRate   = 44100
    local noteLength   = 0.12
    local notes        = {523, 659, 784, 1047, 1319, 1568, 2093}
    local totalSamples = math.floor(#notes * noteLength * sampleRate)
    local soundData    = love.sound.newSoundData(totalSamples, sampleRate, 16, 1)
    for i = 0, totalSamples - 1 do
        local noteIdx = math.min(math.floor(i / (noteLength * sampleRate)) + 1, #notes)
        local freq    = notes[noteIdx]
        local noteT   = (i % math.floor(noteLength * sampleRate)) / (noteLength * sampleRate)
        local period  = sampleRate / freq
        local waveT   = (i % period) / period
        local val     = (4 * math.abs(waveT - 0.5) - 1) * 0.3
        local env     = 1.0
        if noteT < 0.1 then env = noteT / 0.1
        elseif noteT > 0.6 then env = 1.0 - (noteT - 0.6) / 0.4 end
        soundData:setSample(i, val * env)
    end
    return soundData
end

local function generateMenuBlip()
    return generateSquareWave(660, 0.05, 44100, 0.25)
end

local function generateMenuSelect()
    local sampleRate = 44100
    local duration   = 0.1
    local samples    = math.floor(duration * sampleRate)
    local soundData  = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t      = i / samples
        local freq   = 440 + 440 * t
        local period = sampleRate / freq
        local waveT  = (i % period) / period
        local val    = waveT < 0.5 and 0.25 or -0.25
        local env    = t > 0.7 and (1.0 - (t - 0.7) / 0.3) or 1.0
        soundData:setSample(i, val * env)
    end
    return soundData
end

local function generateBackgroundMusic()
    local sampleRate = 44100
    local bpm        = 140
    local beatLength = 60 / bpm
    local barLength  = beatLength * 4
    local totalBars  = 8
    local duration   = totalBars * barLength
    local samples    = math.floor(duration * sampleRate)
    local soundData  = love.sound.newSoundData(samples, sampleRate, 16, 1)

    local noteFreqs = {
        A3=220, C4=262, D4=294, E4=330, G4=392,
        A4=440, C5=523, D5=587, E5=659, G5=784, A5=880
    }
    local melody = {
        "A4",nil,"C5",nil,"D5",nil,"E5",nil,
        "D5",nil,"C5",nil,"A4",nil,"G4",nil,
        "A4",nil,"C5",nil,"E5",nil,"G5",nil,
        "E5",nil,"D5",nil,"C5",nil,nil,nil,
        "A4",nil,"A4","C5","D5",nil,"E5",nil,
        "G5",nil,"E5",nil,"D5",nil,"C5",nil,
        "A4",nil,"C5",nil,"D5",nil,"E5","D5",
        "C5",nil,"A4",nil,nil,nil,nil,nil,
    }
    local bass = {
        "A3","A3","C4","C4","A3","A3","G4","G4",
        "A3","A3","C4","C4","D4","D4","E4","E4",
        "A3","A3","C4","C4","A3","A3","G4","G4",
        "A3","A3","D4","D4","C4","C4","A3","A3",
    }

    local eighthNoteSamples  = math.floor((beatLength / 2) * sampleRate)
    local quarterNoteSamples = math.floor(beatLength * sampleRate)

    for i = 0, samples - 1 do
        local t            = i / sampleRate
        local eighthNote   = math.floor(i / eighthNoteSamples)  % 64
        local quarterNote  = math.floor(i / quarterNoteSamples) % 32
        local beatInBar    = math.floor(i / quarterNoteSamples) % 4
        local eighthNotePos  = (i % eighthNoteSamples)  / eighthNoteSamples
        local quarterNotePos = (i % quarterNoteSamples) / quarterNoteSamples
        local val = 0

        -- Melody
        local mNote = melody[eighthNote + 1]
        if mNote and noteFreqs[mNote] then
            local freq   = noteFreqs[mNote]
            local period = sampleRate / freq
            local waveT  = (i % period) / period
            local sq     = waveT < 0.5 and 1 or -1
            local env    = eighthNotePos < 0.05 and eighthNotePos/0.05
                        or (eighthNotePos > 0.7 and (1-(eighthNotePos-0.7)/0.3) or 1.0)
            val = val + sq * 0.12 * env
        end

        -- Bass
        local bNote = bass[quarterNote + 1]
        if bNote and noteFreqs[bNote] then
            local freq   = noteFreqs[bNote]
            local period = sampleRate / freq
            local waveT  = (i % period) / period
            local tri    = 4 * math.abs(waveT - 0.5) - 1
            local env    = quarterNotePos < 0.02 and quarterNotePos/0.02
                        or (quarterNotePos > 0.6 and (1-(quarterNotePos-0.6)/0.4) or 1.0)
            val = val + tri * 0.15 * env
        end

        -- Drums
        local beatPos = (i % quarterNoteSamples) / quarterNoteSamples
        if (beatInBar == 0 or beatInBar == 2) and beatPos < 0.15 then
            local kickEnv  = 1 - beatPos / 0.15
            local kickFreq = 60 * (1 + (1 - beatPos/0.15) * 2)
            val = val + math.sin(2*math.pi*kickFreq*t) * kickEnv * 0.2
        end
        if (beatInBar == 1 or beatInBar == 3) and beatPos < 0.1 then
            val = val + (math.random()*2-1) * (1-beatPos/0.1) * 0.12
        end
        if eighthNotePos < 0.05 then
            val = val + (math.random()*2-1) * (1-eighthNotePos/0.05) * 0.04
        end

        soundData:setSample(i, math.max(-0.5, math.min(0.5, val)))
    end
    return soundData
end

-- ----------------------------------------------------------------
-- Initialise all sounds
-- ----------------------------------------------------------------
function audio.init()
    audio.sounds.engine    = love.audio.newSource(generateEngineLoop())
    audio.sounds.engine:setLooping(true)
    audio.sounds.engine:setVolume(audio.engineVolume * audio.masterVolume)

    audio.sounds.grass     = love.audio.newSource(generateGrassLoop())
    audio.sounds.grass:setLooping(true)
    audio.sounds.grass:setVolume(audio.effectsVolume * audio.masterVolume * 0.5)

    audio.sounds.brake     = love.audio.newSource(generateRustyBrakeLoop())
    audio.sounds.brake:setLooping(true)
    audio.sounds.brake:setVolume(audio.effectsVolume * audio.masterVolume * 0.6)

    -- Damage sounds
    audio.sounds.crash     = love.audio.newSource(generateCrashImpact())
    audio.sounds.crash:setVolume(audio.effectsVolume * audio.masterVolume)

    audio.sounds.tireBlowout = love.audio.newSource(generateTireBlowout())
    audio.sounds.tireBlowout:setVolume(audio.effectsVolume * audio.masterVolume)

    audio.sounds.flatTire  = love.audio.newSource(generateFlatTireLoop())
    audio.sounds.flatTire:setLooping(true)
    audio.sounds.flatTire:setVolume(audio.effectsVolume * audio.masterVolume * 0.55)

    -- Race events
    audio.sounds.countdownBeep = love.audio.newSource(generateCountdownBeep(false))
    audio.sounds.countdownGo   = love.audio.newSource(generateCountdownBeep(true))
    audio.sounds.lapComplete   = love.audio.newSource(generateLapJingle())
    audio.sounds.raceWin       = love.audio.newSource(generateWinFanfare())

    -- UI
    audio.sounds.menuBlip      = love.audio.newSource(generateMenuBlip())
    audio.sounds.menuSelect    = love.audio.newSource(generateMenuSelect())

    -- Music
    audio.sounds.music = love.audio.newSource(generateBackgroundMusic())
    audio.sounds.music:setLooping(true)
    audio.sounds.music:setVolume(audio.musicVolume * audio.masterVolume)

    -- Set remaining volumes
    audio.sounds.countdownBeep:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.countdownGo:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.lapComplete:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.raceWin:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.menuBlip:setVolume(audio.uiVolume * audio.masterVolume)
    audio.sounds.menuSelect:setVolume(audio.uiVolume * audio.masterVolume)

    -- Reset state
    audio.lastCountdownPhase = nil
    audio.wasOnTrack    = true
    audio.wasBraking    = false
    audio.wasSkidding   = false
    audio.enginePlaying = false
    audio.grassPlaying  = false
    audio.brakePlaying  = false
    audio.flatTirePlaying = false
    audio.musicPlaying  = false
    audio.musicFadedForRace = false
    audio.musicVolume   = 0.35
    audio.musicTargetVolume = 0.35
    audio.crashCooldown = 0

    audio.startMusic()
end

function audio.startMusic()
    if not audio.musicPlaying then
        audio.sounds.music:play()
        audio.musicPlaying = true
    end
end

function audio.fadeOutMusic()
    audio.musicTargetVolume = 0.08
    audio.musicFadedForRace = true
end

function audio.fadeInMusic()
    audio.musicTargetVolume = 0.35
    audio.musicFadedForRace = false
end

local function updateMusicFade(dt)
    if not audio.musicPlaying then return end
    local diff = audio.musicTargetVolume - audio.musicVolume
    if math.abs(diff) > 0.001 then
        local change = audio.musicFadeSpeed * dt
        if diff > 0 then
            audio.musicVolume = math.min(audio.musicTargetVolume, audio.musicVolume + change)
        else
            audio.musicVolume = math.max(audio.musicTargetVolume, audio.musicVolume - change)
        end
        audio.sounds.music:setVolume(audio.musicVolume * audio.masterVolume)
    end
end

-- ----------------------------------------------------------------
-- Main audio update (call every frame)
-- ----------------------------------------------------------------
function audio.update(dt, car, game, track, state)
    if not state then return end

    updateMusicFade(dt)

    if audio.crashCooldown > 0 then
        audio.crashCooldown = audio.crashCooldown - dt
    end

    if state.is("racing") and game.started and not game.won then
        -- Engine
        if not audio.enginePlaying then
            audio.sounds.engine:play()
            audio.enginePlaying = true
        end

        local speedRatio = math.abs(car.speed) / car.physics.maxSpeed
        local pitch      = 0.7 + speedRatio * 0.8

        -- Engine sputter when engine is damaged
        local engineHealth = car.damage and car.damage.engine or 1.0
        local engineVol    = audio.engineVolume * audio.masterVolume
        if engineHealth < 0.6 then
            -- Intermittent volume drops simulate misfiring
            local t = love.timer.getTime()
            local sputter = 0.5 + 0.5 * math.sin(t * 22) * math.sin(t * 7.3)
            local severity = 1 - engineHealth   -- 0..1
            engineVol = engineVol * (1 - severity * 0.7 * (1 - sputter))
            -- Also drop pitch slightly
            pitch = pitch * (0.88 + engineHealth * 0.12)
        end

        audio.sounds.engine:setPitch(pitch)
        local throttleBoost = (car.speed > (car.prevSpeed or 0)) and 1 or 0.5
        audio.sounds.engine:setVolume(engineVol * (0.5 + throttleBoost * 0.5))

        -- Grass / off-track
        local onTrack = track.isOnTrack(car.x, car.y)
        if not onTrack and math.abs(car.speed) > 20 then
            if not audio.grassPlaying then
                audio.sounds.grass:play()
                audio.grassPlaying = true
            end
            local grassPitch = 0.8 + (math.abs(car.speed) / car.physics.maxSpeed) * 0.4
            audio.sounds.grass:setPitch(grassPitch)
        else
            if audio.grassPlaying then
                audio.sounds.grass:stop()
                audio.grassPlaying = false
            end
        end

        -- Brake squeal
        local isBraking = car.speed > 30 and car.speed < (car.prevSpeed or car.speed) - 5
        if isBraking then
            if not audio.brakePlaying then
                audio.sounds.brake:play()
                audio.brakePlaying = true
            end
            local brakePitch     = 0.6 + (car.speed / car.physics.maxSpeed) * 0.8
            local brakeIntensity = math.min(1.0, car.speed / 150)
            audio.sounds.brake:setPitch(brakePitch)
            audio.sounds.brake:setVolume(audio.effectsVolume * audio.masterVolume * 0.6 * brakeIntensity)
        else
            if audio.brakePlaying then
                audio.sounds.brake:stop()
                audio.brakePlaying = false
            end
        end

        -- Flat tyre thumping loop (player car only)
        if car.damage then
            local hasFlat = car.damage.flatTires.FL or car.damage.flatTires.FR
                         or car.damage.flatTires.RL or car.damage.flatTires.RR
            local moving  = math.abs(car.speed) > 15

            if hasFlat and moving then
                if not audio.flatTirePlaying then
                    audio.sounds.flatTire:play()
                    audio.flatTirePlaying = true
                end
                -- Pitch up with speed (faster spin = faster thump)
                local flatPitch = 0.5 + (math.abs(car.speed) / car.physics.maxSpeed) * 1.4
                audio.sounds.flatTire:setPitch(flatPitch)
            else
                if audio.flatTirePlaying then
                    audio.sounds.flatTire:stop()
                    audio.flatTirePlaying = false
                end
            end
        end

    else
        -- Stop all driving sounds when not racing
        if audio.enginePlaying  then audio.sounds.engine:stop();   audio.enginePlaying  = false end
        if audio.grassPlaying   then audio.sounds.grass:stop();    audio.grassPlaying   = false end
        if audio.brakePlaying   then audio.sounds.brake:stop();    audio.brakePlaying   = false end
        if audio.flatTirePlaying then audio.sounds.flatTire:stop(); audio.flatTirePlaying = false end
    end
end

-- ----------------------------------------------------------------
-- One-shot event sounds
-- ----------------------------------------------------------------

function audio.playCrash(force)
    -- force 0..1; small bumps are quieter
    if audio.crashCooldown > 0 then return end
    audio.sounds.crash:stop()
    local vol = audio.effectsVolume * audio.masterVolume * math.max(0.3, force)
    audio.sounds.crash:setVolume(vol)
    audio.sounds.crash:play()
    audio.crashCooldown = 0.18   -- avoid overlapping crunches
end

function audio.playTireBlowout()
    audio.sounds.tireBlowout:stop()
    audio.sounds.tireBlowout:play()
end

function audio.updateCountdown(game)
    if not game then return end
    if game.countdownPhase ~= audio.lastCountdownPhase then
        if game.countdownPhase >= 1 and game.countdownPhase <= 3 then
            audio.sounds.countdownBeep:stop()
            audio.sounds.countdownBeep:play()
        elseif game.countdownPhase <= 0 and audio.lastCountdownPhase == 1 then
            audio.sounds.countdownGo:stop()
            audio.sounds.countdownGo:play()
            audio.fadeOutMusic()
        end
        audio.lastCountdownPhase = game.countdownPhase
    end
end

function audio.playLapComplete()
    audio.sounds.lapComplete:stop()
    audio.sounds.lapComplete:play()
end

function audio.playRaceWin()
    if audio.enginePlaying   then audio.sounds.engine:stop();   audio.enginePlaying   = false end
    if audio.brakePlaying    then audio.sounds.brake:stop();    audio.brakePlaying    = false end
    if audio.flatTirePlaying then audio.sounds.flatTire:stop(); audio.flatTirePlaying = false end
    audio.sounds.raceWin:stop()
    audio.sounds.raceWin:play()
    audio.fadeInMusic()
end

function audio.playMenuBlip()
    audio.sounds.menuBlip:stop()
    audio.sounds.menuBlip:play()
end

function audio.playMenuSelect()
    audio.sounds.menuSelect:stop()
    audio.sounds.menuSelect:play()
end

function audio.stopAll()
    for name, sound in pairs(audio.sounds) do
        if name ~= "music" then sound:stop() end
    end
    audio.enginePlaying   = false
    audio.grassPlaying    = false
    audio.brakePlaying    = false
    audio.flatTirePlaying = false
end

function audio.reset()
    audio.stopAll()
    audio.lastCountdownPhase = nil
    audio.wasOnTrack  = true
    audio.wasBraking  = false
    audio.wasSkidding = false
    audio.crashCooldown = 0
    audio.fadeInMusic()
end

function audio.returnToMenu()
    audio.stopAll()
    audio.fadeInMusic()
end

return audio
