-- Save/load NPC brain data (uses Love2D filesystem when available, falls back to io)

local persistence = {}

-- Serialize a Lua value to a string representation
local function serializeValue(v, indent)
    local t = type(v)
    if t == "number" then
        -- Use enough precision for neural network weights
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return tostring(v)
        end
        return string.format("%.17g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        return persistence.serialize(v, indent)
    end
    return "nil"
end

-- Serialize a table to a Lua source string
function persistence.serialize(tbl, indent)
    indent = indent or ""
    local nextIndent = indent .. "  "
    local parts = {}
    parts[#parts + 1] = "{"

    -- Check if table is array-like
    local isArray = true
    local maxN = 0
    for k in pairs(tbl) do
        if type(k) == "number" and k == math.floor(k) and k > 0 then
            if k > maxN then maxN = k end
        else
            isArray = false
            break
        end
    end

    if isArray and maxN > 0 and maxN <= #tbl + 1 then
        -- Compact array format for weight arrays
        if maxN > 20 then
            -- Large arrays: comma-separated on one line
            local vals = {}
            for i = 1, maxN do
                vals[i] = serializeValue(tbl[i], nextIndent)
            end
            parts[#parts + 1] = table.concat(vals, ",")
        else
            for i = 1, maxN do
                parts[#parts + 1] = nextIndent .. serializeValue(tbl[i], nextIndent) .. ","
            end
        end
    else
        -- Key-value pairs
        local keys = {}
        for k in pairs(tbl) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return tostring(a) < tostring(b) end
            return type(a) < type(b)
        end)
        for _, k in ipairs(keys) do
            local keyStr
            if type(k) == "number" then
                keyStr = "[" .. k .. "]"
            elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. string.format("%q", tostring(k)) .. "]"
            end
            parts[#parts + 1] = nextIndent .. keyStr .. " = " .. serializeValue(tbl[k], nextIndent) .. ","
        end
    end

    parts[#parts + 1] = indent .. "}"
    return table.concat(parts, "\n")
end

-- Save NPC data to file
function persistence.save(data)
    local str = "return " .. persistence.serialize(data) .. "\n"
    if love and love.filesystem then
        local success, err = love.filesystem.write("npc_brains.lua", str)
        return success, err
    end
    return false, "no filesystem available"
end

-- Load NPC data from file
function persistence.load()
    if love and love.filesystem then
        if love.filesystem.getInfo("npc_brains.lua") then
            local chunk = love.filesystem.load("npc_brains.lua")
            if chunk then
                local ok, data = pcall(chunk)
                if ok then return data end
            end
        end
    end
    return nil
end

return persistence
