---@meta

-- FrameXML is empty at the pinned Ketho revision. These signatures describe the Forever
-- UI sources (Gethe/wow-ui-source, forever), not replacements loaded by the addon.

---@type string
UNKNOWN = nil
---@type number
LE_PARTY_CATEGORY_INSTANCE = nil
---@type table<string, {r: number, g: number, b: number}>
ChatTypeInfo = nil
-- ItemButtonTemplate.lua: a modified click on an item (Shift links it to chat); true when the click was used.
---@type fun(link: string, itemLocation?: table): boolean
HandleModifiedItemClick = nil

-- ChatFrame.lua in the Forever UI source: the edit box a Shift+click map link would land in.
---@type (fun(): Frame?)?
ChatEdit_GetActiveWindow = nil
---@type {GetActiveWindow: fun(): Frame?}?
ChatFrameUtil = nil
---@type {AddMessage: fun(message: string, color: {r: number, g: number, b: number})}
RaidWarningUtil = nil
-- The stock objective line's dash, which the client also leaves as the line's indent.
---@type string
QUEST_DASH = nil
---@type string
OFF = nil
-- Blizzard_Menu/MenuConstants.lua: what a menu button's responder answers; CloseAll closes every menu.
---@type {Open: MenuResponse, Refresh: MenuResponse, Close: MenuResponse, CloseAll: MenuResponse}
MenuResponse = nil
---@type {Label: {Right: integer}}
MinimalSliderWithSteppersMixin = nil

---@param value number
---@param minimum number
---@param maximum number
---@return number
function Clamp(value, minimum, maximum) end
-- LibDBIcon and minimap addons supply this optional shared shape query.
---@type (fun(): string)?
GetMinimapShape = nil

-- Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua: the client's callback registry. The minimap rebuilds its
-- waypoint tooltip from C_TooltipInfo.GetMinimapMouseover on every mouseover update.
---@type {AddTooltipPostCall: fun(tooltipType: number, callback: fun(tooltip: GameTooltip, data: table))}
TooltipDataProcessor = nil
-- GlobalStrings: the generic "Map Pin" title the minimap gives a user waypoint.
---@type string
MAP_PIN = nil
-- GlobalStrings: the "Map Pin Sharing" title the map's WaypointLocationPin gives a user waypoint.
---@type string
MAP_PIN_SHARING = nil
-- The shared tooltip's first line, which holds its title (SharedTooltipTemplates.lua).
---@type FontString
GameTooltipTextLeft1 = nil

---@param tooltip GameTooltip
function GameTooltip_AddBlankLineToTooltip(tooltip) end
---@param tooltip GameTooltip
---@param text string
---@param wrap? boolean
function GameTooltip_AddNormalLine(tooltip, text, wrap) end
---@param tooltip GameTooltip
---@param text string
---@param wrap? boolean
function GameTooltip_AddInstructionLine(tooltip, text, wrap) end
---@param tooltip GameTooltip
---@param text string
---@param color ColorMixin
---@param wrap? boolean
function GameTooltip_AddColoredLine(tooltip, text, color, wrap) end
---@param tooltip GameTooltip
---@param left string
---@param right string
---@param leftColor ColorMixin
---@param rightColor ColorMixin
function GameTooltip_AddColoredDoubleLine(tooltip, left, right, leftColor, rightColor) end

-- The world map, as the addon reads it (UI/Canvas.lua lists every read): it adds no provider and acquires no pin.
-- Core declares the frame; these are the reads its annotations do not carry.
---@alias SPFMapCanvas WorldMapFrame
---@class WorldMapFrame : Frame
---@field GetMapID fun(self: WorldMapFrame): number
---@field GetCanvasScale fun(self: WorldMapFrame): number
---@field GetCanvasZoomPercent fun(self: WorldMapFrame): number
---@field GetGlobalPinScale fun(self: WorldMapFrame): number
---@field ScrollContainer Frame
---@field dataProviders table<SPFMapProvider, boolean> -- read only, to find the waypoint provider (JourneyGuide.lua)
---@field GetViewRect fun(self: WorldMapFrame): {left: number, right: number, top: number, bottom: number}
---@field GetNormalizedCursorPosition fun(self: WorldMapFrame): number, number
---@field EnumeratePinsByTemplate fun(self: WorldMapFrame, template: string): fun(): SPFMapPin
---@field AddCanvasClickHandler fun(self: WorldMapFrame, handler: fun(map: WorldMapFrame, button: string): boolean)
---@field AddGlobalPinMouseActionHandler fun(self: WorldMapFrame, handler: fun(map: WorldMapFrame, action: number, button: string): boolean)
---@field RegisterCallback fun(self: WorldMapFrame, event: string, callback: function, owner: any) -- the map's own callback registry (SetFocusedQuestID)

