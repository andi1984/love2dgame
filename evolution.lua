-- Neuroevolution: (1+1) evolutionary strategy per NPC (pure logic)

local nnet = require("nnet")

local evolution = {}

-- Calculate fitness score from race performance
function evolution.calculateFitness(car, track, raceTime, lapsCompleted)
    local fitness = 0

    -- Primary: progress along track (heavily weighted)
    local trackPct = track.getTrackPercent(car.x, car.y)
    fitness = fitness + (lapsCompleted * 2000) + (trackPct * 2000)

    -- Secondary: average speed reward (only meaningful when on track)
    local avgSpeed = car.avgSpeed or 0
    fitness = fitness + avgSpeed * 3

    -- Strong penalty: time off track (primary learning signal)
    fitness = fitness - (car.timeOffTrack or 0) * 100

    -- Penalty: time spent stationary
    fitness = fitness - (car.timeStationary or 0) * 40

    -- Bonus: on-track ratio (reward staying on track throughout the race)
    if raceTime > 0 then
        local onTrackRatio = 1.0 - math.min(1.0, (car.timeOffTrack or 0) / raceTime)
        fitness = fitness + onTrackRatio * 500
    end

    -- Bonus: faster completion
    if lapsCompleted > 0 and raceTime > 0 then
        fitness = fitness + (1000 / raceTime) * lapsCompleted
    end

    return fitness
end

-- Evolve an NPC after a race using (1+1)-ES
function evolution.evolveAfterRace(npc)
    if npc.currentFitness > npc.bestFitness then
        -- Improvement: keep the current brain as the new best
        npc.bestBrain = nnet.serialize(npc.brain)
        npc.bestFitness = npc.currentFitness
        npc.generation = npc.generation + 1
        -- Small mutation for next race (exploit)
        npc.brain = nnet.mutate(
            nnet.deserialize(npc.bestBrain),
            npc.personality.mutationRate,
            npc.personality.mutationStrength * 0.5
        )
    else
        -- No improvement: revert to best and try a larger mutation (explore)
        npc.brain = nnet.mutate(
            nnet.deserialize(npc.bestBrain),
            npc.personality.mutationRate,
            npc.personality.mutationStrength
        )
    end
end

return evolution
