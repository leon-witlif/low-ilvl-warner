local ADDON_NAME = "LowIlvlWarner"
local LIW = _G[ADDON_NAME]

local db
local memberIlvl       = {}     -- [guid] = { name, ilvl }
local inspectQueue     = {}     -- ordered list of units waiting to be inspected
local inspectActive    = false  -- true while NotifyInspect is in flight
local inspectScheduled = false  -- true while a C_Timer.After for ProcessNextInspect is pending

local warnFrame

local function BuildWarningFrame()
    warnFrame = CreateFrame("Frame", "LowIlvlWarnerFrame", UIParent, "BackdropTemplate")
    warnFrame:SetSize(280, 60)
    warnFrame:SetFrameStrata("HIGH")
    warnFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    warnFrame:SetBackdropColor(0, 0, 0, 0.75)
    warnFrame:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)

    local pos = db.warnFrame
    warnFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)

    warnFrame:SetMovable(true)
    warnFrame:EnableMouse(true)
    warnFrame:RegisterForDrag("LeftButton")
    warnFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    warnFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left = self:GetLeft()
        local top  = self:GetTop()
        db.warnFrame.x = math.floor(left + 0.5)
        db.warnFrame.y = math.floor(top  - UIParent:GetHeight() + 0.5)
    end)

    local title = warnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("|cFFFF4444Low Item Level Warning|r")
    warnFrame.title = title
    warnFrame.lines = {}
    warnFrame:Hide()
end

