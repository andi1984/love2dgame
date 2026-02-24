local game = require("game")
local track = require("track")
local tracks = require("tracks")

describe("game", function()
    it("initializes with correct defaults", function()
        game.init()
        expect_eq(game.carLaps[1], 0)
        expect_eq(game.maxLaps, 3)
        expect_eq(game.timer, 0)
        expect_false(game.won)
        expect_false(game.started)
        expect_eq(game.countdown, 3)
    end)

    it("initializes with multiple cars", function()
        game.init(3)
        expect_eq(#game.carLaps, 3)
        expect_eq(game.carLaps[1], 0)
        expect_eq(game.carLaps[2], 0)
        expect_eq(game.carLaps[3], 0)
    end)

    it("countdown decreases over time", function()
        game.init()
        game.updateCountdown(1.0)
        expect_near(game.countdown, 2.0, 0.001)
        expect_false(game.started)
    end)

    it("game starts when countdown reaches zero", function()
        game.init()
        game.updateCountdown(3.5)
        expect_true(game.started)
    end)

    it("checkFinishLine increments laps when crossing left-to-right", function()
        game.init()
        track.init()
        local prevX = track.finishX - 5
        local newX = track.finishX + 5
        local y = (track.finishY1 + track.finishY2) / 2
        game.checkFinishLine(track, prevX, y, newX, y)
        expect_eq(game.carLaps[1], 1)
    end)

    it("checkFinishLine does NOT increment laps when crossing right-to-left", function()
        game.init()
        track.init()
        local prevX = track.finishX + 5
        local newX = track.finishX - 5
        local y = (track.finishY1 + track.finishY2) / 2
        game.checkFinishLine(track, prevX, y, newX, y)
        expect_eq(game.carLaps[1], 0)
    end)

    it("checkFinishLine does NOT count if crossing outside finish line y-range", function()
        game.init()
        track.init()
        local prevX = track.finishX - 5
        local newX = track.finishX + 5
        local y = 10
        game.checkFinishLine(track, prevX, y, newX, y)
        expect_eq(game.carLaps[1], 0)
    end)

    it("game is won after maxLaps crossings", function()
        game.init()
        track.init()
        local y = (track.finishY1 + track.finishY2) / 2
        for _ = 1, game.maxLaps do
            game.checkFinishLine(track, track.finishX - 5, y, track.finishX + 5, y)
        end
        expect_eq(game.carLaps[1], game.maxLaps)
        expect_true(game.won)
        expect_eq(game.winnerIndex, 1)
    end)

    it("tracks laps per car independently", function()
        game.init(3)
        track.init()
        local y = (track.finishY1 + track.finishY2) / 2
        game.checkFinishLine(track, track.finishX - 5, y, track.finishX + 5, y, 2)
        expect_eq(game.carLaps[1], 0)
        expect_eq(game.carLaps[2], 1)
        expect_eq(game.carLaps[3], 0)
    end)

    it("NPC can win the race", function()
        game.init(3)
        track.init()
        local y = (track.finishY1 + track.finishY2) / 2
        for _ = 1, game.maxLaps do
            game.checkFinishLine(track, track.finishX - 5, y, track.finishX + 5, y, 2)
        end
        expect_true(game.won)
        expect_eq(game.winnerIndex, 2)
    end)

    it("player (car 1) can win before NPC in a 3-car race", function()
        game.init(3)
        track.init()
        local y = (track.finishY1 + track.finishY2) / 2
        -- Player completes all laps first
        for _ = 1, game.maxLaps do
            game.checkFinishLine(track, track.finishX - 5, y, track.finishX + 5, y, 1)
        end
        expect_true(game.won)
        expect_eq(game.winnerIndex, 1)
        -- NPC completing laps after should not change winner
        for _ = 1, game.maxLaps do
            game.checkFinishLine(track, track.finishX - 5, y, track.finishX + 5, y, 2)
        end
        expect_eq(game.winnerIndex, 1)
    end)

    it("evolutionDone is reset on init", function()
        game.init(3)
        game.evolutionDone = true
        game.init(3)
        expect_false(game.evolutionDone)
    end)

    it("finish line works on Figure Eight track (non-horizontal start)", function()
        local fig8 = tracks.getById("figure8")
        expect_true(fig8 ~= nil, "figure8 track not found")
        track.initFromConfig(fig8)
        game.init(1)

        -- The car should be able to complete a lap by crossing the finish line
        -- in the track's forward direction, regardless of track orientation
        local fwd = track.finishForward
        expect_true(fwd ~= nil, "track.finishForward not set")

        -- Simulate crossing the finish line in the forward direction
        local cx = track.finishPoint.x
        local cy = track.finishPoint.y
        local prevX = cx - fwd.x * 5
        local prevY = cy - fwd.y * 5
        local newX = cx + fwd.x * 5
        local newY = cy + fwd.y * 5
        game.checkFinishLine(track, prevX, prevY, newX, newY, 1)
        expect_eq(game.carLaps[1], 1, "lap should count when crossing in forward direction")
    end)

    it("finish line rejects backward crossing on Figure Eight", function()
        local fig8 = tracks.getById("figure8")
        track.initFromConfig(fig8)
        game.init(1)

        local fwd = track.finishForward
        -- Cross BACKWARD (reverse of forward direction)
        local cx = track.finishPoint.x
        local cy = track.finishPoint.y
        local prevX = cx + fwd.x * 5
        local prevY = cy + fwd.y * 5
        local newX = cx - fwd.x * 5
        local newY = cy - fwd.y * 5
        game.checkFinishLine(track, prevX, prevY, newX, newY, 1)
        expect_eq(game.carLaps[1], 0, "lap should NOT count when crossing backward")
    end)

    it("finish line works on all tracks", function()
        for _, cfg in ipairs(tracks.list) do
            track.initFromConfig(cfg)
            game.init(1)

            local fwd = track.finishForward
            expect_true(fwd ~= nil, cfg.name .. ": track.finishForward not set")

            local cx = track.finishPoint.x
            local cy = track.finishPoint.y
            local prevX = cx - fwd.x * 5
            local prevY = cy - fwd.y * 5
            local newX = cx + fwd.x * 5
            local newY = cy + fwd.y * 5
            game.checkFinishLine(track, prevX, prevY, newX, newY, 1)
            expect_eq(game.carLaps[1], 1,
                cfg.name .. ": lap should count when crossing finish in forward direction")
        end
    end)
end)
