-- plain_text_app.lua
-- Receives plain-text messages from the host (via data.lua / TxPlainText)
-- and renders them on the display.
-- Pairs with: paired_plain_text.py

local data = require('data.min')
local plain_text = require('plain_text.min')

local TEXT_FLAG = 0x0a

data.parsers[TEXT_FLAG] = plain_text.parse_plain_text

local function show_text(text)
    frame.display.clear(0)
    local line_num = 0
    for line in text:gmatch('([^\n]*)\n?') do
        if line ~= '' then
            frame.display.text(line, 10, line_num * 50 + 20, 0xFFFFFF)
            line_num = line_num + 1
        end
    end
    frame.display.show()
end

show_text('Ready')

-- Signal host that we are ready (await_print)
print(0)

while true do
    rc, err = pcall(function()
        local items_ready = data.process_raw_items()

        if items_ready > 0 then
            if data.app_data[TEXT_FLAG] ~= nil then
                show_text(data.app_data[TEXT_FLAG].string)
                data.app_data[TEXT_FLAG] = nil
                collectgarbage('collect')
            end
        end

        frame.sleep(0.1)
    end)
    if rc == false then
        frame.display.clear(0)
        break
    end
end
