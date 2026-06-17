-- ============================================================
-- Panel.lua  —  the rune-engraving panel (MVP).
--
-- A simple two-column window: the slot list on the left, the runes engravable
-- in the selected slot on the right. Renders entirely from NS.model (built by
-- Comms.lua from the server's BEGIN…END push); actions send ENG/DEL back. No
-- art beyond stock textures — functional first.
-- ============================================================

local NS = RuneEngraverNS

local SLOT_MAX   = 11
local ICON_PATH  = "Interface\\Icons\\"

local selectedSlot = nil   ---@type number|nil  currently-browsed slot index

-- ── Frame shell ─────────────────────────────────────────────────────────────
local panel = CreateFrame("Frame", "RuneEngraverFrame", UIParent)
panel:SetSize(470, 360)
panel:SetPoint("CENTER")
panel:SetFrameStrata("MEDIUM")
panel:SetToplevel(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", panel, "TOP", 0, -16)
title:SetText("Rune Engraver")

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)

local slotHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
slotHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -44)
slotHeader:SetText("Slots")

local runeHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
runeHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 220, -44)
runeHeader:SetText("Runes")

local statusFS = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
statusFS:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 16)
statusFS:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 16)
statusFS:SetJustifyH("LEFT")

-- ── Row factory ─────────────────────────────────────────────────────────────
local function CreateRow(width)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(width, 22)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.label:SetJustifyH("LEFT")
    b:Hide()
    return b
end

-- Slot rows: a fixed pool (one per slot), stacked under the Slots header.
local slotRows = {}
for i = 0, SLOT_MAX - 1 do
    local row = CreateRow(186)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -64 - i * 24)
    row:SetScript("OnClick", function(self)
        selectedSlot = self.slotIndex
        NS.RE_RenderRunes()
    end)
    slotRows[i] = row
end

-- Rune rows: grown on demand, stacked under the Runes header.
local runeRows = {}
local function RuneRow(idx)
    if runeRows[idx] then return runeRows[idx] end
    local row = CreateRow(228)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 218, -64 - (idx - 1) * 24)
    row:SetScript("OnClick", function(self)
        if selectedSlot ~= nil and self.runeId then
            NS.RE_Engrave(selectedSlot, self.runeId)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.runeName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.runeName)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    runeRows[idx] = row
    return row
end

local removeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
removeBtn:SetSize(120, 22)
removeBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 40)
removeBtn:SetText("Remove rune")
removeBtn:SetScript("OnClick", function()
    if selectedSlot ~= nil then NS.RE_Remove(selectedSlot) end
end)
removeBtn:Hide()

-- ── Render ──────────────────────────────────────────────────────────────────

-- Returns the engraved rune's name+icon for a slot (it's always among the slot's
-- engravable runes), or nil if the slot is empty.
local function CurrentRune(slot)
    if not slot or slot.current == 0 then return nil end
    for _, r in ipairs(slot.runes) do
        if r.id == slot.current then return r end
    end
    return nil
end

local function RenderSlots()
    local model = NS.model
    for i = 0, SLOT_MAX - 1 do
        local row  = slotRows[i]
        local slot = model and model.slots[i]
        if not slot then
            row:Hide()
        else
            local locked = model.level < slot.minLevel
            local cur    = CurrentRune(slot)
            if cur then
                row.icon:SetTexture(ICON_PATH .. cur.icon)
            else
                row.icon:SetTexture(nil)
            end
            local text = slot.name
            if locked then
                text = "|cff808080" .. slot.name .. " (unlocks at " .. slot.minLevel .. ")|r"
            elseif cur then
                text = slot.name .. "  |cff00ff00[" .. cur.name .. "]|r"
            end
            row.label:SetText(text)
            row.slotIndex = i
            row:Show()
        end
    end
end

NS.RE_RenderRunes = function()
    for _, row in ipairs(runeRows) do row:Hide() end
    removeBtn:Hide()

    local model = NS.model
    local slot  = model and selectedSlot ~= nil and model.slots[selectedSlot] or nil
    if not slot then return end

    if model.level < slot.minLevel then
        local row = RuneRow(1)
        row.icon:SetTexture(nil)
        row.label:SetText("|cff808080This slot unlocks at level " .. slot.minLevel .. ".|r")
        row.runeId, row.runeName = nil, nil
        row:Show()
        return
    end

    for idx, r in ipairs(slot.runes) do
        local row = RuneRow(idx)
        row.icon:SetTexture(ICON_PATH .. r.icon)
        local text = r.name
        if r.id == slot.current then text = text .. "  |cff00ff00(engraved)|r" end
        row.label:SetText(text)
        row.runeId, row.runeName = r.id, r.name
        row:Show()
    end

    if slot.current ~= 0 then removeBtn:Show() end
end

-- Called by Comms.lua after each server state push (BEGIN…END).
NS.RE_OnStateUpdated = function()
    if not panel:IsShown() then return end
    RenderSlots()
    NS.RE_RenderRunes()
    local status = NS.statusMessage or ""
    if NS.model and not NS.model.prereq then
        status = "|cffff8080You must learn Engraving to engrave runes.|r"
    end
    statusFS:SetText(status)
end

--- Shows/hides the panel; requests fresh state on show.
NS.RE_TogglePanel = function()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        NS.RE_RequestState()
        NS.RE_OnStateUpdated()
    end
end

NS.panel = panel
