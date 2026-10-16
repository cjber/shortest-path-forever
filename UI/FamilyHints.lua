---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

-- Where Shortest Path mentions my other Forever addons, each only while that addon isn't installed and behind the
-- shared rules in UI/ForeverFamily.lua (Suggest my other Forever addons, Don't suggest this again):
-- a grey entry in the quest menus for Adventure Guide, a grey footer in the tracker after a journey arrives with
-- nothing more planned (once a session), and a grey line on a dungeon or raid door's stop for Legacy.

local ADVENTURE, LEGACY = "AdventureGuideForever", "LegacyForever"
local QUEST_MENU, ARRIVAL, ENTRANCE =
	"ShortestPathForever.questMenu", "ShortestPathForever.arrival", "ShortestPathForever.entrance"
-- How long the footer stays under a finished journey with nothing else in the tracker.
local FOOTER_SECONDS = 120

---@class SPFFamilyHints
local Hints = {}
ns.FamilyHints = Hints

---@type { title: string, shownAt: number }?
local footer
local version = 0
---@type SPFPoint?
local journeyPoint

local function Changed()
	version = version + 1
	if ns.RefreshTracker then
		ns.RefreshTracker()
	end
end

-- The quest menus' entry, under Plan journey: Adventure Guide picks quests for the player's level.
---@param root table the menu description being built
function Hints.AddQuestMenu(root)
	if ns.Family.Hint(ns.db, QUEST_MENU, ADVENTURE) then
		root:CreateButton(
			GRAY_FONT_COLOR:WrapTextInColorCode(L["Suggest quests for my level: Adventure Guide Forever"]),
			function()
				ns.Family.ShowLink(ns.db, QUEST_MENU, ADVENTURE)
			end
		)
	end
end

-- The stop pin's tooltip line on a dungeon or raid door. Shortest Path can't tell which instances Legacy has
-- challenges for, so every door gets it.
---@param tooltip GameTooltip
function Hints.AddEntranceLine(tooltip)
	local goal = ns.JourneyGoal()
	if goal and goal.entrance and ns.Family.Hint(ns.db, ENTRANCE, LEGACY) then
		GameTooltip_AddColoredLine(
			tooltip,
			L["Legacy Forever shows the Legacy challenges this counts toward."],
			GRAY_FONT_COLOR
		)
	end
end

-- The footer's block for the tracker, or nil. It goes when a new journey starts, the hint no longer applies (the
-- setting, a dismissal, or Adventure Guide now installed), or FOOTER_SECONDS have passed.
---@return { key: string, title: string, rows: SPFRow[] }?
function Hints.Footer()
	if
		footer
		and (
			ns.HasJourney()
			or GetTime() - footer.shownAt >= FOOTER_SECONDS
			or not ns.Family.Hint(ns.db, ARRIVAL, ADVENTURE)
		)
	then
		footer = nil
		version = version + 1
	end
	if not footer then
		return nil
	end
	return {
		key = "family",
		title = footer.title,
		rows = {
			{
				key = "family",
				text = L["What next? Adventure Guide Forever suggests quests for your level."],
				grey = true,
			},
		},
	}
end

-- Changes whenever the footer comes or goes, for the tracker's own change check.
---@return integer
function Hints.Version()
	return version
end

-- Clicking the footer shows the link and takes the footer away: it has done its job.
function Hints.OpenFooter()
	if not footer then
		return
	end
	if ns.Family.ShowLink(ns.db, ARRIVAL, ADVENTURE) then
		footer = nil
		Changed()
	end
end

-- ns.JourneyChanged: a point is the next stop; nil with "arrived" ends the journey with nothing more planned.
---@param point SPFPoint?
---@param reason? "arrived"|"cleared"
local function JourneyChanged(point, reason)
	if point then
		journeyPoint = point
		return
	end
	local finished = journeyPoint
	journeyPoint = nil
	if reason ~= "arrived" or not finished then
		return
	end
	if ns.Family.Hint(ns.db, ARRIVAL, ADVENTURE) and ns.Family.Once(ARRIVAL) then
		footer = {
			title = finished.routeTitle or L["Journey to %s"]:format(ns.PlaceLabel(finished)),
			shownAt = GetTime(),
		}
		Changed()
		C_Timer.After(FOOTER_SECONDS, ns.RefreshTracker)
	end
end

ns.Init(function()
	-- After every file has loaded, so API.lua's ns.JourneyChanged exists to hook.
	hooksecurefunc(ns, "JourneyChanged", JourneyChanged) -- taint-ok: ns is this addon's own namespace table.
end)
