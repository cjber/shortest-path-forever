-- The cast prompt shares the direction-arrow switch without discarding the guide's teleport target (#881).
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local frames = {}
local create = env.CreateFrame
env.CreateFrame = function(...)
	local frame = create(...)
	frame.events = {}
	function frame:RegisterEvent(event)
		self.events[event] = true
	end
	function frame:UnregisterEvent(event)
		self.events[event] = nil
	end
	function frame:UnregisterAllEvents()
		self.events = {}
	end
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
-- The Hearthstone's name is not in the client's cache yet.
local cachedItems = {}
env.C_Item = env.C_Item or {}
env.C_Item.GetItemNameByID = function(itemID)
	return cachedItems[itemID]
end
ns.Mover = { Attach = function() end, Stock = function() end }
local reads = 0
ns.TeleportAction = function(teleport)
	reads = reads + 1
	return teleport.item and "Use Hearthstone" or "Cast Teleport", 134400
end
driver.load("UI/Arrow.lua")

ns.db.arrow = false
local hearth = { item = 6948 }
local leg = { teleport = hearth }
ns.JourneyGuide.Start()
ns.JourneyGuide.Cast(leg)
assert(#frames == 0, "initial disabled cast must not create visible frames")
assert(ns.JourneyGuide.Casting(), "disabled prompt retains the canonical cast target")
assert(select(2, ns.JourneyGuidance()) == "cast", "disabled cast keeps public guidance in cast phase")
ns.db.arrow = true
ns.JourneyGuide.ArrowChanged()
local prompt = frames[#frames]
assert(prompt and not prompt.hidden, "reenabling restores the retained cast prompt immediately")
assert(prompt.Action.text == "Use Hearthstone", "the restored prompt uses the retained item")
assert(prompt.events.GET_ITEM_INFO_RECEIVED and prompt.events.SPELLS_CHANGED, "visible prompt listens for updates")
local queued = prompt.OnEvent
local before = reads
queued(prompt, "GET_ITEM_INFO_RECEIVED", 2589)
assert(reads == before, "another item's answer does not redraw the prompt (#1029)")
cachedItems[6948] = "Hearthstone"
queued(prompt, "GET_ITEM_INFO_RECEIVED", 6948)
assert(reads == before + 1, "the prompt's own item answer redraws it")
assert(not prompt.events.GET_ITEM_INFO_RECEIVED, "a named item stops listening for item answers")
queued(prompt, "SPELLS_CHANGED")
assert(reads == before + 2, "spell changes refresh the prompt")
cachedItems[6948] = nil

ns.db.arrow = false
ns.JourneyGuide.ArrowChanged()
assert(prompt.hidden and next(prompt.events) == nil, "live disable hides and unregisters the prompt immediately")
assert(ns.JourneyGuide.Casting(), "live disable preserves the cast target")
before = reads
queued(prompt, "GET_ITEM_INFO_RECEIVED", 6948)
queued(prompt, "SPELLS_CHANGED")
assert(prompt.hidden and reads == before, "queued refreshes cannot render a disabled prompt")
ns.db.arrow = true
ns.JourneyGuide.ArrowChanged()
assert(not prompt.hidden and prompt.Action.text == "Use Hearthstone", "live reenable restores the same item")
assert(ns.JourneyGuide.Casting(), "reenabling does not reset canonical cast guidance")

local spell = { spell = 3561 }
ns.JourneyGuide.Cast({ teleport = spell })
assert(prompt.Action.text == "Cast Teleport" and not prompt.hidden, "an enabled spell replaces the item prompt")
ns.db.arrow = false
ns.JourneyGuide.ArrowChanged()
ns.PointCastPrompt(hearth)
assert(prompt.hidden, "a replacement item stays hidden while disabled")
ns.PointCastPrompt(spell)
ns.db.arrow = true
ns.JourneyGuide.ArrowChanged()
assert(prompt.Action.text == "Cast Teleport" and not prompt.hidden, "reenable renders the current spell")

ns.PointCastPrompt(nil)
before = reads
queued(prompt, "GET_ITEM_INFO_RECEIVED")
queued(prompt, "SPELLS_CHANGED")
assert(prompt.hidden and next(prompt.events) == nil and reads == before, "nil clears events and queued rendering")
ns.PointCastPrompt(spell)
assert(not prompt.hidden, "an enabled cast shows its prompt directly")
ns.JourneyGuide.Stop()
before = reads
assert(prompt.hidden and next(prompt.events) == nil, "ending an active cast hides and unregisters its prompt")
ns.db.arrow = false
ns.JourneyGuide.ArrowChanged()
ns.db.arrow = true
ns.JourneyGuide.ArrowChanged()
queued(prompt, "SPELLS_CHANGED")
assert(prompt.hidden and reads == before, "ending the cast cannot resurrect its prompt on a later toggle")
print("cast prompt visibility and transitions passed")
