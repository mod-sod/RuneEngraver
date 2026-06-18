-- ============================================================
-- Panel.lua  —  the rune-engraving panel.
--
-- A SoD-style panel docked to the right of the Character Sheet: a search bar, a
-- scrollable list of every class/slot-legal rune grouped under collapsible
-- equipment-slot headers (locked runes greyed), and a "collected/total" footer.
-- It also badges the paper-doll equipment slots with the engraved rune's icon.
-- Renders entirely from NS.model (built by Comms.lua from the server's BEGIN…END
-- push); actions send ENG/DEL back. Stock textures only — no custom art.
-- ============================================================

local NS = RuneEngraverNS

local SLOT_MAX   = 11
local ICON_PATH  = "Interface\\Icons\\"
local PANEL_W    = 280
local ROW_HEIGHT = 22
local MAX_ROWS   = 30          -- pool cap; only as many as fit are shown
local PAD        = 12
local RUNE_ICON  = "inv_misc_rune_06"

-- model slot index → paper-doll equipment button. "Ring" is a single engraving
-- slot, so only Finger0 is badged (Finger1 is intentionally left unbadged).
local SLOT_BUTTON = {
    [0] = "CharacterHeadSlot",     [1] = "CharacterNeckSlot",
    [2] = "CharacterShoulderSlot", [3] = "CharacterBackSlot",
    [4] = "CharacterChestSlot",    [5] = "CharacterWristSlot",
    [6] = "CharacterHandsSlot",    [7] = "CharacterWaistSlot",
    [8] = "CharacterLegsSlot",     [9] = "CharacterFeetSlot",
    [10] = "CharacterFinger0Slot",
}

local collapsed    = {}   -- [slotIndex] = true when a slot's runes are folded
local searchFilter = ""   -- lowercased; "" means show everything
local rows         = {}   -- pooled list-row buttons (1-based, by screen position)

local RenderList          -- forward declaration (used by the scroll handler)

-- ── Frame shell ─────────────────────────────────────────────────────────────
local panel = CreateFrame("Frame", "RuneEngraverFrame", UIParent)
panel:SetWidth(PANEL_W)
-- Dock flush against the Character Sheet's right edge (the negative x tucks the
-- panel under the sheet's right border art); height is grabbed at runtime in
-- OnShow so it always matches the live frame (see below).
panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -33, 0)
-- DIALOG strata floats above the (MEDIUM) Character Sheet. Note: do NOT use
-- SetToplevel here — it raises the panel above its own lazily-created child rows,
-- so they'd render under the backdrop and stop taking clicks.
panel:SetFrameStrata("DIALOG")
panel:EnableMouse(true)
-- A flat dark backing with a thin border — no blocky dialog frame.
panel:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
panel:SetBackdropBorderColor(0.4, 0.3, 0.2, 1)
panel:Hide()

-- ── Search bar ───────────────────────────────────────────────────────────────
local search = CreateFrame("EditBox", "RuneEngraverSearch", panel, "InputBoxTemplate")
search:SetAutoFocus(false)
search:SetHeight(20)
search:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, -14)
search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD - 2, -14)

local searchHint = search:CreateFontString(nil, "ARTWORK", "GameFontDisable")
searchHint:SetPoint("LEFT", search, "LEFT", 2, 0)
searchHint:SetText("Search")

search:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text == "" then searchHint:Show() else searchHint:Hide() end
    searchFilter = string.lower(text)
    if panel:IsShown() then RenderList() end
end)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- ── Status + footer (bottom) ─────────────────────────────────────────────────
local statusFS = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
statusFS:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD + 4, 28)
statusFS:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD - 4, 28)
statusFS:SetJustifyH("LEFT")

local footerFS = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
footerFS:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD + 4, 14)
footerFS:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD - 4, 14)
footerFS:SetJustifyH("LEFT")

