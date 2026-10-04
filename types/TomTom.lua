---@meta

-- Third-party guides set waypoints through TomTom's API. While TomTom is not installed, Core/TomTom.lua answers
-- those calls with a Shortest Path journey, and this is the shape the guides expect to find.

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

---@class TomTom
---@field waypoints table<integer, table<string, TomTomWaypoint>> -- by map, then by key; this shim keeps one at a time
---@field AddWaypoint fun(self: TomTom, map: integer, x: number, y: number, opts?: TomTomWaypointOptions): TomTomWaypoint? -- uiMapID and 0-1 coordinates
---@field AddMFWaypoint fun(self: TomTom, map: integer, floor: number?, x: number, y: number, opts?: TomTomWaypointOptions): TomTomWaypoint? -- the map and the same 0-1 point
---@field AddZWaypoint fun(self: TomTom, continent: number?, zone: number, x: number, y: number, desc?: string, persistent?: boolean, minimap?: boolean, world?: boolean, callbacks?: table|false, silent?: boolean, crazy?: boolean): TomTomWaypoint? -- 0-100 coordinates
---@field RemoveWaypoint fun(self: TomTom, waypoint: TomTomWaypoint): boolean -- true when it cleared this shim's own waypoint

---@type TomTom?
TomTom = nil
