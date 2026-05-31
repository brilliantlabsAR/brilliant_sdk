-- Module to send individual Tap events as single-byte messages to the host
local _M = {}

-- Frame to Phone flags
local TAP_MSG = 0x09

function _M.send_tap()
	rc, err = pcall(frame.bluetooth.send, string.char(TAP_MSG))

	if rc == false then
		-- send the error back on the stdout stream
		print(err)
	end
end

return _M