---@meta

---@class SPFFarmingChoice : CheckButton
---@field Label FontString

---@class SPFFarmingWindow : Frame
---@field SetTitle fun(self: SPFFarmingWindow, title: string)
---@field GetPortrait fun(self: SPFFarmingWindow): Texture

---@class SPFNamespace
---@field OpenFarming fun() opens the current-zone recorded-location chooser
---@field Farming SPFFarmingFactory
---@field FarmingOrder SPFFarmingOrder
---@field GatherMate SPFGatherMate
