-- Module to send Tap events as messages to the host
local _M = {}

-- Frame to Phone flags
local TAP_MSG = 0x09

-- Halo firmware (0.8.8+) passes the gesture kind to the tap callback and
-- fires once per gesture; the kind is forwarded as a payload byte.
-- Frame's tap_callback passes no kind: the bare flag byte is sent per tap
-- and the host aggregates multi-taps by timing.
local KIND_CODES = { single = 1, double = 2, triple = 3 }

function _M.send_tap(kind)
	local payload = string.char(TAP_MSG)
	local code = kind and KIND_CODES[kind]

	if code then
		payload = payload .. string.char(code)
	end

	rc, err = pcall(frame.bluetooth.send, payload)

	if rc == false then
		-- send the error back on the stdout stream
		print(err)
	end
end

return _M
