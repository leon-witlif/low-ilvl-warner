local ADDON_NAME = "LowIlvlWarner"
local LIW = _G[ADDON_NAME]

local configFrame

local function BuildConfigFrame()
    configFrame = CreateFrame("Frame", "LowIlvlWarnerConfig", UIParent, "BackdropTemplate")
    configFrame:SetSize(270, 140)
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    configFrame:SetBackdropColor(0, 0, 0, 0.92)
    local cfgPos = LIW.db.configFrame
    configFrame:SetPoint("CENTER", UIParent, "CENTER", cfgPos.x, cfgPos.y)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    configFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local fx, fy = self:GetCenter()
        local cx = UIParent:GetWidth()  / 2
        local cy = UIParent:GetHeight() / 2
        LIW.db.configFrame.x = math.floor(fx - cx + 0.5)
        LIW.db.configFrame.y = math.floor(fy - cy + 0.5)
    end)
    configFrame:Hide()

    -- Title
    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("LowIlvlWarner - Settings")

    -- Divider below title
    local div1 = configFrame:CreateTexture(nil, "ARTWORK")
    div1:SetSize(230, 1)
    div1:SetPoint("TOP", 0, -30)
    div1:SetColorTexture(0.4, 0.4, 0.4, 0.8)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() configFrame:Hide() end)

    -- Threshold
    local threshLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    threshLabel:SetPoint("TOPLEFT", 18, -46)
    threshLabel:SetText("Item Level Threshold:")

    local threshBox = CreateFrame("EditBox", "LowIlvlWarnerThreshBox", configFrame, "InputBoxTemplate")
    threshBox:SetSize(70, 20)
    threshBox:SetPoint("LEFT", threshLabel, "RIGHT", 8, 0)
    threshBox:SetNumeric(true)
    threshBox:SetMaxLetters(5)
    threshBox:SetAutoFocus(false)

    local function CommitThreshold()
        local val = tonumber(threshBox:GetText())
        if val and val >= 1 then
            LIW.db.threshold = val
            LIW.RefreshWarningFrame()
        else
            threshBox:SetText(tostring(LIW.db.threshold))
        end
    end

    threshBox:SetScript("OnEnterPressed", function(self) CommitThreshold(); self:ClearFocus() end)
    threshBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(LIW.db.threshold)); self:ClearFocus()
    end)
    threshBox:SetScript("OnEditFocusLost", CommitThreshold)

    local partyCB = LIW.CreateCheckbox(
        configFrame, "Enable for Party", threshLabel, -10,
        function() return LIW.db.enableParty end,
        function(v) LIW.db.enableParty = v end
    )

    local raidCB = LIW.CreateCheckbox(
        configFrame, "Enable for Raid", partyCB, -4,
        function() return LIW.db.enableRaid end,
        function(v) LIW.db.enableRaid = v end
    )

    -- Version
    local ver = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("BOTTOMRIGHT", -14, 10)
    ver:SetText(LIW.VERSION)

    -- Sync controls to current db values every time the panel opens
    configFrame:SetScript("OnShow", function()
        threshBox:SetText(tostring(LIW.db.threshold))
        partyCB:SetChecked(LIW.db.enableParty)
        raidCB:SetChecked(LIW.db.enableRaid)
    end)
end

function LIW.ToggleConfig()
    if not configFrame then
        BuildConfigFrame()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end

local function SetupMinimapButton()
    local LDB  = LibStub("LibDataBroker-1.1", true)
    local Icon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not Icon then return end

    local dataObj = LDB:NewDataObject(ADDON_NAME, {
        type  = "launcher",
        icon  = "Interface\\Icons\\INV_Misc_Gear_01",
        label = "LowIlvlWarner",
        OnClick = function(_, button)
            if button == "LeftButton" then LIW.ToggleConfig() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cFFFFFFFFLowIlvlWarner|r")
            tt:AddLine("Left-click to toggle settings", 0.8, 0.8, 0.8)
            tt:AddLine(string.format("Threshold: |cFFFFAA00%d ilvl|r", LIW.db.threshold), 1, 1, 1)
        end,
    })

    Icon:Register(ADDON_NAME, dataObj, LIW.db.minimap)
end

local function RegisterSlash()
    SLASH_LOWILVLWARNER1 = "/liw"
    SLASH_LOWILVLWARNER2 = "/lowilvlwarner"

    SlashCmdList["LOWILVLWARNER"] = function(args)
        args = args and args:match("^%s*(.-)%s*$") or ""
        if args == "config" then
            LIW.ToggleConfig()
        elseif args == "minimap" then
            local Icon = LibStub("LibDBIcon-1.0", true)
            if Icon then
                LIW.db.minimap.hide = not LIW.db.minimap.hide
                if LIW.db.minimap.hide then
                    Icon:Hide(ADDON_NAME)
                    print("|cFFFFFFFFLowIlvlWarner:|r Minimap button hidden.")
                else
                    Icon:Show(ADDON_NAME)
                    print("|cFFFFFFFFLowIlvlWarner:|r Minimap button shown.")
                end
            end
        else
            print("|cFFFFFFFFLowIlvlWarner commands:|r")
            print("  /liw config - toggle settings panel")
            print("  /liw minimap - show/hide minimap button")
        end
    end
end

function LIW.InitOptions()
    SetupMinimapButton()
    RegisterSlash()
end
