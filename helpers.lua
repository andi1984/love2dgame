-- Drawing utility functions (requires Love2D)

local helpers = {}
local cos, sin, pi = math.cos, math.sin, math.pi

local SEGMENTS = 64

local function buildEllipseVertices(cx, cy, rx, ry)
    local vertices = {}
    for i = 0, SEGMENTS - 1 do
        local angle = (i / SEGMENTS) * pi * 2
        vertices[#vertices + 1] = cx + cos(angle) * rx
        vertices[#vertices + 1] = cy + sin(angle) * ry
    end
    return vertices
end

function helpers.drawFilledEllipse(cx, cy, rx, ry)
    love.graphics.polygon("fill", buildEllipseVertices(cx, cy, rx, ry))
end

function helpers.drawEllipseOutline(cx, cy, rx, ry)
    love.graphics.polygon("line", buildEllipseVertices(cx, cy, rx, ry))
end

return helpers
