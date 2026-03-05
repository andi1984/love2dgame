-- Shared spline utilities (pure Lua, no Love2D dependency)

local spline = {}

-- Catmull-Rom spline interpolation for smooth curves
function spline.catmullRom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    local x = 0.5 * ((2 * p1.x) +
        (-p0.x + p2.x) * t +
        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
    local y = 0.5 * ((2 * p1.y) +
        (-p0.y + p2.y) * t +
        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
    return {x = x, y = y}
end

return spline
