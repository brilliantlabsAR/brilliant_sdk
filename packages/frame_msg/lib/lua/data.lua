-- Module containing generic data handling code.
-- Messages with a specific message code are accumulated, concatenated,
-- and parsed into an app_data table item
local _M = {}

-- accumulates chunks of input message into this table
local app_data_accum = {}
_M.app_data_accum = app_data_accum

-- after table.concat, this table contains the message code mapped to the full input message payload
local app_data_block = {}
_M.app_data_block = app_data_block

-- contains typed objects representing full messages
local app_data = {}
_M.app_data = app_data

-- table of parsers per message type
local parsers = {}
_M.parsers = parsers

-- Data Handler: called when data arrives, must execute quickly.
-- Update the app_data_accum item based on the contents of the current packet
-- The first byte of the packet indicates the message type, and the item's key
-- The first packet also has a Uint16 message length field right after the message type
-- If the key is not present, initialise a new app data item
-- Accumulate chunks of data of the specified type, for later processing
-- The message codes and message length fields are not included in the accumulated chunks.
-- When the message is fully received, the full concatenated bytes are saved in the block
-- table associated to the message type, so no need to pass on the length or message type in the payload
-- TODO add reliability features (packet acknowledgement or dropped packet retransmission requests, message and packet sequence numbers)
function _M.update_app_data_accum(data)
    rc, err = pcall(
        function()
            local msg_flag = string.byte(data, 1)
            local item = _M.app_data_accum[msg_flag]
            if item == nil or next(item) == nil then
                item = { chunk_table = {}, num_chunks = 0, size = 0, recv_bytes = 0 }
                _M.app_data_accum[msg_flag] = item
            end

            if item.num_chunks == 0 then
                -- first chunk of new data contains size (Uint16)
                item.size = string.byte(data, 2) << 8 | string.byte(data, 3)
                item.chunk_table[1] = string.sub(data, 4)
                item.num_chunks = 1
                item.recv_bytes = string.len(data) - 3

                if item.recv_bytes == item.size then
                    _M.app_data_block[msg_flag] = item.chunk_table[1]
                    item.size = 0
                    item.recv_bytes = 0
                    item.num_chunks = 0
                    item.chunk_table[1] = nil
                    app_data_accum[msg_flag] = item
                end
            else
                item.chunk_table[item.num_chunks + 1] = string.sub(data, 2)
                item.num_chunks = item.num_chunks + 1
                item.recv_bytes = item.recv_bytes + string.len(data) - 1

                -- if all bytes are received, concat and move message to block
                -- but don't parse yet
                if item.recv_bytes == item.size then
                    collectgarbage('collect')
                    _M.app_data_block[msg_flag] = table.concat(item.chunk_table)
                    for k, v in pairs(item.chunk_table) do item.chunk_table[k] = nil end
                    collectgarbage('collect')
                    item.size = 0
                    item.recv_bytes = 0
                    item.num_chunks = 0
                    _M.app_data_accum[msg_flag] = item
                end
            end

            -- send some data back as an ACK for receiver-paced flow control
            -- and send_message() must use await_data=True
            while true do
                -- If the Bluetooth is busy, this simply tries again until it gets through
                -- data/ack/success
                if (pcall(frame.bluetooth.send, '\x01\x00\x00')) then
                    break
                end
                frame.sleep(0.0025)
            end

        end
    )
    if rc == false then
        -- send the error back on the stdout stream otherwise the data handler thread fails silently
        print('Error in data accumulator: ' .. err)
        while true do
            -- If the Bluetooth is busy, this simply tries again until it gets through
            -- data/ack/failure
            if (pcall(frame.bluetooth.send, '\x01\x00\x01')) then
                break
            end
            frame.sleep(0.0025)
        end
        -- rethrow the error, especially important to propagate the break signal to stop execution
        error(err)
    end
end

-- register the handler as a callback for all data sent from the host
frame.bluetooth.receive_callback(_M.update_app_data_accum)

-- Works through app_data_block and if any items are ready, run the corresponding parser
-- Returns the number of new items in app_data{}
function _M.process_raw_items()
    local processed = 0
    rc, err = pcall(
        function()
            collectgarbage('collect')

            for flag, block in pairs(_M.app_data_block) do
                -- parse the app_data_block item into an app_data item
                if _M.parsers[flag] == nil then
                    print('Error: No parser for flag: ' .. tostring(flag))
                else
                    -- call the parser and pass in the previous value in
                    -- case it accumulates, like the text_sprite_block can
                    _M.app_data[flag] = _M.parsers[flag](block, _M.app_data[flag])

                    -- then clear out the raw data
                    _M.app_data_block[flag] = nil

                    processed = processed + 1
                end
            end
        end
    )
    if rc == false then
        -- send the error back on the stdout stream otherwise the data handler thread fails silently
        print('Error processing raw items: ' .. err)
        -- rethrow the error, especially important to propagate the break signal to stop execution
        error(err)
    end

    return processed
end

return _M