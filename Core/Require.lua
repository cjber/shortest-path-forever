local _, ns = ...

-- The game refuses to load this addon when ForeverCore is absent (## Dependencies), but an older ForeverCore still
-- loads. Its API version and the kit this addon's own API is built on say whether it has everything called here, so an
-- out-of-date one stops the addon's own files with one line on screen, never a chat message.
if ForeverCore == nil or (ForeverCore.API or 0) < 1 or ForeverCore.APIKit == nil then
	ns.broken = true
	local errors = rawget(_G, "UIErrorsFrame")
	if errors then
		errors:AddMessage("Shortest Path Forever needs ForeverCore, which is missing or too old.", 1, 0.1, 0.1)
	end
end
