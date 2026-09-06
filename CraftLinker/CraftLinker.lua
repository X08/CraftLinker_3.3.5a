-- CraftLinker
-- Whisper "craft" to the player running this addon and it will whisper back
-- real trade-skill links for their known crafting professions -- the kind
-- that let the recipient browse the recipe list and request a craft.
--
-- How the link is obtained: WoW only exposes a profession's trade-skill
-- link (GetTradeSkillListLink) while that profession's window is open, and
-- opening a profession window programmatically is a protected action that
-- the game blocks unless a real click/keypress triggered it. So instead of
-- forcing windows open, this addon passively caches the link every time
-- you open one of your crafting professions during normal play, and
-- replies with those cached links (one whisper per profession, after a
-- short intro line) when someone whispers the trigger word.
--
-- First-time setup: open each of your crafting profession windows once
-- (just like you normally would to craft something) so it gets cached.
-- After that it's remembered per character between sessions.

local DEFAULTS = {
    enabled = true,
    trigger = "craft",   -- exact word (case-insensitive) that fires the reply
    cooldown = 30,        -- seconds before the same whisperer can trigger it again
    noneMessage = "I haven't cached my crafting links yet -- ask me to open my profession windows once.",
    links = {},            -- [professionName] = tradeSkillLink, filled in as windows are opened
}

-- NOTE: CraftLinkerDB isn't restored from disk until ADDON_LOADED fires for
-- this addon -- that happens AFTER this file's top-level code has already
-- run. Doing the defaults-merge here instead (rather than at file load)
-- avoids the saved data overwriting a merge we did too early.
local function EnsureDefaults()
    CraftLinkerDB = CraftLinkerDB or {}
    for k, v in pairs(DEFAULTS) do
        if CraftLinkerDB[k] == nil then
            CraftLinkerDB[k] = v
        end
    end
    CraftLinkerDB.links = CraftLinkerDB.links or {}
end

-- Only these have an actual trade-skill/crafting window that can be linked
-- for someone else to browse. Fishing, First Aid, and the gathering skills
-- don't, so they're left out on purpose.
local CRAFTING_PROFESSIONS = {
    ["Alchemy"]        = true,
    ["Blacksmithing"]  = true,
    ["Enchanting"]     = true,
    ["Engineering"]    = true,
    ["Inscription"]    = true,
    ["Jewelcrafting"]  = true,
    ["Leatherworking"] = true,
    ["Tailoring"]      = true,
    ["Cooking"]        = true,
}

local lastReply = {}

-- Distinguishes your own open profession window from one you're viewing
-- because someone else whispered/linked you theirs -- so a stranger's link
-- never overwrites your own cached one.
local function IsViewingOwnTradeSkill()
    if IsTradeSkillLinked then
        local ok, linked = pcall(IsTradeSkillLinked)
        if ok then
            return not linked
        end
    end

    -- Fallback for clients without IsTradeSkillLinked: the displayed rank
    -- should match your own known rank for that skill if it's really yours.
    local name, currentRank = GetTradeSkillLine()
    if not name then return false end

    local numSkills = GetNumSkillLines()
    for i = 1, numSkills do
        local skillName, isHeader, _, skillRank = GetSkillLineInfo(i)
        if not isHeader and skillName == name then
            return skillRank == currentRank
        end
    end

    return false
end

