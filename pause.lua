-- Pause menu UI (pure logic, no Love2D dependency)

local pause = {}

-- Menu options
pause.options = {"Resume", "Controls", "Main Menu"}

function pause.init()
    pause.selectedIndex = 1
end

function pause.moveUp()
    pause.selectedIndex = pause.selectedIndex - 1
    if pause.selectedIndex < 1 then
        pause.selectedIndex = #pause.options
    end
end

function pause.moveDown()
    pause.selectedIndex = pause.selectedIndex + 1
    if pause.selectedIndex > #pause.options then
        pause.selectedIndex = 1
    end
end

function pause.getSelected()
    return pause.options[pause.selectedIndex]
end

function pause.getSelectedIndex()
    return pause.selectedIndex
end

function pause.getOptions()
    return pause.options
end

-- Handle mouse click on pause menu
-- Returns: "resume", "controls", "mainmenu", or nil
function pause.handleClick(x, y, screenWidth, screenHeight)
    local menuW = 200
    local menuH = 180
    local menuX = (screenWidth - menuW) / 2
    local menuY = (screenHeight - menuH) / 2
    
    local btnH = 35
    local btnPadding = 10
    local startY = menuY + 50
    
    for i, option in ipairs(pause.options) do
        local btnY = startY + (i - 1) * (btnH + btnPadding)
        
        if x >= menuX + 20 and x <= menuX + menuW - 20 and
           y >= btnY and y <= btnY + btnH then
            pause.selectedIndex = i
            if option == "Resume" then
                return "resume"
            elseif option == "Controls" then
                return "controls"
            elseif option == "Main Menu" then
                return "mainmenu"
            end
        end
    end
    
    return nil
end

return pause
