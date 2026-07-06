local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')

-- Phone to Frame flags
START_ANCS_MSG = 0x40
STOP_ANCS_MSG = 0x41

-- Frame to Phone flags
NOTIF_MSG = 0x0B

-- message parsers, keyed by message flag
local parsers = {}
parsers[START_ANCS_MSG] = code.parse_code
parsers[STOP_ANCS_MSG] = code.parse_code

-- ANCS notification state
local MAX_SHOWN = 4
local FIELD_SEP = string.char(0x1F) -- unit separator; won't occur in UTF-8 text

local notifications = {} -- uid -> {category, important, title, message, app, seq}
local pending = {}       -- FIFO of uids awaiting an attribute fetch
local fetching = nil     -- uid with a fetch in flight
local seq = 0
local dirty = true

-- Send one event line to the phone: fields joined by FIELD_SEP after the
-- flag byte. Truncated to a single BLE packet (frame.bluetooth.send splits
-- larger payloads across packets, which would break flag-based parsing).
local function send_to_phone(kind, uid, n)
    local fields = {
        kind,
        tostring(uid or 0),
        n and (n.category or "") or "",
        n and (n.title or "") or "",
        n and (n.message or "") or "",
        n and (n.app or "") or "",
    }
    local msg = string.char(NOTIF_MSG) .. table.concat(fields, FIELD_SEP)
    local budget = frame.bluetooth.max_length()
    if #msg > budget then
        msg = msg:sub(1, budget)
    end
    pcall(frame.bluetooth.send, msg)
end

local function queue_fetch(uid)
    for _, v in ipairs(pending) do
        if v == uid then return end
    end
    pending[#pending + 1] = uid
end

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

    if not frame.ancs.is_available() then
        frame.display.text("No ANCS (needs an iPhone host)", 10, 30, 0xFFD54F)
    elseif not frame.ancs.is_subscribed() then
        frame.display.text("ANCS ready - press Start on phone", 10, 30, 0x9E9E9E)
    else
        local count = 0
        for _ in pairs(notifications) do count = count + 1 end
        frame.display.text("Notifications: " .. count, 10, 30, 0x66BB6A)
    end
    frame.display.line(10, 45, w - 10, 45, 0x9E9E9E)

    local y = 80
    local shown = 0
    for _, uid in ipairs(sorted_uids()) do
        if shown >= MAX_SHOWN then break end
        local n = notifications[uid]
        local color = n.important and 0xEF5350 or 0xFFFFFF
        frame.display.text(truncate(n.title or n.app or n.category or "...", 40), 10, y, color)
        if n.message and #n.message > 0 then
            frame.display.text(truncate(n.message, 48), 30, y + 30, 0x9E9E9E)
        end
        y = y + 75
        shown = shown + 1
    end
end

-- ANCS event callbacks (immediate updates) --------------------------------

local function register_ancs_callbacks()
    frame.ancs.availability_callback(function(available)
        if not available then
            notifications = {}
            pending = {}
            fetching = nil
        end
        send_to_phone(available and "available" or "unavailable", 0, nil)
        dirty = true
    end)

    frame.ancs.attributes_callback(function(result)
        local n = notifications[result.uid]
        if n then
            if result.error then
                if result.error == "invalid_parameter" then
                    -- dismissed before we could fetch it
                    notifications[result.uid] = nil
                    send_to_phone("removed", result.uid, nil)
                end
            else
                n.app = result.app_identifier
                n.title = result.title
                n.message = result.message
                send_to_phone("attrs", result.uid, n)
            end
            dirty = true
        end
        if fetching == result.uid then fetching = nil end
    end)

    frame.ancs.notification_callback(function(event)
        if event.event == "removed" then
            notifications[event.uid] = nil
            send_to_phone("removed", event.uid, nil)
        else
            local n = notifications[event.uid]
            if not n then
                seq = seq + 1
                n = {seq = seq}
                notifications[event.uid] = n
            end
            n.category = event.category
            n.important = event.important
            queue_fetch(event.uid)
            send_to_phone(event.event, event.uid, n)
        end
        dirty = true
    end)
end

local function unregister_ancs_callbacks()
    frame.ancs.notification_callback(nil) -- unsubscribes from ANCS
    frame.ancs.attributes_callback(nil)
    frame.ancs.availability_callback(nil)
    notifications = {}
    pending = {}
    fetching = nil
    dirty = true
end

-- Main app loop ------------------------------------------------------------

function app_loop()
    frame.display.power_save(false)
    frame.display.brightness(25)
    render()

    local last_batt_update = 0

    -- message handlers, dispatched in arrival order by the main loop
    local handlers = {}

    handlers[START_ANCS_MSG] = function(item)
        register_ancs_callbacks()
        dirty = true
    end

    handlers[STOP_ANCS_MSG] = function(item)
        unregister_ancs_callbacks()
    end

    while true do
        -- drain the message queue, parse and dispatch in arrival order
        local items = data.process_raw_items()

        for i = 1, #items do
            local flag = items[i][1]
            local raw  = items[i][2]

            if parsers[flag] == nil then
                print('Error: No parser for flag: ' .. tostring(flag))
            else
                local parsed = parsers[flag](raw)

                if handlers[flag] ~= nil then
                    handlers[flag](parsed)
                else
                    print('Error: No handler for flag: ' .. tostring(flag))
                end
            end
        end

        -- one attribute fetch at a time (the ANCS control point is serialized)
        if not fetching and #pending > 0 and frame.ancs.is_available() then
            local uid = table.remove(pending, 1)
            if notifications[uid] then
                local ok = frame.ancs.get_notification_attributes(uid, {
                    app_identifier = true,
                    title = 32,
                    message = 60,
                })
                if ok then
                    fetching = uid
                else
                    queue_fetch(uid) -- busy/unavailable: retry next pass
                end
            end
        end

        if dirty then
            render()
            dirty = false
        end

        -- periodic battery level updates
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)
        frame.sleep(0.1)
    end
end

-- run the main app loop
app_loop()
