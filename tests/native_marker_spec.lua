-- The game's in-world navigation marker (Blizzard_QuestNavigation/SuperTrackedFrame.lua) wears Shortest Path's own
-- pin while it points at the waypoint the guide placed, and Blizzard's icon for any other super-tracked target (#474).
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

-- The real arrow is the guide's waypoint consumer, and Art carries ns.PIN_FILE and Art.Icon.
driver.load("UI/Art.lua")
driver.load("UI/Mover.lua")
driver.load("UI/TurnAround.lua")
driver.load("UI/Arrow.lua")

local function texture()
	local t = { alpha = 1 }
	function t:SetTexCoord(...)
		self.coords = { ... }
	end
	function t:SetTexture(file)
		self.texture, self.atlas = file, nil
	end
	function t:SetAtlas(atlas)
		self.atlas, self.texture = atlas, nil
	end
	function t:SetSize(width, height)
		self.width, self.height = width, height
	end
	function t:SetPoint(...)
		self.point = { ... }
	end
	function t:SetAlpha(alpha)
		self.alpha = alpha
	end
	function t:SetShown(shown)
		self.hidden = not shown
	end
	function t:Hide()
		self.hidden = true
	end
	return t
end

-- Blizzard's own UpdateIcon only picks an atlas and the border's shown state; it never sets either alpha.
local marker = { Icon = texture(), IconBorder = texture() }
function marker:UpdateIcon()
	self.updates = (self.updates or 0) + 1
	self.Icon:SetAtlas("Navigation-Tracked-Icon")
	self.IconBorder:SetShown(false)
end
function marker:UpdateIconSize()
	self.sizes = (self.sizes or 0) + 1
end

-- The addon's marker overlay is a child of SuperTrackedFrame, so catch the frame it creates there.
local overlays = {}
local create = env.CreateFrame
env.CreateFrame = function(kind, name, parent)
	if parent ~= marker then
		return create(kind, name, parent)
	end
	local overlay = { parent = parent }
	function overlay:CreateTexture()
		self.texture = texture()
		return self.texture
	end
	function overlay:SetPoint(...)
		self.point = { ... }
	end
	function overlay:Show()
		self.hidden = false
	end
	function overlay:Hide()
		self.hidden = true
	end
	overlays[#overlays + 1] = overlay
	return overlay
end

-- Blizzard_QuestNavigation is load-on-demand: with no frame yet the guide does nothing and draws nothing.
assert(env.SuperTrackedFrame == nil, "the harness starts without the load-on-demand marker frame")
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 })
assert(ns.IsJourneyGuided() and driver.waypoint(), "the journey guides and places its waypoint")
assert(#overlays == 0, "no marker frame, so no overlay to draw")

-- The marker arrives late: its own load is the signal, and a different ADDON_LOADED leaves us waiting.
marker:UpdateIcon()
assert(
	marker.updates == 1 and marker.Icon.atlas == "Navigation-Tracked-Icon",
	"the stock marker starts on Blizzard's icon"
)
env.SuperTrackedFrame = marker
driver.fire("ADDON_LOADED", "SomeOtherAddon")
assert(#overlays == 0, "another addon loading does not draw our pin")
driver.fire("ADDON_LOADED", "Blizzard_QuestNavigation")
assert(#overlays == 1, "a late marker frame gets our overlay")
local overlay = overlays[1]
assert(overlay.parent == marker, "the overlay is parented to the marker")
assert(not overlay.hidden, "the overlay shows while the marker is ours")
assert(overlay.texture.texture == ns.PIN_FILE and overlay.texture.atlas == nil, "the overlay wears the addon's pin")
assert(overlay.texture.width == 36 and overlay.texture.height == 36, "the pin is square at the arrow's size")
assert(
	overlay.texture.point[1] == "CENTER"
		and overlay.texture.point[2] == marker.Icon
		and overlay.texture.point[3] == "CENTER",
	"the pin centers on the marker's icon"
)
assert(marker.Icon.alpha == 0 and marker.IconBorder.alpha == 0, "Blizzard's icon and border fade out beneath it")
assert(marker.updates == 1, "we never call Blizzard's UpdateIcon")
assert(marker.sizes == nil, "we never call Blizzard's UpdateIconSize")

-- The client repaints the icon on its own (tracking changes, the party-member ticker): its atlas comes back, but our
-- alpha and our pin are untouched.
marker:UpdateIcon()
assert(marker.updates == 2, "the client repaint ran")
assert(marker.Icon.atlas == "Navigation-Tracked-Icon", "the client still sets its own atlas")
assert(marker.Icon.alpha == 0 and marker.IconBorder.alpha == 0, "a stock repaint does not undo the fade")
assert(not overlay.hidden and overlay.texture.texture == ns.PIN_FILE, "our pin stays over the hidden icon")

-- Clearing the journey gives the native marker back.
ns.ClearJourney()
assert(not ns.IsJourneyGuided() and driver.waypoint() == nil, "the journey and its waypoint are gone")
assert(overlay.hidden, "the overlay hides with the journey")
assert(marker.Icon.alpha == 1 and marker.IconBorder.alpha == 1, "Blizzard's icon is back at full alpha")
assert(
	marker.Icon.atlas == "Navigation-Tracked-Icon" and marker.Icon.texture == nil,
	"Blizzard's stock icon was never overwritten"
)

-- A waypoint the player places and super-tracks is not the guide's, so it keeps the stock icon.
env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(1, 0.2, 0.3))
env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
driver.update(0)
local playerWaypoint, tracked = driver.waypoint()
assert(playerWaypoint and tracked, "the player's own waypoint is super-tracked")
assert(overlay.hidden and marker.Icon.alpha == 1 and marker.IconBorder.alpha == 1, "a player's own pin stays stock")
marker:UpdateIcon()
assert(
	marker.Icon.atlas == "Navigation-Tracked-Icon" and marker.Icon.texture == nil,
	"a stock repaint leaves the player's own pin alone"
)
assert(overlay.hidden, "a stock repaint does not bring our pin back")

print("native marker: the guide's waypoint wears our pin, everything else stays stock")
