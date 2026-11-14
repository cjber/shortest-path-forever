---@meta

-- Public addon-to-addon interface. Coordinates are uiMapID and normalized 0-1 x/y, not world yards.
-- Version 2 removes the peer and leaderboard surface. Callers must accept versions 1 and 2, and reject future versions.

---@alias SPFAPIMode "walk"|"flight"|"boat"|"zeppelin"|"lift"|"tram"|"portal"|"passage"|"teleport"
---@alias SPFAPINoRoute "combat"|"invalid"|"unreachable"|"loading" -- retry after combat; never for bad input; unreachable with what this character knows; loading while the addon builds its data

---@alias SPFAPIEnded "arrived"|"cleared"|"replaced"|"cancelled" -- reached the last stop; the player cleared it; another journey took over; the owner's own Cancel

---@alias SPFAPINotReady "loading"|"none" -- still building the data; nothing to answer

--- Why Guidance has no point to give: loading while the addon or its first plan is still being built, none with no
--- journey, paused while guidance is off or waiting at a held stop, disabled when Journeys is switched off, cast when
--- a teleport must be cast where the player stands, and unavailable when a point cannot be placed on this client.
---@alias SPFAPIGuidanceReason "loading"|"none"|"paused"|"disabled"|"cast"|"unavailable"

-- What stands at a stop. Its numbered pin on the world map wears that mark (a quest's "!" or "?", a trainer, a
-- flight master, a dock) as a small badge on its lower right, a lone stop shows the mark alone, and the minimap
-- rings the spot instead of covering the game's own icon there.
---@alias SPFAPIStopKind "pickup"|"turnin"|"objective"|"trainer"|"innkeeper"|"flightmaster"|"battlemaster"|"dungeon"|"boat"|"zeppelin"|"lift"|"tram"|"portal"|"vendor"

--- An objective area a held stop stands for: a circle on one map. Circles are never drawn: they decide whether the
-- player stands in the area when the stop names no quest, or the client has no answer for the quests it names.
---@class SPFAPIShape
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1
---@field radius number -- yards, finite and nonnegative

---@class SPFAPIStop
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1
---@field z? number -- world height in yards; above or below the terrain there, the stop pin wears the map's arrow
---@field title? string
---@field tooltip? string -- optional destination detail shown on the stop pin tooltip, never used as the arrow label
---@field kind? SPFAPIStopKind -- any other value is ignored and the stop keeps the plain pin
---@field hold? boolean -- keep guidance at this stop until the caller submits an updated route
---@field radius? number -- yards around a held stop where travel cues pause; finite and nonnegative
---@field questID? number -- the quest this held stop's area belongs to; the client's own "inside the area" state for it decides inside, and the client's own area for it is shown while the player is inside
---@field questIDs? number[] -- every quest the area belongs to, when it has several: 1 or more positive integers; inside any of them is inside, and each one's area is shown. May be given with or without questID
---@field handins? number[] -- the quests handed in at this stop: 1 or more positive integers; the game's own pin for each is hidden while the stop is drawn, and they never decide arrival or the stop's area
--- The NPC whose service this stop reaches. Shortest Path marks that NPC's nameplate while the stop is current.
--- Another addon's route passes no npc, so its own highlight is the only one.
---@field npc? integer
---@field shapes? SPFAPIShape[] -- objective areas a held stop stands for; they decide inside when no quest is named or the client has no answer, and are never drawn

---@class SPFAPILeg
---@field mode SPFAPIMode
---@field to string -- where the leg ends, named as SPF's tracker names it
---@field seconds number -- from the previous leg's arrival (the first from the start), waits included
---@field wait? number -- seconds waiting for a boat, zeppelin, lift or tram; present only from 60 up
---@field newFlightPath? boolean -- true on a walk to a flight master this character has not discovered

---@class SPFAPIDetail
---@field seconds number -- equal to Estimate's answer
---@field legs SPFAPILeg[] -- fresh copies on every call, never SPF's own tables

--- A place as the API names it: a uiMapID and normalized 0-1 coordinates.
---@class SPFAPIPlace
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1

--- Where a journey ends: a place, and the goal's own title.
---@class SPFAPIJourneyGoal : SPFAPIPlace
---@field title string -- the stop's title, or where it stands when it has none

--- One leg still ahead, as the tracker words it, with the leg's own ends as the planner drew them.
---@class SPFAPIJourneyLeg
---@field mode SPFAPIMode
---@field text string -- the step's action words, plain and without the tracker's colours
---@field seconds number -- this leg's own whole seconds, its wait included
---@field from? SPFAPIPlace -- where the leg starts, as the planner's own leg points name it; absent when this client cannot place it
---@field to? SPFAPIPlace -- where the leg ends; absent when this client cannot place it

--- The journey under way, whoever owns it.
---@class SPFAPIJourney
---@field owner? string -- the addon that owns it; absent for the player's own journey
---@field goal SPFAPIJourneyGoal
---@field legs SPFAPIJourneyLeg[] -- fresh copies from the leg under way to the goal
---@field index integer -- the 1-based leg under way
---@field guided boolean -- whether guidance is on
---@field secondsLeft number -- whole seconds from the leg under way to the goal, as the tracker header shows it

