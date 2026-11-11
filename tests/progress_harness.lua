local TOC = dofile("tests/toc_fields.lua").read("ShortestPathForever.toc")

local function harness(saved, progress, leaderboards)
	local h = { now = 1000, timers = {}, frames = {}, sent = {}, guild = true, group = true, printed = {}, toc = TOC }
	local ns = {
		db = saved or { stats = true, statsShare = true },
		charDB = { progress = progress },
		Leaderboards = leaderboards,
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		Init = function(fn)
			fn()
		end,
		OnTravelTick = function() end,
		JourneyPosition = function() end,
		FormatDistance = function(value)
			return value .. " yd"
		end,
		Print = function(line)
			h.printed[#h.printed + 1] = line
		end,
		core = {
			SafeCall = function(_, fn, ...)
				return pcall(fn, ...)
			end,
		},
	}
	local env = setmetatable({
		GetTime = function()
			return h.now
		end,
		GetServerTime = function()
			return math.floor(h.now)
		end,
		GetRealmName = function()
			return "Test Realm"
		end,
		GetNormalizedRealmName = function()
			return "TestRealm"
		end,
		UnitName = function()
			return "Tester"
		end,
		IsInGuild = function()
			return h.guild
		end,
		IsInGroup = function(category)
			return not category and h.group
		end,
		IsInRaid = function()
			return false
		end,
		C_AddOns = {
			GetAddOnMetadata = function(name, field)
				return name == "ShortestPathForever" and TOC[field] or nil
			end,
		},
		C_ChatInfo = {
			RegisterAddonMessagePrefix = function()
				return true
			end,
			SendAddonMessage = function(prefix, payload, channel)
				h.sent[#h.sent + 1] = { prefix = prefix, payload = payload, channel = channel }
				return 0
			end,
		},
		C_Timer = {
			After = function(delay, fn)
				h.timers[#h.timers + 1] = { at = h.now + delay, fn = fn }
			end,
		},
		CreateFrame = function()
			local frame = { RegisterEvent = function() end }
			function frame:SetScript(name, fn)
				self[name] = fn
			end
			h.frames[#h.frames + 1] = frame
			return frame
		end,
	}, { __index = _G })
	env._G = env
	local ForeverCore = dofile("tests/forever_core.lua")
	local coreNs = ForeverCore.load(env, "ForeverCore", { "Locales/enUS.lua", "Core/PeerStats.lua" })
	env.ForeverCore = {
		API = 1,
		APIKit = { Hub = function() end, NotReady = function() end },
		TrackerSection = { Create = function() end, UpdateText = function() end },
		TrackerLine = { SetInteractive = function() end },
		PeerStats = coreNs.PeerStats,
		Leaderboards = leaderboards or { Register = function() end, Open = function() end },
	}
	ns.PeerStats = coreNs.PeerStats
	setfenv(assert(loadfile("Core/ForeverRequire.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("Core/Require.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("Core/Progress.lua")), env)("ShortestPathForever", ns)
	function h:Fire(event, ...)
		for _, frame in ipairs(self.frames) do
			frame:OnEvent(event, ...)
		end
	end
	function h:Tick(seconds)
		self.now = self.now + (seconds or 1)
		local pending = self.timers
		self.timers = {}
		for _, timer in ipairs(pending) do
			if timer.at <= self.now then
				timer.fn()
			else
				self.timers[#self.timers + 1] = timer
			end
		end
	end
	h.ns = ns
	return h
end

return harness
