local game = require("game")
local track = require("track")

describe("game", function()
    it("initializes with correct defaults", function()
        game.init()
        expect_eq(game.laps, 0)
        expect_eq(game.maxLaps, 3)
        expect_eq(game.timer, 0)
        expect_false(game.won)
        expect_false(game.started)
        expect_eq(game.countdown, 3)
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
        expect_eq(game.laps, 1)
    end)

    it("checkFinishLine does NOT increment laps when crossing right-to-left", function()
        game.init()
        track.init()
        local prevX = track.finishX + 5
        local newX = track.finishX - 5
        local y = (track.finishY1 + track.finishY2) / 2
        game.checkFinishLine(track, prevX, y, newX, y)
        expect_eq(game.laps, 0)
    end)

    it("checkFinishLine does NOT count if crossing outside finish line y-range", function()
        game.init()
        track.init()
        local prevX = track.finishX - 5
        local newX = track.finishX + 5
        local y = 10 -- well above the finish line
        game.checkFinishLine(track, prevX, y, newX, y)
        expect_eq(game.laps, 0)
    end)

    it("game is won after maxLaps crossings", function()
        game.init()
        track.init()
        local y = (track.finishY1 + track.finishY2) / 2
        for _ = 1, game.maxLaps do
            game.checkFinishLine(track, track.finishX - 5, y, track.finishX + 5, y)
        end
        expect_eq(game.laps, game.maxLaps)
        expect_true(game.won)
    end)
end)
