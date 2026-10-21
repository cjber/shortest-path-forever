---@meta

-- FrameXML is empty at the pinned Ketho revision. These signatures describe the Forever
-- UI sources (Gethe/wow-ui-source, forever), not replacements loaded by the addon.

---@type string
UNKNOWN = nil
---@type number
LE_PARTY_CATEGORY_INSTANCE = nil
---@type table<string, fun(message: string, editBox: EditBox)>
SlashCmdList = nil
---@type table<string, {r: number, g: number, b: number}>
ChatTypeInfo = nil
-- UIParent.lua: the frame names Escape closes like a panel (UI/Report.lua lists its own window).
---@type string[]
UISpecialFrames = nil

-- ChatFrame.lua in the Forever UI source: the edit box a Shift+click map link would land in.
---@type (fun(): Frame?)?
ChatEdit_GetActiveWindow = nil
---@type {GetActiveWindow: fun(): Frame?}?
ChatFrameUtil = nil
---@type {AddMessage: fun(message: string, color: {r: number, g: number, b: number})}
RaidWarningUtil = nil
---@type {Normal: ColorMixin, NormalHighlight: ColorMixin, Header: ColorMixin}
OBJECTIVE_TRACKER_COLOR = nil
---@type string
OFF = nil
-- InputInterfaceStyleDocumentation.lua: which interface the game shows, mouse and keyboard or the gamepad one.
---@type {GetCurrentStyle: fun(): number}?
C_InputInterfaceStyle = nil
---@type {Label: {Right: integer}}
MinimalSliderWithSteppersMixin = nil

---@param value number
---@param minimum number
---@param maximum number
---@return number
function Clamp(value, minimum, maximum) end
---@param value number
---@return number
function Saturate(value) end
---@param start number
---@param finish number
---@param amount number
---@return number
function Lerp(start, finish, amount) end

-- LibDBIcon and minimap addons supply this optional shared shape query.
---@type (fun(): string)?
GetMinimapShape = nil

---@param tooltip GameTooltip
---@param title string
---@param color? ColorMixin
---@param wrap? boolean
function GameTooltip_SetTitle(tooltip, title, color, wrap) end
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

-- The world map, as the addon reads it (UI/MapCanvas.lua lists every read): it adds no provider and acquires no pin.
---@class SPFMapCanvas : Frame
---@field ScrollContainer Frame
---@field dataProviders table<SPFMapProvider, boolean>
---@field GetMapID fun(self: SPFMapCanvas): number
---@field GetCanvas fun(self: SPFMapCanvas): Frame
---@field GetGlobalPinScale fun(self: SPFMapCanvas): number
---@field GetCanvasScale fun(self: SPFMapCanvas): number
---@field GetCanvasZoomPercent fun(self: SPFMapCanvas): number
---@field GetNormalizedCursorPosition fun(self: SPFMapCanvas): number, number
---@field GetPinFrameLevelsManager fun(self: SPFMapCanvas): {GetValidFrameLevel: fun(self: table, levelType: string, index?: number): number}
---@field AddCanvasClickHandler fun(self: SPFMapCanvas, handler: fun(map: SPFMapCanvas, button: string): boolean)
---@field AddGlobalPinMouseActionHandler fun(self: SPFMapCanvas, handler: fun(map: SPFMapCanvas, action: number, button: string): boolean)
---@type SPFMapCanvas
WorldMapFrame = nil
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
---@class SPFFlightPin : SPFMapPin
---@field poiInfo {nodeID: number, name: string, isUndiscovered: boolean}

-- Blizzard_GamepadMapCursor: the gamepad's cursor on the world map, read for its place.
---@type Frame
SoftCursor = nil

-- The Forever addons' world map markers, for each other (UI/MapCanvas.lua): each addon's function gives its shown
-- markers on a map, as map fractions.
---@type table<string, fun(map: SPFMapCanvas): {x: number, y: number, kind: string}[]>
ForeverMapMarkers = nil

---@class SPFQuestPin : SPFMapPin
---@field GetQuestID fun(self: SPFQuestPin): number?
---@field GetStyle fun(self: SPFQuestPin): number
---@class SPFQuestMenuOwner : Frame
---@field questID? number

---@class SPFTrackerLine : Frame
---@field Text FontString
---@field used boolean
---@class SPFTrackerBlock : Frame
---@field id number|string
---@field HeaderButton Button
---@field HeaderText FontString
---@field headerHeight number
---@field parentModule SPFTrackerModule
---@field isHighlighted boolean
---@field used boolean
---@field SetHeader fun(self: SPFTrackerBlock, text: string)
---@field AddObjective fun(self: SPFTrackerBlock, id: number|string, text: string, template?: string, wrap?: boolean, dashStyle?: number, color?: ColorMixin): SPFTrackerLine
---@field GetExistingLine fun(self: SPFTrackerBlock, id: number|string): SPFTrackerLine?
---@field SetStringText fun(self: SPFTrackerBlock, font: FontString, text: string, wrap: boolean?, color: ColorMixin, highlight?: boolean): number
---@class SPFTrackerHeader : Frame
---@field Text FontString
---@class SPFTrackerModule : Frame
---@field Header SPFTrackerHeader
---@field headerText string
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

