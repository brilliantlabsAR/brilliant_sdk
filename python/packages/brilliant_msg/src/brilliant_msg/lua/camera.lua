-- Module to encapsulate taking and sending photos as simple frame app messages
local _M = {}

-- Frame to phone flags
local IMAGE_MSG = 0x07
local IMAGE_FINAL_MSG = 0x08
local AUTOEXP_DATA_MSG = 0x11
local METERING_DATA_MSG = 0x12

-- local state to capture the stateful camera settings
local quality_values = {'VERY_LOW', 'LOW', 'MEDIUM', 'HIGH', 'VERY_HIGH'}
local metering_values = {'SPOT', 'CENTER_WEIGHTED', 'AVERAGE'}

-- default settings
local auto_exp_settings = {
	metering = 'CENTER_WEIGHTED',
	exposure = 0.1,
	exposure_speed = 0.45,
	shutter_limit = 16383,
	analog_gain_limit = 16.0,
	white_balance_speed = 0.5,
	rgb_gain_limit = 287
}

local manual_exp_settings = {
	shutter = 4096,
	analog_gain = 1,
	red_gain = 121,
	green_gain = 64,
	blue_gain = 140
}

-- auto/manual status, accessible outside the module
_M.is_auto_exp = true

-- helper function to update settings if they are present (otherwise keep defaults)
function update_if_present(settings, updates)
    for k, v in pairs(updates) do
        if v ~= nil then
            settings[k] = v
        end
    end
end

-- Update the saved auto exposure settings with the provided args
-- The caller still needs to _M.run_auto_exposure() every 100ms after this
function _M.set_auto_exp_settings(args)
	update_if_present(auto_exp_settings, args)
	_M.is_auto_exp = true
end

-- Turns off auto exposure flag if present and updates the manual exposure settings with the provided args
-- Sets the manual exposure settings into the camera using the low level functions
function _M.set_manual_exp_settings(args)
	_M.is_auto_exp = false
	update_if_present(manual_exp_settings, args)

	-- actually update the state of the camera
	frame.camera.set_shutter(manual_exp_settings.shutter)
	frame.camera.set_gain(manual_exp_settings.analog_gain)
	frame.camera.set_white_balance(manual_exp_settings.red_gain, manual_exp_settings.green_gain, manual_exp_settings.blue_gain)
end

-- parse the auto exposure settings message from the host into a table we can use with set_auto_exp_settings()
function _M.parse_auto_exp_settings(data)
	local settings = {}

	settings.metering = metering_values[string.byte(data, 1) + 1]
	settings.exposure = string.byte(data, 2) / 255.0
	settings.exposure_speed = string.byte(data, 3) / 255.0
	settings.shutter_limit = string.byte(data, 4) << 8 | string.byte(data, 5) & 0x3FFF
	settings.analog_gain_limit = string.byte(data, 6) & 0xFF
	settings.white_balance_speed = string.byte(data, 7) / 255.0
	settings.rgb_gain_limit = string.byte(data, 8) << 8 | string.byte(data, 9) & 0x3FF

	return settings
end

-- parse the manual exposure settings message from the host into a table we can use with set_manual_exp_settings()
function _M.parse_manual_exp_settings(data)
	local settings = {}

    settings.shutter = string.byte(data, 1) << 8 | string.byte(data, 2) & 0x3FFF
	settings.analog_gain = string.byte(data, 3) & 0xFF
	settings.red_gain = string.byte(data, 4) << 8 | string.byte(data, 5) & 0x3FF
	settings.green_gain = string.byte(data, 6) << 8 | string.byte(data, 7) & 0x3FF
	settings.blue_gain = string.byte(data, 8) << 8 | string.byte(data, 9) & 0x3FF

	return settings
end

-- parse the capture settings message from the host into a table we can use with the capture_and_send function
function _M.parse_capture_settings(data)

	local settings = {}
	-- quality and metering mode are indices into arrays of values (0-based phoneside; 1-based in Lua)
	settings.quality = quality_values[string.byte(data, 1) + 1]
	local half_res = string.byte(data, 2) << 8 | string.byte(data, 3)
	settings.resolution = half_res * 2
	local pan_shifted = string.byte(data, 4) << 8 | string.byte(data, 5)
	settings.pan = pan_shifted - 140
	settings.raw = string.byte(data, 6) > 0

	return settings
end

-- send data with retries and no sleeps, bail after 2 seconds
function send_data(data)
	local sent = false

	-- 2 second time limit for this packet else bail out
	local try_until = frame.time.utc() + 2

	while frame.time.utc() < try_until do
		if pcall(frame.bluetooth.send, data) then
			sent = true
			break
		end
	end

	if not sent then
		error('Error sending photo data')
	end
