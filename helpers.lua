-- Drawing utility functions (requires Love2D)

local helpers = {}

function helpers.drawFilledEllipse(cx, cy, rx, ry)
    local segments = 64
    local vertices = {}
    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2
        table.insert(vertices, cx + math.cos(angle) * rx)
        table.insert(vertices, cy + math.sin(angle) * ry)
    end
    love.graphics.polygon("fill", vertices)
end

function helpers.drawEllipseOutline(cx, cy, rx, ry)
    local segments = 64
    local vertices = {}
    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2
        table.insert(vertices, cx + math.cos(angle) * rx)
        table.insert(vertices, cy + math.sin(angle) * ry)
    end
    love.graphics.polygon("line", vertices)
end

return helpers
