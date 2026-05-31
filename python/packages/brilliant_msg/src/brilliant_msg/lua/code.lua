-- Module to parse message codes sent from phoneside app as TxCode messages
local _M = {}

-- Parse the TxCode message raw data, which is a single byte
function _M.parse_code(data)
	local code = {}
	code.value = string.byte(data, 1)
	return code
end

return _M