-- discord_relay/init.lua
-- Fully crash-proof Discord relay for Minetest

-- ===== SETTINGS =====
-- Set in minetest.conf:
-- discord_webhook = https://discord.com/api/webhooks/XXXX/XXXXXXXX
local webhook_url = minetest.settings:get("discord_webhook") or ""

-- Check HTTP support
if not minetest.request_http_api then
    minetest.log("error", "[discord_relay] This mod requires `secure.http_mods` set for 'discord_relay' in minetest.conf.")
    minetest.log("error", "[discord_relay] Example: secure.http_mods = discord_relay")
    return
end

local http = minetest.request_http_api()
if not http then
    minetest.log("error", "[discord_relay] HTTP API not available, relay disabled.")
    return
end

-- ===== SAFE DISCORD SENDER =====
local function send_to_discord(msg)
    -- Prevent empty or nil messages
    if not msg or msg == "" then
        return
    end

    -- Ensure webhook is configured
    if webhook_url == "" then
        minetest.log("warning", "[discord_relay] No webhook URL configured. Add `discord_webhook` in minetest.conf.")
        return
    end

    -- Build safe JSON payload
    local ok, payload = pcall(minetest.write_json, {
        username = "ServerBot",
        content = msg
    })

    if not ok or not payload then
        minetest.log("error", "[discord_relay] JSON encoding failed, message skipped.")
        return
    end

    -- Do async HTTP call
    local ok2, err = pcall(function()
        http.fetch({
            url = webhook_url,
            method = "POST",
            timeout = 5, -- don’t hang server
            extra_headers = {"Content-Type: application/json"},
            data = payload
        }, function(res)
            if not res.succeeded then
                minetest.log("warning", "[discord_relay] Failed webhook send. Code=" ..
                    tostring(res.code) .. " Msg=" .. (res.data or "nil"))
            end
        end)
    end)

    if not ok2 then
        minetest.log("error", "[discord_relay] HTTP fetch crashed: " .. tostring(err))
    end
end

-- ===== HOOKS =====
minetest.register_on_chat_message(function(name, message)
    local safe_msg = message:gsub("[\r\n]", " ") -- prevent multiline crash
    send_to_discord("💬 **" .. name .. "**: " .. safe_msg)
end)

minetest.register_on_joinplayer(function(player)
    local pname = player:get_player_name() or "?"
    send_to_discord("✅ **" .. pname .. "** joined the server.")
end)

minetest.register_on_leaveplayer(function(player, timed_out)
    local pname = player and player:get_player_name() or "?"
    local msg = "❌ **" .. pname .. "** left the server."
    if timed_out then msg = msg .. " (timed out)" end
    send_to_discord(msg)
end)

minetest.register_on_mods_loaded(function()
    send_to_discord("🟢 **Server started successfully!**")
end)

minetest.register_on_shutdown(function()
    send_to_discord("🔴 **Server shutting down...**")
end)

-- ===== ADMIN COMMAND =====
minetest.register_chatcommand("dsay", {
    params = "<text>",
    privs = {server = true},
    description = "Send a manual message to Discord",
    func = function(name, param)
        if param == "" then
            return false, "Usage: /dsay <text>"
        end
        local safe_text = param:gsub("[\r\n]", " ")
        send_to_discord("📢 [Admin ".. name .. "]: " .. safe_text)
        return true, "Message sent to Discord."
    end,
})
