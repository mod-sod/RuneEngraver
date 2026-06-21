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
local ICON_SIZE  = 39          -- $parentIconTexture size in LargeItemButtonTemplate
local ROW_HEIGHT = ICON_SIZE + 3   -- a rune row holds one quest-reward-style icon
local HEADER_HEIGHT = math.floor(ROW_HEIGHT / 2)  -- slot headers are half as tall
local MAX_ROWS   = 30          -- pool cap; only as many as fit are shown
local PAD        = 12

-- The parchment name-plate that the stock quest-reward widget
-- (LargeItemButtonTemplate) sits beside its icon. We stretch it to the row width.
local NAMEPLATE_TEX = "Interface\\QuestFrame\\UI-QuestItemNameFrame"

-- The Character Sheet's frame is taller than its visible (non-transparent) art,
-- so matching its raw height overshoots. Trim the top and bottom independently
-- to line the panel up with the sheet's visible edges.
local FRAME_INSET_TOP    = 10
local FRAME_INSET_BOTTOM = 74

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
panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -37, -FRAME_INSET_TOP)
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
panel:Hide()

-- ── Search bar ───────────────────────────────────────────────────────────────
local search = CreateFrame("EditBox", "RuneEngraverSearch", panel, "InputBoxTemplate")
search:SetAutoFocus(false)
search:SetHeight(20)
search:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, -14)
search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD - 2, -14)

-- Magnifier icon (SoD's search box uses this), inset the text past it.
local searchIcon = search:CreateTexture(nil, "OVERLAY")
searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
searchIcon:SetSize(14, 14)
searchIcon:SetPoint("LEFT", search, "LEFT", 2, -1)
search:SetTextInsets(18, 0, 0, 0)

local searchHint = search:CreateFontString(nil, "ARTWORK", "GameFontDisable")
searchHint:SetPoint("LEFT", search, "LEFT", 18, 0)
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

-- ── Rune list ────────────────────────────────────────────────────────────────
-- A nested, inset section with its own dark-brown parchment background, distinct
-- from the outer frame. The scroll frame and its rows live inside it.
local list = CreateFrame("Frame", "RuneEngraverList", panel)
list:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -38)
list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 44)
-- Border only; the parchment is a single stretched fill below.
list:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})

-- Parchment fill: one stretched piece of the spellbook page background. All the
-- knobs are here so you can move/stretch and pan/zoom it freely:
--   PARCHMENT_TEX    — source texture (the spellbook panel quadrants)
--   PARCHMENT_COLOR  — {r,g,b} tint (1,1,1 = natural)
--   PARCHMENT_EDGE   — px offsets from each list edge; the texture is anchored
--                      TOPLEFT (+left,+top) and BOTTOMRIGHT (+right,+bottom).
--                      Positive grows the quad up/right, negative down/left — so
--                      these both move and stretch it.
--   PARCHMENT_CROP   — sub-rectangle of the texture shown, 0..1 (pan/zoom).
local PARCHMENT_TEX   = "Interface\\Spellbook\\UI-SpellbookPanel-TopLeft"
local PARCHMENT_COLOR = { 0.65, 0.46, 0.28 }   -- dark brown
local PARCHMENT_EDGE  = { left = 0, top = 0, right = 0, bottom = 0 }
local PARCHMENT_CROP  = { left = 0.1, right = 1, top = 0.31, bottom = 1 }

local parchment = list:CreateTexture(nil, "BACKGROUND")
parchment:SetTexture(PARCHMENT_TEX)
parchment:SetVertexColor(PARCHMENT_COLOR[1], PARCHMENT_COLOR[2], PARCHMENT_COLOR[3])
parchment:SetTexCoord(PARCHMENT_CROP.left, PARCHMENT_CROP.right,
                      PARCHMENT_CROP.top, PARCHMENT_CROP.bottom)
parchment:SetPoint("TOPLEFT", list, "TOPLEFT", PARCHMENT_EDGE.left, PARCHMENT_EDGE.top)
parchment:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", PARCHMENT_EDGE.right, PARCHMENT_EDGE.bottom)

local scroll = CreateFrame("ScrollFrame", "RuneEngraverScroll", list, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -26, 8)
scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RenderList)
end)

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

