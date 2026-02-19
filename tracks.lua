-- Track definitions and configuration (pure logic, no Love2D dependency)
-- Each track is defined by control points that form a closed spline path

local tracks = {}

-- List of available tracks
tracks.list = {
    {
        id = "oval",
        name = "Classic Oval",
        description = "Simple oval - great for beginners",
        width = 75,
        -- Control points defining the center line of the track
        -- These will be interpolated into a smooth spline
        points = {
            {x = 400, y = 50},   -- top
            {x = 700, y = 150},  -- top-right
            {x = 750, y = 300},  -- right
            {x = 700, y = 450},  -- bottom-right
            {x = 400, y = 550},  -- bottom
            {x = 100, y = 450},  -- bottom-left
            {x = 50, y = 300},   -- left
            {x = 100, y = 150},  -- top-left
        },
        startAngle = 0,  -- car starts facing right
        surfaceZones = {
            { startPct = 0.0,  endPct = 0.15, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.15, endPct = 0.30, grip = 0.7,  bumpiness = 0.3,  name = "Worn Patch",    color = {0.6, 0.4, 0.2, 0.08} },
            { startPct = 0.30, endPct = 0.50, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.50, endPct = 0.65, grip = 0.85, bumpiness = 0.6,  name = "Bumpy Section", color = {0.4, 0.35, 0.3, 0.06} },
            { startPct = 0.65, endPct = 0.80, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.80, endPct = 1.0,  grip = 0.6,  bumpiness = 0.1,  name = "Damp Corner",   color = {0.2, 0.3, 0.7, 0.07} },
        },
    },
    {
        id = "serpentine",
        name = "Serpentine",
        description = "Winding S-curves through the hills",
        width = 65,
        points = {
            {x = 100, y = 100},
            {x = 300, y = 80},
            {x = 500, y = 180},
            {x = 700, y = 100},
            {x = 750, y = 200},
            {x = 650, y = 300},
            {x = 500, y = 350},
            {x = 350, y = 280},
            {x = 200, y = 350},
            {x = 100, y = 450},
            {x = 200, y = 530},
            {x = 400, y = 500},
            {x = 600, y = 530},
            {x = 700, y = 480},
            {x = 650, y = 400},
            {x = 500, y = 450},
            {x = 300, y = 420},
            {x = 150, y = 350},
            {x = 50, y = 250},
        },
        startAngle = 0,
        surfaceZones = {
            { startPct = 0.0,  endPct = 0.25, grip = 0.9,  bumpiness = 0.1,  name = "Mountain Road", color = {0.45, 0.4, 0.35, 0.05} },
            { startPct = 0.25, endPct = 0.40, grip = 0.7,  bumpiness = 0.4,  name = "Gravel Patch",  color = {0.6, 0.5, 0.4, 0.1} },
            { startPct = 0.40, endPct = 0.60, grip = 0.95, bumpiness = 0.05, name = "Fresh Tarmac",  color = {0.3, 0.3, 0.35, 0.0} },
            { startPct = 0.60, endPct = 0.75, grip = 0.65, bumpiness = 0.2,  name = "Wet Section",   color = {0.2, 0.25, 0.5, 0.08} },
            { startPct = 0.75, endPct = 1.0,  grip = 0.85, bumpiness = 0.15, name = "Shaded Road",   color = {0.35, 0.35, 0.4, 0.05} },
        },
    },
    {
        id = "figure8",
        name = "Figure Eight",
        description = "Cross yourself at the intersection!",
        width = 60,
        points = {
            {x = 200, y = 150},
            {x = 100, y = 250},
            {x = 150, y = 400},
            {x = 300, y = 480},
            {x = 450, y = 400},  -- crossing point approach
            {x = 550, y = 300},  -- crossing point
            {x = 650, y = 200},  -- after crossing
            {x = 700, y = 120},
            {x = 650, y = 80},
            {x = 500, y = 100},
            {x = 350, y = 180},  -- crossing point approach from other side
            {x = 250, y = 300},  -- near crossing
            {x = 200, y = 400},
            {x = 300, y = 500},
            {x = 500, y = 520},
            {x = 680, y = 450},
            {x = 720, y = 350},
            {x = 680, y = 280},
            {x = 550, y = 200},
            {x = 400, y = 150},
        },
        startAngle = -0.5,
        surfaceZones = {
            { startPct = 0.0,  endPct = 0.20, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.20, endPct = 0.35, grip = 0.8,  bumpiness = 0.25, name = "Worn Surface",  color = {0.55, 0.45, 0.35, 0.06} },
            { startPct = 0.35, endPct = 0.50, grip = 0.7,  bumpiness = 0.4,  name = "Crossing Zone", color = {0.6, 0.4, 0.3, 0.1} },
            { startPct = 0.50, endPct = 0.70, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.70, endPct = 0.85, grip = 0.85, bumpiness = 0.15, name = "Patched Road",  color = {0.4, 0.4, 0.45, 0.04} },
            { startPct = 0.85, endPct = 1.0,  grip = 0.9,  bumpiness = 0.1,  name = "Start Zone",    color = {0.5, 0.5, 0.5, 0.0} },
        },
    },
    {
        id = "coastal",
        name = "Coastal Circuit",
        description = "Tight turns along the scenic coast",
        width = 55,
        points = {
            {x = 150, y = 80},
            {x = 350, y = 60},
            {x = 550, y = 100},
            {x = 680, y = 180},
            {x = 720, y = 300},
            {x = 700, y = 420},
            {x = 600, y = 500},
            {x = 450, y = 540},
            {x = 300, y = 520},
            {x = 180, y = 460},
            {x = 100, y = 380},
            {x = 80, y = 280},
            {x = 120, y = 180},
            {x = 200, y = 120},
        },
        startAngle = 0.2,
        surfaceZones = {
            { startPct = 0.0,  endPct = 0.18, grip = 0.9,  bumpiness = 0.1,  name = "Coastal Road",  color = {0.5, 0.5, 0.55, 0.03} },
            { startPct = 0.18, endPct = 0.35, grip = 0.7,  bumpiness = 0.05, name = "Sandy Stretch", color = {0.7, 0.65, 0.5, 0.08} },
            { startPct = 0.35, endPct = 0.55, grip = 0.95, bumpiness = 0.05, name = "Cliff Road",    color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.55, endPct = 0.70, grip = 0.75, bumpiness = 0.3,  name = "Rocky Section", color = {0.5, 0.45, 0.4, 0.07} },
            { startPct = 0.70, endPct = 0.85, grip = 0.6,  bumpiness = 0.1,  name = "Wet Hairpin",   color = {0.25, 0.3, 0.55, 0.1} },
            { startPct = 0.85, endPct = 1.0,  grip = 0.9,  bumpiness = 0.08, name = "Harbor Road",   color = {0.5, 0.5, 0.5, 0.0} },
        },
    },
    {
        id = "speedring",
        name = "Speed Ring",
        description = "High-speed sweeping curves",
        width = 85,
        points = {
            {x = 400, y = 40},
            {x = 600, y = 60},
            {x = 740, y = 150},
            {x = 760, y = 300},
            {x = 720, y = 450},
            {x = 580, y = 540},
            {x = 400, y = 560},
            {x = 220, y = 540},
            {x = 80, y = 450},
            {x = 40, y = 300},
            {x = 60, y = 150},
            {x = 200, y = 60},
        },
        startAngle = 0,
        surfaceZones = {
            { startPct = 0.0,  endPct = 0.25, grip = 0.98, bumpiness = 0.02, name = "Racing Line",   color = {0.45, 0.45, 0.5, 0.0} },
            { startPct = 0.25, endPct = 0.50, grip = 0.95, bumpiness = 0.05, name = "Smooth Tarmac", color = {0.5, 0.5, 0.5, 0.0} },
            { startPct = 0.50, endPct = 0.75, grip = 0.98, bumpiness = 0.02, name = "Racing Line",   color = {0.45, 0.45, 0.5, 0.0} },
            { startPct = 0.75, endPct = 1.0,  grip = 0.92, bumpiness = 0.08, name = "Pit Straight",  color = {0.5, 0.5, 0.5, 0.0} },
        },
    },
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

return tracks
