std = "lua51"
max_line_length = 120
exclude_files = { "forever-core/**", ".claude/**", "tools/.cache/**", ".types/**", "types/**", ".release/**", "Nav/**", ".bugpatrol/runs/**", ".speedpatrol/runs/**", ".sloppatrol/runs/**" }
globals = {
	"EventUtil",
	"ShortestPathForever",
	"ShortestPathForeverCharDB",
	"ShortestPathForeverDB",
	"ShortestPathForever_OnAddonCompartmentClick",
	"TomTom",
	"SLASH_SHORTESTPATHFOREVER1",
	"SLASH_SHORTESTPATHFOREVER2",
	"SlashCmdList",
	"bit",
	"SLASH_SPFNEAR1",
	"SLASH_SHORTESTPATHFOREVERWAY1",
}
read_globals = {
	"ForeverCore",
	"Guidelime",
	"GuidelimeArrow",
	"TomTomCrazyArrow",
	"IsAltKeyDown",
	"QuestMapFrame",
	"QuestMapFrameOverrides",
	"QUESTS_LABEL",
	"GetSubZoneText",
	"GetZoneText",
	"C_XMLUtil",
	"Ambiguate",
	"C_ChatInfo",
	"Clamp",
	"CreateSettingsButtonInitializer",
	"Lerp",
	"Menu",
	"MenuUtil",
	"MenuResponse",
	"Saturate",
	"C_InputInterfaceStyle",
	"C_Map",
	"C_Texture",
	"C_Timer",
	"CreateFrame",
	"CreateFromMixins",
	"CreateVector2D",
	"Enum",
	"GameTooltip",
	"GameTooltip_AddBlankLineToTooltip",
	"GameTooltip_AddColoredDoubleLine",
	"GameTooltip_AddColoredLine",
	"GameTooltip_AddInstructionLine",
	"GameTooltip_AddNormalLine",
	"GameTooltip_SetTitle",
	"geterrorhandler",
	"GetInstanceInfo",
	"GetNormalizedRealmName",
	"GetRealmName",
	"GetRealZoneText",
	"GetServerTime",
	"GetTime",
	"GRAY_FONT_COLOR",
	"RED_FONT_COLOR",
	"HIGHLIGHT_FONT_COLOR",
	"hooksecurefunc",
	"securecallfunction",
	"IsInGroup",
	"IsInGuild",
	"IsInInstance",
	"IsInRaid",
	"LE_PARTY_CATEGORY_INSTANCE",
	"Mixin",
	"NORMAL_FONT_COLOR",
	"ObjectiveTrackerFrame",
	"ObjectiveTrackerManager",
	"ORANGE_FONT_COLOR",
	"Settings",
	"MinimalSliderWithSteppersMixin",
	"SecondsToTime",
	"OFF",
	"RaidWarningUtil",
	"PlaySoundFile",
	"FlashClientIcon",
	"ChatTypeInfo",
	"UIParent",
	"UiMapPoint",
	"IsShiftKeyDown",
	"IsModifierKeyDown",
	"GetUnitSpeed",
	"GetTaxiMapID",
	"NumTaxiNodes",
	"TaxiNodeGetType",
	"TaxiNodeName",
	"TaxiGetNodeSlot",
	"GetNumRoutes",
	"TaxiFrame",
	"TaxiRouteMap",
	"NUM_TAXI_ROUTES",
	"TAXIROUTE_LINEFACTOR",
	"DrawOneHopLines",
	"DrawLine",
	"C_TaxiMap",
	"C_SuperTrack",
	"UnitFactionGroup",
	"UnitExists",
	"UnitIsUnit",
	"UnitName",
	"UnitOnTaxi",
	"UnitPosition",
	"UnitIsDeadOrGhost",
	"UnitIsGhost",
	"C_DeathInfo",
	"UNKNOWN",
	"WorldMapFrame",
	"Minimap",
	"GetPlayerFacing",
	"GetCVar",
	"GetCVarBool",
	"GetMinimapShape",
	"C_Minimap",
}
files["tests/"] = { std = "+luajit" }

