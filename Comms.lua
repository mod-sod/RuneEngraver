-- ============================================================
-- Comms.lua  —  the `RUNE` addon-message protocol (client side).
--
-- Mirrors CleanBot's Bridge transport: addon messages, `~`-separated bodies,
-- a BEGIN…END sequence so each line stays well under the 254-char cap. Transport
-- is a self-whisper; the server (mod-rune-engraving) receives it via
-- OnPlayerBeforeSendChatMessage and replies with addon whispers we render here.
--
-- The parse is kept pure (NS.RE_NewState / NS.RE_HandleLine) so spec/ can test it
-- without a live client. See docs/protocol.md for the full message grammar.
-- ============================================================

local NS = RuneEngraverNS

local PREFIX = "RUNE"

-- ── Outbound ────────────────────────────────────────────────────────────────

--- Sends one protocol body to the server (self-whisper addon message).
---@param body string
NS.RE_Send = function(body)
    if NS.RE_Debug then NS.RE_Print("send -> " .. body) end
    SendAddonMessage(PREFIX, body, "WHISPER", UnitName("player"))
end

--- Asks the server for the full panel state.
NS.RE_RequestState = function() NS.RE_Send("REQ") end

--- Requests engraving `runeId` into `slot`.
---@param slot   number
---@param runeId number
NS.RE_Engrave = function(slot, runeId)
    NS.RE_Send("ENG~" .. slot .. "~" .. runeId)
end

--- Requests clearing `slot`.
---@param slot number
NS.RE_Remove = function(slot)
    NS.RE_Send("DEL~" .. slot)
end

-- ── Inbound parse (pure) ────────────────────────────────────────────────────

--- A fresh accumulator for one BEGIN…END push.
---@return table
NS.RE_NewState = function()
    return { model = nil, complete = false, message = nil }
end

--- Folds one protocol body line into `state`. Returns the line kind so the caller
--- can react to END. Lines outside a BEGIN…END block (no model yet) are ignored.
---@param state table
---@param body  string
---@return string kind
NS.RE_HandleLine = function(state, body)
    local kind, rest = NS.RE_SplitOnce(body, "~")

    if kind == "BEGIN" then
        local prereq, level = NS.RE_SplitOnce(rest, "~")
        state.model    = { prereq = (prereq == "1"), level = tonumber(level) or 0, slots = {} }
        state.complete = false
        state.message  = nil

    elseif kind == "SLOT" and state.model then
        -- slot ~ name ~ minLevel ~ current  (slot names carry no "~")
        local f   = NS.RE_Split(rest, "~")
        local idx = tonumber(f[1])
        if idx then
            state.model.slots[idx] = {
                index    = idx,
                name     = f[2] or "",
                minLevel = tonumber(f[3]) or 0,
                current  = tonumber(f[4]) or 0,
                runes    = {},
            }
        end

    elseif kind == "RUNE" and state.model then
        -- slot ~ runeId ~ icon ~ locked ~ spellId ~ name
        -- (name last, so it may contain "~")
        local slotStr,   r1 = NS.RE_SplitOnce(rest, "~")
        local idStr,     r2 = NS.RE_SplitOnce(r1, "~")
        local icon,      r3 = NS.RE_SplitOnce(r2, "~")
        local lockedStr, r4 = NS.RE_SplitOnce(r3, "~")
        local spellStr,  name = NS.RE_SplitOnce(r4, "~")
        local idx  = tonumber(slotStr)
        local slot = idx and state.model.slots[idx]
        if slot then
            slot.runes[#slot.runes + 1] = {
                id      = tonumber(idStr) or 0,
                icon    = icon ~= "" and icon or "inv_misc_questionmark",
                locked  = lockedStr == "1",
                spellId = tonumber(spellStr) or 0,
                name    = name or "",
            }
        end

    elseif kind == "MSG" then
        state.message = rest

    elseif kind == "END" then
        state.complete = true
    end

    return kind
end

-- ── Event wiring ────────────────────────────────────────────────────────────

local incoming = NS.RE_NewState()

local frame = CreateFrame("Frame", "RuneEngraverCommsFrame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, message)
    if prefix ~= PREFIX then return end

    local kind = NS.RE_HandleLine(incoming, message)
    if kind == "END" then
        NS.model         = incoming.model
        NS.statusMessage = incoming.message
        if NS.RE_OnStateUpdated then NS.RE_OnStateUpdated() end
        incoming = NS.RE_NewState()
    end
end)
