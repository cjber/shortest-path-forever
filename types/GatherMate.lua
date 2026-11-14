---@meta

---@alias SPFGatherMateKind "Herb Gathering"|"Mining"
---@alias SPFGatherMateStatus "ready"|"empty"|"absent"|"unsupported"|"not-ready"|"invalid-zone"|"invalid-kind"|"invalid-selection"|"invalid-record"|"unknown-name"|"provider-error"

-- Structural subset of the optional released GatherMate2 1.52.7 provider. gmdbs
-- is checked for readiness only; storage and profile filters belong to GatherMate.
---@alias SPFGatherMateIterator fun(state: any, coord?: number): number?, integer?

---@class SPFGatherMateProvider
---@field gmdbs? table<SPFGatherMateKind, table>
---@field GetNodesForZone fun(self: SPFGatherMateProvider, uiMapID: integer, kind: SPFGatherMateKind, ignoreFilter: boolean): SPFGatherMateIterator, any, number?
---@field DecodeLoc fun(self: SPFGatherMateProvider, coord: number): number, number
---@field GetNameForNode fun(self: SPFGatherMateProvider, kind: SPFGatherMateKind, nodeID: integer): string?

---@type SPFGatherMateProvider?
GatherMate2 = nil

-- Owned scalar fields only. (uiMapID, kind, coord, nodeID) is the identity;
-- title is a localized display label. x/y are map fractions in 0..1. This is
-- directly compatible with route stop fields, without promising a valid route.
---@class SPFGatherMateNode
---@field uiMapID integer
---@field kind SPFGatherMateKind
---@field coord number
---@field nodeID integer
---@field x number
---@field y number
---@field title string

---@class SPFGatherMate
---@field Snapshot fun(uiMapID: integer, kind: SPFGatherMateKind, selectedIDs?: table<integer, boolean>): SPFGatherMateNode[]?, SPFGatherMateStatus
---@field CurrentZone fun(kind: SPFGatherMateKind, selectedIDs?: table<integer, boolean>): SPFGatherMateNode[]?, SPFGatherMateStatus
