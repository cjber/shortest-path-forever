---@class SPFRestedXPElement
---@field skip? boolean
---@field arrow? boolean
---@field hidden? boolean
---@field generated? number
---@field completed? boolean
---@field text? string
---@field parent? {completed: boolean?, skip: boolean?}
---@field zone? integer
---@field x? number
---@field y? number
---@field title? string
---@field step? {arrowtext: string?, title: string?, active: boolean?, index: integer?}

---@class SPFRestedXPArrow: Frame
---@field texture Texture
---@field text FontString
---@field wrongContinent? boolean
---@field element? SPFRestedXPElement

---@class SPFRestedXP
---@field arrowFrame SPFRestedXPArrow
---@field settings? {profile: {showEnabled: boolean?}}
---@field activeWaypoints? SPFRestedXPElement[]
---@field currentGuide? table
---@field hideArrow? boolean
---@field ResetArrowPosition? fun()
---@field UpdateMap fun(resetPins: boolean?)
---@field UpdateGotoSteps fun()

---@type SPFRestedXP?
RXP = nil

---@type {API: {RestedXPIntegrated?: fun(): boolean}}?
AdventureGuideForever = nil
