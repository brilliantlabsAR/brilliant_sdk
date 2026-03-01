-- Background view (battery indicator plus circle)
-- -----------------------------------------------
local View = require("view")

-- Battery level: 0-100
-- 8 triangles cover the full display (each covers 45 degrees)
-- Every 12.5% battery loss = 1 grey triangle
-- Remaining triangles = blue

local cx, cy = 127, 127

-- The 8 triangle tip points, going clockwise from top
-- Center is 127,127. Each triangle: center + two adjacent edge points
local points = {
    {127, 0},      -- top (0)
    {255, 0},      -- top-right corner (45)
    {255, 127},    -- right (90)
    {255, 255},    -- bottom-right corner (135)
    {127, 255},    -- bottom (180)
    {0, 255},      -- bottom-left corner (225)
    {0, 127},      -- left (270)
    {0, 0},        -- top-left corner (315)
}

local function draw_battery(battery_level)
    -- Number of grey triangles (lost battery)
    local grey_count = math.floor((100 - battery_level) / 12.5)

    for i = 1, 8 do
        local p1 = points[i]
        local p2 = points[(i % 8) + 1]
        local color
        if i <= grey_count then
            color = 0x888888  -- grey = lost battery
        else
            color = 0x4444FF  -- blue = remaining battery
        end
        frame.display.polygon(
            {cx, cy, p1[1], p1[2], p2[1], p2[2]},
            color
        )
    end
end

local BgView = setmetatable({}, {__index = View})
BgView.__index = BgView
function BgView:render()
    if frame.HARDWARE_VERSION ~= 'Frame' then
        -- black background
        -- not necessary since we now cover the whole display
        --frame.display.clear(0x000000)

        -- blue/grey triangles for battery level
        draw_battery(self.last_batt)

        -- black circle
        frame.display.circle(127, 127, 110, 0x000000, true)
    end
    self.is_dirty = false
end

function BgView:update(dt)
    if frame.HARDWARE_VERSION ~= 'Frame' then
            -- on Halo we need to redraw the battery indicator every frame since we don't have a separate view layer for it and we want it to be visible on all layouts, but on Frame we draw it once in the bg_view and it stays there since we have a separate view layer for it
        local batt = frame.battery_level()

        -- TODO smooth this out so we don't flap between two battery levels when hovering around a threshold
        if batt ~= self.last_batt then
            self.last_batt = batt

            self:invalidate()
        end
    end
end

return BgView