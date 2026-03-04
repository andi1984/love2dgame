local trackgen = require("trackgen")
local track = require("track")

describe("trackgen", function()
    it("generates a track config from a seed", function()
        local config = trackgen.generate(42)
        expect_true(config ~= nil)
        expect_true(config.name ~= nil)
        expect_true(config.description ~= nil)
        expect_true(config.width ~= nil)
        expect_true(config.points ~= nil)
        expect_true(config.startAngle ~= nil)
        expect_true(config.surfaceZones ~= nil)
        expect_true(config.seed ~= nil)
        expect_true(config.generated == true)
        expect_true(config.id ~= nil)
    end)

    it("is deterministic (same seed = same output)", function()
        local a = trackgen.generate(999)
        local b = trackgen.generate(999)
        expect_eq(a.name, b.name)
        expect_eq(#a.points, #b.points)
        expect_eq(a.width, b.width)
        for i = 1, #a.points do
            expect_near(a.points[i].x, b.points[i].x, 0.001, "point " .. i .. " x mismatch")
            expect_near(a.points[i].y, b.points[i].y, 0.001, "point " .. i .. " y mismatch")
        end
    end)

    it("different seeds produce different tracks", function()
        local a = trackgen.generate(42)
        local b = trackgen.generate(137)
        -- At least name or point count should differ
        local differ = (a.name ~= b.name) or (#a.points ~= #b.points)
        if not differ and #a.points == #b.points then
            for i = 1, #a.points do
                if math.abs(a.points[i].x - b.points[i].x) > 1 then
                    differ = true
                    break
                end
            end
        end
        expect_true(differ, "Seeds 42 and 137 should produce different tracks")
    end)

    it("points fit within 800x600 viewport", function()
        for _, seed in ipairs({42, 137, 314, 1000, 2024}) do
            local config = trackgen.generate(seed)
            for j, p in ipairs(config.points) do
                expect_true(p.x >= 0 and p.x <= 800,
                    "Seed " .. seed .. " point " .. j .. " x=" .. p.x .. " out of bounds")
                expect_true(p.y >= 0 and p.y <= 600,
                    "Seed " .. seed .. " point " .. j .. " y=" .. p.y .. " out of bounds")
            end
        end
    end)

    it("has at least 6 control points", function()
        local config = trackgen.generate(42)
        expect_true(#config.points >= 6, "Expected >= 6 points, got " .. #config.points)
    end)

    it("surface zones cover 0 to 1", function()
        local config = trackgen.generate(42)
        local zones = config.surfaceZones
        expect_true(#zones >= 4, "Expected >= 4 zones")
        expect_near(zones[1].startPct, 0, 0.001, "First zone should start at 0")
        expect_near(zones[#zones].endPct, 1, 0.001, "Last zone should end at 1")

        -- Check all zones have required fields
        for i, z in ipairs(zones) do
            expect_true(z.grip ~= nil, "Zone " .. i .. " missing grip")
            expect_true(z.bumpiness ~= nil, "Zone " .. i .. " missing bumpiness")
            expect_true(z.name ~= nil, "Zone " .. i .. " missing name")
            expect_true(z.color ~= nil, "Zone " .. i .. " missing color")
        end
    end)

    it("is compatible with track.initFromConfig", function()
        local config = trackgen.generate(42)
        track.initFromConfig(config)
        expect_true(track.centerPath ~= nil)
        expect_true(#track.centerPath > 0)
        expect_true(track.isOnTrack(track.startX, track.startY),
            "Start position should be on track")
    end)

    it("validatePoints rejects self-intersecting shapes", function()
        -- Create a figure-8 that definitely self-intersects
        local bad = {
            {x = 100, y = 100},
            {x = 700, y = 500},
            {x = 700, y = 100},
            {x = 100, y = 500},
        }
        expect_false(trackgen.validatePoints(bad, 60))
    end)

    it("works with multiple seeds without error", function()
        for seed = 1, 20 do
            local config = trackgen.generate(seed * 73)
            expect_true(config ~= nil, "Seed " .. (seed * 73) .. " returned nil")
            expect_true(#config.points >= 6, "Seed " .. (seed * 73) .. " too few points")
        end
    end)
end)
