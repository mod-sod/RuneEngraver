-- ============================================================
-- RuneEngraver.lua  —  core: namespace, shared utilities, the
--                      Character Sheet toggle button, and login init.
--
-- The addon-message protocol lives in Comms.lua and the panel UI in
-- Panel.lua. This addon is the client front-end for the server-side
-- mod-rune-engraving engine; they couple only through the `RUNE`
-- addon-message protocol (see docs/protocol.md). Scaffolded from CleanBot.
-- ============================================================

RuneEngraverNS = {}
local NS = RuneEngraverNS

-- ============================================================
-- Shared utilities
-- ============================================================

-- Chat output with the standard RuneEngraver tag.
---@param msg string  Message to print to the default chat frame.
NS.RE_Print = function(msg)
    print("|cff66ccffRuneEngraver|r: " .. tostring(msg))
end

-- One-shot timer: run fn() once, `delay` seconds from now. Backed by a single
-- shared ticker so repeated calls don't each leak a throwaway frame.
local timerFrame = CreateFrame("Frame")
local timers     = {}
timerFrame:SetScript("OnUpdate", function(_, dt)
    local due
    for t in pairs(timers) do
        t.elapsed = t.elapsed + dt
        if t.elapsed >= t.delay then
            due = due or {}
            due[#due + 1] = t
        end
    end
    if due then
        for _, t in ipairs(due) do
            timers[t] = nil
            t.fn()
        end
    end
end)

--- Runs `fn` once after `delay` seconds via the shared one-shot timer.
---@param delay number
---@param fn    fun()
NS.RE_After = function(delay, fn)
    timers[{ elapsed = 0, delay = delay, fn = fn }] = true
end

--- Splits `str` on the first literal `sep`, returning (before, after-or-"").
---@param str string
---@param sep string
---@return string, string
NS.RE_SplitOnce = function(str, sep)
    local i = string.find(str, sep, 1, true)
    if i then return string.sub(str, 1, i - 1), string.sub(str, i + 1) end
    return str, ""
end

--- Splits `str` into an array on every literal `sep`.
---@param str string
---@param sep string
---@return string[]
NS.RE_Split = function(str, sep)
    local out, start = {}, 1
    while true do
        local i = string.find(str, sep, start, true)
        if not i then
            out[#out + 1] = string.sub(str, start)
            return out
        end
        out[#out + 1] = string.sub(str, start, i - 1)
        start = i + 1
    end
end

-- ============================================================
-- Character Sheet toggle button
-- ============================================================
-- A small button on the character sheet (top-right, just left of the close
-- button) that toggles the rune panel. MEDIUM strata so it captures clicks.
do
    local btn = CreateFrame("Button", "RuneEngraverToggleButton", CharacterFrame)
    btn:SetSize(26, 26)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 4)
    btn:SetPoint("RIGHT", CharacterFrameCloseButton, "LEFT", 4, 0)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_StudentOfMagic")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the default icon border

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnClick", function()
        if NS.RE_TogglePanel then NS.RE_TogglePanel() end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Rune Engraver")
        GameTooltip:AddLine("Engrave runes you've unlocked.", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NS.toggleButton = btn
end

-- ============================================================
-- Slash command fallback
-- ============================================================
SLASH_RUNEENGRAVER1 = "/rune"
SLASH_RUNEENGRAVER2 = "/runeengraver"
SlashCmdList["RUNEENGRAVER"] = function()
    if NS.RE_TogglePanel then NS.RE_TogglePanel() end
end

-- ============================================================
-- Login init
-- ============================================================
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    RuneEngraver_SavedVars = RuneEngraver_SavedVars or {}
    -- Prime the model so the panel has data the first time it opens.
    if NS.RE_RequestState then NS.RE_RequestState() end
end)
