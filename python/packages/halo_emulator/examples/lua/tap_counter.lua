-- tap_counter.lua
-- Counts IMU taps and sends the running total to the host via BLE.
-- Host can send 0xFF to reset the count.
-- Pairs with: paired_tap_counter.py

local count = 0
local MSG_COUNT = 0x10  -- msg code for outgoing tap count reports
local MSG_RESET = 0xFF  -- msg code for incoming reset command

local function show_count()
    frame.display.clear(0)
    frame.display.text('Taps: ' .. count, 20, 110, 0xFFFFFF)
    frame.display.show()
end

-- Initial display
show_count()

-- Signal host that we are ready
print(0)

frame.imu.tap_callback(function()
    count = count + 1
    show_count()
    frame.bluetooth.send(string.char(MSG_COUNT) .. string.char(count & 0xFF))
end)

frame.bluetooth.receive_callback(function(data)
    local cmd = string.byte(data, 1)
    if cmd == MSG_RESET then
        count = 0
        show_count()
    end
end)

while true do
    rc, err = pcall(function()
        frame.sleep(0.1)
    end)
    if rc == false then
        frame.display.clear(0)
        break
    end
end