-- The levels manager's own extra argument, which core's annotation leaves out.
---@class ForeverCanvasLevels
---@field GetValidFrameLevel fun(self: ForeverCanvasLevels, levelType: string, index?: number): number?
---@type {MouseAction: {Click: number}}
MapCanvasMixin = nil
---@type {Style: {Waypoint: number}}
POIButtonUtil = nil

-- One of the map's own pins, as a Shift-click on it is read (JourneyInput.lua).
---@class SPFMapPin : Frame
---@field pinTemplate string
---@field GetMap fun(self: SPFMapPin): SPFMapCanvas
---@field GetGlobalPosition fun(self: SPFMapPin): number?, number?

-- The map's own waypoint provider, whose pin JourneyGuide.lua hides under its own.
---@class SPFMapProvider
---@field RefreshAllData fun(self: SPFMapProvider, fromOnShow?: boolean)
---@field pin? Frame
---@type SPFMapProvider
WaypointLocationDataProviderMixin = nil

-- The game's in-world navigation marker (Blizzard_QuestNavigation/SuperTrackedFrame.lua), loaded on demand. JourneyGuide.lua
-- paints the addon's own pin over its icon while the marker points at the waypoint the guide placed.
---@class SPFSuperTrackedFrame : Frame
---@field Icon Texture
---@field IconBorder Texture
---@type SPFSuperTrackedFrame?
SuperTrackedFrame = nil
---@class SPFFlightPin : SPFMapPin
---@field poiInfo {nodeID: number, name: string, isUndiscovered: boolean}

-- The Forever addons' world map markers, for each other (UI/Canvas.lua): each addon's function gives its shown
-- markers on a map, as map fractions.
---@type table<string, fun(map: SPFMapCanvas): {x: number, y: number, kind: string}[]>
ForeverMapMarkers = nil

---@class SPFQuestPin : SPFMapPin
---@field GetQuestID fun(self: SPFQuestPin): number?
---@field GetStyle fun(self: SPFQuestPin): number
---@class SPFQuestMenuOwner : Frame
---@field questID? number
---@field questId? number

---@class SPFTrackerLine : Frame
---@field Text FontString
---@field Dash FontString
---@field template string the XML template whose pool this line belongs to
---@field used boolean
---@class SPFTrackerBlockHeader : Button
---@field questID? number
---@class SPFTrackerBlock : Frame
---@field id number|string
---@field questID? number
---@field HeaderButton Button
---@field HeaderText FontString
---@field headerHeight number
---@field parentModule SPFTrackerModule
---@field isHighlighted boolean
---@field used boolean
---@field SetHeader fun(self: SPFTrackerBlock, text: string)
---@field AddObjective fun(self: SPFTrackerBlock, id: number|string, text: string, template?: string, wrap?: boolean, dashStyle?: number, color?: ColorMixin): SPFTrackerLine
---@field GetExistingLine fun(self: SPFTrackerBlock, id: number|string): SPFTrackerLine?
---@field SetStringText fun(self: SPFTrackerBlock, font: FontString, text: string, wrap: boolean?, color: ColorMixin|ForeverObjectiveTrackerColor, highlight?: boolean): number
---@class SPFTrackerHeader : Frame
---@field Text FontString
---@class SPFTrackerModule : ForeverTrackerModule
---@field Header SPFTrackerHeader
---@field headerText string
---@field lineTemplate string
---@field uiOrder number
---@field hasDisplayPriority boolean
---@field GetBlock fun(self: SPFTrackerModule, id: number|string): SPFTrackerBlock
---@field GetExistingBlock fun(self: SPFTrackerModule, id: number|string): SPFTrackerBlock?
---@field LayoutBlock fun(self: SPFTrackerModule, block: SPFTrackerBlock): boolean
---@field SetHeader fun(self: SPFTrackerModule, text: string)
---@field MarkDirty fun(self: SPFTrackerModule)
---@field IsDirty fun(self: SPFTrackerModule): boolean
---@field GetContextMenuParent fun(self: SPFTrackerModule): Frame
---@type ForeverNativeTrackerFrame
ObjectiveTrackerFrame = nil
---@class SPFTrackerManager
---@type SPFTrackerManager
ObjectiveTrackerManager = nil

