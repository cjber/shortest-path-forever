---@meta

-- Third-party guides set waypoints through TomTom's API. While TomTom is not installed, Core/TomTom.lua answers
-- those calls with a Shortest Path journey, and this is the shape the guides expect to find. While TomTom is installed,
-- the same file can follow its arrow through TomTom's own SetCrazyArrow.

---@class TomTomWaypointOptions
---@field title? string -- what the waypoint is for, used as the journey's title
---@field from? string -- the addon that set it, copied onto the waypoint
---@field crazy? boolean
---@field persistent? boolean
---@field minimap? boolean
---@field world? boolean
---@field silent? boolean
---@field callbacks? table|false
---@field cleardistance? number
---@field arrivaldistance? number

---@class TomTomWaypoint
---@field [integer] number -- map, then x and y in 0-1
---@field title? string
---@field from? string
---@field corpse? boolean -- TomTom's own corpse waypoint (TomTom_Corpse.lua)

---@class TomTom
---@field waypoints table<integer, table<string, TomTomWaypoint>> -- by map, then by key; this shim keeps one at a time
---@field AddWaypoint fun(self: TomTom, map: integer, x: number, y: number, opts?: TomTomWaypointOptions): TomTomWaypoint? -- uiMapID and 0-1 coordinates
---@field AddMFWaypoint fun(self: TomTom, map: integer, floor: number?, x: number, y: number, opts?: TomTomWaypointOptions): TomTomWaypoint? -- the map and the same 0-1 point
---@field AddZWaypoint fun(self: TomTom, continent: number?, zone: number, x: number, y: number, desc?: string, persistent?: boolean, minimap?: boolean, world?: boolean, callbacks?: table|false, silent?: boolean, crazy?: boolean): TomTomWaypoint? -- 0-100 coordinates
---@field RemoveWaypoint fun(self: TomTom, waypoint: TomTomWaypoint): boolean -- true when it cleared this shim's own waypoint
---@field SetCrazyArrow? fun(self: TomTom, waypoint: TomTomWaypoint, arrival?: number, title?: string) -- TomTom's own: points its arrow at a waypoint
---@field ClearWaypoint? fun(self: TomTom, waypoint: TomTomWaypoint) -- TomTom's own: takes a waypoint off the maps; every removal goes through it
---@field IsValidWaypoint? fun(self: TomTom, waypoint: TomTomWaypoint): boolean -- TomTom's own: whether the waypoint is still set
---@field WaypointExists? fun(self: TomTom, map: integer, x: number, y: number, desc?: string): boolean -- a waypoint with this map, point and title is set
---@field ClearAllWaypoints? fun(self: TomTom) -- every waypoint off; the shim cancels its journey
---@field GetClosestWaypoint? fun(self: TomTom): TomTomWaypoint? -- the shim keeps one, so it is the closest
---@field SetClosestWaypoint? fun(self: TomTom): TomTomWaypoint? -- points at the closest; the shim's journey already goes there
---@field GetDistanceToWaypoint? fun(self: TomTom, waypoint: TomTomWaypoint): number? -- yards from you, on your continent
---@field AddWaypointToCurrentZone? fun(self: TomTom, x: number, y: number, desc?: string): TomTomWaypoint? -- 0-100 coordinates on the map you are on

---@type TomTom?
TomTom = nil

-- Polestar (fitzforge/polestar), only as far as Core/TomTom.lua reads it: its own TomTom stand-in, to tell it from
-- TomTom, whether it hands its target to Shortest Path, and its settings through its Get.
---@class SPFPolestarNav
---@field tomtomShim? TomTom
---@field HandedOff? fun(): boolean -- whether Polestar hands its target to Shortest Path rather than guiding it

---@class SPFPolestar
---@field Nav? SPFPolestarNav
---@field Get? fun(path: string): any

---@type SPFPolestar?
Polestar = nil
