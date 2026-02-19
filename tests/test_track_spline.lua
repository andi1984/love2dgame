local track = require("track")
local tracks = require("tracks")

describe("track (spline-based)", function()
    it("initFromConfig creates track from config", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        expect_eq(track.name, "Classic Oval")
        expect_eq(track.width, config.width)
        expect_true(track.centerPath ~= nil)
        expect_true(#track.centerPath > 0)
    end)

    it("generates inner and outer paths", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        expect_true(track.innerPath ~= nil)
        expect_true(track.outerPath ~= nil)
        expect_eq(#track.innerPath, #track.centerPath)
        expect_eq(#track.outerPath, #track.centerPath)
    end)

    it("sets up start position", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        expect_true(track.startX ~= nil)
        expect_true(track.startY ~= nil)
        expect_true(track.startAngle ~= nil)
    end)

    it("sets up finish line", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        expect_true(track.finishX ~= nil)
        expect_true(track.finishY1 ~= nil)
        expect_true(track.finishY2 ~= nil)
    end)

    it("isOnTrack returns true for point on track", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        -- Use start position which should be on track
        expect_true(track.isOnTrack(track.startX, track.startY))
    end)

    it("isOnTrack returns false for point off track", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        -- Far corner should be off track
        expect_false(track.isOnTrack(0, 0))
    end)

    it("getSurfaceAt returns valid zone", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        local zone = track.getSurfaceAt(track.startX, track.startY)
        expect_true(zone ~= nil)
        expect_true(zone.grip ~= nil)
        expect_true(zone.bumpiness ~= nil)
        expect_true(zone.name ~= nil)
    end)

    it("generates curbs", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        expect_true(track.outerCurbs ~= nil)
        expect_true(track.innerCurbs ~= nil)
        expect_true(#track.outerCurbs > 0)
        expect_true(#track.innerCurbs > 0)
    end)

    it("generates trees", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        expect_true(track.trees ~= nil)
        expect_true(#track.trees > 0)
    end)

    it("getCircumference returns path length", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        local circumference = track.getCircumference()
        expect_true(circumference > 0)
    end)

    it("getTrackPercent returns value between 0 and 1", function()
        local config = tracks.getById("oval")
        track.initFromConfig(config)
        
        local pct = track.getTrackPercent(track.startX, track.startY)
        expect_true(pct >= 0 and pct <= 1)
    end)

    it("works with all defined tracks", function()
        for i = 1, tracks.count() do
            local config = tracks.getByIndex(i)
            track.initFromConfig(config)
            
            expect_true(track.centerPath ~= nil, "Track " .. config.name .. " failed to init")
            expect_true(#track.centerPath > 0, "Track " .. config.name .. " has no path")
            expect_true(track.isOnTrack(track.startX, track.startY), 
                "Track " .. config.name .. " start pos not on track")
        end
    end)

    it("legacy init() still works", function()
        track.init()
        
        expect_true(track.centerPath ~= nil)
        expect_true(track.isOnTrack(track.startX, track.startY))
    end)
end)
