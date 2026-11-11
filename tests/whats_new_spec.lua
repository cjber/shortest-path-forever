-- After an update the addon says once what changed; a first install, the same version, a maintenance release, a
-- checkout and the setting turned off stay quiet, and a missing saved table never errors.
local version, printed, frame, handler = "1.4.0", {}, nil, nil
local env = setmetatable({
	C_AddOns = {
		GetAddOnMetadata = function(name, field)
			assert(name == "ShortestPathForever" and field == "Version")
			return version
		end,
	},
	CreateFrame = function()
		frame = {
			RegisterEvent = function(_, event)
				assert(event == "PLAYER_LOGIN")
			end,
			UnregisterEvent = function() end,
			SetScript = function(_, script, fn)
				assert(script == "OnEvent")
				handler = fn
			end,
		}
		return frame
	end,
}, { __index = _G })
local ns = {
	Init = function(fn)
		fn()
	end,
	Print = function(message)
		printed[#printed + 1] = message
	end,
}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
setfenv(assert(loadfile("UI/WhatsNew.lua")), env)("ShortestPathForever", ns)
assert(type(ns.WHATS_NEW) == "string" and ns.WHATS_NEW:find("%.$"), "one sentence")
local shippedVersion = assert(ns.WHATS_NEW_VERSION, "the release the headline belongs to")
assert(shippedVersion:match("^%d+%.%d+%.%d+$"), shippedVersion)

-- The next patch above the shipped release, the version a core sync's maintenance entry would carry.
local function Bump(release)
	local major, minor, patch = release:match("^(%d+)%.(%d+)%.(%d+)$")
	return ("%s.%s.%d"):format(major, minor, tonumber(patch) + 1)
end

local function login(db)
	ns.db = db
	handler(frame, "PLAYER_LOGIN")
	return db
end

-- First install: remember the version, say nothing.
local db = login({ whatsNew = true })
assert(#printed == 0 and db.seenVersion == "1.4.0")

-- Same version again: nothing.
login(db)
assert(#printed == 0)

-- A release with a headline: one line, then quiet on the next login.
version = shippedVersion
login(db)
assert(#printed == 1 and printed[1] == "updated to " .. shippedVersion .. ". " .. ns.WHATS_NEW, printed[1])
assert(db.seenVersion == shippedVersion)
login(db)
assert(#printed == 1)

-- A maintenance release above it, as a core sync adds: silent, and still remembered.
version = Bump(shippedVersion)
login(db)
assert(#printed == 1, "a maintenance release prints nothing new")
assert(db.seenVersion == version)

-- The setting off: quiet, and the version still moves on.
version, db.whatsNew = Bump(version), false
login(db)
assert(#printed == 1 and db.seenVersion == version)

-- A checkout reads the packager's keyword, not a version: quiet, and nothing stored.
version = "@" .. "project-version@"
local kept = db.seenVersion
login(db)
assert(#printed == 1 and db.seenVersion == kept)

-- The newest release with a bold lead, skipping the maintenance entries a core sync adds above it. Each entry is its
-- heading and the text up to the next versioned heading.
local function Releases(text)
	local found = {}
	local nextSearch = 1
	while true do
		local start, finish, release = text:find("\n## %[(%d+%.%d+%.%d+)%] %- %d%d%d%d%-%d%d%-%d%d\n", nextSearch)
		if not start then
			return found
		end
		local following = text:find("\n## %[", finish + 1)
		found[#found + 1] = { version = release, body = text:sub(finish + 1, (following or #text + 1) - 1) }
		nextSearch = finish + 1
	end
end

local function Headline(text)
	for _, release in ipairs(Releases("\n" .. text)) do
		local headline = release.body:match("%- %*%*(.-)%*%*")
		if headline then
			return release.version, headline
		end
	end
end

-- The shipped version and headline are the newest release's with a bold lead, so a release that forgets to rewrite
-- them fails here instead of announcing the release before it.
local changelog = assert(io.open("CHANGELOG.md")):read("*a")
local newestVersion, newestHeadline = Headline(changelog)
assert(
	newestVersion == ns.WHATS_NEW_VERSION,
	("UI/WhatsNew.lua is release %s, CHANGELOG.md's newest headline release is %s"):format(
		tostring(ns.WHATS_NEW_VERSION),
		tostring(newestVersion)
	)
)
assert(newestHeadline == ns.WHATS_NEW, "UI/WhatsNew.lua carries that release's headline")

-- A core sync's maintenance entry has no bold lead, so the headline above it is the one a player still sees.
local maintenance = table.concat({
	"## [9.9.9] - 2026-11-12",
	"",
	"<!-- forever-core-sync -->",
	"",
	"- Ships with the same shared code as your other Forever addons, so they keep working together.",
	"",
	"## [9.9.8] - 2026-11-11",
	"",
	"- **A real headline.** What it says.",
}, "\n")
local maintenanceVersion, maintenanceHeadline = Headline(maintenance)
assert(maintenanceVersion == "9.9.8", "a maintenance entry on top is skipped for the newest version")
assert(maintenanceHeadline == "A real headline.", "and for its headline")

print("whats_new_spec: ok")
