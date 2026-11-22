---@meta

-- OpenMap's public API for other addons (its API.lua, release v0.5.0-beta: major 1, version 2). Read-only, and every
-- call is safe before the map has opened. UI/OpenMap.lua reads these only when the corresponding functions exist.
---@class OpenMapAPI
---@field major number
---@field version number
---@field IsStitched fun(): boolean
---@field CanvasFromWorldPos? fun(continent: number, x: number, y: number): number?, number?
---@field WorldFromMap? fun(uiMapID: number, x: number, y: number): number?, number?
---@field ArtTopLevel? fun(): number?

---@type OpenMapAPI?
OpenMapAPI = nil
