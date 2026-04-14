local ADDON_NAME = "LowIlvlWarner"
local LIW = _G[ADDON_NAME]

function LIW.DBG(msg)
    -- print("|cFF88CCFFLowIlvlWarner:|r " .. tostring(msg))
end

function LIW.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            LIW.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function LIW.IterateGroup(callback)
    local inRaid = IsInRaid()
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = inRaid and ("raid" .. i) or ("party" .. i)
        callback(unit)
    end
end

function LIW.CreateCheckbox(parent, label, anchorFrame, offsetY, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent)

    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, offsetY)

    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb.label = text

    cb:SetScript("OnShow", function(self)
        self:SetChecked(getter())
    end)

    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
        LIW.ScanGroup()
        LIW.RefreshWarningFrame()
    end)

    return cb
end