-- Stock 3.3.5a textures (confirmed against the Interface 30300 source):
--   header bar  — the grey-stone channel-button background (FriendsFrame channels)
--   highlight   — the yellow quest-log title highlight
local HEADER_TEX  = "Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg"
local HILIGHT_TEX = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    -- Position (y offset) and height are set per-render in RenderList so headers
    -- and rune rows can stack at their own heights.
    -- Sit a few levels above the list so rows render over the parchment and
    -- keep receiving clicks.
    row:SetFrameLevel(list:GetFrameLevel() + 5)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Hover highlight on the special HIGHLIGHT layer (3.3.5a auto-shows it on
    -- mouseover); a dimmer always-on copy marks the engraved rune.
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetTexture(HILIGHT_TEX)
    row.hl:SetBlendMode("ADD")
    row.hl:SetAllPoints(row)

    row.sel = row:CreateTexture(nil, "ARTWORK")
    row.sel:SetTexture(HILIGHT_TEX)
    row.sel:SetBlendMode("ADD")
    row.sel:SetAllPoints(row)
    row.sel:SetAlpha(0.4)
    row.sel:Hide()

    -- Header background (channel-button texture, header rows only).
    row.hdr = row:CreateTexture(nil, "BORDER")
    row.hdr:SetTexture(HEADER_TEX)
    row.hdr:SetTexCoord(0, 0.53125, 0, 0.625)
    row.hdr:SetAllPoints(row)

    -- Collapse +/- as a text glyph (no button background), header rows only.
    row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.toggle:SetPoint("LEFT", row, "LEFT", 6, 0)

    -- Rune-row visuals mirror the stock quest-reward widget
    -- (LargeItemButtonTemplate): a bare icon with a parchment name-plate beside
    -- it. No metallic/quality border — runes carry no item rarity.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

    -- Name-plate: the UI-QuestItemNameFrame art, stretched from the icon to the
    -- scroll's right edge. The 128x64 texture has ~11px fully-transparent margins
    -- on every side (visible parchment spans x 11..116, y 11..52), so we crop the
    -- left/right padding with SetTexCoord — otherwise the margins scale with the
    -- quad and the parchment never reaches the edges. Native 64px height keeps the
    -- vertical body un-squished (its transparent top/bottom overhang the row).
    row.plate = row:CreateTexture(nil, "BACKGROUND")
    row.plate:SetTexture(NAMEPLATE_TEX)
    row.plate:SetTexCoord(11 / 128, 117 / 128, 0, 1)
    row.plate:SetHeight(64)
    row.plate:SetPoint("LEFT", row.icon, "RIGHT", -2, 0)
    row.plate:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    -- Name sits inside the plate (template anchors it LEFT at +15); RIGHT kept in
    -- the plate so long names stay on the parchment.
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.plate, "LEFT", 15, 0)
    row.label:SetPoint("RIGHT", row.plate, "RIGHT", -10, 0)
    row.label:SetJustifyH("LEFT")

    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", function(self)
        if self.kind ~= "rune" or not self.runeName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The rune teaches a spell the client already knows (our DBC patch injects
        -- it), so show that spell's full tooltip — like the quest-reward widget
        -- shows a spell reward. Fall back to the bare name if the link is empty.
        if self.spellId and self.spellId > 0 then
            GameTooltip:SetHyperlink("spell:" .. self.spellId)
        else
            GameTooltip:SetText(self.runeName)
        end
        if self.locked then GameTooltip:AddLine("Undiscovered", 1, 0.4, 0.4) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ElvUI: flatten the parchment/stone row art (no-op without ElvUI).
    if NS.RE_SkinRow then NS.RE_SkinRow(row) end

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
        row.hdr:Show()
        row.sel:Hide()
        row.icon:Hide()
        row.plate:Hide()
        row.toggle:Show()
        row.toggle:SetText(collapsed[entry.index] and "+" or " -")
        row.label:ClearAllPoints()
        row.label:SetPoint("CENTER", row, "CENTER", 0, 0)
        row.label:SetJustifyH("CENTER")
        local level = NS.model and NS.model.level or 0
        local text  = slot.name
        if slot.minLevel > level then
            text = text .. "  |cff808080(unlocks at " .. slot.minLevel .. ")|r"
        end
        row.label:SetText(text)
        row.label:SetTextColor(1, 0.82, 0)  -- gold, like the default slot headers
        row.runeId, row.runeName, row.spellId = nil, nil, nil
        row.locked, row.isCurrent = false, false
    else
        local slot, r = entry.slot, entry.rune
        row.hdr:Hide()
        row.toggle:Hide()
        row.icon:Show()
        row.plate:Show()
        row.icon:SetTexture(ICON_PATH .. r.icon)
        row.icon:SetDesaturated(r.locked)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.plate, "LEFT", 15, 0)
        row.label:SetPoint("RIGHT", row.plate, "RIGHT", -10, 0)
        row.label:SetJustifyH("LEFT")
        local isCurrent = r.id == slot.current and slot.current ~= 0
        if isCurrent then row.sel:Show() else row.sel:Hide() end
        local text = r.name
        if r.locked then
            text = "|cff808080" .. r.name .. "|r"
        elseif isCurrent then
            text = r.name .. "  |cff00ff00(engraved)|r"
        end
        row.label:SetText(text)
        row.label:SetTextColor(1, 1, 1)
        row.runeId, row.runeName, row.spellId = r.id, r.name, r.spellId
        row.locked, row.isCurrent = r.locked, isCurrent
    end
