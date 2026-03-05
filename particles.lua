-- Particle system (pure logic, no Love2D dependency)

local particles = {}
local cos, sin, random, pi = math.cos, math.sin, math.random, math.pi

particles.list = {}

function particles.init()
    particles.list = {}
end

function particles.update(dt)
    for i = #particles.list, 1, -1 do
        local p = particles.list[i]
        p.life = p.life - dt
        p.x    = p.x + p.vx * dt
        p.y    = p.y + p.vy * dt
        p.vx   = p.vx * 0.95
        p.vy   = p.vy * 0.95
        if p.life <= 0 then
            table.remove(particles.list, i)
        end
    end
end

-- White/grey tyre-smoke (braking / sharp turns)
function particles.spawnSmoke(car)
    local rearX = car.x - cos(car.angle) * car.width * 0.4
    local rearY = car.y - sin(car.angle) * car.height * 0.4
    for _ = 1, 2 do
        table.insert(particles.list, {
            x      = rearX + (random() - 0.5) * 8,
            y      = rearY + (random() - 0.5) * 8,
            life   = 0.5,
            maxLife = 0.5,
            size   = 3 + random() * 3,
            vx     = (random() - 0.5) * 20,
            vy     = (random() - 0.5) * 20,
            -- no color field → draw.lua uses default grey
        })
    end
end

-- Dark/black engine-damage smoke
function particles.spawnDarkSmoke(car)
    local rearX = car.x - cos(car.angle) * car.width * 0.45
    local rearY = car.y - sin(car.angle) * car.height * 0.45
    -- Spawn less frequently (caller controls rate)
    table.insert(particles.list, {
        x      = rearX + (random() - 0.5) * 6,
        y      = rearY + (random() - 0.5) * 6,
        life   = 1.2,
        maxLife = 1.2,
        size   = 5 + random() * 5,
        vx     = (random() - 0.5) * 12,
        vy     = (random() - 0.5) * 12 - 8,  -- drift upward
        color  = { 0.12, 0.10, 0.10, 1.0 },        -- near-black
    })
end

-- Yellow/orange sparks for collisions
-- side: "front"|"rear"|"left"|"right" or nil
function particles.spawnSparks(car, side)
    -- Determine spark origin based on impact side
    local ox, oy = car.x, car.y
    local hw, hh = car.width / 2, car.height / 2
    local ca, sa = cos(car.angle), sin(car.angle)

    if side == "front" then
        ox = car.x + ca * hw
        oy = car.y + sa * hw
    elseif side == "rear" then
        ox = car.x - ca * hw
        oy = car.y - sa * hw
    elseif side == "left" then
        ox = car.x - sa * hh
        oy = car.y + ca * hh
    elseif side == "right" then
        ox = car.x + sa * hh
        oy = car.y - ca * hh
    end

    local numSparks = 6 + random(5)
    for _ = 1, numSparks do
        local angle  = random() * pi * 2
        local speed  = 40 + random() * 120
        -- Color from bright white-yellow → orange
        local r = 1.0
        local g = 0.5 + random() * 0.5
        local b = random() * 0.2
        table.insert(particles.list, {
            x      = ox + (random() - 0.5) * 6,
            y      = oy + (random() - 0.5) * 6,
            life   = 0.15 + random() * 0.25,
            maxLife = 0.4,
            size   = 1.5 + random() * 2,
            vx     = cos(angle) * speed,
            vy     = sin(angle) * speed,
            color  = { r, g, b, 1.0 },
        })
    end
end

return particles
