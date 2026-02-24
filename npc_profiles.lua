-- NPC personality profiles

local profiles = {}

profiles.list = {
    {
        name = "Aggressive Axel",
        color = {0.2, 0.4, 0.9},
        stripeColor = {0.4, 0.6, 1.0},
        personality = {
            mutationRate = 0.15,
            mutationStrength = 0.3,
            initialBias = {
                throttle = 0.3,
                brake = -0.2,
                steerSensitivity = 0.1,
            },
            physics = {
                engineForce = 260000,
                brakeForce = 180000,
                baseTurnSpeed = 2.8,
                gripMultiplier = 0.95,
            },
            -- Aggressive mistakes: pushes too hard, brakes late, but stays focused
            errors = {
                sensorNoise = 0.10,         -- rushes, misreads the track
                lapseChance = 0.15,         -- rarely loses focus
                lapseDurationMin = 0.15,    -- short lapses
                lapseDurationMax = 0.35,
                steerJitter = 0.04,         -- fairly steady hands
                brakeLateChance = 0.30,     -- often ignores brake signal (enters corners too fast)
            },
        },
    },
    {
        name = "Cautious Clara",
        color = {0.9, 0.7, 0.1},
        stripeColor = {1.0, 0.85, 0.3},
        personality = {
            mutationRate = 0.10,
            mutationStrength = 0.2,
            initialBias = {
                throttle = 0.0,
                brake = 0.1,
                steerSensitivity = 0.2,
            },
            physics = {
                engineForce = 240000,
                brakeForce = 220000,
                baseTurnSpeed = 3.2,
                gripMultiplier = 1.05,
            },
            -- Cautious mistakes: loses concentration, overcorrects
            errors = {
                sensorNoise = 0.05,         -- careful reader
                lapseChance = 0.30,         -- drifts off more often
                lapseDurationMin = 0.25,    -- longer lapses
                lapseDurationMax = 0.60,
                steerJitter = 0.08,         -- overcorrects / wobbles
                brakeLateChance = 0.08,     -- rarely misjudges braking
            },
        },
    },
}

return profiles
