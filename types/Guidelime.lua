---@meta

-- Guidelime 6.017 (CurseForge 327139) publishes these two globals; its current step is the target its arrow
-- points at. Nothing else of Guidelime's addon table is read.

---@class SPFGuidelimeElement
---@field t? string the parsed code, such as TEXT, APPLIES, ACCEPT or TARGET
---@field mapID? integer
---@field x? number percent of the map
---@field y? number percent of the map
---@field title? string the name the guide wrote into the code
---@field text? string the guide's own words, already parsed out of the line
---@field questId? integer|string a string only for a guide parsed leniently
---@field targetNpcId? integer
---@field useItemId? integer
---@field itemId? integer
---@field radius? number
---@field completed? boolean
---@field attached? SPFGuidelimeElement the quest element a generated step was made for
---@field step? {text: string?, active: boolean?, index: integer?, elements: SPFGuidelimeElement[]?}

---@class SPFGuidelimeArrow: Frame
---@field element? SPFGuidelimeElement
---@field texture Texture
---@field text FontString

---@class SPFGuidelimeAddon
---@field registerGuide? fun(guide: table, group: string?)

---@type SPFGuidelimeAddon?
Guidelime = nil

---@type SPFGuidelimeArrow?
GuidelimeArrow = nil
