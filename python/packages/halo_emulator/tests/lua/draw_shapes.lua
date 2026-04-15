-- Draws primitives and shows
frame.display.clear(0)
frame.display.rect(10, 10, 50, 50, 0xFF0000, true)   -- filled red rect
frame.display.circle(128, 128, 30, 0x00FF00, false)  -- green circle outline
frame.display.line(1, 1, 256, 256, 0x0000FF)         -- blue diagonal
frame.display.show()
