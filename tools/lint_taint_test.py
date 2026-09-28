"""Regression cases for the Blizzard-taint lint: what it must flag, what stays clean, and the escape comment."""

import unittest

from tools.lint_taint import check


class TaintTest(unittest.TestCase):
    def test_flagged(self):
        cases = {
            "ObjectiveTrackerManager:SetModuleContainer(module, ObjectiveTrackerFrame)": "taint-blizzard-call",
            'hooksecurefunc(ns.frame, "SetUnit", f)': "taint-method-hook",
            'local frame = ProfessionsFrame; hooksecurefunc(frame, "RefreshRightTabs", f)': "taint-method-hook",
            'hooksecurefunc(ProfessionsFrame, \n"RightTabSelected", f)': "taint-method-hook",
            'hooksecurefunc(GameTooltip, "SetUnit", f)': "taint-method-hook",
            'local function F(frame) hooksecurefunc(frame, "UpdateAnchors", f) end': "taint-method-hook",
            'hooksecurefunc(ContainerFrameItemButtonMixin, "OnLoad", f)': "taint-method-hook",
            "bag:UpdateFrameSize()": "taint-blizzard-call",
            "for _, b in bag:EnumerateValidItems() do end": "taint-blizzard-call",
            "UpdateContainerFrameAnchors()": "taint-blizzard-call",
            "local n = frame:GetBagSize()": "taint-blizzard-call",
            "initializer:SetParentInitializer(parent)": "taint-blizzard-call",
            "StaticPopupDialogs.TF_CONFIRM = {}": "taint-blizzard-write",
            'StaticPopupDialogs["TF_CONFIRM"] = {}': "taint-blizzard-write",
            "WorldMapFrame.tfPins = {}": "taint-blizzard-write",
            "function UIErrorsFrame.ShouldDisplayMessageType() end": "taint-blizzard-write",
            "function GameTooltip:SetUnit() end": "taint-blizzard-write",
        }
        for source, code in cases.items():
            with self.subTest(source=source):
                findings = check(source)
                self.assertEqual(len(findings), 1, findings)
                self.assertTrue(findings[0][1].startswith(code + ":"), findings)

    def test_clean(self):
        cases = [
            'hooksecurefunc("ContainerFrame_GenerateFrame", f)',
            'hooksecurefunc(ns, "RefreshConflicts", f)',
            'local Model = {}\nhooksecurefunc(Model, "Layout", f)',
            'frame:HookScript("OnShow", f)',
            "TooltipDataProcessor.AddTooltipPostCall(kind, f)",
            "local Model = {}\nModel.lift = 0\nfunction Model.Layout() end",
            "ns.db = {}\nfunction ns.Print() end",
            "local t = {}\nt[key] = true",
            "local function F(frame) frame.x = 1 end",
            "for _, v in ipairs(list) do v.seen = true end",
            "SlashCmdList.TWEAKSFOREVER = f",
            "function TweaksForeverDungeonEntrancePinMixin:OnLoad() end",
            "local t = { name = 1, [2] = 3 }",
            "if a == b then end",
            'local s = "bag:UpdateFrameSize()"',
            "-- hooksecurefunc(GameTooltip, 'SetUnit', f)\nf()",
            "local function UpdateAnchors() end\nlocal Model = {}\nfunction Model.GetRows() end",
            "WorldMapFrame.tf = 1 -- taint-ok: our own field, read only by this addon",
            "bag:UpdateFrameSize() -- taint-ok: run from a secure delegate",
        ]
        for source in cases:
            with self.subTest(source=source):
                self.assertEqual(check(source), [])

    def test_empty_escape_still_flags(self):
        self.assertEqual(len(check("bag:UpdateFrameSize() -- taint-ok:")), 1)


if __name__ == "__main__":
    unittest.main()