---@class ForeverTrackerHostAPI
---@field IsAttachedToQuestTracker fun(): boolean
---@field SetAttached fun(attached: boolean)
---@field GetSettings fun(): ForeverTrackerSettings
---@field GetScale fun(): number
---@field SetScale fun(scale: number)
---@field OnAttachmentChanged fun(callback: fun(attached: boolean))
---@field SavePosition fun(x: number, y: number)
---@field IsLocked fun(): boolean
---@field SetLocked fun(value: boolean)
---@type ForeverTrackerHostAPI?
ForeverTrackerHost = nil

---@class SPFSetting
---@field SetValue fun(self: SPFSetting, value: boolean|number)
---@field SetValueChangedCallback fun(self: SPFSetting, callback: fun(setting: SPFSetting, value: boolean|number))
---@class SPFSettingsCategory
---@field GetID fun(self: SPFSettingsCategory): number
---@class SPFSettingsInitializer
---@class SPFSettings
---@field VarType {Boolean: string, Number: string}
---@field RegisterVerticalLayoutCategory fun(name: string): SPFSettingsCategory
---@field RegisterVerticalLayoutSubcategory fun(parent: SPFSettingsCategory, name: string): SPFSettingsCategory
---@field RegisterCanvasLayoutSubcategory fun(parent: SPFSettingsCategory, frame: Frame, name: string): SPFSettingsCategory
---@field RegisterProxySetting fun(category: SPFSettingsCategory, variable: string, variableType: string, name: string, default: boolean|number, getter: (fun(): boolean|number), setter: (fun(value: boolean|number))): SPFSetting
---@field NotifyUpdate fun(variable: string)
---@field RegisterAddOnSetting fun(category: SPFSettingsCategory, variable: string, key: string, storage: SPFDatabase, variableType: string, name: string, default: boolean|number): SPFSetting
---@field CreateSliderOptions fun(minimum: number, maximum: number, step: number): table
---@field CreateSliderInitializer fun(setting: SPFSetting, options: table, tooltip?: string): SPFSettingsInitializer
---@field CreateCheckboxInitializer fun(setting: SPFSetting, options?: table, tooltip?: string): SPFSettingsInitializer
---@field RegisterInitializer fun(category: SPFSettingsCategory, initializer: SPFSettingsInitializer)
---@field RegisterAddOnCategory fun(category: SPFSettingsCategory)
---@field OpenToCategory fun(id: number)
---@type SPFSettings
Settings = nil

-- Blizzard's settings button initializer, absent from the pinned annotations (Ketho/vscode-wow-api).
---@param name string
---@param description string
---@param callback function
---@param searchTags? table
---@param addSearchTags? boolean
---@return SPFSettingsInitializer
function CreateSettingsButtonInitializer(name, description, callback, searchTags, addSearchTags) end

---@class SPFUiMapPointFactory
---@field CreateFromVector2D fun(uiMapID: number, position: Vector2DMixin): UiMapPoint
---@field CreateFromCoordinates fun(uiMapID: number, x: number, y: number, z?: number): UiMapPoint
---@type SPFUiMapPointFactory
UiMapPoint = nil

EventUtil = {}
---@param callback function
---@param ... string
function EventUtil.ContinueAfterAllEvents(callback, ...) end

---@class ForeverTrackerSettings
---@field attached boolean
---@field locked? boolean the grip ignores drag while the tracker is locked
---@field scale? number tracker size, 1 is the stock size
---@field x? number
---@field y? number

---@class ForeverTrackerGrip
---@field Show fun(value: boolean) shows or hides the grip, which the host keeps hidden while attached
---@field SetLabel fun(value: boolean) redraws the label from the switch, without waiting for a hover

---@class ForeverTrackerOrderAPI
---@field Sort fun(modules: ForeverTrackerModule[]) orders the shared column's sections in place

---@class ForeverTrackerLock
---@field Locked fun(): boolean reads the saved switch through the host
---@field Grip fun(host: Frame, source: ForeverTrackerHostAPI): ForeverTrackerGrip draws the grip on the column it drags

---@class ForeverTrackerNamespace
---@field TrackerHost? ForeverTrackerHostAPI
---@field TrackerOrder? ForeverTrackerOrderAPI the section order, from UI/TrackerOrder.lua
---@field TrackerQuestie? ForeverTrackerQuestie Questie's quest list, from UI/TrackerQuestie.lua
---@field TrackerLock? ForeverTrackerLock the grip and its Lock switch, from UI/TrackerLock.lua
---@field TrackerHostSettings? fun(): ForeverTrackerSettings
---@field L table<string, string>
