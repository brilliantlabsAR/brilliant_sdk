-- Registers a BLE receive callback that echoes data back, then sleeps
frame.bluetooth.receive_callback(function(data)
    frame.bluetooth.send(data)
end)
frame.sleep(5.0)