-- ── Scroll frame ─────────────────────────────────────────────────────────────
local scroll = CreateFrame("ScrollFrame", "RuneEngraverScroll", panel, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -40)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD - 22, 46)
scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RenderList)
end)

-- Dark-brown parchment behind the list (rows sit a few frame levels above it).
local listBg = scroll:CreateTexture(nil, "BACKGROUND")
listBg:SetTexture("Interface\\QuestFrame\\QuestBackground")
listBg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -2, 2)
listBg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 2, -2)
listBg:SetVertexColor(0.45, 0.3, 0.18)

-- ── Row pool ─────────────────────────────────────────────────────────────────
local function OnRowClick(self, button)
    if self.kind == "header" then
        collapsed[self.slotIndex] = not collapsed[self.slotIndex]
        RenderList()
    elseif self.kind == "rune" then
        if button == "RightButton" then
            if self.isCurrent then NS.RE_Remove(self.slotIndex) end
        elseif not self.locked then
            NS.RE_Engrave(self.slotIndex, self.runeId)
        end
    end
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    -- Sit a few levels above the panel so rows render over the backdrop and
    -- keep receiving clicks.
    row:SetFrameLevel(panel:GetFrameLevel() + 5)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.toggle = row:CreateTexture(nil, "ARTWORK")
    row.toggle:SetSize(16, 16)
    row.toggle:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)  -- indented under its header
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")

    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", function(self)
        if self.kind ~= "rune" or not self.runeName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.runeName)
        if self.locked then GameTooltip:AddLine("Undiscovered", 1, 0.4, 0.4) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = row
    return row
end

-- ── Model helpers ────────────────────────────────────────────────────────────

-- The engraved rune's entry for a slot (it's always among the slot's runes), or
-- nil if the slot is empty.
local function CurrentRune(slot)
    if not slot or slot.current == 0 then return nil end
    for _, r in ipairs(slot.runes) do
        if r.id == slot.current then return r end
    end
    return nil
end

local function MatchesFilter(rune)
    if searchFilter == "" then return true end
    return string.find(string.lower(rune.name), searchFilter, 1, true) ~= nil
end

