-- spec/comms_spec.lua — the RUNE protocol parser + outbound senders.
dofile("Comms.lua")

local NS = RuneEngraverNS

describe("RUNE protocol parse", function()
    it("builds a model from a BEGIN…END push", function()
        local s = NS.RE_NewState()
        NS.RE_HandleLine(s, "BEGIN~1~42")
        NS.RE_HandleLine(s, "SLOT~4~Chest~25~7000001")
        NS.RE_HandleLine(s, "RUNE~4~7000001~spell_arcane_studentofmagic~0~401417~Regeneration")
        NS.RE_HandleLine(s, "RUNE~4~7000002~spell_arcane_arcane03~1~412510~Mass Regeneration")
        local kind = NS.RE_HandleLine(s, "END")

        assert.equals("END", kind)
        assert.is_true(s.complete)
        assert.is_true(s.model.prereq)
        assert.equals(42, s.model.level)

        local slot = s.model.slots[4]
        assert.is_not_nil(slot)
        assert.equals("Chest", slot.name)
        assert.equals(25, slot.minLevel)
        assert.equals(7000001, slot.current)
        assert.equals(2, #slot.runes)
        assert.equals("Regeneration", slot.runes[1].name)
        assert.is_false(slot.runes[1].locked)
        assert.equals(401417, slot.runes[1].spellId)
        assert.equals(7000002, slot.runes[2].id)
        assert.equals("spell_arcane_arcane03", slot.runes[2].icon)
        assert.equals(412510, slot.runes[2].spellId)
        assert.is_true(slot.runes[2].locked) -- gated rune not yet discovered
    end)

    it("captures a MSG status and defaults a missing icon", function()
        local s = NS.RE_NewState()
        NS.RE_HandleLine(s, "BEGIN~0~10")
        NS.RE_HandleLine(s, "SLOT~8~Legs~1~0")
        NS.RE_HandleLine(s, "RUNE~8~7000003~~0~0~Some Rune")
        NS.RE_HandleLine(s, "MSG~You must learn Engraving first.")
        NS.RE_HandleLine(s, "END")

        assert.is_false(s.model.prereq)
        assert.equals("You must learn Engraving first.", s.message)
        local rune = s.model.slots[8].runes[1]
        assert.equals("inv_misc_questionmark", rune.icon) -- empty icon fell back
        assert.equals("Some Rune", rune.name)
    end)

    it("preserves a rune name that contains the separator", function()
        local s = NS.RE_NewState()
        NS.RE_HandleLine(s, "BEGIN~1~60")
        NS.RE_HandleLine(s, "SLOT~0~Head~41~0")
        NS.RE_HandleLine(s, "RUNE~0~123~some_icon~1~55883~Odd~Name")
        assert.equals("Odd~Name", s.model.slots[0].runes[1].name)
        assert.is_true(s.model.slots[0].runes[1].locked) -- locked flag parsed, name intact
    end)

    it("ignores lines outside a BEGIN…END block", function()
        local s = NS.RE_NewState()
        NS.RE_HandleLine(s, "SLOT~4~Chest~25~0")
        assert.is_nil(s.model)
    end)
end)

describe("RUNE protocol senders", function()
    it("REQ / ENG / DEL route through self-whisper addon messages", function()
        Mock.reset()
        NS.RE_RequestState()
        NS.RE_Engrave(4, 7000001)
        NS.RE_Remove(8)

        assert.equals(3, #Mock.addon)
        assert.equals("RUNE", Mock.addon[1].prefix)
        assert.equals("WHISPER", Mock.addon[1].channel)
        assert.equals("TestPlayer", Mock.addon[1].target)
        assert.equals("REQ", Mock.addon[1].text)
        assert.equals("ENG~4~7000001", Mock.addon[2].text)
        assert.equals("DEL~8", Mock.addon[3].text)
    end)
end)
