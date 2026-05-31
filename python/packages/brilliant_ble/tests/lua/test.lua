for i = 1, 3 do
    frame.display.text('Hello world!', 10, 10)
    frame.display.show()
    frame.sleep(1)
    
    if frame.HARDWARE_VERSION == 'Frame' then
        frame.display.text('Test was run from file', 10, 10, { color = 'GREEN' })
        frame.display.show()
    else
        frame.display.clear()
        frame.display.text('Test was run from file', 10, 10, 0x00FF00)
    end
    
    frame.sleep(1)
end
