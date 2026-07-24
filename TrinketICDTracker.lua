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
    enabled = true,
    debug = false,
}

-- Standard Blizzard action-bar button groups in TBC Classic.
local ACTIONBAR_GROUPS = {
    "Action",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
}

local tracker = {
    initialized = false,
    playerGUID = nil,
    timers = {},
    actionBarOverlays = {},
    trinketMenuOverlays = {},
    trinketMenuOverlayButtons = {},
    trinketMenuHooked = false,
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

function tracker:GetActionButtonSlot(button)
    if not button then
        return nil
    end

    -- TBC Classic's standard action buttons expose their current action slot
    -- through the action field and ActionButton_GetPagedID().
    if button.action then
        return button.action
    end
    if ActionButton_GetPagedID then
        return ActionButton_GetPagedID(button)
    end
    if ActionButton_CalculateAction then
        return ActionButton_CalculateAction(button)
    end
    if button.GetAttribute then
        return button:GetAttribute("action")
    end

    return nil
end

function tracker:CollectActionButtons()
    local buttons = {}
    local seen = {}

    local function AddButton(button)
        if button and not seen[button] then
            seen[button] = true
            buttons[#buttons + 1] = button
        end
    end

    for _, groupName in ipairs(ACTIONBAR_GROUPS) do
        for index = 1, 12 do
            AddButton(_G[groupName .. "Button" .. index])
        end
    end

    -- Some Classic UI builds expose the same buttons through this registry.
    -- Include it as a fallback without requiring it to exist.
    if ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do
            AddButton(button)
        end
    end

    return buttons
end

function tracker:CreateActionBarOverlays()
    if not self.initialized or #self.actionBarOverlays > 0 then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end

    for _, button in ipairs(self:CollectActionButtons()) do
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(button)
        cooldown:SetFrameLevel(button:GetFrameLevel() + 10)
        if cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(false)
        end
        if cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(true)
        end
        if cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(true)
        end
        cooldown:Hide()

        self.actionBarOverlays[#self.actionBarOverlays + 1] = {
            button = button,
            cooldown = cooldown,
        }
    end

    self:Debug("Created " .. tostring(#self.actionBarOverlays) .. " action-bar cooldown overlays")
end

function tracker:IsActionButtonForItem(button, itemID)
    local actionSlot = self:GetActionButtonSlot(button)
    if not actionSlot then
        return false
    end

    local actionType, actionID = GetActionInfo(actionSlot)
    return actionType == "item" and tonumber(actionID) == tonumber(itemID)
end

function tracker:RefreshActionBarCooldowns()
    if not self.initialized then
        return
    end

    for _, overlay in ipairs(self.actionBarOverlays) do
        overlay.cooldown:Hide()
    end

    if not self.db.enabled then
        return
    end

    local now = GetTime()
    for itemID, timer in pairs(self.timers) do
        if timer.endTime > now and self:IsItemEquipped(itemID) then
            local entry = TRINKETS[itemID]
            for _, overlay in ipairs(self.actionBarOverlays) do
                if self:IsActionButtonForItem(overlay.button, itemID) then
                    if overlay.cooldown.SetHideCountdownNumbers then
                        overlay.cooldown:SetHideCountdownNumbers(false)
                    end
                    if CooldownFrame_SetTimer then
                        CooldownFrame_SetTimer(overlay.cooldown, timer.startTime, entry.cooldown, 1)
                    else
                        overlay.cooldown:SetCooldown(timer.startTime, entry.cooldown)
                    end
                    overlay.cooldown:Show()
                end
            end
        end
    end
end

function tracker:CreateTrinketMenuOverlays()
    if not self.initialized then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end

    -- TrinketMenu creates these buttons even when its windows are hidden. We
    -- attach a separate cooldown frame so TrinketMenu's normal item cooldown
    -- refreshes cannot overwrite the internal cooldown.
    for index = 0, 1 do
        local button = _G["TrinketMenu_Trinket" .. index]
        if button and not self.trinketMenuOverlayButtons[button] then
            local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cooldown:SetAllPoints(button)
            cooldown:SetFrameLevel(button:GetFrameLevel() + 10)
            if cooldown.SetHideCountdownNumbers then
                cooldown:SetHideCountdownNumbers(false)
            end
            if cooldown.SetDrawSwipe then
                cooldown:SetDrawSwipe(true)
            end
            if cooldown.SetDrawEdge then
                cooldown:SetDrawEdge(true)
            end
            cooldown:Hide()

            local overlay = {
                button = button,
                cooldown = cooldown,
                kind = "worn",
                index = index,
            }
            self.trinketMenuOverlays[#self.trinketMenuOverlays + 1] = overlay
            self.trinketMenuOverlayButtons[button] = overlay
        end
    end

    for index = 1, 30 do
        local button = _G["TrinketMenu_Menu" .. index]
        if button and not self.trinketMenuOverlayButtons[button] then
            local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cooldown:SetAllPoints(button)
            cooldown:SetFrameLevel(button:GetFrameLevel() + 10)
            if cooldown.SetHideCountdownNumbers then
                cooldown:SetHideCountdownNumbers(false)
            end
            if cooldown.SetDrawSwipe then
                cooldown:SetDrawSwipe(true)
            end
            if cooldown.SetDrawEdge then
                cooldown:SetDrawEdge(true)
            end
            cooldown:Hide()

            local overlay = {
                button = button,
                cooldown = cooldown,
                kind = "menu",
                index = index,
            }
            self.trinketMenuOverlays[#self.trinketMenuOverlays + 1] = overlay
            self.trinketMenuOverlayButtons[button] = overlay
        end
    end

    if #self.trinketMenuOverlays > 0 then
        self:Debug("Created " .. tostring(#self.trinketMenuOverlays) .. " TrinketMenu cooldown overlays")
    end
end

function tracker:HookTrinketMenu()
    if self.trinketMenuHooked or not TrinketMenu or not TrinketMenu.BuildMenu or not hooksecurefunc then
        return
    end

    hooksecurefunc(TrinketMenu, "BuildMenu", function()
        tracker:CreateTrinketMenuOverlays()
        tracker:RefreshTrinketMenuCooldowns()
    end)
    self.trinketMenuHooked = true
end

function tracker:GetTrinketMenuItemID(overlay)
    if overlay.kind == "worn" then
        local slot = 13 + overlay.index
        local itemID = GetInventoryItemID("player", slot)
        if not itemID then
            local link = GetInventoryItemLink("player", slot)
            if link then
                itemID = tonumber(link:match("item:(%d+)"))
            end
        end
        return itemID
    end

    if TrinketMenu and TrinketMenu.BaggedTrinkets then
        local item = TrinketMenu.BaggedTrinkets[overlay.index]
        return item and tonumber(item.id)
    end

    return nil
end

function tracker:RefreshTrinketMenuCooldowns()
    if not self.initialized then
        return
    end

    self:CreateTrinketMenuOverlays()

    for _, overlay in ipairs(self.trinketMenuOverlays) do
        overlay.cooldown:Hide()
    end

    if not self.db.enabled then
        return
    end

    local now = GetTime()
    for itemID, timer in pairs(self.timers) do
        if timer.endTime > now then
            local entry = TRINKETS[itemID]
            for _, overlay in ipairs(self.trinketMenuOverlays) do
                if self:GetTrinketMenuItemID(overlay) == itemID then
                    if overlay.cooldown.SetHideCountdownNumbers then
                        overlay.cooldown:SetHideCountdownNumbers(false)
                    end
                    if CooldownFrame_SetTimer then
                        CooldownFrame_SetTimer(overlay.cooldown, timer.startTime, entry.cooldown, 1)
                    else
                        overlay.cooldown:SetCooldown(timer.startTime, entry.cooldown)
                    end
                    overlay.cooldown:Show()
                end
            end
        end
    end
end

function tracker:RefreshVisibility()
    if not self.initialized then
        return
    end

    self:RefreshActionBarCooldowns()
    self:RefreshTrinketMenuCooldowns()
end

function tracker:UpdateTimers()
    if not self.initialized then
        return
    end

    local now = GetTime()
    local changed = false
    for itemID, timer in pairs(self.timers) do
        if timer.endTime <= now then
            self.timers[itemID] = nil
            changed = true
        end
    end

    if changed then
        self:RefreshVisibility()
    end
end

function tracker:StartCooldown(itemID, entry)
    local now = GetTime()
    self.timers[itemID] = {
        startTime = now,
        endTime = now + entry.cooldown,
    }

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
        if loadedName == ADDON_NAME then
            self:EnsureDatabase()
            self.initialized = true
            self:RefreshVisibility()
        elseif (loadedName == "TrinketMenu" or loadedName == "TrinketMenuClassic") and self.initialized then
            self:CreateTrinketMenuOverlays()
            self:HookTrinketMenu()
            self:RefreshTrinketMenuCooldowns()
        end
        return
    end

    if not self.initialized then
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        self.playerGUID = UnitGUID("player")
        self:CreateActionBarOverlays()
        self:CreateTrinketMenuOverlays()
        self:HookTrinketMenu()
        self:RefreshVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:CreateActionBarOverlays()
        self:CreateTrinketMenuOverlays()
        self:RefreshActionBarCooldowns()
        self:RefreshTrinketMenuCooldowns()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        self:CreateTrinketMenuOverlays()
        self:RefreshVisibility()
    elseif event == "BAG_UPDATE" then
        self:CreateTrinketMenuOverlays()
        self:RefreshTrinketMenuCooldowns()
    elseif event == "ACTIONBAR_SLOT_CHANGED"
        or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTIONBAR" then
        self:CreateActionBarOverlays()
        self:RefreshActionBarCooldowns()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog(...)
    end
end

function tracker:PrintHelp()
    Print("Commands:")
    Print("/tic help - show this help")
    Print("/tic debug - toggle combat-log debug output")
    Print("/tic enable - enable the tracker")
    Print("/tic disable - disable the tracker")
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
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    tracker:OnEvent(event, ...)
end)
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    tracker.updateElapsed = (tracker.updateElapsed or 0) + elapsed
    if tracker.updateElapsed >= 0.1 then
        tracker.updateElapsed = 0
        tracker:UpdateTimers()
    end
end)
