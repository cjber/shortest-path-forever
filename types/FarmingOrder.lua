---@meta

---@alias SPFFarmingOrderStatus 'working'|'ready'|'cancelled'|'invalid-input'|'invalid-world'
---@class SPFFarmingOrderJob
---@field status SPFFarmingOrderStatus
---@field nodes? SPFGatherMateNode[]
---@field Step fun(self: SPFFarmingOrderJob): SPFFarmingOrderStatus, SPFGatherMateNode[]? call at most once per client frame; results owned by this job
---@field Cancel fun(self: SPFFarmingOrderJob) permanent, discards any result
---@class SPFFarmingOrder
---@field Begin fun(nodes: SPFGatherMateNode[], player: SPFPoint): SPFFarmingOrderJob captures scalar snapshot; same-world projection required; closed geometric cycle, no terrain/time guarantee
