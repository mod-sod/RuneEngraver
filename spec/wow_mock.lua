-- ============================================================
-- spec/wow_mock.lua  —  Minimal WoW 3.3.5a API mock for the protocol specs.
--
-- Just enough for Comms.lua to LOAD under a standalone Lua interpreter and for
-- its pure parse/send helpers to run. Frame rendering (Panel.lua) is out of
-- scope — verified in-game. `Mock` is the test-facing control surface.
-- ============================================================

_G.RuneEngraverNS = _G.RuneEngraverNS or {}
local NS = _G.RuneEngraverNS

_G.Mock = { addon = {} }   -- recorded SendAddonMessage → { prefix, text, channel, target }
function Mock.reset() Mock.addon = {} end

_G.UnitName = function() return "TestPlayer" end
_G.SendAddonMessage = function(prefix, text, channel, target)
    Mock.addon[#Mock.addon + 1] = { prefix = prefix, text = text, channel = channel, target = target }
end

-- Chainable frame stub: every method is a no-op returning the frame, so load-time
-- frame setup (CreateFrame + RegisterEvent + SetScript) survives `dofile`.
local function makeFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() return f end end })
    return f
end
_G.CreateFrame = function() return makeFrame() end
_G.UIParent    = makeFrame()

-- Pure splitters normally provided by RuneEngraver.lua (not loaded in specs, as
-- it touches CharacterFrame). Kept identical so the parser tests are faithful.
NS.RE_SplitOnce = function(str, sep)
    local i = string.find(str, sep, 1, true)
    if i then return string.sub(str, 1, i - 1), string.sub(str, i + 1) end
    return str, ""
end
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
