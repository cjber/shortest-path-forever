-- The current cast gets a visible prompt; walking, pauses and cancellation clear it.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, prompt = driver.ns, nil
local create = driver.env.CreateFrame
local label, icon, itemName = nil, nil, "Hearthstone"
driver.env.CreateFrame = function(...)
	prompt = create(...)
	function prompt:CreateFontString()
		return setmetatable({
			SetText = function(_, text)
				label = text
			end,
		}, getmetatable(self))
	end
	return prompt
end
driver.env.C_Item = {
	GetItemNameByID = function()
		return itemName
	end,
	GetItemIconByID = function()
		return 134414
	end,
}
driver.env.C_Spell = {
	GetSpellName = function()
		return "Teleport: Stormwind"
	end,
	GetSpellTexture = function()
		return 135763
	end,
}
ns.Art = {
	Icon = function(_, file)
		icon = file
	end,
}
driver.load("UI/Arrow.lua")
local hearth = { teleport = { item = 6948, spell = 8690 } }
ns.JourneyGuide.Start()
ns.JourneyGuide.Cast(hearth)
assert(
	prompt and not prompt.hidden and label == "Use Hearthstone" and icon == 134414,
	"current hearth action has its own prompt"
)
local castFrame = prompt
ns.JourneyGuide.Pause()
assert(castFrame.hidden, "pausing clears the cast prompt")
ns.JourneyGuide.Retarget()
ns.JourneyGuide.Cast({ teleport = { spell = 3561 } })
assert(
	not prompt.hidden and label == "Cast Teleport: Stormwind" and icon == 135763,
	"class teleport uses the spell's name and icon"
)
ns.JourneyGuide.To({ map = 1, x = 200, y = 0 }, nil, nil)
assert(castFrame.hidden, "walking clears the cast prompt")
ns.JourneyGuide.Cast(hearth)
itemName = "Hearthstone (cached)"
castFrame:OnEvent("GET_ITEM_INFO_RECEIVED")
assert(label == "Use Hearthstone (cached)", "cached item names refresh without polling")
ns.JourneyGuide.Retarget()
assert(castFrame.hidden, "retargeting clears the old action")
ns.JourneyGuide.Cast(hearth)
ns.JourneyGuide.Stop()
assert(castFrame.hidden and ns.GuideTargets() == nil, "cancellation leaves no cast prompt or walking guidance")
local queued = castFrame.OnEvent
queued(castFrame, "SPELLS_CHANGED")
assert(castFrame.hidden, "queued cache events cannot revive stopped prompts")
ns.JourneyGuide.Start()
ns.RefreshCompass = function()
	ns.RefreshCompass = nil
	ns.JourneyGuide.Stop()
end
ns.JourneyGuide.Cast(hearth)
assert(
	castFrame.hidden and not ns.JourneyGuide.Active(),
	"cancellation during compass refresh wins over the cast prompt"
)
print("cast_prompt_spec: 9 checks passed")
