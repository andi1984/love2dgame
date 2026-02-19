-- Main menu with track selection (pure logic, no Love2D dependency)

local tracks = require("tracks")

local menu = {}

function menu.init()
    menu.selectedTrack = 1
    menu.selectedButton = "track"  -- "track" or "controls"
    menu.trackCount = tracks.count()
end

function menu.selectNext()
    if menu.selectedButton == "track" then
        menu.selectedTrack = menu.selectedTrack + 1
        if menu.selectedTrack > menu.trackCount then
            menu.selectedTrack = 1
        end
    end
end

function menu.selectPrev()
    if menu.selectedButton == "track" then
        menu.selectedTrack = menu.selectedTrack - 1
        if menu.selectedTrack < 1 then
            menu.selectedTrack = menu.trackCount
        end
    end
end

function menu.moveUp()
    if menu.selectedButton == "controls" then
        menu.selectedButton = "track"
    end
end

function menu.moveDown()
    if menu.selectedButton == "track" then
        menu.selectedButton = "controls"
    end
end

function menu.getSelectedTrack()
    return tracks.getByIndex(menu.selectedTrack)
end

function menu.getTrackList()
    return tracks.list
end

-- Handle mouse click on menu items
-- Returns: "start", "controls", or nil
function menu.handleClick(x, y, screenWidth, screenHeight)
    -- Track cards layout
    local startY = 180
    local cardW = 160
    local cardH = 120
    local padding = 20
    local cols = 3
    
    -- Calculate grid position
    local totalW = cols * cardW + (cols - 1) * padding
    local startX = (screenWidth - totalW) / 2
    
    for i, _ in ipairs(tracks.list) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cardX = startX + col * (cardW + padding)
        local cardY = startY + row * (cardH + padding)
        
        if x >= cardX and x <= cardX + cardW and y >= cardY and y <= cardY + cardH then
            menu.selectedTrack = i
            menu.selectedButton = "track"
            return "start"
        end
    end
    
    -- Controls button
    local btnW = 200
    local btnH = 40
    local btnX = (screenWidth - btnW) / 2
    local btnY = screenHeight - 80
    
    if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
        return "controls"
    end
    
    return nil
end

return menu
