-- base_layout.lua
local View = require("view")

local BaseLayout = setmetatable({}, {__index = View})
BaseLayout.__index = BaseLayout

function BaseLayout:new(x, y, w, h)
    local obj = View.new(self, x or 0, y or 0, w or 256, h or 256)
    obj.children = {} -- Maintains the render and update order
    return obj
end

-- Helper method to register a view to the layout
function BaseLayout:add_child(name, view_obj)
    self[name] = view_obj
    table.insert(self.children, name)
end

function BaseLayout:update(dt)
    for _, name in ipairs(self.children) do
        local child = self[name]
        if child and child.update then
            child:update(dt)
            if child.is_dirty then
                self.is_dirty = true
            end
        end
    end
end

function BaseLayout:render()
    if not self.is_dirty then return end

    for _, name in ipairs(self.children) do
        local child = self[name]
        if child and child.is_dirty then
            child:clear()
            child:render()
            child.is_dirty = false
        end
    end

    self.is_dirty = false
end

return BaseLayout