local function CacheCurrentTradeSkill()
    local name = GetTradeSkillLine and GetTradeSkillLine()
    if not (name and CRAFTING_PROFESSIONS[name] and IsViewingOwnTradeSkill()) then
        return
    end

    local link = GetTradeSkillListLink()
    if not link then return end

    -- Only announce when something actually changed -- TRADE_SKILL_SHOW and
    -- TRADE_SKILL_UPDATE can both fire, sometimes more than once, for a
    -- single window opening.
    if CraftLinkerDB.links[name] ~= link then
        CraftLinkerDB.links[name] = link
        print("|cff33ff99CraftLinker|r cached a link for " .. name .. ".")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "CraftLinker" then
            EnsureDefaults()
        end
        return
    end

    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        CacheCurrentTradeSkill()
        return
    end

    if event == "CHAT_MSG_WHISPER" then
        if not CraftLinkerDB.enabled then return end

        local message, sender = ...
        local trimmed = message:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if trimmed ~= CraftLinkerDB.trigger then return end

        local now = GetTime()
        if lastReply[sender] and (now - lastReply[sender]) < CraftLinkerDB.cooldown then
            return
        end
        lastReply[sender] = now

        -- Trust the cache directly -- no re-scanning the skill list here.
        -- Sent as separate whispers, one profession per message: combining
        -- multiple hyperlinks into a single message either overruns the
        -- chat length limit or trips servers' anti-spam filtering for
        -- multi-link messages (a common gold-seller pattern) -- either way
        -- everything past the first link tends to get silently dropped.
        local any = false
        for _, link in pairs(CraftLinkerDB.links) do
            if not any then
                SendChatMessage("[CraftLinker] My crafting professions:", "WHISPER", nil, sender)
                any = true
            end
            SendChatMessage(link, "WHISPER", nil, sender)
        end

        if not any then
            SendChatMessage(CraftLinkerDB.noneMessage, "WHISPER", nil, sender)
        end
    end
end)

-- /craftlink on|off, /craftlink trigger <word>, /craftlink cooldown <seconds>,
-- /craftlink status, /craftlink clear <ProfessionName>, /craftlink clearall
SLASH_CRAFTLINKER1 = "/craftlink"
SlashCmdList["CRAFTLINKER"] = function(msg)
    local rawArgs = {}
    for word in msg:gmatch("%S+") do
        table.insert(rawArgs, word)
    end

    local args = {}
    for i, word in ipairs(rawArgs) do
        args[i] = word:lower()
    end

    if args[1] == "on" then
        CraftLinkerDB.enabled = true
        print("|cff33ff99CraftLinker|r enabled.")
    elseif args[1] == "off" then
        CraftLinkerDB.enabled = false
        print("|cff33ff99CraftLinker|r disabled.")
    elseif args[1] == "trigger" and args[2] then
        CraftLinkerDB.trigger = args[2]
        print("|cff33ff99CraftLinker|r trigger word set to: " .. args[2])
    elseif args[1] == "cooldown" and tonumber(args[2]) then
        CraftLinkerDB.cooldown = tonumber(args[2])
        print("|cff33ff99CraftLinker|r cooldown set to " .. args[2] .. "s.")
    elseif args[1] == "status" then
        print("|cff33ff99CraftLinker|r cached professions:")
        local any = false
        for name in pairs(CraftLinkerDB.links) do
            print("  - " .. name)
            any = true
        end
        if not any then
            print("  (none yet -- open a profession window to cache it)")
        end
    elseif args[1] == "clear" and args[2] then
        local target = args[2]
        local removed = false
        for profName in pairs(CraftLinkerDB.links) do
            if profName:lower() == target then
                CraftLinkerDB.links[profName] = nil
                removed = true
                break
            end
        end
        if removed then
            print("|cff33ff99CraftLinker|r cleared cached link for that profession.")
        else
            print("|cff33ff99CraftLinker|r no cached link found matching that name.")
        end
    elseif args[1] == "clearall" then
        CraftLinkerDB.links = {}
        print("|cff33ff99CraftLinker|r cleared all cached links.")
    else
        print("|cff33ff99CraftLinker|r commands:")
        print("  /craftlink on|off")
        print("  /craftlink trigger <word>  (current: " .. CraftLinkerDB.trigger .. ")")
        print("  /craftlink cooldown <seconds>  (current: " .. CraftLinkerDB.cooldown .. ")")
        print("  /craftlink status  (show which professions are cached)")
        print("  /craftlink clear <ProfessionName>  (remove one cached entry)")
        print("  /craftlink clearall  (wipe all cached entries)")
    end
end
