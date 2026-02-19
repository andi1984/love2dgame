-- Particle system (pure logic, no Love2D dependency)

local particles = {}

particles.list = {}

function particles.init()
    particles.list = {}
end

function particles.update(dt)
    for i = #particles.list, 1, -1 do
        local p = particles.list[i]
        p.life = p.life - dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * 0.95
        p.vy = p.vy * 0.95
        if p.life <= 0 then
            table.remove(particles.list, i)
        end
    end
end

function particles.spawnSmoke(car)
    local rearX = car.x - math.cos(car.angle) * car.width * 0.4
    local rearY = car.y - math.sin(car.angle) * car.height * 0.4
    for _ = 1, 2 do
        table.insert(particles.list, {
            x = rearX + (math.random() - 0.5) * 8,
            y = rearY + (math.random() - 0.5) * 8,
            life = 0.5,
            maxLife = 0.5,
            size = 3 + math.random() * 3,
            vx = (math.random() - 0.5) * 20,
            vy = (math.random() - 0.5) * 20,
        })
    end
end

return particles