end

RenderList = function()
    if not panel:IsShown() then return end
    local display = BuildDisplay()
    local scrollH = scroll:GetHeight()

    -- The scrollbar still steps in whole ROW_HEIGHT units (one display entry per
    -- step); offset is the entry index to start at. numRows is the worst case
    -- (all full-height rune rows) so the bar always lets us reach the last entry.
    local numRows = math.floor(scrollH / ROW_HEIGHT)
    if numRows < 1 then numRows = 1 end
    if numRows > MAX_ROWS then numRows = MAX_ROWS end

    FauxScrollFrame_Update(scroll, #display, numRows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scroll)

    -- Stack the visible entries top-down, each at its own height (headers are
    -- half as tall as rune rows), until the next one wouldn't fit.
    local y, used = 0, 0
    for di = offset + 1, #display do
        local entry = display[di]
        local h = entry.kind == "header" and HEADER_HEIGHT or ROW_HEIGHT
        if used >= MAX_ROWS then break end
        if used > 0 and y + h > scrollH then break end
        used = used + 1
        local row = GetRow(used)
        RenderRow(row, entry)
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -y)
        row:Show()
        y = y + h
    end
    for i = used + 1, MAX_ROWS do
        if rows[i] then rows[i]:Hide() end
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
-- A small slot-corner badge per engravable equipment slot: a mini "rune slot"
-- whose background matches the active skin's equipment slots (ElvUI's flat
-- template, else a Blizzard-style recessed slot). The rune icon shows only when a
-- rune is engraved; an empty engravable slot shows just the background.
local badges     = {}
local BADGE_SIZE = 14

-- Builds the badge frame on an equipment slot button, styled to the active skin.
local function CreateBadge(btn)
    local f = CreateFrame("Frame", nil, btn)
    f:SetSize(BADGE_SIZE, BADGE_SIZE)
    f:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    f:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)

    local icon = f:CreateTexture(nil, "OVERLAY")
    f.icon = icon

    if NS.ElvUI_S then
        -- Exactly how ElvUI skins the equipment slots themselves.
        f:SetTemplate("Default")
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(unpack((NS.ElvUI_E and NS.ElvUI_E.TexCoords) or { 0.08, 0.92, 0.08, 0.92 }))
    else
        -- Blizzard: a dark recessed mini-slot (stone border + dark fill).
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.85)
        f:SetBackdropBorderColor(0.45, 0.4, 0.3, 1)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    return f
end

local function UpdateBadges()
    local model = NS.model
    for i, btnName in pairs(SLOT_BUTTON) do
        local badge = badges[i]
        if not badge then
            local btn = _G[btnName]
            if btn then
                badge = CreateBadge(btn)
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
                    badge.icon:SetTexture(ICON_PATH .. cur.icon)
                    badge.icon:Show()
                else
                    badge.icon:Hide()  -- empty: keep the slot background, no icon
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
    -- Match the Character Sheet's height at runtime, trimmed to its visible art.
    self:SetHeight(CharacterFrame:GetHeight() - FRAME_INSET_TOP - FRAME_INSET_BOTTOM)
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