function LIW.RefreshWarningFrame()
    if not warnFrame then return end

    local inRaid  = IsInRaid()
    local inParty = IsInGroup() and not inRaid
    local enabled = (inRaid and db.enableRaid) or (inParty and db.enableParty)

    if not enabled or not IsInGroup() then
        warnFrame:Hide()
        return
    end

    local offenders = {}
    for _, info in pairs(memberIlvl) do
        if info.ilvl > 0 and info.ilvl < db.threshold then
            table.insert(offenders, info)
        end
    end
    table.sort(offenders, function(a, b) return a.ilvl < b.ilvl end)

    if #offenders == 0 then
        warnFrame:Hide()
        return
    end

    local lineHeight        = 14
    local titleHeight       = 20
    local padding           = 14
    local horizontalPadding = 16

    warnFrame:SetHeight(titleHeight + #offenders * lineHeight + padding)

    local maxWidth = warnFrame.title:GetStringWidth() + horizontalPadding * 2

    for i, info in ipairs(offenders) do
        if not warnFrame.lines[i] then
            local fs = warnFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", 8, -(titleHeight + (i - 1) * lineHeight + 4))
            warnFrame.lines[i] = fs
        end
        local diff = info.ilvl - db.threshold
        warnFrame.lines[i]:SetText(string.format(
            "|cFFFFAA00%s|r  |cFFFF4444%d ilvl|r  |cFFAAAAAA(%+d)|r",
            info.name, info.ilvl, diff))
        warnFrame.lines[i]:Show()
        local w = warnFrame.lines[i]:GetStringWidth() + horizontalPadding * 2
        if w > maxWidth then maxWidth = w end
    end
    for i = #offenders + 1, #warnFrame.lines do
        warnFrame.lines[i]:Hide()
    end

    warnFrame:SetWidth(math.max(maxWidth, 160))

    warnFrame:Show()
end

local ProcessNextInspect

ProcessNextInspect = function()
    inspectScheduled = false

    -- Remove entries for units that no longer exist
    while #inspectQueue > 0 and not UnitExists(inspectQueue[1]) do
        LIW.DBG("Skipping non-existent unit: " .. inspectQueue[1])
        table.remove(inspectQueue, 1)
    end

    if #inspectQueue == 0 then
        inspectActive = false
        LIW.DBG("Inspect queue empty.")
        return
    end

    local unit = inspectQueue[1]

    if not CanInspect(unit) then
        LIW.DBG("CanInspect false for " .. unit .. " (NPC or hostile PvP), dropping")
        table.remove(inspectQueue, 1)
        inspectActive = false
        if #inspectQueue > 0 then
            inspectScheduled = true
            C_Timer.After(LIW.INSPECT_DELAY, ProcessNextInspect)
        end
        return
    end

    LIW.DBG("Inspecting " .. (UnitName(unit) or unit) .. " (" .. unit .. ")...")
    inspectActive = true
    NotifyInspect(unit)

    C_Timer.After(8, function()
        if inspectActive and inspectQueue[1] == unit then
            LIW.DBG("Inspect timeout for " .. unit .. ", re-queuing at back")
            table.remove(inspectQueue, 1)
            if UnitExists(unit) then
                inspectQueue[#inspectQueue + 1] = unit
            end
            inspectActive    = false
            inspectScheduled = true
            C_Timer.After(LIW.INSPECT_DELAY, ProcessNextInspect)
        end
    end)
end

local function EnqueueInspect(unit)
    for _, u in ipairs(inspectQueue) do
        if u == unit then return end
    end

    inspectQueue[#inspectQueue + 1] = unit
    LIW.DBG("Queued inspect for " .. unit .. " (queue length: " .. #inspectQueue .. ")")

    if not inspectActive and not inspectScheduled then
        inspectScheduled = true
        C_Timer.After(LIW.INSPECT_DELAY, ProcessNextInspect)
    end
end

local rosterScanTimer = nil

local function DoScanGroup()
    rosterScanTimer = nil

    local inRaid  = IsInRaid()
    local inParty = IsInGroup() and not inRaid

    LIW.DBG(string.format("DoScanGroup - inGroup=%s inRaid=%s inParty=%s",
        tostring(IsInGroup()), tostring(inRaid), tostring(inParty)))

    local currentGUIDs = {}

    -- Always track the player (no inspect needed)
    do
        local guid = UnitGUID("player")
        local name = UnitName("player") or "You"
        if guid then
            currentGUIDs[guid] = true
            local _, avgEquipped = GetAverageItemLevel()
            local ilvl = math.floor(avgEquipped or 0)
            memberIlvl[guid] = { name = name, ilvl = ilvl }
            LIW.DBG(string.format("Player [%s] ilvl=%d", name, ilvl))
        end
    end

    if IsInGroup() then
        local n = GetNumGroupMembers()
        LIW.DBG("Group members: " .. n)
        LIW.IterateGroup(function(unit)
            if not UnitExists(unit) then
                LIW.DBG("  " .. unit .. " does not exist, skipping")
                return
            end
            local guid = UnitGUID(unit)
            local name = UnitName(unit) or unit
            if not guid then
                LIW.DBG("  " .. unit .. " has no GUID, skipping")
                return
            end
            currentGUIDs[guid] = true
            if not memberIlvl[guid] then
                memberIlvl[guid] = { name = name, ilvl = 0 }
            end
            if memberIlvl[guid].ilvl == 0 then
                LIW.DBG(string.format("  Enqueuing inspect for %s (%s) [unknown]", name, unit))
                EnqueueInspect(unit)
            else
                LIW.DBG(string.format("  Skipping %s (%s) - ilvl already known (%d)", name, unit, memberIlvl[guid].ilvl))
            end
        end)
    else
        LIW.DBG("Not in a group - only tracking local player")
    end

    -- Prune stale entries
    for guid in pairs(memberIlvl) do
        if not currentGUIDs[guid] then
            LIW.DBG("Pruning stale entry: " .. (memberIlvl[guid].name or guid))
            memberIlvl[guid] = nil
        end
    end

    LIW.DBG("memberIlvl after scan:")
    for guid, info in pairs(memberIlvl) do
        LIW.DBG(string.format("  %s  ilvl=%d", info.name, info.ilvl))
    end

    LIW.RefreshWarningFrame()
end

function LIW.ScanGroup()
    if rosterScanTimer then
        rosterScanTimer:Cancel()
    end
    rosterScanTimer = C_Timer.NewTimer(0.5, DoScanGroup)
end

local fastTicker
local slowTicker

local function DoFastScan()
    if not IsInGroup() then return end
    LIW.IterateGroup(function(unit)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        if not memberIlvl[guid] or memberIlvl[guid].ilvl == 0 then
            LIW.DBG("Fast scan: enqueuing unknown " .. (UnitName(unit) or unit))
            EnqueueInspect(unit)
        end
    end)
end

local function StartTicker()
    if fastTicker then fastTicker:Cancel() end
    if slowTicker then slowTicker:Cancel() end

    fastTicker = C_Timer.NewTicker(LIW.FAST_SCAN_INTERVAL, DoFastScan)
    slowTicker = C_Timer.NewTicker(LIW.SLOW_SCAN_INTERVAL, DoScanGroup)
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("INSPECT_READY")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON_NAME then return end

        LowIlvlWarnerDB = LowIlvlWarnerDB or {}
        LIW.ApplyDefaults(LowIlvlWarnerDB, LIW.DB_DEFAULTS)
        db = LowIlvlWarnerDB
        LIW.db = db

        LIW.DBG("Initialized. Threshold=" .. db.threshold
            .. " party=" .. tostring(db.enableParty)
            .. " raid=" .. tostring(db.enableRaid))

        BuildWarningFrame()

        if LIW.InitOptions then
            LIW.InitOptions()
        end

        print("LowIlvlWarner loaded")

    elseif event == "PLAYER_ENTERING_WORLD" then
        LIW.DBG("PLAYER_ENTERING_WORLD fired")
        if db then
            LIW.ScanGroup()
            StartTicker()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        LIW.DBG("GROUP_ROSTER_UPDATE fired")
        if db then LIW.ScanGroup() end

    elseif event == "INSPECT_READY" then
        local guid = ...

        local resolvedUnit = nil
        local resolvedName = nil

        LIW.IterateGroup(function(unit)
            if UnitGUID(unit) == guid then
                resolvedUnit = unit
                resolvedName = UnitName(unit) or unit
            end
        end)

        if not resolvedUnit then
            LIW.DBG("INSPECT_READY: could not resolve unit for guid=" .. tostring(guid) .. ", ignoring")
            inspectActive = false
            if #inspectQueue > 0 then
                inspectScheduled = true
                C_Timer.After(LIW.INSPECT_DELAY, ProcessNextInspect)
            end
            return
        end

        local ilvl = C_PaperDollInfo.GetInspectItemLevel(resolvedUnit) or 0
        local flooredIlvl = math.floor(ilvl)

        LIW.DBG(string.format("INSPECT_READY %s (%s) rawIlvl=%.1f stored=%d",
            resolvedName, resolvedUnit, ilvl, flooredIlvl))

        memberIlvl[guid] = { name = resolvedName, ilvl = flooredIlvl }

        if inspectQueue[1] and UnitGUID(inspectQueue[1]) == guid then
            table.remove(inspectQueue, 1)
        end
        inspectActive    = false
        inspectScheduled = true
        C_Timer.After(LIW.INSPECT_DELAY, ProcessNextInspect)

        LIW.RefreshWarningFrame()
    end
end)