-- Flattens the model into the visible row list: a header per slot that has any
-- matching runes, followed (unless collapsed) by its rune rows, slot order 0..10.
local function BuildDisplay()
    local out   = {}
    local model = NS.model
    if not model then return out end
    for i = 0, SLOT_MAX - 1 do
        local slot = model.slots[i]
        if slot then
            local matched = {}
            for _, r in ipairs(slot.runes) do
                if MatchesFilter(r) then matched[#matched + 1] = r end
            end
            if #matched > 0 then
                out[#out + 1] = { kind = "header", index = i, slot = slot }
                if not collapsed[i] then
                    for _, r in ipairs(matched) do
                        out[#out + 1] = { kind = "rune", index = i, slot = slot, rune = r }
                    end
                end
            end
        end
    end
    return out
end

-- ── Render ───────────────────────────────────────────────────────────────────
local function RenderRow(row, entry)
    row:SetWidth(scroll:GetWidth())
    row.kind      = entry.kind
    row.slotIndex = entry.index

    if entry.kind == "header" then
        local slot = entry.slot
        row.icon:Hide()
        row.toggle:Show()
        row.toggle:SetTexture(collapsed[entry.index]
            and "Interface\\Buttons\\UI-PlusButton-Up"
            or  "Interface\\Buttons\\UI-MinusButton-Up")
        row.label:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)
        local level = NS.model and NS.model.level or 0
        local text  = slot.name
        if slot.minLevel > level then
            text = text .. "  |cff808080(unlocks at " .. slot.minLevel .. ")|r"
        end
        row.label:SetText(text)
        row.label:SetTextColor(1, 0.82, 0)  -- gold, like the default slot headers
        row.runeId, row.runeName, row.locked, row.isCurrent = nil, nil, false, false
    else
        local slot, r = entry.slot, entry.rune
        row.toggle:Hide()
        row.icon:Show()
        row.icon:SetTexture(ICON_PATH .. r.icon)
        row.icon:SetDesaturated(r.locked)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        local isCurrent = r.id == slot.current and slot.current ~= 0
        local text = r.name
        if r.locked then
            text = "|cff808080" .. r.name .. "|r"
        elseif isCurrent then
            text = r.name .. "  |cff00ff00(engraved)|r"
        end
        row.label:SetText(text)
        row.label:SetTextColor(1, 1, 1)
        row.runeId, row.runeName  = r.id, r.name
        row.locked, row.isCurrent = r.locked, isCurrent
    end
end

RenderList = function()
    if not panel:IsShown() then return end
    local display = BuildDisplay()
    local numRows = math.floor(scroll:GetHeight() / ROW_HEIGHT)
    if numRows < 1 then numRows = 1 end
    if numRows > MAX_ROWS then numRows = MAX_ROWS end

    FauxScrollFrame_Update(scroll, #display, numRows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)

    for i = 1, MAX_ROWS do
        local entry = i <= numRows and display[i + offset] or nil
        if entry then
            local row = GetRow(i)
            RenderRow(row, entry)
            row:Show()
        elseif rows[i] then
            rows[i]:Hide()
        end
    end
end
NS.RE_RenderRunes = RenderList  -- kept under the legacy name other code calls

local function UpdateFooter()
    local model = NS.model
    local collected, total = 0, 0
    if model then
        for i = 0, SLOT_MAX - 1 do
            local slot = model.slots[i]
            if slot then
                for _, r in ipairs(slot.runes) do
                    total = total + 1
                    if not r.locked then collected = collected + 1 end
                end
            end
        end
    end
    footerFS:SetText(collected .. "/" .. total .. " Runes Collected")
end

-- ── Paper-doll badges ────────────────────────────────────────────────────────
local badges = {}
local function UpdateBadges()
    local model = NS.model
    for i, btnName in pairs(SLOT_BUTTON) do
        local badge = badges[i]
        if not badge then
            local btn = _G[btnName]
            if btn then
                badge = btn:CreateTexture(nil, "OVERLAY")
                badge:SetSize(13, 13)
                badge:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                badges[i] = badge
            end
        end
        if badge then
            local slot = model and model.slots[i]
            if not slot then
                badge:Hide()
            else
                local cur = CurrentRune(slot)
                if cur then
                    badge:SetTexture(ICON_PATH .. cur.icon)
                    badge:SetDesaturated(false)
                    badge:SetVertexColor(1, 1, 1)
                else
                    -- engravable but empty: a greyed rune marker
                    badge:SetTexture(ICON_PATH .. RUNE_ICON)
                    badge:SetDesaturated(true)
                    badge:SetVertexColor(0.6, 0.6, 0.6)
                end
                badge:Show()
            end
        end
    end
end

-- ── Public entry points ──────────────────────────────────────────────────────

-- Called by Comms.lua after each server state push (BEGIN…END).
NS.RE_OnStateUpdated = function()
    UpdateBadges()  -- always — the badges live on the sheet even when closed
    if not panel:IsShown() then return end
    RenderList()
    UpdateFooter()
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

panel:SetScript("OnShow", function(self)
    -- Match the Character Sheet's height at runtime, minus its bottom tab strip.
    local tabH = CharacterFrameTab1 and CharacterFrameTab1:GetHeight() or 0
    self:SetHeight(CharacterFrame:GetHeight() - tabH)
    RenderList()
    UpdateFooter()
end)

-- The panel is docked to the sheet: close it with the sheet, and refresh state
-- (so the paper-doll badges stay current) whenever the sheet opens.
CharacterFrame:HookScript("OnHide", function() panel:Hide() end)
CharacterFrame:HookScript("OnShow", function()
    if NS.RE_RequestState then NS.RE_RequestState() end
end)

NS.panel = panel