-- Tracker colours and the stock line's dash.
read_globals[#read_globals + 1] = "OBJECTIVE_TRACKER_COLOR"
read_globals[#read_globals + 1] = "QUEST_DASH"
-- UI/Canvas.lua: the Forever addons' shared list of world map markers, and the gamepad's map cursor.
globals[#globals + 1] = "ForeverMapMarkers"
read_globals[#read_globals + 1] = "SoftCursor"
-- Shared-workspace arrow: Blizzard_QuestNavigation/SuperTrackedFrame.lua:291.
read_globals[#read_globals + 1] = "C_Navigation"
-- Blizzard_SharedXMLBase/Color.lua:3, saturated route colours.
read_globals[#read_globals + 1] = "CreateColor"
-- Native quest menus, locations and MapCanvas's consuming pin-click handler.
read_globals[#read_globals + 1] = "C_QuestLog"
read_globals[#read_globals + 1] = "GetQuestUiMapID"
read_globals[#read_globals + 1] = "GetMouseFoci"
-- Shift+click on the map defers to an open chat box.
read_globals[#read_globals + 1] = "ChatEdit_GetActiveWindow"
read_globals[#read_globals + 1] = "ChatFrameUtil"
read_globals[#read_globals + 1] = "MapCanvasMixin"
read_globals[#read_globals + 1] = "POIButtonUtil"
-- PathGrid.lua: its per-frame CPU clock and the per-continent walking-map addons it loads on demand.
read_globals[#read_globals + 1] = "debugprofilestop"
read_globals[#read_globals + 1] = "ShortestPathForeverPathData"
read_globals[#read_globals + 1] = "C_AddOns"
-- Whether a value the client may hold secret can be read: checked across Core, Journey, Transport and UI.
read_globals[#read_globals + 1] = "canaccessvalue"
-- JourneyGuide.lua: picks out the map's own waypoint data provider, and names its pin rather than the client's
-- generic "Map Pin".
read_globals[#read_globals + 1] = "WaypointLocationDataProviderMixin"
-- The game's in-world navigation marker, loaded on demand.
read_globals[#read_globals + 1] = "SuperTrackedFrame"
read_globals[#read_globals + 1] = "TooltipDataProcessor"
read_globals[#read_globals + 1] = "GameTooltipTextLeft1"
read_globals[#read_globals + 1] = "MAP_PIN"
read_globals[#read_globals + 1] = "MAP_PIN_SHARING"
-- Journey.lua: water walking from its buffs, or a spell to cast.
read_globals[#read_globals + 1] = "C_UnitAuras"
read_globals[#read_globals + 1] = "C_Spell"
-- UI/ServicesPanel.lua: Shift-click on a row's goods links them, as on any item button.
read_globals[#read_globals + 1] = "HandleModifiedItemClick"
-- UI/Nearby.lua: a profession trainer group's localised skill line name.
read_globals[#read_globals + 1] = "C_TradeSkillUI"
-- Route.lua: the cursor over the minimap.
read_globals[#read_globals + 1] = "GetCursorPosition"
-- UI/OpenMap.lua: the seamless world map addon's public API for other addons (version 2 and up).
read_globals[#read_globals + 1] = "OpenMapAPI"

-- UI/NpcArrows.lua: the nameplate the NPC a Nearby services journey walks to carries, and the unit's own GUID.
read_globals[#read_globals + 1] = "C_NamePlate"
read_globals[#read_globals + 1] = "UnitGUID"

read_globals[#read_globals + 1] = "IsPlayerMoving"
read_globals[#read_globals + 1] = "InCombatLockdown"
read_globals[#read_globals + 1] = "C_AddOnProfiler"
read_globals[#read_globals + 1] = "UpdateAddOnMemoryUsage"
read_globals[#read_globals + 1] = "GetAddOnMemoryUsage"
-- Teleports.lua: which teleports this character can cast, and where it is bound.
read_globals[#read_globals + 1] = "C_Item"
read_globals[#read_globals + 1] = "C_SpellBook"
read_globals[#read_globals + 1] = "GetBindLocation"
-- Floor.lua: indoors, where floors stack, the floor is followed whenever you move; swimming, you are on water.
read_globals[#read_globals + 1] = "IsIndoors"
read_globals[#read_globals + 1] = "IsSwimming"
-- tests/ui_client.lua and tests/ui_map.lua are one chunk defining the client for the UI checks, which append code
-- reading their locals. 2xx: locals and arguments only the appended checks use; 43x: stub methods named like the
-- client's.
files["tests/ui_client.lua"] = {
	allow_defined_top = true,
	ignore = { "2", "43" },
	-- Blizzard_SharedXML/Spinner.lua defines SpinnerMixin.
	read_globals = { "SpinnerMixin" },
}
-- ui_map.lua continues ui_client.lua's chunk, so its "globals" are ui_client.lua's locals.
files["tests/ui_map.lua"] = { ignore = { "1", "2", "43" } }
read_globals[#read_globals + 1] = "EventRegistry"

read_globals[#read_globals + 1] = "C_EncodingUtil"

read_globals[#read_globals + 1] = "RXP"

read_globals[#read_globals + 1] = "AdventureGuideForever"
-- Core/TomTom.lua: Polestar's TomTom stand-in and its settings.
read_globals[#read_globals + 1] = "Polestar"
-- The report window ForeverCore draws for this addon.
read_globals[#read_globals + 1] = "date"
read_globals[#read_globals + 1] = "strtrim"
read_globals[#read_globals + 1] = "GetLocale"
read_globals[#read_globals + 1] = "UnitClass"
read_globals[#read_globals + 1] = "UnitLevel"
-- Nearby.lua: your professions' trainers come first.
read_globals[#read_globals + 1] = "GetProfessions"
read_globals[#read_globals + 1] = "GetProfessionInfo"
-- Nearby.lua: a better arrow, shot or drink far off is offered to whoever has the ranged weapon or the mana for it.
read_globals[#read_globals + 1] = "GetInventorySlotInfo"
read_globals[#read_globals + 1] = "GetInventoryItemID"
read_globals[#read_globals + 1] = "UnitPowerMax"
read_globals[#read_globals + 1] = "UISpecialFrames"
read_globals[#read_globals + 1] = "tContains"
-- Mover.lua: whether the button of a fine drag is still held.
read_globals[#read_globals + 1] = "IsMouseButtonDown"

-- Forever Leaderboards: the shared window's client surfaces the travel board reads.
read_globals[#read_globals + 1] = "GREEN_FONT_COLOR"

-- A translated line is one string; StyLua already wraps what it can, and CJK text counts bytes, not columns.
files["Locales/*.lua"] = { max_line_length = false }
-- Generated road data carries long encoded strings; the producers decide their line length.
files["Data/RoadCells.lua"] = { max_line_length = false }
files["Data/RoadEdges.lua"] = { max_line_length = false }

files["tests/companion_maps_spec.lua"] = { globals = { "C_AddOns", "GetTime" } }
-- The client's secure delegate: map pins set their restricted button passthrough through it (#645).
read_globals[#read_globals + 1] = "CreateSecureDelegate"
