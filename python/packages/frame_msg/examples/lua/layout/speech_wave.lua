-- SpeechWave Class
-- Call `:start()` when speech begins, `:stop()` when it ends.
-- Call `:update()` in the 50ms main loop; it returns 14 {r,g,b,height} bars.
-- Usage: local sw = SpeechWave:new(); sw:start(); sw:update(); sw:draw(x,y)

local SpeechWave = {}
SpeechWave.__index = SpeechWave

-- Rainbow colors for 14 bars (left to right, mirrored 7+7)
-- Each pair shares a color so the 14-bar display is symmetric
local COLORS = {
  0xDC1E1E, -- {220,  30,  30}  -- red
  0xE65000, -- {230,  80,   0}  -- red-orange
  0xF08C00, -- {240, 140,   0}  -- orange
  0xF0C800, -- {240, 200,   0}  -- yellow
  0xB4DC00, -- {180, 220,   0}  -- yellow-green
  0x3CC81E, -- { 60, 200,  30}  -- green
  0x00B4DC, -- {  0, 180, 220}  -- cyan-blue
}
-- Internal defaults
local DECAY = 0.18 -- how fast bars fall when silent (per tick, multiplicative)
local RISE  = 0.45 -- how fast bars chase their target when speaking
local MIN_H = 0.08 -- idle resting height

local function rand(lo, hi) return lo + math.random() * (hi - lo) end

local function color_idx(i)
  return i <= 7 and i or (15 - i)
end

function SpeechWave:new(w, h)
  local o = setmetatable({}, self)
  o.w = w or 140
  o.h = h or 40
  o.speaking = false
  o.tick = 0
  o.bars = {}
  o.targets = {}
  o.phases = {}
  o.decay = DECAY
  o.rise = RISE
  o.min_h = MIN_H
  for i = 1, 14 do
    o.bars[i] = o.min_h
    o.targets[i] = o.min_h
    o.phases[i] = rand(0, math.pi * 2)
  end
  return o
end

function SpeechWave:start()
  self.speaking = true
end

function SpeechWave:stop()
  self.speaking = false
end

-- Call every ~50 ms. Returns array of 14 values in [0,1].
function SpeechWave:update()
  self.tick = self.tick + 1
  if self.speaking then
    local tick = self.tick
    local base = 0.45 + 0.30 * math.sin(tick * 0.18)
    local mid  = 0.20 * math.sin(tick * 0.31 + 1.2)
    for i = 1, 14 do
      local wave = 0.25 * math.sin(tick * 0.22 + self.phases[i])
      local n = rand(-0.12, 0.12)
      self.targets[i] = math.max(0.08, math.min(1.0, base + mid + wave + n))
    end
    for i = 1, 14 do
      self.bars[i] = self.bars[i] + (self.targets[i] - self.bars[i]) * self.rise
    end
  else
    for i = 1, 14 do
      local wobble = self.min_h * 0.5 * math.sin(self.tick * 0.08 + self.phases[i])
      local floor = self.min_h + wobble
      self.bars[i] = self.bars[i] * (1 - self.decay) + floor * self.decay
    end
  end
  return self.bars
end

-- Draw the speech wave with the top-left corner at (x,y). 
-- Each bar is 2px wide with 8px spacing.
function SpeechWave:draw(x, y)
  local cy = y + self.h // 2
  for i, b in ipairs(self.bars) do
    local h = math.ceil(b * self.h // 2)
    frame.display.rect(x + (i-1)*10, cy-h, 2, 2*h, COLORS[color_idx(i)], true)
  end
end

return SpeechWave