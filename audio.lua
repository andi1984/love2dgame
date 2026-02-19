-- 8-bit Audio System for Racing Game
-- Generates retro-style sounds procedurally using Love2D's SoundData

local audio = {}

-- Sound sources
audio.sounds = {}
audio.engineSource = nil
audio.enginePlaying = false
audio.grassSource = nil
audio.grassPlaying = false
audio.brakeSource = nil
audio.brakePlaying = false

-- Music state
audio.musicSource = nil
audio.musicPlaying = false
audio.musicVolume = 0.35
audio.musicTargetVolume = 0.35
audio.musicFadeSpeed = 0.5  -- Volume change per second
audio.musicFadedForRace = false

-- State tracking
audio.lastCountdownPhase = nil
audio.wasOnTrack = true
audio.wasBraking = false
audio.wasSkidding = false

-- Volume settings
audio.masterVolume = 0.7
audio.engineVolume = 0.3
audio.effectsVolume = 0.5
audio.uiVolume = 0.4

-- Generate a square wave (classic 8-bit sound)
local function generateSquareWave(frequency, duration, sampleRate, dutyCycle)
    sampleRate = sampleRate or 44100
    dutyCycle = dutyCycle or 0.5
    local samples = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    
    local period = sampleRate / frequency
    for i = 0, samples - 1 do
        local t = (i % period) / period
        local value = t < dutyCycle and 0.3 or -0.3
        -- Apply envelope
        local env = 1.0
        local attackEnd = samples * 0.05
        local releaseStart = samples * 0.7
        if i < attackEnd then
            env = i / attackEnd
        elseif i > releaseStart then
            env = 1.0 - (i - releaseStart) / (samples - releaseStart)
        end
        soundData:setSample(i, value * env)
    end
    return soundData
end

-- Generate engine loop sound (continuous sawtooth with harmonics)
local function generateEngineLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration = 0.5  -- Short loop
    local samples = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    
    local baseFreq = 80  -- Low engine rumble
    
    for i = 0, samples - 1 do
        local t = i / sampleRate
        local value = 0
        
        -- Fundamental + harmonics for that chunky 8-bit engine sound
        value = value + math.sin(2 * math.pi * baseFreq * t) * 0.15
        value = value + math.sin(2 * math.pi * baseFreq * 2 * t) * 0.1
        value = value + math.sin(2 * math.pi * baseFreq * 3 * t) * 0.05
        
        -- Add some noise for texture
        value = value + (math.random() * 2 - 1) * 0.03
        
        -- Slight amplitude modulation for "putt-putt" feel
        local mod = 0.8 + 0.2 * math.sin(2 * math.pi * 15 * t)
        value = value * mod
        
        soundData:setSample(i, value)
    end
    return soundData
end

-- Generate grass/off-track rumble loop
local function generateGrassLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration = 0.3
    local samples = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    
    for i = 0, samples - 1 do
        local value = (math.random() * 2 - 1) * 0.15
        -- Low-pass filter simulation (rough)
        if i > 0 then
            local prev = soundData:getSample(i - 1)
            value = prev * 0.7 + value * 0.3
        end
        soundData:setSample(i, value)
    end
    return soundData
end

-- Generate rusty brake squeal - high-pitched metallic singing sound
-- Real rusty brakes have a high-pitched squeal from metal-on-metal vibration
-- with pulsating/wavering quality as the pad catches unevenly on the rotor
local function generateRustyBrakeLoop(sampleRate)
    sampleRate = sampleRate or 44100
    local duration = 0.3  -- Short loop for seamless looping
    local samples = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    
    -- Base frequency for the squeal (high-pitched, like real brake squeal ~2-4kHz)
    local baseFreq = 2800
    
    for i = 0, samples - 1 do
        local t = i / sampleRate
        local value = 0
        
        -- Primary squeal tone - high pitched sine wave
        -- with slight pitch wobble to simulate uneven rotor contact
        local pitchWobble = 1 + 0.02 * math.sin(2 * math.pi * 8 * t)  -- Slow wobble
        local freq1 = baseFreq * pitchWobble
        local squeal1 = math.sin(2 * math.pi * freq1 * t)
        
        -- Secondary harmonic for richness (slightly detuned for beating effect)
        local freq2 = baseFreq * 1.502 * pitchWobble  -- Not exactly 1.5x = dissonant
        local squeal2 = math.sin(2 * math.pi * freq2 * t)
        
        -- Third tone even higher for that piercing quality
        local freq3 = baseFreq * 2.03 * pitchWobble
        local squeal3 = math.sin(2 * math.pi * freq3 * t)
        
        -- Combine the tones
        value = squeal1 * 0.25 + squeal2 * 0.15 + squeal3 * 0.1
        
        -- Amplitude modulation - pulsating as rotor rotates (uneven contact)
        -- This creates the characteristic "wah-wah-wah" of rusty brakes
        local pulseRate = 15  -- Simulates rotor rotation speed
        local pulse = 0.5 + 0.5 * math.sin(2 * math.pi * pulseRate * t)
        -- Make it more dramatic - sometimes cuts out almost completely
        pulse = pulse * pulse  -- Square it for sharper pulsing
        value = value * (0.3 + 0.7 * pulse)
        
        -- Occasional shudder/stutter (warped rotor catching)
        local shudder = math.sin(2 * math.pi * 47 * t)
        if shudder > 0.7 then
            value = value * 0.3  -- Brief volume drop = stutter
        end
        
        -- Very subtle noise for texture (dust/rust particles)
        local noise = (math.random() * 2 - 1) * 0.02
        value = value + noise
        
        -- Clamp
        value = math.max(-0.4, math.min(0.4, value))
        
        soundData:setSample(i, value)
    end
    return soundData
