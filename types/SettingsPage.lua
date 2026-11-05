---@meta

-- The client surfaces Forever Core's shared settings-page chrome (UI/SettingsPage.lua, ns.SettingsPage) reads that
-- Ketho's pinned annotations do not carry, plus the one field the page adds to its own canvas frame. Signatures follow
-- Gethe/wow-ui-source forever @ (see tools/typecheck.sh for the pinned revision). These declarations never load in the
-- client.

-- The three templates the shared page creates, each the widget its row is: the return type of CreateFrame with a
-- template is the union of the template class and the widget class, and a template that is a widget does not have to
-- be cast back to one.
---@class InterfaceOptionsCheckButtonTemplate : CheckButton
---@class OptionsSliderTemplate : Slider
---@class SharedButtonSmallTemplate : Button

-- Settings: the canvas category the page registers itself as.
---@class Settings
---@field RegisterCanvasLayoutCategory fun(self: Settings, frame: Frame, name: string): table
---@field RegisterAddOnCategory fun(self: Settings, category: table)

-- The page keeps one cursor down its canvas, so every row claims its height.
---@class Frame
---@field settingsRowY? number

-- Forever Core's shared text fold (Core/Text.lua): Core/Way.lua folds a zone name and a typed name through it.
---@class SPFTextModule
---@field Fold fun(text: string?): string lower case with Latin accents folded, for matching only; nil reads as ""
---@field Rank fun(folded: string, query: string): integer? 0 an empty query, 1 the whole title, 2 a prefix, 3 a word
-- start, 4 anywhere, nil for no match

---@class SPFNamespace
---@field Text SPFTextModule
