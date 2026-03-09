-- Background view (battery indicator plus circle)
-- -----------------------------------------------
local View = require("view.min")

local BgView = setmetatable({}, {__index = View})
BgView.__index = BgView

-- Configuration
local CX, CY = 128, 128
local OUTER_RADIUS = 127
local INNER_RADIUS = 110
local NUM_SEGMENTS = 64

local outer_points = {}
local inner_points = {}

-- Track the state so we only draw what changes
local current_active_segments = -1
local last_active_segments = -1

-- TODO update to clamp between 1..256 after 0.7.7
local function roundClamp(value)
    local int_val = math.floor(value + 0.5)
    if int_val < 0 then return 0 end
    if int_val > 255 then return 255 end
    return int_val
end

-- 1. Pre-calculate vertices on initialization
local function initAnnulus()
    local angle_step = (math.pi * 2) / NUM_SEGMENTS
    for i = 0, NUM_SEGMENTS do
        local angle = (i * angle_step) - (math.pi / 2)
        local cos_a = math.cos(angle)
        local sin_a = math.sin(angle)
        
        table.insert(outer_points, { x = roundClamp(CX + cos_a * OUTER_RADIUS), y = roundClamp(CY + sin_a * OUTER_RADIUS) })
        table.insert(inner_points, { x = roundClamp(CX + cos_a * INNER_RADIUS), y = roundClamp(CY + sin_a * INNER_RADIUS) })
    end
end
initAnnulus()

-- 2. Helper function to render a single segment
local function renderSegment(index, is_active)
    local out1, out2 = outer_points[index], outer_points[index + 1]
    local in1, in2   = inner_points[index], inner_points[index + 1]

    local color = is_active and 0x4444FF or 0x888888
    frame.display.polygon({in1.x, in1.y, out1.x, out1.y, out2.x, out2.y}, color)
    frame.display.polygon({in1.x, in1.y, out2.x, out2.y, in2.x, in2.y}, color)    
end

-- blue/grey triangles for battery level, only draw changed segments
function BgView:render()
    if frame.HARDWARE_VERSION ~= 'Frame' then
        -- Case A: First time drawing, draw everything
        if last_active_segments == -1 then
            for i = 1, NUM_SEGMENTS do
                renderSegment(i, i <= current_active_segments)
            end
            
        -- Case B: Battery increased (e.g., charging), draw the newly lit segments
        elseif current_active_segments > last_active_segments then
            for i = last_active_segments + 1, current_active_segments do
                renderSegment(i, true)
            end
            
        -- Case C: Battery decreased, draw the newly darkened segments
        elseif current_active_segments < last_active_segments then
            for i = current_active_segments + 1, last_active_segments do
                renderSegment(i, false)
            end
        end
        -- (If current == last, do nothing at all - but should not be called)

        last_active_segments = current_active_segments
    end
    self.is_dirty = false
end

function BgView:update(dt)
    -- only Halo can draw the filled triangles
    if frame.HARDWARE_VERSION ~= 'Frame' then
        current_active_segments = math.ceil((frame.battery_level() / 100) * NUM_SEGMENTS)

        -- TODO smooth this out so we don't flap between two battery levels when hovering around a threshold
        -- It's already okay because we're in segment space not battery % space
        if current_active_segments ~= last_active_segments then
            self.is_dirty = true
        end
    end
end

function BgView:invalidate()
    self.is_dirty = true
    current_active_segments = -1
    last_active_segments = -1
end

return BgView