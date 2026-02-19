-- Dev menu with physics sliders

local devmenu = {}

function devmenu.init(physics)
    devmenu.open = false
    devmenu.activeSlider = nil
    devmenu.panelX = 530
    devmenu.panelY = 10
    devmenu.panelW = 260
    devmenu.sliderH = 16
    devmenu.sliderPad = 22
    devmenu.sliders = {
        { label = "Car Mass",      unit = "kg",  min = 400,   max = 1500,  get = function() return physics.mass end,              set = function(v) physics.mass = v end },
        { label = "Fuel",          unit = "kg",  min = 0,     max = 50,    get = function() return physics.fuelMass end,           set = function(v) physics.fuelMass = v end },
        { label = "Fuel Rate",     unit = "kg/s",min = 0,     max = 5,     get = function() return physics.fuelRate end,           set = function(v) physics.fuelRate = v end },
        { label = "Tire Pressure", unit = "bar", min = 1.5,   max = 3.0,   get = function() return physics.tirePressure end,       set = function(v) physics.tirePressure = v end },
        { label = "Engine Force",  unit = "",    min = 50000, max = 500000,get = function() return physics.engineForce end,        set = function(v) physics.engineForce = v end },
        { label = "Brake Force",   unit = "",    min = 50000, max = 400000,get = function() return physics.brakeForce end,         set = function(v) physics.brakeForce = v end },
        { label = "Drag Coeff",    unit = "",    min = 0.5,   max = 10.0,  get = function() return physics.dragCoeff end,          set = function(v) physics.dragCoeff = v end },
        { label = "Rolling Res.",  unit = "",    min = 0.005,  max = 0.05, get = function() return physics.rollingResistance end,  set = function(v) physics.rollingResistance = v end },
        { label = "Grip Multi.",   unit = "x",   min = 0.1,   max = 1.5,   get = function() return physics.gripMultiplier end,     set = function(v) physics.gripMultiplier = v end },
        { label = "Bump Multi.",   unit = "x",   min = 0.0,   max = 3.0,   get = function() return physics.bumpMultiplier end,     set = function(v) physics.bumpMultiplier = v end },
    }
end

function devmenu.mousepressed(x, y, button)
    if not devmenu.open or button ~= 1 then return end
    for i, s in ipairs(devmenu.sliders) do
        local sy = devmenu.panelY + 30 + (i - 1) * devmenu.sliderPad
        local sx = devmenu.panelX + 105
        local sw = devmenu.panelW - 115
        if x >= sx and x <= sx + sw and y >= sy and y <= sy + devmenu.sliderH then
            devmenu.activeSlider = i
            local t = math.max(0, math.min(1, (x - sx) / sw))
            s.set(s.min + t * (s.max - s.min))
        end
    end
end

function devmenu.mousereleased(x, y, button)
    if button == 1 then
        devmenu.activeSlider = nil
    end
end

function devmenu.mousemoved(x, y)
    if not devmenu.open or not devmenu.activeSlider then return end
    local s = devmenu.sliders[devmenu.activeSlider]
    local sx = devmenu.panelX + 105
    local sw = devmenu.panelW - 115
    local t = math.max(0, math.min(1, (x - sx) / sw))
    s.set(s.min + t * (s.max - s.min))
end

return devmenu
