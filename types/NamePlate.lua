---@meta

-- The client's nameplates (Blizzard_NamePlates/NamePlateManager.lua): C_NamePlate answers the plate for a unit, and
-- each plate's UnitFrame carries the health bar the arrows anchor to. Nothing here writes to either.
---@class SPFNamePlateUnitFrame : Frame
---@field healthBar? StatusBar

---@class SPFNamePlate : Frame
---@field UnitFrame? SPFNamePlateUnitFrame

---@type {GetNamePlateForUnit: fun(unit: string): SPFNamePlate?}
C_NamePlate = nil

-- The arrows' own frame on UIParent: its two textures are anchored to the plate's health bar.
---@class SPFNpcArrowsFrame : Frame
---@field Left Texture
---@field Right Texture
