-- Trinket ICD Tracker
-- A small, intentionally simple internal cooldown tracker for WoW TBC Anniversary.
--
-- To add another trinket, add an entry to TRINKETS below:
-- [ITEM_ID] = {
--     name = "Trinket name",
--     procSpellID = SPELL_ID_OF_THE_PROC_BUFF,
--     cooldown = INTERNAL_COOLDOWN_IN_SECONDS,
-- }

local ADDON_NAME = "TrinketICDTracker"
local FRAME_NAME = "TrinketICDTrackerFrame"

-- Supported trinkets.
-- Sextant of Unstable Currents applies Unstable Currents (spell ID 38348).
local TRINKETS = {
    [30626] = {
        name = "Sextant of Unstable Currents",
        procSpellID = 38348,
        cooldown = 45,
    },
}

local DEFAULTS = {
    x = 0,
    y = -140,
    locked = false,
    enabled = true,
    debug = false,
}

local tracker = {
    initialized = false,
    playerGUID = nil,
    timers = {},
    frames = {},
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffTrinket ICD Tracker:|r " .. tostring(message))
end

local function Trim(text)
    text = tostring(text or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

function tracker:Debug(message)
    if self.db and self.db.debug then
        Print("|cffaaaaaa[debug]|r " .. tostring(message))
    end
end

function tracker:EnsureDatabase()
    if type(TrinketICDTrackerDB) ~= "table" then
        TrinketICDTrackerDB = {}
    end

    self.db = TrinketICDTrackerDB
    for key, value in pairs(DEFAULTS) do
        if self.db[key] == nil then
            self.db[key] = value
        end
    end
end

function tracker:PlaceRoot()
    self.root:ClearAllPoints()
    self.root:SetPoint("CENTER", UIParent, "CENTER", self.db.x, self.db.y)
end

function tracker:SaveRootPosition()
    local _, _, _, x, y = self.root:GetPoint(1)
    if x and y then
        self.db.x = x
        self.db.y = y
    end
end

function tracker:IsItemEquipped(itemID)
    for _, slot in ipairs({13, 14}) do
        local equippedID = GetInventoryItemID("player", slot)

        -- GetInventoryItemID is available in TBC Classic. The link fallback is
        -- useful on clients where the item ID is not returned until the item is
        -- cached.
        if not equippedID then
            local link = GetInventoryItemLink("player", slot)
            if link then
                equippedID = tonumber(link:match("item:(%d+)"))
            end
        end

        if equippedID == itemID then
            return true
        end
    end

    return false
end

function tracker:GetEquippedSupportedItem()
    for itemID, entry in pairs(TRINKETS) do
        if self:IsItemEquipped(itemID) then
            return itemID, entry
        end
    end
    return nil, nil
end

function tracker:CreateItemFrame(itemID, entry)
    local frame = CreateFrame("Frame", nil, self.root)
    frame:SetSize(48, 48)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame.icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon:SetAllPoints(frame)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.border:SetBlendMode("ADD")
    frame.border:SetAllPoints(frame)

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame)

    -- Allow Blizzard's native cooldown countdown text to be used. The global
    -- countdownForCooldowns CVar, controlled by the "Show Numbers for
    -- Cooldowns" option, decides whether the number is actually visible.
    if frame.cooldown.SetHideCountdownNumbers then
        frame.cooldown:SetHideCountdownNumbers(false)
    end
    if frame.cooldown.SetDrawSwipe then
        frame.cooldown:SetDrawSwipe(true)
    end
    if frame.cooldown.SetDrawEdge then
        frame.cooldown:SetDrawEdge(true)
    end

    frame:SetScript("OnDragStart", function()
        if not tracker.db.locked then
            tracker.root:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function()
        tracker.root:StopMovingOrSizing()
        tracker:SaveRootPosition()
    end)

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink("item:" .. itemID)
        else
            GameTooltip:SetText(entry.name)
        end
        GameTooltip:AddLine("Internal cooldown: " .. tostring(entry.cooldown) .. " sec", 1, 1, 1)
        GameTooltip:Show()
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:SetScript("OnUpdate", function(self)
        local timer = tracker.timers[itemID]
        if not timer then
            return
        end

        local remaining = timer.endTime - GetTime()
        if remaining <= 0 then
            tracker.timers[itemID] = nil
            self.cooldown:SetCooldown(0, 0)
            tracker:RefreshVisibility()
            return
        end
    end)

    local icon = entry.icon
    if not icon then
        icon = GetItemIcon(itemID)
    end
    frame.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    self.frames[itemID] = frame
    return frame
end

function tracker:CreateFrames()
    for itemID, entry in pairs(TRINKETS) do
        if not self.frames[itemID] then
            self:CreateItemFrame(itemID, entry)
        end
    end
end

function tracker:RefreshVisibility()
    if not self.initialized then
        return
    end

    local visible = {}
    local now = GetTime()

    for itemID, frame in pairs(self.frames) do
        local timer = self.timers[itemID]
        local show = self.db.enabled and timer and timer.endTime > now and self:IsItemEquipped(itemID)

        if timer and timer.endTime <= now then
            self.timers[itemID] = nil
            timer = nil
        end

        if show then
            visible[#visible + 1] = itemID
            frame:Show()
        else
            frame:Hide()
        end
    end

    table.sort(visible)

    if #visible == 0 then
        self.root:Hide()
        return
    end

    self.root:SetHeight(48 + ((#visible - 1) * 52))
    self.root:Show()

    for index, itemID in ipairs(visible) do
        local frame = self.frames[itemID]
        frame:ClearAllPoints()
        frame:SetPoint("TOP", self.root, "TOP", 0, -((index - 1) * 52))
    end
end

function tracker:StartCooldown(itemID, entry)
    local now = GetTime()
    local timer = {
        startTime = now,
        endTime = now + entry.cooldown,
    }

    self.timers[itemID] = timer
    local frame = self.frames[itemID]
    if frame then
        -- Use the same Blizzard cooldown path used by action-bar and item
        -- buttons. SetHideCountdownNumbers(false) opts this frame into the
        -- native number display; the global "Show Numbers for Cooldowns"
        -- option still controls whether the number is visible.
        if frame.cooldown.SetHideCountdownNumbers then
            frame.cooldown:SetHideCountdownNumbers(false)
        end
        if CooldownFrame_SetTimer then
            CooldownFrame_SetTimer(frame.cooldown, timer.startTime, entry.cooldown, 1)
        else
            frame.cooldown:SetCooldown(timer.startTime, entry.cooldown)
        end
    end

    self:Debug(entry.name .. " proc detected; started " .. tostring(entry.cooldown) .. " second cooldown")
    self:RefreshVisibility()
end

function tracker:HandleCombatLog(...)
    local timestamp, subevent, hideCaster
    local sourceGUID, sourceName, sourceFlags, sourceRaidFlags
    local destGUID, destName, destFlags, destRaidFlags
    local spellID, spellName, spellSchool

    if CombatLogGetCurrentEventInfo then
        timestamp, subevent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellID, spellName, spellSchool = CombatLogGetCurrentEventInfo()
    else
        -- Compatibility fallback for clients that pass combat-log arguments
        -- directly to the event handler.
        timestamp, subevent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellID, spellName, spellSchool = ...
    end

    if not subevent then
        return
    end

    local affectsPlayer = destGUID == self.playerGUID or sourceGUID == self.playerGUID
    if self.db.debug and affectsPlayer and subevent:find("SPELL_AURA_") then
        self:Debug(string.format(
            "%s: %s (%s), source=%s, dest=%s",
            subevent,
            tostring(spellName or "unknown spell"),
            tostring(spellID or "?"),
            tostring(sourceName or "?"),
            tostring(destName or "?")
        ))
    end

    if not self.db.enabled or subevent ~= "SPELL_AURA_APPLIED" or destGUID ~= self.playerGUID then
        return
    end

    for itemID, entry in pairs(TRINKETS) do
        if spellID == entry.procSpellID and self:IsItemEquipped(itemID) then
            self:StartCooldown(itemID, entry)
            return
        end
    end
end

function tracker:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ADDON_NAME then
            return
        end

        self:EnsureDatabase()
        self.root = CreateFrame("Frame", FRAME_NAME, UIParent)
        self.root:SetSize(48, 48)
        self.root:SetMovable(true)
        self.root:SetClampedToScreen(true)
        self.root:SetFrameStrata("MEDIUM")
        self:PlaceRoot()
        self:CreateFrames()
        self.initialized = true
        self:RefreshVisibility()
        return
    end

    if not self.initialized then
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        self.playerGUID = UnitGUID("player")
        self:RefreshVisibility()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        self:RefreshVisibility()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog(...)
    end
end

function tracker:ResetPosition()
    self.db.x = DEFAULTS.x
    self.db.y = DEFAULTS.y
    self:PlaceRoot()
    Print("Position reset.")
end

function tracker:PrintHelp()
    Print("Commands:")
    Print("/tic help - show this help")
    Print("/tic debug - toggle combat-log debug output")
    Print("/tic lock - lock the tracker position")
    Print("/tic unlock - allow the tracker to be dragged")
    Print("/tic reset - reset the tracker position")
    Print("Supported: Sextant of Unstable Currents (30626)")
end

SLASH_TRINKETICDTRACKER1 = "/tic"
SlashCmdList.TRINKETICDTRACKER = function(message)
    local command = Trim(message):lower()

    if command == "" or command == "help" then
        tracker:PrintHelp()
    elseif command == "debug" then
        tracker.db.debug = not tracker.db.debug
        Print("Debug output " .. (tracker.db.debug and "enabled" or "disabled") .. ".")
    elseif command == "lock" then
        tracker.db.locked = true
        Print("Tracker locked.")
    elseif command == "unlock" then
        tracker.db.locked = false
        Print("Tracker unlocked; drag the icon to move it.")
    elseif command == "reset" then
        tracker:ResetPosition()
    elseif command == "enable" then
        tracker.db.enabled = true
        tracker:RefreshVisibility()
        Print("Tracker enabled.")
    elseif command == "disable" then
        tracker.db.enabled = false
        tracker:RefreshVisibility()
        Print("Tracker disabled.")
    else
        Print("Unknown command. Use /tic help.")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    tracker:OnEvent(event, ...)
end)
