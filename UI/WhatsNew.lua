local addonName = ...
---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The newest release in CHANGELOG.md with a bold headline, and that headline, printed once after an update. A core
-- sync's maintenance entry has no headline, so these stay on the release before it: an update to a maintenance
-- version says nothing new but still remembers the version. Rewrite both lines for each release that has a headline
-- (tests/whats_new_spec.lua checks them against CHANGELOG.md).
ns.WHATS_NEW_VERSION = "1.36.0"
ns.WHATS_NEW = L["Fewer market stalls on the map, and every NPC apart at full zoom."]

-- Once per new version, after an update: never on a first install, nor in a checkout, whose TOC still holds the
-- packager's version keyword (matched by its "@", as the packager would rewrite the whole keyword here too). The
-- chat line is said only for the version with a headline: a maintenance release is remembered but says nothing new.
function ns.CheckWhatsNew()
	local db = ns.db
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if not version or version:find("^@") then
		return
	end
	local seen = db.seenVersion
	db.seenVersion = version
	if seen and seen ~= version and version == ns.WHATS_NEW_VERSION and db.whatsNew then
		ns.Print(string.format(L["updated to %s. %s"], version, ns.WHATS_NEW))
	end
end

ns.Init(function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_LOGIN")
		ns.CheckWhatsNew()
	end)
end)
