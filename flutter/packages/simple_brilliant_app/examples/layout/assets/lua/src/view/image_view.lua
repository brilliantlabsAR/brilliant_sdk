-- Body: Content area
-- ------------------
local View = require("view.min")

local function set_palette(num_colors, palette_data)
	local colors = {'VOID', 'WHITE', 'GREY', 'RED', 'PINK', 'DARKBROWN','BROWN', 'ORANGE', 'YELLOW', 'DARKGREEN', 'GREEN', 'LIGHTGREEN', 'NIGHTBLUE', 'SEABLUE', 'SKYBLUE', 'CLOUDBLUE'}

	-- we usually wouldn't want to reassign VOID, so the first entry should be black but we won't force it
	for i=1,num_colors do
		local col_offset = (i - 1) * 3

		-- Frame indexes are the color names, Halo indexes are 0-15
		local index
		if frame.HARDWARE_VERSION == 'Frame' then
			index = colors[i]
		else
			index = i-1
		end

		frame.display.assign_color(index,
			string.byte(palette_data, col_offset + 1),
			string.byte(palette_data, col_offset + 2),
			string.byte(palette_data, col_offset + 3))
	end
end

local ImageView = setmetatable({}, {__index = View})
ImageView.__index = ImageView
function ImageView:render()
    -- no need to self:clear()
    if self.lines then
        for i, spr in ipairs(self.lines) do
            local y_offset = self.y + (i-1) * self.line_height
            -- center the text sprites horizontally within the body view
            -- NOTE: splitting over two lines to avoid a minifier bug: self.x + (self.w - spr.width) // 2 -> self.x+self.w-d.width//2
            local width_diff = self.w - spr.width
            local x_offset = self.x + width_diff // 2
            if frame.HARDWARE_VERSION ~= 'Frame' then
                frame.display.bitmap(x_offset, y_offset, spr.width, 2^spr.bpp, 0, spr.pixel_data, {palette_data=spr.palette_data})
            else
                set_palette(spr.num_colors, spr.palette_data)
                frame.display.bitmap(x_offset, y_offset, spr.width, 2^spr.bpp, 0, spr.pixel_data)
            end
        end
    end
    self.is_dirty = false
end

function ImageView:set_lines(lines, line_height)
    self.lines = lines
    self.line_height = line_height
    self:invalidate()
end

function ImageView:clear_lines()
    if self.lines then
        for k in pairs(self.lines) do self.lines[k] = nil end
        self.lines = nil
    end
    self:invalidate()
end

return ImageView