-- text_page_app.lua
-- Receives TxTextPage messages (page header + one sprite per line) and renders
-- each line at its per-line (x, y) offset, so CircularTextLayout pages
-- actually follow the round display's chords.
-- NOTE: keep this file ASCII-only; the emulator loads Lua source as latin-1.
-- Also sends button click events to the host (RxClick, msg code 0x0B).
-- Pairs with: paired_click_text_page.py

local data = require('data.min')
local text_page = require('text_page.min')

local PAGE_FLAG = 0x20
local CLEAR_FLAG = 0x10
local CLICK_FLAG = 0x0B

local page = nil

frame.button.single(function()
    pcall(frame.bluetooth.send, string.char(CLICK_FLAG) .. string.char(1))
end)

frame.button.double(function()
    pcall(frame.bluetooth.send, string.char(CLICK_FLAG) .. string.char(2))
end)

frame.button.long(function()
    pcall(frame.bluetooth.send, string.char(CLICK_FLAG) .. string.char(3))
end)

-- Signal host that we are ready (await_print)
print(0)

while true do
    rc, err = pcall(function()
        local items = data.process_raw_items()

        for i = 1, #items do
            local flag = items[i][1]
            local raw = items[i][2]

            if flag == PAGE_FLAG then
                page = text_page.parse_text_page(raw, page)
                if text_page.is_complete(page) then
                    frame.display.clear(0)
                    text_page.draw(page)
                    collectgarbage('collect')
                end
            elseif flag == CLEAR_FLAG then
                page = nil
                frame.display.clear(0)
            end
        end

        frame.sleep(0.1)
    end)
    if rc == false then
        frame.display.clear(0)
        break
    end
end
