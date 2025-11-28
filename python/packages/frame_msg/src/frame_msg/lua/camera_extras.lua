-- Wait that the IMU becomes stable before taking an image capture.
function wait_imu_stable(
   -- The initial threshold for taking a picture
   thres_accelerometer,
   -- How much the threshold increases every attempt
   thres_accelerometer_inc,
   -- The initial threshold for taking a picture
   thres_compass,
   -- How much the threshold increases every attempt
   thres_compass_inc
)
   -- Collect the initial values
   prev = frame.imu.raw()

   while true do

      -- Give some time to the IMU
      frame.sleep(0.05)

      -- Take a measurement
      this = frame.imu.raw()

      -- Compute the difference in orientation
      dx = this.compass.x - prev.compass.x
      dy = this.compass.y - prev.compass.y
      dz = this.compass.z - prev.compass.z
      d_compass = dx * dx + dy * dy + dz * dz

      -- Compute the difference in acceleration
      dx = this.accelerometer.x - prev.accelerometer.x
      dy = this.accelerometer.y - prev.accelerometer.y
      dz = this.accelerometer.z - prev.accelerometer.z
      d_accelerometer = dx * dx + dy * dy + dz * dz

      --print("compass (d:"..d_compass..", t:"..thres_compass..", accelerometer (d:"..d_accelerometer..", t: "..thres_accelerometer..")")

      -- Perform the comparison of both
      if d_compass < thres_compass and d_accelerometer < thres_accelerometer then
         break
      end

      -- Decrease exigence of the thresholds
      thres_accelerometer = thres_accelerometer + thres_accelerometer_inc
      thres_compass = thres_compass + thres_compass_inc

      -- Persist the previous sample for comparison
      prev = this
   end
end

function set_pipeline()
   -- Replace the default image pipeline
   pipeline = {}
   frame.camera.mpix.op.debayer_2x2(pipeline)
   frame.camera.mpix.op.crop(pipeline, 128, 128, 256, 256)
   frame.camera.mpix.op.correct_black_level(pipeline)
   frame.camera.mpix.op.correct_white_balance(pipeline)
   frame.camera.mpix.op.kernel_denoise_3x3(pipeline)
   frame.camera.mpix.op.jpeg_encode(pipeline)
   frame.camera.mpix.set_pipeline(pipeline)
end

function auto_black_level(stats)
   sum = 0
   for i = 1, #stats.y_histogram do
      sum = sum + stats.y_histogram[i]
      if sum > 10 then black_level = stats.y_histogram_vals[i] break end
   end

   -- Apply the controls
   frame.camera.mpix.set_ctrl(frame.camera.mpix.cid.BLACK_LEVEL, black_level or 0)
end

function auto_white_balance(stats)
   if stats.rgb_average_r == 0 then
      red_balance_q10 = 1.0
   else
      red_balance_q10 = (stats.rgb_average_g << 10) // stats.rgb_average_r;
   end

   if stats.rgb_average_b == 0 then
      blue_balance_q10 = 1.0
   else
     blue_balance_q10 = (stats.rgb_average_g << 10) // stats.rgb_average_b;
   end

   -- Apply the controls
   frame.camera.mpix.set_ctrl(frame.camera.mpix.cid.RED_BALANCE, red_balance_q10)
   frame.camera.mpix.set_ctrl(frame.camera.mpix.cid.BLUE_BALANCE, blue_balance_q10)
end

function capture()
   set_pipeline()

   frame.camera.power_save(false)
   wait_imu_stable(100, 10, 100, 10)
   frame.camera.capture{resolution=640}
   while not frame.camera.image_ready() do
      frame.sleep(0.005)
   end

   stats = frame.camera.mpix.get_stats()

   auto_black_level(stats)
   auto_white_balance(stats)
end

-- Helper to print the data as hexadecimal
function tohex(data)
    local hex = ""
    for i = 1, #data do hex = hex .. string.format('%02x', data:byte(i)) end
    return hex
end
