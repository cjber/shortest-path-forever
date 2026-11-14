---@meta

-- Flat source-independent scalar records. The controller validates/project stops before start;
-- the cursor preserves their supplied order and copies them without selecting or dropping locations.
---@alias SPFFarmingCursorNode table<string, string|number|boolean>

---@class SPFFarmingBatch
---@field generation integer session identity, invalidated before cancellation
---@field serial integer monotonically increasing batch identity within this cursor
---@field last integer final snapshot index in this batch

---@class SPFFarmingCursorDriver
---@field busy fun(): boolean synchronous internal journey ownership check, including unowned journeys
---@field defer fun(callback: fun()) queue a later frame, never invoke inline
---@field submit fun(nodes: SPFFarmingCursorNode[], token: SPFFarmingBatch, done: fun(reason: string)): boolean no yield between ownership check and submission; unique owner per token; report arrived only after verifying batch ownership and terminal state
---@field pause fun(token: SPFFarmingBatch): boolean commit pause only on successful navigation pause
---@field resume fun(token: SPFFarmingBatch): boolean commit resume only on successful navigation resume
---@field cancel fun(token: SPFFarmingBatch) cancel only this token's owned journey

---@class SPFFarmingCursorState
---@field generation integer
---@field serial integer
---@field state 'idle'|'running'|'paused'|'stopped'
---@field reason? string
---@field nodes SPFFarmingCursorNode[]
---@field next integer next uncommitted snapshot index
---@field cycles integer completed visits to the entire snapshot
---@field pending? SPFFarmingBatch
---@class SPFFarmingCursor: SPFFarmingCursorState
---@field start fun(self: SPFFarmingCursor, nodes: SPFFarmingCursorNode[]): boolean nonempty dense ordered flat snapshot; invalid nested records assert before replacing the active session
---@field pause fun(self: SPFFarmingCursor): boolean
---@field resume fun(self: SPFFarmingCursor): boolean
---@field stop fun(self: SPFFarmingCursor)
