local tracks = require("tracks")

describe("tracks", function()
    it("has at least 3 default tracks", function()
        expect_true(tracks.count() >= 3)
    end)

    it("getByIndex returns correct track", function()
        local first = tracks.getByIndex(1)
        expect_true(first ~= nil)
        expect_true(first.name ~= nil)
        expect_true(first.points ~= nil)
        expect_true(first.width ~= nil)
    end)

    it("getByIndex returns nil for out-of-range", function()
        local bad = tracks.getByIndex(9999)
        expect_eq(bad, nil)
    end)

    it("getById returns nil for unknown id", function()
        local unknown = tracks.getById("nonexistent")
        expect_eq(unknown, nil)
    end)

    it("all tracks have required properties", function()
        for i = 1, tracks.count() do
            local t = tracks.getByIndex(i)
            expect_true(t.id ~= nil, "Track " .. i .. " missing id")
            expect_true(t.name ~= nil, "Track " .. i .. " missing name")
            expect_true(t.description ~= nil, "Track " .. i .. " missing description")
            expect_true(t.width ~= nil, "Track " .. i .. " missing width")
            expect_true(t.points ~= nil, "Track " .. i .. " missing points")
            expect_true(#t.points >= 3, "Track " .. i .. " needs at least 3 points")
        end
    end)

    it("all track points have x and y coordinates", function()
        for i = 1, tracks.count() do
            local t = tracks.getByIndex(i)
            for j, p in ipairs(t.points) do
                expect_true(p.x ~= nil, "Track " .. i .. " point " .. j .. " missing x")
                expect_true(p.y ~= nil, "Track " .. i .. " point " .. j .. " missing y")
            end
        end
    end)

    it("all tracks have surface zones", function()
        for i = 1, tracks.count() do
            local t = tracks.getByIndex(i)
            expect_true(t.surfaceZones ~= nil, "Track " .. i .. " missing surfaceZones")
            expect_true(#t.surfaceZones >= 1, "Track " .. i .. " needs at least 1 surface zone")
        end
    end)

    it("surface zones cover 0 to 1 range", function()
        for i = 1, tracks.count() do
            local t = tracks.getByIndex(i)
            local zones = t.surfaceZones
            expect_near(zones[1].startPct, 0, 0.001, "Track " .. i .. " first zone should start at 0")
            expect_near(zones[#zones].endPct, 1, 0.001, "Track " .. i .. " last zone should end at 1")
        end
    end)

    it("default tracks are generated (have seed field)", function()
        for i = 1, 3 do
            local t = tracks.getByIndex(i)
            expect_true(t.seed ~= nil, "Default track " .. i .. " should have seed")
            expect_true(t.generated == true, "Default track " .. i .. " should be generated")
        end
    end)

    it("add() increases track count", function()
        local before = tracks.count()
        tracks.add({
            id = "test_track", name = "Test", description = "Test",
            width = 60, points = {{x=100,y=100},{x=200,y=100},{x=200,y=200},{x=100,y=200}},
            startAngle = 0, surfaceZones = {{startPct=0,endPct=1,grip=0.9,bumpiness=0.1,name="Test",color={0.5,0.5,0.5,0}}},
        })
        expect_eq(tracks.count(), before + 1)
        -- Clean up: remove the test track
        table.remove(tracks.list)
    end)
end)
