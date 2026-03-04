-- Track definitions and configuration (pure logic, no Love2D dependency)
-- Default tracks are procedurally generated from fixed seeds

local trackgen = require("trackgen")

local tracks = {}

-- Generate 3 default tracks from fixed seeds
tracks.list = {
    trackgen.generate(42),
    trackgen.generate(137),
    trackgen.generate(314),
}

function tracks.getById(id)
    for _, t in ipairs(tracks.list) do
        if t.id == id then
            return t
        end
    end
    return nil
end

function tracks.getByIndex(index)
    return tracks.list[index]
end

function tracks.count()
    return #tracks.list
end

function tracks.add(config)
    table.insert(tracks.list, config)
end

return tracks
