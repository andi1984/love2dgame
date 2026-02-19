local track = require("track")

describe("track", function()
    track.init()

    it("isOnTrack returns true for point on track surface", function()
        -- Top of track, between inner and outer ellipse
        local y = track.cy - (track.innerRy + track.outerRy) / 2
        expect_true(track.isOnTrack(track.cx, y))
    end)

    it("isOnTrack returns false for center of track (infield)", function()
        expect_false(track.isOnTrack(track.cx, track.cy))
    end)

    it("isOnTrack returns false for point outside track", function()
        expect_false(track.isOnTrack(0, 0))
    end)

    it("isOnTrack returns true for right side of track", function()
        local x = track.cx + (track.innerRx + track.outerRx) / 2
        expect_true(track.isOnTrack(x, track.cy))
    end)

    it("getSurfaceAt returns a zone with valid properties", function()
        local zone = track.getSurfaceAt(track.cx + track.midRx, track.cy)
        expect_true(zone ~= nil)
        expect_true(zone.grip ~= nil)
        expect_true(zone.name ~= nil)
    end)

    it("getSurfaceAt returns different zones at different angles", function()
        -- Right side (angle ~0)
        local zone1 = track.getSurfaceAt(track.cx + track.midRx, track.cy)
        -- Bottom-right (angle ~pi*0.4, "Worn Patch" region)
        local x2 = track.cx + math.cos(math.pi * 0.4) * track.midRx
        local y2 = track.cy + math.sin(math.pi * 0.4) * track.midRy
        local zone2 = track.getSurfaceAt(x2, y2)
        expect_eq(zone1.name, "Smooth Tarmac")
        expect_eq(zone2.name, "Worn Patch")
    end)

    it("generates curbs for inner and outer track", function()
        expect_true(#track.outerCurbs > 0)
        expect_true(#track.innerCurbs > 0)
        expect_eq(#track.outerCurbs, 80)
        expect_eq(#track.innerCurbs, 80)
    end)

    it("generates trees", function()
        expect_true(#track.trees > 0)
    end)

    it("generates surface zones covering 0 to 2*pi", function()
        expect_eq(#track.surfaceZones, 8)
        expect_near(track.surfaceZones[1].angleStart, 0, 0.001)
        expect_near(track.surfaceZones[#track.surfaceZones].angleEnd, math.pi * 2, 0.001)
    end)
end)