---@class SPFSetting
---@field SetValue fun(self: SPFSetting, value: boolean|number|string)
---@field SetValueChangedCallback fun(self: SPFSetting, callback: fun(setting: SPFSetting, value: boolean|number|string))
---@class SPFControlTextContainer
---@field Add fun(self: SPFControlTextContainer, value: string, text: string)
---@field GetData fun(self: SPFControlTextContainer): table[]
---@class SPFSettingsCategory
---@field GetID fun(self: SPFSettingsCategory): number
---@class SPFSettingsInitializer
---@class SPFSettings
---@field VarType {Boolean: string, Number: string, String: string}
---@field RegisterVerticalLayoutCategory fun(name: string): SPFSettingsCategory
---@field RegisterCanvasLayoutCategory fun(frame: Frame, name: string): SPFSettingsCategory
---@field RegisterAddOnCategory fun(category: SPFSettingsCategory)
---@field RegisterVerticalLayoutSubcategory fun(parent: SPFSettingsCategory, name: string): SPFSettingsCategory
---@field RegisterCanvasLayoutSubcategory fun(parent: SPFSettingsCategory, frame: Frame, name: string): SPFSettingsCategory
---@field RegisterProxySetting fun(category: SPFSettingsCategory, variable: string, variableType: string, name: string, default: boolean|number, getter: (fun(): boolean|number), setter: (fun(value: boolean|number))): SPFSetting
---@field NotifyUpdate fun(variable: string)
---@field RegisterAddOnSetting fun(category: SPFSettingsCategory, variable: string, key: string, storage: SPFDatabase, variableType: string, name: string, default: boolean|number|string): SPFSetting
---@field CreateSliderOptions fun(minimum: number, maximum: number, step: number): table
---@field CreateSliderInitializer fun(setting: SPFSetting, options: table, tooltip?: string): SPFSettingsInitializer
---@field CreateCheckboxInitializer fun(setting: SPFSetting, options?: table, tooltip?: string): SPFSettingsInitializer
---@field CreateCheckbox fun(category: SPFSettingsCategory, setting: SPFSetting, tooltip?: string)
---@field CreateControlTextContainer fun(): SPFControlTextContainer
---@field CreateDropdownInitializer fun(setting: SPFSetting, getData: (fun(): table[]), tooltip?: string): SPFSettingsInitializer
---@field RegisterInitializer fun(category: SPFSettingsCategory, initializer: SPFSettingsInitializer)
---@field RegisterAddOnCategory fun(category: SPFSettingsCategory)
---@field OpenToCategory fun(id: number)
---@type SPFSettings
Settings = nil

-- Blizzard's settings button initializer, absent from the pinned annotations (Ketho/vscode-wow-api).
---@param name string
---@param buttonText string
---@param click fun()
---@param tooltip? string
---@param addSearchTags? boolean
---@return SPFSettingsInitializer
function CreateSettingsButtonInitializer(name, buttonText, click, tooltip, addSearchTags) end

-- Blizzard_SharedXMLGame InputUtil.lua: the client's input-device switch.
---@class SPFInputUtil
---@field IsGamepadUIEnabled fun(): boolean
---@type SPFInputUtil?
InputUtil = nil

---@class SPFUiMapPointFactory
---@field CreateFromVector2D fun(uiMapID: number, position: Vector2DMixin): UiMapPoint
---@field CreateFromCoordinates fun(uiMapID: number, x: number, y: number, z?: number): UiMapPoint
---@type SPFUiMapPointFactory
UiMapPoint = nil

-- ForeverCore's shared quest log tab: the addon fits its art after registering it.
---@class ForeverQuestLogTab : Button
---@field Icon Texture the tab's art, fitted to its template
---@class ForeverQuestMapFrame : Frame
---@field ContentsAnchor Frame
