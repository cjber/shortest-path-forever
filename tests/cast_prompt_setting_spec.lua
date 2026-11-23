-- "Show cast prompt" off hides only the prompt: the cast stays the guide's step and journeys plan as before (#1086).
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local frames = {}
local create = env.CreateFrame
env.CreateFrame = function(...)
	local frame = create(...)
	local font = frame.CreateFontString
	function frame:CreateFontString(...)
		local text = font(self, ...)
		text.SetText = function(fontString, value)
			fontString.text = value
		end
		return text
	end
	frames[#frames + 1] = frame
	return frame
end
ns.Art = { Icon = function() end }
env.C_Item = env.C_Item or {}
env.C_Item.GetItemNameByID = function()
	return "Hearthstone"
end
ns.Mover = { Attach = function() end, Stock = function() end }
ns.TeleportAction = function()
	return "Use Hearthstone", 134414
end
driver.load("UI/CastButton.lua")
driver.load("UI/Arrow.lua")

ns.db.castPrompt = false
local leg = { teleport = { item = 6948, spell = 8690, bind = true } }
ns.JourneyGuide.Start()
ns.JourneyGuide.Cast(leg)
local prompt = frames[#frames]
assert(not prompt or prompt.Action == nil or prompt.hidden, "with the switch off no cast prompt shows")
assert(ns.JourneyGuide.Casting(), "the Hearthstone stays the journey's current step")
assert(select(2, ns.JourneyGuidance()) == "cast", "public guidance still reports the cast")

ns.db.castPrompt = true
ns.JourneyGuide.ArrowChanged()
prompt = frames[#frames]
assert(
	prompt and not prompt.hidden and prompt.Action.text == "Use Hearthstone",
	"turning it on shows the prompt at once"
)

ns.db.castPrompt = false
ns.JourneyGuide.ArrowChanged()
assert(prompt.hidden, "turning it off hides the prompt at once")
assert(ns.JourneyGuide.Casting(), "hiding the prompt keeps the cast step")
ns.JourneyGuide.Stop()
print("cast prompt setting passed")
