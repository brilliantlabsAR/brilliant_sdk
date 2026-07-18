-- Module handling raw IMU Data (accelerometer, magnetometer)
local _M = {}

-- Frame to phone flags
local IMU_DATA_MSG = 0x0A

function _M.send_imu_data(msg_code)
    local mc = msg_code or IMU_DATA_MSG
    local imu_data_raw = frame.imu.raw()
    local data = nil

    -- Pack msg_code as an unsigned byte, one byte of padding, and then
    -- 6 float32 in host frame order: compass (X,Y,Z) then accel (X,Y,Z),
    -- where host axes are +X = right, +Y = forward, +Z = up.
    -- Frame: each 14-bit signed value as a 32-bit float
    -- Halo: each 32-bit float value as a 32-bit float
    if (frame.HARDWARE_VERSION == 'Frame') then
      local scale_factor = 4096
      data = string.pack("<Bxffffff", mc,
      imu_data_raw.compass.x,
      imu_data_raw.compass.y,
      imu_data_raw.compass.z,
      imu_data_raw.accelerometer.x / scale_factor,
      imu_data_raw.accelerometer.y / scale_factor,
      imu_data_raw.accelerometer.z / scale_factor)
    else
      -- Halo: the magnetometer and accelerometer dies are mounted in DIFFERENT
      -- orientations, so each needs its own remap into the host (right, fwd, up)
      -- frame. Both remaps verified empirically (Sydney) via examples/imu_diagnostic.py.
      --   accel: host(X,Y,Z) = (-dev.z, dev.y, dev.x)
      --   compass: host(X,Y,Z) = (dev.x, dev.z, -dev.y)
      local scale_factor = 1000
      data = string.pack("<Bxffffff", mc,
      imu_data_raw.compass.x,
      imu_data_raw.compass.z,
      -imu_data_raw.compass.y,
      -imu_data_raw.accelerometer.z / scale_factor,
      imu_data_raw.accelerometer.y / scale_factor,
      imu_data_raw.accelerometer.x / scale_factor)
    end

    -- send the data that was read and packed
    pcall(frame.bluetooth.send, data)
end

return _M