-- Voice Feedback Equalizer Animator
-- Call `eq_start()` when speech begins, `eq_stop()` when it ends.
-- Call `eq_update()` in your 50ms main loop; it returns 14 {r,g,b,height} bars.

local EQ = {}

-- Rainbow colors for 14 bars (left to right, mirrored 7+7)
-- Each pair shares a color so the 14-bar display is symmetric
local COLORS = {
  {220,  30,  30},  -- red
  {230,  80,   0},  -- red-orange
  {240, 140,   0},  -- orange
  {240, 200,   0},  -- yellow
  {180, 220,   0},  -- yellow-green
  { 60, 200,  30},  -- green
  {  0, 180, 220},  -- cyan-blue
}

-- Internal state
local speaking   = false
local bars       = {}   -- current heights [1..14], 0.0–1.0
local targets    = {}   -- target heights
local phases     = {}   -- per-bar sine phase offsets for organic motion
local DECAY      = 0.18 -- how fast bars fall when silent (per tick, multiplicative)
local RISE       = 0.45 -- how fast bars chase their target when speaking
local MIN_H      = 0.03 -- idle resting height

-- Speech rhythm: bars move in slow waves when speaking
local tick = 0

local function rand(lo, hi) return lo + math.random() * (hi - lo) end

-- Mirror index: bar 1..7 maps to color 1..7, bar 8..14 mirrors 7..1
local function color_idx(i)
  return i <= 7 and i or (15 - i)
end

-- Init
for i = 1, 14 do
  bars[i]    = MIN_H
  targets[i] = MIN_H
  phases[i]  = rand(0, math.pi * 2)
end

local function set_palette()
  for i = 1, 14 do
    local c = COLORS[color_idx(i)]
    frame.display.assign_color(i, c[1], c[2], c[3])
  end
  -- make the last color (index 15) pure black for drawing the background rectangle
  -- because the black at index 0 is transparent
  frame.display.assign_color(0, 0, 0, 0)
  frame.display.assign_color(15, 0, 0, 0)
end

-- Public API ----------------------------------------------------------------

function eq_start()
  speaking = true
  set_palette()
end

function eq_stop()
  speaking = false
end

-- Call every ~50 ms. Returns array of 14 values in [0,1].
function eq_update()
  tick = tick + 1

  if speaking then
    -- Generate organic targets: base wave + per-bar noise
    local base  = 0.45 + 0.30 * math.sin(tick * 0.18)          -- slow global pulse
    local mid   = 0.20 * math.sin(tick * 0.31 + 1.2)           -- secondary wave
    for i = 1, 14 do
      -- Each bar gets its own phase-shifted sine + randomness
      local wave = 0.25 * math.sin(tick * 0.22 + phases[i])
      local n    = rand(-0.12, 0.12)                            -- jitter
      targets[i] = math.max(0.08, math.min(1.0, base + mid + wave + n))
    end
    -- Smooth bars toward targets
    for i = 1, 14 do
      bars[i] = bars[i] + (targets[i] - bars[i]) * RISE
    end
  else
    -- Decay toward MIN_H with a gentle residual wobble
    for i = 1, 14 do
      local wobble = MIN_H * 0.5 * math.sin(tick * 0.08 + phases[i])
      local floor  = MIN_H + wobble
      bars[i] = bars[i] * (1 - DECAY) + floor * DECAY
    end
  end

  return bars
end

function draw_bars(bars)
  frame.display.rect(50, 30, 140, 40, 15, true)  -- clear background
  for i, b in ipairs(bars) do
    local h = math.ceil(b * 20)  -- scale to 0–20 pixel height
    frame.display.bitmap(50 + (i-1)*10, 50-h, 2, 4, i, '\x11', {x_scale=2, y_scale=h})
  end
end

-- Example / test loop -------------------------------------------------------
if true then
  frame.display.clear()
  math.randomseed(math.floor(frame.time.utc()))
  print("Silent for 20 ticks…")
  for _=1,20 do
    draw_bars(eq_update())
    frame.sleep(0.05)
  end
  eq_start()
  print("Speaking for 100 ticks…")
  for _=1,100 do
    draw_bars(eq_update())
    frame.sleep(0.05)
  end
  eq_stop()
  print("Stopping, silent for 16 ticks…")
  for _=1,16 do
    draw_bars(eq_update())
    frame.sleep(0.05)
  end
end