-- Module handling raw IMU Data (accelerometer, magnetometer)
local _M = {}

-- Frame to phone flags
local IMU_DATA_MSG = 0x0A

function _M.send_imu_data(msg_code)
    local mc = msg_code or IMU_DATA_MSG
    local imu_data_raw = frame.imu.raw()

    -- Pack msg_code as an unsigned byte, one byte of padding, and then 
    -- Frame: each 14-bit signed value as a 32-bit float
    -- Halo: each 32-bit float value as a 32-bit float
    local data = string.pack("<Bxffffff", mc,
		imu_data_raw.compass.x,
		imu_data_raw.compass.y,
		imu_data_raw.compass.z,
		imu_data_raw.accelerometer.x,
		imu_data_raw.accelerometer.y,
		imu_data_raw.accelerometer.z)

    -- send the data that was read and packed
    pcall(frame.bluetooth.send, data)
end

return _M