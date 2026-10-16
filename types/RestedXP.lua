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

-- One of Adventure Guide's cards, as its API.Suggestions answers (minor 2).
---@class SPFAdventureSuggestion
---@field id string
---@field title string
---@field level? integer
---@field kind string
---@field map integer
---@field x? number
---@field y? number

-- Adventure Guide's API once it has both suggestion calls (UI/FamilyHints.lua checks before using them).
---@class SPFAdventureSuggestionsAPI
---@field Suggestions fun(limit?: integer): SPFAdventureSuggestion[]?
---@field StartSuggestion fun(id: string): boolean

---@class SPFRestedXPFrontendAPI
---@field Suggestions? fun(limit?: integer): SPFAdventureSuggestion[]?
---@field StartSuggestion? fun(id: string): boolean
---@field ResumeRestedXP? fun(): boolean
---@field RestedXPIntegrated? fun(): boolean
---@field RestedXPNativeUI? fun(): boolean

---@type {API: SPFRestedXPFrontendAPI}?
AdventureGuideForever = nil
