-- ANCS notification display (Halo-only)
--
-- Shows the current iOS notifications on the Halo display. Runs standalone
-- as main.lua: pair/connect the Halo from an iPhone and notifications appear
-- immediately via the frame.ancs callbacks; the screen also refreshes
-- periodically so the header/status stays current.
--
-- Uploaded by examples/halo_ancs_notifications.py

local MAX_SHOWN = 4       -- notification rows on screen
local TITLE_MAX = 32      -- bytes of title to fetch
local MESSAGE_MAX = 80    -- bytes of message to fetch
local REFRESH_TICKS = 100 -- periodic re-render interval (x 0.1s loop delay)

local WHITE = 0xFFFFFF
local GREY = 0x9E9E9E
local YELLOW = 0xFFD54F
local GREEN = 0x66BB6A
local RED = 0xEF5350

-- uid -> {category=..., important=..., title=..., message=..., app=..., seq=...}
local notifications = {}
local pending = {}        -- FIFO of uids awaiting an attribute fetch
local fetching = nil      -- uid with a fetch in flight
local seq = 0             -- arrival counter, newest = highest
local dirty = true
local ticks = 0

local function queue_fetch(uid)
    for _, v in ipairs(pending) do
        if v == uid then return end
    end
    pending[#pending + 1] = uid
end

-- Newest-first list of known notifications
local function sorted_uids()
    local uids = {}
    for uid in pairs(notifications) do
        uids[#uids + 1] = uid
    end
    table.sort(uids, function(a, b)
        return notifications[a].seq > notifications[b].seq
    end)
    return uids
end

local function truncate(s, max_chars)
    if s and #s > max_chars then
        return s:sub(1, max_chars - 3) .. "..."
    end
    return s
end

local function render()
    local w = frame.display.width()
    frame.display.clear(0x000000)

    -- Header
    local header
    if not frame.bluetooth.is_connected() then
        header = "Waiting for iPhone..."
        frame.display.text(header, 10, 30, GREY)
    elseif not frame.ancs.is_available() then
        header = "Connected (no ANCS - unlock iPhone?)"
        frame.display.text(header, 10, 30, YELLOW)
    else
        local count = 0
        for _ in pairs(notifications) do count = count + 1 end
        header = "Notifications: " .. count
        frame.display.text(header, 10, 30, GREEN)
    end
    frame.display.line(10, 45, w - 10, 45, GREY)

    -- Notification rows: title line + message line
    local y = 80
    local shown = 0
    for _, uid in ipairs(sorted_uids()) do
        if shown >= MAX_SHOWN then break end
        local n = notifications[uid]
        local color = n.important and RED or WHITE
        local title = truncate(n.title or n.app or n.category or "...", 40)
        frame.display.text(title, 10, y, color)
        if n.message and #n.message > 0 then
            frame.display.text(truncate(n.message, 48), 30, y + 30, GREY)
        end
        y = y + 75
        shown = shown + 1
    end

    if shown == 0 and frame.ancs.is_available() then
        frame.display.text("No notifications", 10, 100, GREY)
    end
end

-- Immediate updates: ANCS event callbacks --------------------------------

frame.ancs.availability_callback(function(available)
    if not available then
        -- Handles are gone (disconnect or service moved); notification UIDs
        -- are no longer valid.
        notifications = {}
        pending = {}
        fetching = nil
    end
    dirty = true
end)

frame.ancs.attributes_callback(function(result)
    local n = notifications[result.uid]
    if n then
        if result.error then
            -- e.g. "invalid_parameter": dismissed before we could fetch it
            if result.error == "invalid_parameter" then
                notifications[result.uid] = nil
            else
                n.title = n.title or ("<" .. result.error .. ">")
            end
        else
            n.app = result.app_identifier
            n.title = result.title
            n.message = result.message
        end
        dirty = true
    end
    if fetching == result.uid then fetching = nil end
end)

frame.ancs.notification_callback(function(event)
    if event.event == "removed" then
        notifications[event.uid] = nil
    else
        -- "added" and "modified" (pre-existing ones replay on subscribe)
        local n = notifications[event.uid]
        if not n then
            seq = seq + 1
            n = {seq = seq}
            notifications[event.uid] = n
        end
        n.category = event.category
        n.important = event.important
        queue_fetch(event.uid)
    end
    dirty = true
end)

-- Main loop ---------------------------------------------------------------

frame.display.power_save(false)
frame.display.brightness(25)
render()

while true do
    -- One attribute fetch at a time (the control point is serialized)
    if not fetching and #pending > 0 and frame.ancs.is_available() then
        local uid = table.remove(pending, 1)
        if notifications[uid] then
            local ok = frame.ancs.get_notification_attributes(uid, {
                app_identifier = true,
                title = TITLE_MAX,
                message = MESSAGE_MAX,
            })
            if ok then
                fetching = uid
            else
                queue_fetch(uid) -- busy/unavailable: retry next pass
            end
        end
    end

    ticks = ticks + 1
    if dirty or ticks >= REFRESH_TICKS then
        render()
        dirty = false
        ticks = 0
    end

    frame.sleep(0.1)
end
