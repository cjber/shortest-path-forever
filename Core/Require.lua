local addonName, ns = ...

-- The one client icon this addon shows for itself in game, declared once in the TOC and read here so no other file
-- repeats the path. The leaderboard tab and every other identity surface draw this value.
ns.Icon = C_AddOns.GetAddOnMetadata(addonName, "X-Forever-Icon")

-- The game refuses to load this addon when ForeverCore is absent (## Dependencies), but an older ForeverCore still
-- loads. Its API version stays at 1 while it adds members, so a core is out of date when a member this addon calls is
-- missing, never because of a version comparison.
--
-- API 1 has the tracker host, the family suggestions, the map and settings openers, the
-- text helper, the quest log tabs and the context menu, all of which this addon calls. The API kit arrived after it
-- (ForeverCore 1.1.0), and Core/API.lua builds this addon's own API on its Hub and NotReady. The tracker section and
-- line arrived after it too (ForeverCore 1.2.0), and UI/Tracker.lua builds its section with Section.Create and
-- Section.UpdateText and makes its objectives clickable with Line.SetInteractive. Publishing to the suite's list
-- (APIKit.Publish) is guarded by the kit's minor, so an older kit is not a reason to stop. The step markers arrived in
-- ForeverCore 1.11.0 (Art minor 2): UI/Art.lua's NumberFile is Art.Marker and UI/Arrow.lua's no-number centre is
-- Art.Diamond, so the addon's own media/Numbers art is gone.
--
-- The warning itself is Core/ForeverRequire.lua, shared by every Forever addon: one line on screen, never a chat
-- message, naming the addon to update and never ForeverCore.
local ready = ForeverCore ~= nil
	and type(ForeverCore.APIKit) == "table"
	and type(ForeverCore.APIKit.Hub) == "function"
	and type(ForeverCore.APIKit.NotReady) == "function"
	and type(ForeverCore.TrackerSection) == "table"
	and type(ForeverCore.TrackerSection.Create) == "function"
	and type(ForeverCore.TrackerSection.UpdateText) == "function"
	and type(ForeverCore.TrackerLine) == "table"
	and type(ForeverCore.TrackerLine.SetInteractive) == "function"
	and type(ForeverCore.Art) == "table"
	and type(ForeverCore.Art.Marker) == "function"
	and type(ForeverCore.Art.Diamond) == "function"

ns.ForeverRequire(ready)