--- The guidance another addon steers by: the next point the arrow leads to and the whole source walk of the leg under
--- way, as fresh copies on every call.
---@class SPFAPIGuidance
---@field owner? string -- the addon that owns the journey; absent for the player's own journey and a corpse run
---@field leg integer -- the 1-based leg under way in Journey()
---@field point SPFAPIPlace -- the next point the arrow leads to
---@field waypoints SPFAPIPlace[] -- every bend of the leg under way, from the route's original source walk
---@field index integer -- where point stands in waypoints: 1-based, so waypoints[index] is that point

--- One travel record of this character's.
---@class SPFAPIStat
---@field addon string -- always "ShortestPathForever"
---@field metric string -- "distance_yards", "routes_completed", "transports_used", "flights_taken" or "portals_used"
---@field subject string -- always "all"
---@field value number
---@field eventUnix? number -- absent: the travel journal records no event time

--- One player's row on the all-time travel board.
--- What happened to guidance since the subscriber was last called; each field is true or absent. Several can be
--- true together, from one burst of changes.
---@class SPFAPIChanges
---@field started? boolean -- a journey began where none was under way
---@field changed? boolean -- the journey under way now heads somewhere else: replaced by a new one, or on to its next stop
---@field ended? boolean -- the journey under way ended, with nothing after it
---@field stop? boolean -- what CurrentStop answers changed: an addon's route started, moved on to another stop or ended
---@field leg? boolean -- the leg under way moved on without the goal changing: the player or an owner skipped it
---@field guidance? boolean -- the guidance point changed: a bend passed within the leg, the leg or its source walk
--- replaced, or guidance started or ended
---@field replan? boolean -- the plan was worked out again: the first plan is ready, a new route replaced the
--- followed one, or its walks were redrawn; read Journey() again, since its legs' from and to may have changed
---@field active? boolean -- what Active answers changed

---@class SPFPublicAPI
---@field version integer -- 2 removes peer sharing and Leaderboard; callers accept 1 or 2 and reject future versions
---@field minor integer -- 2 adds each journey leg's from and to, ResumeRestedXP and the replan change; 1 adds Guidance and the guidance change; version 1 minor 3 added Journey, Pause, Resume, SkipLeg, Stats and the leg change
---@field Estimate fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): seconds: number?, reason: SPFAPINoRoute? -- travel seconds; nil comes with the reason
---@field Navigate fun(owner: string, map: integer, x: number, y: number, title?: string, kind?: SPFAPIStopKind): boolean -- starts/replaces guidance outside combat when journeys are enabled
---@field NavigateRoute fun(owner: string, stops: SPFAPIStop[]): boolean -- starts/replaces guidance through 1-64 stops in order; false leaves the current journey intact
---@field CurrentStop fun(owner: string): index: integer?, reason: SPFAPINotReady? -- 1-based current stop, or nil and why there is none
---@field Cancel fun(owner: string): boolean -- true only when this owner's current journey was cancelled
---@field Journey fun(): journey: SPFAPIJourney?, reason: SPFAPINotReady? -- the journey under way, whoever owns it, or nil and why there is none
---@field Guidance fun(): guidance: SPFAPIGuidance?, reason: SPFAPIGuidanceReason? -- the next point the arrow leads to and every bend of the leg under way, as fresh copies, or nil and why there is no point
---@field Pause fun(owner: string): boolean -- stops that owner's guidance and keeps its goal; false for another owner, no journey, an already stopped journey or combat
---@field Resume fun(owner: string): boolean -- starts that owner's guidance again on the same goal; false for another owner, no journey, an already guided journey or combat
---@field SkipLeg fun(owner: string, index?: integer): boolean -- advances that owner's current leg; false for another owner or when nothing was skipped
---@field ResumeRestedXP fun(): success: true?, reason: ("invalid"|"unavailable")? -- resumes the RestedXP guide the player follows, or nil and why it could not
---@field Stats fun(): rows: SPFAPIStat[]?, reason: SPFAPINotReady? -- this character's travel records, one fresh row per metric
---@field RenameStop fun(owner: string, index: integer, title: string, renamePoints?: fun(point: SPFPoint): boolean?): boolean -- relabels a running route's stop in place; false leaves it as it was
---@field EstimateDetail fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): detail: SPFAPIDetail?, reason: SPFAPINoRoute? -- Estimate leg by leg, sharing its cache
---@field Active fun(): boolean -- true while any journey is guiding, whoever started it
---@field Ended fun(owner: string): reason: (SPFAPIEnded|SPFAPINotReady)?, at: (number|SPFAPINotReady)? -- why owner's last journey ended and its GetTime(), or nil and why there is none
---@field Subscribe fun(callback: fun(changes: SPFAPIChanges)): unsubscribe: fun() -- calls back at most once per burst of journey changes, the next frame; errors go to the game's error handler

---@class SPFPublicAddon
---@field API SPFPublicAPI
ShortestPathForever = {}
