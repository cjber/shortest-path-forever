---@meta

-- A Questie world map icon (Questie/Questie, Modules/FramePool/QuestieFramePool.lua and Modules/Map/QuestieMap.lua,
-- DrawWorldIcon): a QuestieFrame button holding the spawn it marks. Journey/JourneyInput.lua reads these fields only.
---@class SPFQuestieIcon : Button
---@field data? table the icon's quest and spawn data, set while the icon is drawn
---@field x? number the spawn's place on its zone map, in percent
---@field y? number
---@field UiMapID? number the zone map x and y are on
---@field miniMapIcon? boolean false on the world map's icon, true on its minimap twin
