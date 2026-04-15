-- blinks text
-- run from `../examples/` with: `halo-emulator ./lua/ --script blink_main.lua`

local function show_text(text)
    frame.display.clear(0)
    local line_num = 0
    for line in text:gmatch('([^\n]*)\n?') do
        if line ~= '' then
            frame.display.text(line, 100, line_num * 50 + 100, 0xFFFFFF)
            line_num = line_num + 1
        end
    end
    frame.display.show()
end

show_text('Ready')
local visible = true

while true do
    rc, err = pcall(function()
        if visible then
            show_text('Blink!')
            print('Blink!')
        else
            frame.display.clear(0)
        end
        visible = not visible

        frame.sleep(1)
    end)
    if rc == false then
        frame.display.clear(0)
        break
    end
end
