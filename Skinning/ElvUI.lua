-- ============================================================
-- Skinning\ElvUI.lua  —  optional ElvUI skin for the rune panel.
--
-- When ElvUI is installed, the panel chrome (outer frame, inset
-- rune list, search box, scroll bar) is restyled to ElvUI's flat
-- dark templates so it sits natively beside an ElvUI'd Character
-- Sheet. Without ElvUI every function no-ops and the stock SoD
-- parchment look built in Panel.lua is left untouched.
--
-- Pattern mirrored from CleanBot's Skinning\ElvUI.lua, scaled down
-- to RuneEngraver's single panel. The skin reaches the panel's parts
-- by their global names (RuneEngraverList / RuneEngraverSearch /
-- RuneEngraverScrollScrollBar), so Panel.lua needs no changes.
-- ============================================================

local NS = RuneEngraverNS

-- ElvUI handles, populated by RE_InitElvUI at login (when ElvUI is loaded).
NS.ElvUI_E = nil
NS.ElvUI_S = nil

--- Detects ElvUI and grabs its Skins module. Call once at PLAYER_LOGIN, when
--- ElvUI is guaranteed loaded.
NS.RE_InitElvUI = function()
    if IsAddOnLoaded("ElvUI") then
        NS.ElvUI_E = unpack(ElvUI)
        if NS.ElvUI_E then NS.ElvUI_S = NS.ElvUI_E:GetModule("Skins") end
    end
end

-- Skins the search EditBox by calling SetBackdrop on the box itself rather than
-- ElvUI's HandleEditBox. HandleEditBox builds a separate `.backdrop` child frame
-- that renders behind a DIALOG-strata docked panel, leaving the box blank (the
-- same reason CleanBot ships its own CB_SkinEditBoxSafe). We hide only the named
-- InputBoxTemplate border art (Left/Middle/Right) so the magnifier icon and the
-- "Search" hint FontString — both added in Panel.lua — survive.
---@param box table  The RuneEngraverSearch EditBox.
local function SkinSearchBox(box)
    for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
        local art = _G["RuneEngraverSearch" .. suffix]
        if art then art:Hide() end
    end
    local E   = NS.ElvUI_E
    local tex = (E and E.media and E.media.blank) or "Interface\\ChatFrame\\ChatFrameBackground"
    local bc  = (E and E.db and E.db.general and E.db.general.bordercolor) or {}
    box:SetBackdrop({
        bgFile = tex, edgeFile = tex, tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0.06, 0.06, 0.06, 1)
    box:SetBackdropBorderColor(bc.r or 0.3, bc.g or 0.3, bc.b or 0.3, 1)
end

--- Applies the ElvUI chrome skin to the rune panel. No-op without ElvUI, and
--- idempotent. Call after RE_InitElvUI (i.e. at PLAYER_LOGIN).
NS.RE_ApplyPanelSkin = function()
    if not NS.ElvUI_S then return end
    local panel = NS.panel
    if not panel or panel.reSkinned then return end
    panel.reSkinned = true

    -- Outer window: replace the tooltip backdrop with a flat ElvUI panel.
    panel:StripTextures()
    panel:SetTemplate("Default")

    -- Inset list: StripTextures drops the parchment fill (it is the list's only
    -- texture region); the transparent template recesses it like an input area.
    local list = _G.RuneEngraverList
    if list then
        list:StripTextures()
        list:SetTemplate("Transparent")
    end

    local search = _G.RuneEngraverSearch
    if search then SkinSearchBox(search) end

    local bar = _G.RuneEngraverScrollScrollBar
    if bar then NS.ElvUI_S:HandleScrollBar(bar) end
end

-- Reskins one pooled list row to ElvUI's flat look. Called once per row from
-- Panel.lua's GetRow (after the row's textures exist). RenderRow only Show/Hides
-- these regions per render — it never re-SetTexture's them — so retargeting the
-- textures here sticks across every render. No-op without ElvUI.
--
-- The parchment name-plate and grey-stone header art are the two regions that
-- clash with an ElvUI panel; both become flat fills. The hover/selected glows are
-- ADD-blended, so they read fine on a dark backdrop — only retinted for cohesion.
---@param row table  A pooled row Button from GetRow.
NS.RE_SkinRow = function(row)
    if not NS.ElvUI_S then return end
    local E     = NS.ElvUI_E
    local blank = (E and E.media and E.media.blank) or "Interface\\Buttons\\WHITE8X8"

    -- Header bar: flat band, a touch lighter than the list so it reads as a header
    -- (the gold label + collapse glyph carry the rest).
    if row.hdr then
        row.hdr:SetTexture(blank)
        row.hdr:SetTexCoord(0, 1, 0, 1)
        row.hdr:SetVertexColor(0.22, 0.22, 0.22, 1)
    end

    -- Rune-row name-plate: drop the parchment; the white label reads on the
    -- transparent list. The label stays anchored to the (now invisible) plate, so
    -- its position is unchanged.
    if row.plate then
        row.plate:SetTexture(nil)
    end

    -- Mouseover highlight: neutral white ADD glow instead of the warm quest tint.
    if row.hl then
        row.hl:SetTexture(blank)
        row.hl:SetVertexColor(1, 1, 1, 0.10)
    end

    -- Engraved marker: soft green ADD, reinforcing the green "(engraved)" label.
    if row.sel then
        row.sel:SetTexture(blank)
        row.sel:SetVertexColor(0.2, 0.9, 0.2)
    end
end
