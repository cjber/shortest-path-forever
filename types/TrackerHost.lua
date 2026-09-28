---@meta
-- Blizzard_SharedXML/Pool.lua; addon-owned instances, never ObjectiveTrackerManager's pool.
---@class ForeverPrivateFramePool
---@field Acquire fun(self: ForeverPrivateFramePool, template: string): Frame, boolean
---@class ForeverPrivatePoolCollection
---@field GetOrCreatePool fun(self: ForeverPrivatePoolCollection, frameType: string, parent: Frame, template: string): ForeverPrivateFramePool
---@field Release fun(self: ForeverPrivatePoolCollection, frame: Frame)
---@return ForeverPrivatePoolCollection
function CreateFramePoolCollection() end
