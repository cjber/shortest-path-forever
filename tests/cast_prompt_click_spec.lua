local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local combat, button, tooltip, combatHint, regenListener
local create = env.CreateFrame
env.InCombatLockdown = function()
	return combat
end
env.CreateFrame = function(kind, name, parent, template)
	local widget = create(kind, name, parent, template)
	if template ~= "SecureActionButtonTemplate" then
		widget.GetTop = function()
			return 600
		end
		widget.GetCenter = function()
			return 680, 565
		end
		widget.GetFrameLevel = function()
			return 1
		end
		function widget:RegisterEvent(event)
			if event == "PLAYER_REGEN_ENABLED" then
				regenListener = self
			end
		end
		function widget:UnregisterEvent(event)
			if event == "PLAYER_REGEN_ENABLED" and regenListener == self then
				regenListener = nil
			end
		end
		function widget:UnregisterAllEvents()
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
		-- A frame anchored to a protected frame turns protected, and the prompt must stay free to move in combat.
		local setPoint = widget.SetPoint
		function widget:SetPoint(point, relative, ...)
			assert(not button or relative ~= button, "nothing anchors to the secure button")
			return setPoint(self, point, relative, ...)
		end
		return widget
	end
	assert(not combat and not button, "create one secure button outside combat")
	assert(kind == "Button" and parent == env.UIParent, "the secure button has no addon parent")
	button = widget
	button.attributes = {}
	function button:SetAttribute(key, value)
		assert(not combat, "no protected attribute writes in combat")
		self.attributes[key] = value
	end
	function button:RegisterForClicks(...)
		self.clicks = { ... }
	end
	for _, method in ipairs({
		"Show",
		"Hide",
		"SetPoint",
		"ClearAllPoints",
		"SetScale",
		"SetSize",
		"SetParent",
		"SetFrameLevel",
	}) do
		local original = button[method]
		button[method] = function(self, ...)
			assert(not combat, "no protected " .. method .. " in combat")
			if method == "SetPoint" then
				assert(select(2, ...) == env.UIParent, "the secure button has no addon anchor")
			end
			return original(self, ...)
		end
	end
	return button
end
env.GameTooltip = {
	SetOwner = function() end,
	IsOwned = function()
		return false
	end,
	AddLine = function(_, value)
		combatHint = value
	end,
	SetText = function(_, value)
		tooltip = value
	end,
	Show = function() end,
}
env.C_Item = {
	GetItemNameByID = function()
		return "Hearthstone"
	end,
	GetItemIconByID = function()
		return 134414
	end,
}
env.C_Spell = {
	GetSpellName = function()
		return "Teleport: Stormwind"
	end,
	GetSpellTexture = function()
		return 135763
	end,
}
ns.Art = { Icon = function() end }
driver.load("UI/Mover.lua")
driver.load("UI/CastButton.lua")
driver.load("UI/Arrow.lua")

local hearth = { item = 6948, spell = 8690, bind = true }
local spell = { spell = 3561 }
local party = { spell = 10059, partyMage = "Jaina", destination = "Stormwind" }

local function EndCombat()
	combat = false
	if regenListener then
		regenListener:OnEvent("PLAYER_REGEN_ENABLED")
	end
end

combat = true
ns.PointCastPrompt(hearth)
assert(not button, "a first cast in combat cannot create a secure button")
EndCombat()
assert(button and not button.hidden, "the Hearthstone prompt has a visible secure button after combat")
assert(button.attributes.type == "item" and button.attributes.item == "item:6948" and not button.attributes.spell)
assert(table.concat(button.clicks, ",") == "AnyUp,AnyDown")
button:OnEnter()
assert(tooltip == "Click to use Hearthstone")

combat = true
ns.PointCastPrompt(nil)
ns.PointCastPrompt(party)
ns.PointCastPrompt(spell)
assert(not button.hidden and button.attributes.item == "item:6948", "combat keeps the applied Hearthstone action")
button:OnEnter()
assert(tooltip == "Click to use Hearthstone", "the tooltip describes the applied action")
assert(combatHint == "The travel action will update after combat.")
EndCombat()
assert(not button.hidden and button.attributes.type == "spell" and button.attributes.spell == 3561)
assert(not button.attributes.item, "the spell clears the previous item attribute")
button:OnEnter()
assert(tooltip == "Click to cast Teleport: Stormwind")

ns.PointCastPrompt(party)
assert(button.hidden and not button.attributes.type, "another mage's portal has no clickable action")
ns.PointCastPrompt(spell)
combat = true
ns.db.castPrompt = false
ns.PointCastPrompt(spell)
assert(not button.hidden, "combat defers the hide")
EndCombat()
assert(button.hidden and not button.attributes.type, "disabling the prompt hides and clears the button after combat")
ns.db.castPrompt = true
ns.PointCastPrompt({ item = 18984, spell = 23442 })
assert(not button.hidden and button.attributes.item == "item:18984", "a teleport item uses its own item ID")
ns.PointCastPrompt(nil)
assert(button.hidden and not button.attributes.item, "clearing the prompt clears the item action")
print("cast prompt secure actions, tooltips and combat deferral passed")
