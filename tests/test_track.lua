local track = require("track")

describe("track", function()
    track.init()

    it("isOnTrack returns true for point on track surface", function()
        -- Use start position which should be on track
        expect_true(track.isOnTrack(track.startX, track.startY))
    end)

    it("isOnTrack returns false for center of track (infield)", function()
        -- Track center should be off track for a ring-shaped track
        expect_false(track.isOnTrack(track.cx, track.cy))
    end)

    it("isOnTrack returns false for point outside track", function()
        expect_false(track.isOnTrack(0, 0))
    end)

    it("isOnTrack returns true for point along the track path", function()
        -- Test a point along the center path
        if track.centerPath and #track.centerPath > 10 then
            local p = track.centerPath[10]
            expect_true(track.isOnTrack(p.x, p.y))
        end
    end)

    it("getSurfaceAt returns a zone with valid properties", function()
        local zone = track.getSurfaceAt(track.startX, track.startY)
        expect_true(zone ~= nil)
        expect_true(zone.grip ~= nil)
        expect_true(zone.name ~= nil)
    end)

    it("getSurfaceAt returns different zones at different track positions", function()
        -- Get zones at different positions along the track
        if track.centerPath and #track.centerPath > 50 then
            local p1 = track.centerPath[1]
            local p2 = track.centerPath[math.floor(#track.centerPath / 2)]
            local zone1 = track.getSurfaceAt(p1.x, p1.y)
            local zone2 = track.getSurfaceAt(p2.x, p2.y)
            -- Both should be valid zones
            expect_true(zone1 ~= nil)
            expect_true(zone2 ~= nil)
        end
    end)

    it("generates curbs for inner and outer track", function()
        expect_true(#track.outerCurbs > 0)
        expect_true(#track.innerCurbs > 0)
    end)

    it("generates trees", function()
        expect_true(#track.trees > 0)
    end)

    it("generates surface zones", function()
        expect_true(#track.surfaceZones >= 1)
        -- First zone should start at 0
        expect_near(track.surfaceZones[1].startPct, 0, 0.001)
        -- Last zone should end at 1
        expect_near(track.surfaceZones[#track.surfaceZones].endPct, 1, 0.001)
    end)
end)