end

-- Runs the auto exposure algorithm with the current settings (call this every 100ms)
function _M.run_auto_exposure()
	-- pass the table into the function with parentheses, don't wrap again in curly braces, it's already a table
	return frame.camera.auto(auto_exp_settings)
end

function _M.send_autoexp_result(autoexp)
	-- Pack the message code as an unsigned byte (B)
    -- followed by 16 floats (f) in little-endian format
    local data = string.pack("<Bffffffffffffffff",
		AUTOEXP_DATA_MSG,
        -- Top level values
        autoexp['error'],
        autoexp['shutter'],
        autoexp['analog_gain'],
        autoexp['red_gain'],
        autoexp['green_gain'],
        autoexp['blue_gain'],

        -- Brightness values
        autoexp['brightness']['center_weighted_average'],
        autoexp['brightness']['scene'],

        -- Brightness matrix values
        autoexp['brightness']['matrix']['r'],
        autoexp['brightness']['matrix']['g'],
        autoexp['brightness']['matrix']['b'],
        autoexp['brightness']['matrix']['average'],

        -- Brightness spot values
        autoexp['brightness']['spot']['r'],
        autoexp['brightness']['spot']['g'],
        autoexp['brightness']['spot']['b'],
        autoexp['brightness']['spot']['average']
    )

    -- Total size: 1 byte for message code + (16 floats * 4 bytes) = 65 bytes
	send_data(data)
end

-- send the current spot and matrix rgb values from the FPGA (as used by the auto exposure algorithm)
function _M.send_metering_data()
	send_data(string.char(METERING_DATA_MSG) .. frame.fpga_read(0x25, 6))
end

-- Bytes of image data per packet: at most 240, so that with the data marker
-- and message flag each notification fits in one 251-byte Bluetooth
-- link-layer packet, including over the EATT bearers Android uses (2 bytes
-- more overhead than plain ATT); less if the connection's MTU is smaller.
-- Packets that each fit in one link-layer packet transfer faster than larger
-- ones split across two. Read per call: the MTU can change after the app starts.
local function chunk_size()
	return math.min(frame.bluetooth.max_length() - 1, 240)
end

-- reads the next chunk of the current image, raw (no jpeg header) or not
local function read_chunk(raw)
	if raw then
		return frame.camera.read_raw(chunk_size())
	else
		return frame.camera.read(chunk_size())
	end
end

-- takes a capture_settings table and sends the image data to the host,
-- blocking until the whole image is sent
function _M.capture_and_send(args)
	frame.camera.capture { resolution=args.resolution, quality=args.quality, pan=args.pan }

	-- wait until the capture is finished and the image is ready before continuing
	while not frame.camera.image_ready() do
		frame.sleep(0.005)
	end

	while true do
		-- skip the 623 byte header if the caller requested raw data
		local data = read_chunk(args.raw)

		if (data == nil) then
			send_data(string.char(IMAGE_FINAL_MSG))
			break
		elseif (data ~= '') then
			send_data(string.char(IMAGE_MSG) .. data)
		end
	end
end

-- Non-blocking alternative to capture_and_send(): start_capture() starts a
-- capture, then call send_pending() from the app loop until it returns false.
-- Between calls the loop can keep doing other work, such as sending
-- microphone audio, so a photo doesn't hold it up for the whole transfer.
local pending = nil

-- starts a capture with a capture_settings table (from parse_capture_settings)
function _M.start_capture(args)
	frame.camera.capture { resolution=args.resolution, quality=args.quality, pan=args.pan }
	pending = { raw = args.raw, ready = false }
end

-- true while a capture started with start_capture() is still being sent
function _M.is_sending()
	return pending ~= nil
end

-- Sends up to max_packets packets (default 1) of the image from start_capture(),
-- once it is ready; until then it sleeps for 1 ms, so a loop calling it
-- without sleeping doesn't hold the CPU while the image is being processed.
-- Returns true while there is more to send, and false once the final packet
-- has been sent (or if no capture is pending).
function _M.send_pending(max_packets)
	if pending == nil then
		return false
	end

	if not pending.ready then
		if not frame.camera.image_ready() then
			frame.sleep(0.001)
			return true
		end
		pending.ready = true
	end

	for _ = 1, (max_packets or 1) do
		local data = read_chunk(pending.raw)

		if (data == nil) then
			send_data(string.char(IMAGE_FINAL_MSG))
			pending = nil
			return false
		elseif (data ~= '') then
			send_data(string.char(IMAGE_MSG) .. data)
		end
	end

	return true
end

return _M