end

-- Generate countdown beep
local function generateCountdownBeep(isGo)
    local freq = isGo and 880 or 440  -- Higher pitch for "GO!"
    local duration = isGo and 0.3 or 0.15
    return generateSquareWave(freq, duration, 44100, 0.25)
end

-- Generate lap complete jingle (arpeggio)
local function generateLapJingle()
    local sampleRate = 44100
    local noteLength = 0.08
    local notes = {523, 659, 784, 1047}  -- C5, E5, G5, C6
    local totalSamples = math.floor(#notes * noteLength * sampleRate)
    local soundData = love.sound.newSoundData(totalSamples, sampleRate, 16, 1)
    
    for i = 0, totalSamples - 1 do
        local noteIdx = math.floor(i / (noteLength * sampleRate)) + 1
        noteIdx = math.min(noteIdx, #notes)
        local freq = notes[noteIdx]
        
        local noteT = (i % math.floor(noteLength * sampleRate)) / (noteLength * sampleRate)
        
        -- Square wave
        local period = sampleRate / freq
        local waveT = (i % period) / period
        local value = waveT < 0.5 and 0.25 or -0.25
        
        -- Per-note envelope
        local env = 1.0
        if noteT > 0.7 then
            env = 1.0 - (noteT - 0.7) / 0.3
        end
        
        soundData:setSample(i, value * env)
    end
    return soundData
end

-- Generate win fanfare (longer jingle)
local function generateWinFanfare()
    local sampleRate = 44100
    local noteLength = 0.12
    -- Victory melody: C E G C E G C (ascending)
    local notes = {523, 659, 784, 1047, 1319, 1568, 2093}
    local totalSamples = math.floor(#notes * noteLength * sampleRate)
    local soundData = love.sound.newSoundData(totalSamples, sampleRate, 16, 1)
    
    for i = 0, totalSamples - 1 do
        local noteIdx = math.floor(i / (noteLength * sampleRate)) + 1
        noteIdx = math.min(noteIdx, #notes)
        local freq = notes[noteIdx]
        
        local noteT = (i % math.floor(noteLength * sampleRate)) / (noteLength * sampleRate)
        
        -- Triangle wave for a warmer sound
        local period = sampleRate / freq
        local waveT = (i % period) / period
        local value = 4 * math.abs(waveT - 0.5) - 1
        value = value * 0.3
        
        -- Envelope
        local env = 1.0
        if noteT < 0.1 then
            env = noteT / 0.1
        elseif noteT > 0.6 then
            env = 1.0 - (noteT - 0.6) / 0.4
        end
        
        soundData:setSample(i, value * env)
    end
    return soundData
end

-- Generate menu navigation blip
local function generateMenuBlip()
    return generateSquareWave(660, 0.05, 44100, 0.25)
end

-- Generate menu select sound
local function generateMenuSelect()
    local sampleRate = 44100
    local duration = 0.1
    local samples = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    
    for i = 0, samples - 1 do
        local t = i / samples
        -- Rising pitch
        local freq = 440 + 440 * t
        local period = sampleRate / freq
        local waveT = (i % period) / period
        local value = waveT < 0.5 and 0.25 or -0.25
        
        -- Envelope
        local env = 1.0
        if t > 0.7 then
            env = 1.0 - (t - 0.7) / 0.3
        end
        
        soundData:setSample(i, value * env)
    end
    return soundData
end

-- Generate 8-bit background music loop (catchy retro racing tune)
local function generateBackgroundMusic()
    local sampleRate = 44100
    local bpm = 140
    local beatLength = 60 / bpm
    local barLength = beatLength * 4
    local totalBars = 8  -- 8 bar loop
    local duration = totalBars * barLength
    local samples = math.floor(duration * sampleRate)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
    
    -- Note frequencies (A minor pentatonic + some extras for melody)
    local noteFreqs = {
        A3 = 220, C4 = 262, D4 = 294, E4 = 330, G4 = 392,
        A4 = 440, C5 = 523, D5 = 587, E5 = 659, G5 = 784,
        A5 = 880
    }
    
    -- Melody pattern (notes per 8th note, 64 total for 8 bars)
    local melody = {
        -- Bar 1
        "A4", nil, "C5", nil, "D5", nil, "E5", nil,
        -- Bar 2
        "D5", nil, "C5", nil, "A4", nil, "G4", nil,
        -- Bar 3
        "A4", nil, "C5", nil, "E5", nil, "G5", nil,
        -- Bar 4
        "E5", nil, "D5", nil, "C5", nil, nil, nil,
        -- Bar 5
        "A4", nil, "A4", "C5", "D5", nil, "E5", nil,
        -- Bar 6
        "G5", nil, "E5", nil, "D5", nil, "C5", nil,
        -- Bar 7
        "A4", nil, "C5", nil, "D5", nil, "E5", "D5",
        -- Bar 8
        "C5", nil, "A4", nil, nil, nil, nil, nil,
    }
    
    -- Bass pattern (notes per quarter note, 32 total)
    local bass = {
        -- Bar 1-2
        "A3", "A3", "C4", "C4", "A3", "A3", "G4", "G4",
        -- Bar 3-4
        "A3", "A3", "C4", "C4", "D4", "D4", "E4", "E4",
        -- Bar 5-6
        "A3", "A3", "C4", "C4", "A3", "A3", "G4", "G4",
        -- Bar 7-8
        "A3", "A3", "D4", "D4", "C4", "C4", "A3", "A3",
    }
    
    -- Drum pattern (kick on 1,3, snare on 2,4)
    local eighthNoteSamples = math.floor((beatLength / 2) * sampleRate)
    local quarterNoteSamples = math.floor(beatLength * sampleRate)
    
    for i = 0, samples - 1 do
        local t = i / sampleRate
        local value = 0
        
        -- Calculate current position in pattern
        local eighthNote = math.floor(i / eighthNoteSamples) % 64
        local quarterNote = math.floor(i / quarterNoteSamples) % 32
        local beatInBar = math.floor(i / quarterNoteSamples) % 4
        
        -- Position within current note
        local eighthNotePos = (i % eighthNoteSamples) / eighthNoteSamples
        local quarterNotePos = (i % quarterNoteSamples) / quarterNoteSamples
        
        -- MELODY (square wave, lead)
        local melodyNote = melody[eighthNote + 1]
        if melodyNote and noteFreqs[melodyNote] then
            local freq = noteFreqs[melodyNote]
            local period = sampleRate / freq
            local waveT = (i % period) / period
            local square = waveT < 0.5 and 1 or -1
            -- Envelope
            local env = 1.0
            if eighthNotePos < 0.05 then
                env = eighthNotePos / 0.05
            elseif eighthNotePos > 0.7 then
                env = 1.0 - (eighthNotePos - 0.7) / 0.3
            end
            value = value + square * 0.12 * env
        end
        
        -- BASS (triangle wave, lower)
        local bassNote = bass[quarterNote + 1]
        if bassNote and noteFreqs[bassNote] then
            local freq = noteFreqs[bassNote]
            local period = sampleRate / freq
            local waveT = (i % period) / period
            local triangle = 4 * math.abs(waveT - 0.5) - 1
            -- Envelope
            local env = 1.0
            if quarterNotePos < 0.02 then
                env = quarterNotePos / 0.02
            elseif quarterNotePos > 0.6 then
                env = 1.0 - (quarterNotePos - 0.6) / 0.4
            end
            value = value + triangle * 0.15 * env
        end
        
        -- DRUMS (noise-based)
        local beatPos = (i % quarterNoteSamples) / quarterNoteSamples
        
        -- Kick drum on beats 1 and 3
        if (beatInBar == 0 or beatInBar == 2) and beatPos < 0.15 then
            local kickEnv = 1.0 - beatPos / 0.15
            local kickFreq = 60 * (1 + (1 - beatPos / 0.15) * 2)
            local kick = math.sin(2 * math.pi * kickFreq * t) * kickEnv * 0.2
            value = value + kick
        end
        
        -- Snare/hi-hat on beats 2 and 4
        if (beatInBar == 1 or beatInBar == 3) and beatPos < 0.1 then
            local snareEnv = 1.0 - beatPos / 0.1
            local snare = (math.random() * 2 - 1) * snareEnv * 0.12
            value = value + snare
        end
        
        -- Hi-hat on every 8th note
        if eighthNotePos < 0.05 then
            local hihatEnv = 1.0 - eighthNotePos / 0.05
            local hihat = (math.random() * 2 - 1) * hihatEnv * 0.04
            value = value + hihat
        end
        
        -- Clamp
        value = math.max(-0.5, math.min(0.5, value))
        soundData:setSample(i, value)
    end
    
    return soundData
end

-- Initialize all sounds
function audio.init()
    -- Engine loop
    local engineData = generateEngineLoop()
    audio.sounds.engine = love.audio.newSource(engineData)
    audio.sounds.engine:setLooping(true)
    audio.sounds.engine:setVolume(audio.engineVolume * audio.masterVolume)
    
    -- Grass/off-track loop
    local grassData = generateGrassLoop()
    audio.sounds.grass = love.audio.newSource(grassData)
    audio.sounds.grass:setLooping(true)
    audio.sounds.grass:setVolume(audio.effectsVolume * audio.masterVolume * 0.5)
    
    -- Nasty rusty brake screech loop
    local brakeData = generateRustyBrakeLoop()
    audio.sounds.brake = love.audio.newSource(brakeData)
    audio.sounds.brake:setLooping(true)
    audio.sounds.brake:setVolume(audio.effectsVolume * audio.masterVolume * 0.6)
    
    -- Countdown beeps
    audio.sounds.countdownBeep = love.audio.newSource(generateCountdownBeep(false))
    audio.sounds.countdownGo = love.audio.newSource(generateCountdownBeep(true))
    
    -- Race events
    audio.sounds.lapComplete = love.audio.newSource(generateLapJingle())
    audio.sounds.raceWin = love.audio.newSource(generateWinFanfare())
    
    -- UI sounds
    audio.sounds.menuBlip = love.audio.newSource(generateMenuBlip())
    audio.sounds.menuSelect = love.audio.newSource(generateMenuSelect())
    
    -- Background music
    local musicData = generateBackgroundMusic()
    audio.sounds.music = love.audio.newSource(musicData)
    audio.sounds.music:setLooping(true)
    audio.sounds.music:setVolume(audio.musicVolume * audio.masterVolume)
    
    -- Set volumes
    audio.sounds.countdownBeep:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.countdownGo:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.lapComplete:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.raceWin:setVolume(audio.effectsVolume * audio.masterVolume)
    audio.sounds.menuBlip:setVolume(audio.uiVolume * audio.masterVolume)
    audio.sounds.menuSelect:setVolume(audio.uiVolume * audio.masterVolume)
    
    -- Reset state
    audio.lastCountdownPhase = nil
    audio.wasOnTrack = true
    audio.wasBraking = false
    audio.wasSkidding = false
    audio.enginePlaying = false
    audio.grassPlaying = false
    audio.brakePlaying = false
    audio.musicPlaying = false
    audio.musicFadedForRace = false
    audio.musicVolume = 0.35
    audio.musicTargetVolume = 0.35
    
    -- Start background music
    audio.startMusic()
end

-- Start background music
function audio.startMusic()
    if not audio.musicPlaying then
        audio.sounds.music:play()
        audio.musicPlaying = true
    end
end

-- Fade music out (for race start)
function audio.fadeOutMusic()
    audio.musicTargetVolume = 0.08  -- Quiet but still audible
    audio.musicFadedForRace = true
end

-- Fade music back in (for race end/menu)
function audio.fadeInMusic()
    audio.musicTargetVolume = 0.35
    audio.musicFadedForRace = false
end

-- Update music volume fading
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

-- Update audio based on game state
function audio.update(dt, car, game, track, state)
    if not state then return end
    
    -- Always update music fading
    updateMusicFade(dt)
    
    -- Handle engine sound during racing
    if state.is("racing") and game.started and not game.won then
        -- Start engine if not playing
        if not audio.enginePlaying then
            audio.sounds.engine:play()
            audio.enginePlaying = true
        end
        
        -- Adjust engine pitch based on speed
        local speedRatio = math.abs(car.speed) / car.physics.maxSpeed
        local pitch = 0.7 + speedRatio * 0.8  -- Range: 0.7 to 1.5
        audio.sounds.engine:setPitch(pitch)
        
        -- Adjust engine volume based on throttle
        local throttle = love.keyboard.isDown("up") and 1 or 0.5
        audio.sounds.engine:setVolume(audio.engineVolume * audio.masterVolume * (0.5 + throttle * 0.5))
        
        -- Handle off-track grass sound
        local onTrack = track.isOnTrack(car.x, car.y)
        if not onTrack and math.abs(car.speed) > 20 then
            if not audio.grassPlaying then
                audio.sounds.grass:play()
                audio.grassPlaying = true
            end
            -- Adjust grass rumble based on speed
            local grassPitch = 0.8 + (math.abs(car.speed) / car.physics.maxSpeed) * 0.4
            audio.sounds.grass:setPitch(grassPitch)
        else
            if audio.grassPlaying then
                audio.sounds.grass:stop()
                audio.grassPlaying = false
            end
        end
        
        -- Handle nasty rusty brake sound
        local isBraking = love.keyboard.isDown("down") and car.speed > 30
        if isBraking then
            if not audio.brakePlaying then
                audio.sounds.brake:play()
                audio.brakePlaying = true
            end
            -- Adjust brake screech pitch based on speed (faster = higher pitch screech)
            local brakePitch = 0.6 + (car.speed / car.physics.maxSpeed) * 0.8
            audio.sounds.brake:setPitch(brakePitch)
            -- Volume based on how hard we're braking
            local brakeIntensity = math.min(1.0, car.speed / 150)
            audio.sounds.brake:setVolume(audio.effectsVolume * audio.masterVolume * 0.6 * brakeIntensity)
        else
            if audio.brakePlaying then
                audio.sounds.brake:stop()
                audio.brakePlaying = false
            end
        end
        
    else
        -- Stop engine/effect sounds when not racing
        if audio.enginePlaying then
            audio.sounds.engine:stop()
            audio.enginePlaying = false
        end
        if audio.grassPlaying then
            audio.sounds.grass:stop()
            audio.grassPlaying = false
        end
        if audio.brakePlaying then
            audio.sounds.brake:stop()
            audio.brakePlaying = false
        end
    end
end

-- Update countdown sounds
function audio.updateCountdown(game)
    if not game then return end
    
    if game.countdownPhase ~= audio.lastCountdownPhase then
        if game.countdownPhase >= 1 and game.countdownPhase <= 3 then
            audio.sounds.countdownBeep:stop()
            audio.sounds.countdownBeep:play()
        elseif game.countdownPhase <= 0 and audio.lastCountdownPhase == 1 then
            audio.sounds.countdownGo:stop()
            audio.sounds.countdownGo:play()
            -- Fade out music when race starts
            audio.fadeOutMusic()
        end
        audio.lastCountdownPhase = game.countdownPhase
    end
end

-- Play lap complete sound
function audio.playLapComplete()
    audio.sounds.lapComplete:stop()
    audio.sounds.lapComplete:play()
end

-- Play race win sound
function audio.playRaceWin()
    -- Stop engine and effects
    if audio.enginePlaying then
        audio.sounds.engine:stop()
        audio.enginePlaying = false
    end
    if audio.brakePlaying then
        audio.sounds.brake:stop()
        audio.brakePlaying = false
    end
    audio.sounds.raceWin:stop()
    audio.sounds.raceWin:play()
    -- Fade music back in
    audio.fadeInMusic()
end

-- Play menu navigation sound
function audio.playMenuBlip()
    audio.sounds.menuBlip:stop()
    audio.sounds.menuBlip:play()
end

-- Play menu select sound
function audio.playMenuSelect()
    audio.sounds.menuSelect:stop()
    audio.sounds.menuSelect:play()
end

-- Stop all sounds (for state transitions)
function audio.stopAll()
    for name, sound in pairs(audio.sounds) do
        if name ~= "music" then  -- Don't stop music
            sound:stop()
        end
    end
    audio.enginePlaying = false
    audio.grassPlaying = false
    audio.brakePlaying = false
end

-- Reset audio state (call when starting new race)
function audio.reset()
    audio.stopAll()
    audio.lastCountdownPhase = nil
    audio.wasOnTrack = true
    audio.wasBraking = false
    audio.wasSkidding = false
    -- Fade music back to full for countdown
    audio.fadeInMusic()
end

-- Called when returning to menu
function audio.returnToMenu()
    audio.stopAll()
    audio.fadeInMusic()
end

return audio
