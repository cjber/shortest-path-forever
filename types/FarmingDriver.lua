---@meta

---@class SPFFarmingController
---@field Start fun(self: SPFFarmingController, nodes: SPFGatherMateNode[]): boolean, string? accepts a flat immutable ordered snapshot, at least two distinct map locations
---@field Pause fun(self: SPFFarmingController): boolean commits only on accepted navigation transition
---@field Resume fun(self: SPFFarmingController): boolean
---@field Stop fun(self: SPFFarmingController)
---@field Status fun(self: SPFFarmingController): state: string, reason: string?, next: integer, cycles: integer state idle/running/paused/stopped/waiting; reason is the actual path or lifecycle failure, combat or corpse

---@class SPFFarmingFactory
---@field new fun(): SPFFarmingController

---@class SPFFarmingDriverBatch
---@field token SPFFarmingBatch
---@field done fun(reason: string)
---@field count integer
---@field owner string
---@field goal? SPFPoint
---@field unsubscribe? fun()
---@field arrived? boolean
---@field unobserve? fun()

---@class SPFNamespace
---@field ObserveFarmingJourney fun(owner: string, callback: fun(phase: string, index: integer, goal: SPFPoint, plan: SPFPlan?)): fun()
---@field FarmingJourneyProof fun(phase: string, goal: SPFPoint?, plan: SPFPlan?)
