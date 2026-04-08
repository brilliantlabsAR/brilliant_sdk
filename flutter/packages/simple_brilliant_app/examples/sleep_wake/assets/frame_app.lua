local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')

-- Phone to Frame flags
local STANDBY_MSG = 0x40
local WAKEUP_MSG = 0x41

-- message parsers, keyed by message flag
local parsers = {}
parsers[STANDBY_MSG] = code.parse_code
parsers[WAKEUP_MSG] = code.parse_code

-- Main app loop
function app_loop()
    -- wake the display on startup and show a ready indicator
    if frame.HARDWARE_VERSION ~= 'Frame' then
        frame.display.power_save(false)
        frame.display.clear()
        frame.display.text('Ready', 100, 127, 0xFFFFFF)
    else
        frame.display.text('Ready', 1, 1)
        frame.display.show()
    end

    print('Standby app started')

    local last_batt_update = 0

    while true do
        -- drain the message queue, parse and dispatch in arrival order
        local items = data.process_raw_items()
        for i = 1, #items do
            local flag = items[i][1]
            local raw  = items[i][2]

            if parsers[flag] == nil then
                print('Error: No parser for flag: ' .. tostring(flag))
            elseif flag == STANDBY_MSG then
                print('Going into standby')
                frame.standby()
                -- execution resumes here after wakeup
                local source = frame.wakeup_source()
                print('Wakeup source: ' .. tostring(source))
            elseif flag == WAKEUP_MSG then
                print('Wake up bluetooth message received')
            end
        end

        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

        frame.sleep(0.1)
    end
end

-- run the main app loop
app_loop()
