local MAJOR_VERSION, MINOR_VERSION = "iLib", 6
if not LibStub then error(MAJOR_VERSION .. " requires LibStub") end

local iLib, oldLib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not iLib then
	return
end
LibStub("AceComm-3.0"):Embed(iLib) -- we need this to communicate with other users for version syncing

local _G = _G

local ME_UPDATE, EQUAL, USER_UPDATE = 1, 2, 3 -- currently we only use USER_UPDATE to check if we need to send an update message

local inGroup = false -- determines if we are in a group
local addonsChanged = false -- determines if new mods registered with the iLib
local player = _G.GetUnitName("player")

local askGuild = true -- will be false if we sent a version sync message to the guild
local askGroup = true -- ...to the group
local askPVP   = true -- ...to the battleground

local Embed -- will become a function later

iLib.mods = iLib.mods or {}
setmetatable(iLib.mods, {__newindex = function(t, k, v) -- new indexes in iLib.mods will cause addonsChanged to be true
	rawset(t, k, v)
	addonsChanged = true
end})

iLib.update = iLib.update or {} -- stores ADDONNAME/VERSION pairs if there is an update for us

-- this makes sync messages unreadable and shorter
local function msgencode(msg) return LibStub("LibCompress"):CompressHuffman(msg) end
-- this makes it readable again
local function msgdecode(msg) return LibStub("LibCompress"):DecompressHuffman(msg) end

-- iLib currently uses two version syncing commands in the game:
--  ?%addon1%version1%addon2%version2%..%addonN%versionN - asks other players if we are up to date
--  !%addon1%version1%..%addonN%versionN - the respond only(!) includes addons which can be updated
--  If playerX asked for updates, playerY will respond. If playerY isn't up to date, too, there is another !-message fired
local send_ask_message
do
	local ask_str
	
	send_ask_message = function(chat)
		if addonsChanged then
			ask_str = "?"
			for k, v in pairs(iLib.mods) do
				ask_str = ask_str.."%"..k.."%"..v
			end
			addonsChanged = false
		end
		iLib:SendCommMessage("iLib", msgencode(ask_str), chat, nil, "BULK")
	end
end

local send_update_message
do
	local t = {}
	
	send_update_message = function(user, ...)
		local addon, version, chat
		for i = 1, select("#", ...), 2 do
			addon, chat = select(i, ...), select(i+1, ...)
			version = iLib.mods[addon]
			if not t[chat] then
				t[chat] = {}
			end
			table.insert(t[chat], addon)
			table.insert(t[chat], version)
		end
		
		for chat, mods in pairs(t) do
			iLib:SendCommMessage("iLib", msgencode("!%"..table.concat(mods, "%")), chat, (chat == "WHISPER" and user or nil))
			t[chat] = nil
		end
		t[''] = 1
		t[''] = nil
	end
end

-- iLib doesn't fire a message for every addon to be updated, it stores this kind of information in the "warn-list"
-- The warn-list is a table, accessed by the name of the user, which holds an array with some informations.
-- Each necessary update consists of two indexes in this array.
--  index 1: the addon name
--  index 2: the chat where to communicate
function add_user_warn(user, addon, chat)
	if not iLib.frame.warn[user] then
		iLib.frame.warn[user] = {}
	end
	if not _G.tContains(iLib.frame.warn[user], addon) then
		table.insert(iLib.frame.warn[user], addon)
		table.insert(iLib.frame.warn[user], chat)
	end
end

-- The OnUpdate scripts, which currently just can warn users for a new addon version
local warnTime, warnExec
local function iLib_OnUpdate(self, elapsed)
	if not warnExec then return end
	self.warnElapsed = self.warnElapsed + elapsed
	if self.warnElapsed >= warnTime then
		for user, v in pairs(self.warn) do
			send_update_message(user, unpack(self.warn[user]))
			self.warn[user] = nil
		end
		self.warn[''] = 1
		self.warn[''] = nil
		warnExec = false
	end
end

-- On received a comm message, we check if its another player and warn him, if his versions are lower than ours
-- We also warn player, if they warn another player, but with as well too low versions
function iLib:CommReceived(prefix, msg, chat, user)
	msg = msgdecode(msg)
	--@do-not-package@
	print(user.." ("..chat..") - "..msg)
	--@end-do-not-package@
	if user == player then
		return
	end
	local addon, version
	local t = {strsplit("%", msg)}
	
	if t[1] == "?" or t[1] == "!" then
		for i = 2, #t, 2 do
			addon, version = t[i], t[i+1]
			if self:Compare(addon, tonumber(version)) == USER_UPDATE then
				add_user_warn(user, addon, chat)
			end
		end
	end
end
iLib:RegisterComm("iLib", "CommReceived")

-- Event Handler
-- If we are logging in, we send Ask querys to guild (if in guild), group (if in group), pvp (if in pvp)
-- And if our guild changes or the group changes
local function iLib_OnEvent(self, event)
	if askGuild and (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE") then
		if _G.IsInGuild() then
			askGuild = false
			send_ask_message("GUILD")
		end
	end
	if askGroup and (event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE") then
		if _G.IsInRaid() or _G.IsInGroup() then
			if not inParty then
				inGroup = true
				askGroup = false
				send_ask_message("RAID")
			end
		else
			inGroup = false
			askGroup = true
		end
	end
	if askPVP and event == "PLAYER_ENTERING_WORLD" then
		if _G.UnitInBattleground("player") then
			askPVP = false
			send_ask_message("BATTLEGROUND")
		end
	end
end

-- This function inits our frame which will listen for events and OnUpdates
local function init_frame()
	local f = _G.CreateFrame("Frame")	
	f.warn = {}
	f.warnElapsed = 0
	setmetatable(f.warn, {__newindex = function(t, k, v)
		warnTime = (random(9.5, 50) / 10)
		warnExec = true
		f.warnElapsed = 0
		rawset(t, k, v)
	end})
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PLAYER_GUILD_UPDATE")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:SetScript("OnEvent", iLib_OnEvent)
	f:SetScript("OnUpdate", iLib_OnUpdate)
	return f
end
iLib.frame = iLib.frame or init_frame()

-- Smart version creator
-- It loads the version from the TOC. If its a number, it gets returned
-- If not, we bet that its a string in the format major.minor.rev or at least major.minor
local function smart_version_number(addon)
	local aver = _G.GetAddOnMetadata(addon, "Version") or 1
	if tonumber(aver) then
		return aver
	end
	local _, _, major, minor, rev = string.find(aver, "(%d).?(%d?).?(%d?)")
	major = tonumber(major) and major or 0
	minor = tonumber(minor) and minor or 0
	rev   = tonumber( rev ) and  rev  or 0
	return (major * 10000) + (minor * 1000) + rev
end

--- Registers an addon with the iLib
-- @param addonName Your addon's name. Please use the same name as in the TOC (for smart versioning).
-- @param version The version as number. If its a string or nil, iLib trys to create a number from it (e.g. 2.1.0 => 21000)
-- @param addonTable Your addon table. Only use if you want to use the iLib tooltip handler.
-- @return Returns true if registration was successful.
-- @usage -- without tooltip handling
-- LibStub("iLib"):Register("MyAddon")
-- LibStub("iLib"):Register("MyAddon", 10200)
-- 
-- -- with tooltip handling
-- LibStub("iLib"):Register("MyAddon", nil, myAddon)
-- LibStub("iLib"):Register("MyAddon", 10200, myAddon)
function iLib:Register(addonName, version, addonTable)
	if not addonName then
		error("Usage: Register(addonName [, version [, addonTable]])")
	end
	
	if not self:IsRegistered(addonName) then
		-- no version provided by addon, so we create it by ourselves
		if not tonumber(version) then
			version = smart_version_number(addonName)
		end
		self.mods[addonName] = version
		-- an addon table is present, so we embed the tooltip functions into it
		if type(addonTable) == "table" then
			Embed(addonTable, addonName)
		end
		return true
	end
	return false
end

--- Checks whether there is an update for the given addon or not.
-- @param addonName The name of the addon.
-- @return False if no update, the version number if update.
-- @usage local update = iLib:IsUpdate("myAddon")
-- print(update and "New version: "..update or "No updates at all")
function iLib:IsUpdate(addonName)
	if self.mods[addonName] and self.update[addonName] then
		return self.update[addonName]
	end
	return false
end

--- Checks if the given addon is registered with the iLib.
-- @param addonName The name of your addon.
-- @return Returns true if the addon is registered.
-- @usage if LibStub("iLib"):IsRegistered("MyAddon") then
--   -- do something
-- end
function iLib:IsRegistered(addonName)
	if not addonName then
		error("Usage: IsRegistered( \"AddonName\" )")
	end

	return self.mods[addonName] and true or false
end

--- Compares the given addon and version with an addon registered with the iLib.
-- @param addonName The name of the addon to compare with.
-- @param version The version to compare with.
-- @return Returns a number which indicates the result:
-- * 1 = The version is higher than ours. We need to update. In this case, iLib automatically stores the new version number for further use.
-- * 2 = Both versions are equal. This is also returned if the given addon isn't registered with iLib.
-- * 3 = We have a higher version installed.
-- @usage if LibStub("iLib"):Compare("MyAddon", 2034) == 3 then
--   SendChatMessage("addon update: "..addonName, "WHISPER", nil, "user")
-- end
function iLib:Compare(addonName, version)
	if not addonName or not version then
		error("Usage: IsRegistered( \"AddonName\" , version)")
	end
	
	if not self:IsRegistered(addonName) then
		return EQUAL
	end
	
	if self.mods[addonName] < version then
		if self.update[addonName] then
			self.update[addonName] = version > self.update[addonName] and version or self.update[addonName]
		else
			self.update[addonName] = version
		end
		return ME_UPDATE
	elseif self.mods[addonName] > version then
		return USER_UPDATE
	else
		return EQUAL
	end
end

---------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------

local LibQTip = LibStub("LibQTip-1.0")
local tipFadeAfter = 0.25

local tips = {}

local mixins = {
	"GetTooltip",
	"IsTooltip",
	"CheckTooltips",
	"HideAllTooltips",
	"SetSharedAutoHideDelay"
}

Embed = function(t, addon)
	for i, v in ipairs(mixins) do
		t[v] = iLib[v]
	end
	t.baseName = addon -- I chose t.baseName because AceAddon-3.0 uses it, too - many mods use AceAddon-3.0 :)
end

-- creates an iLib tooltip name of t.baseName and name, e.g. iLibiFriendsMain
-- this is necessary because the HideAllTooltips function hides all tooltip provided by the iLib
local function tip_name(t, name)
	return "iLib"..(t.baseName or "Anonymous")..(name or "Main")
end

-- executes the tooltip update callback if there is one
local function tooltip_update(t, name, name2)
	if not name2 then
		name2 = tip_name(t, name)
	end
	if type(t[tips[name2]]) == "function" then
		t[tips[name2]](t, t:GetTooltip(name))
	end
end

-- this function is inserted to all Qtips by the iLib. So, on release, they will delete themselves out of the tips table
local function tip_OnRelease(tip)
	tips[tip.key] = nil
	tips[''] = 1
	tips[''] = nil
end

--- Acquires a LibQTip tooltip with the specified name and registers an updateCallback with it. If the tooltip is already acquired, returns the LibQTip object. This function becomes available on your addon table when you registered it via iLib:Register()!
-- @param name The name for the tooltip object.
-- @param updateCallback The function name of the function which fills the tooltip with content. Must be a String. The function must be available on your addon table.
-- @return Returns a LibQTip object.
-- @usage -- for registering a new tooltip
-- local tip = myAddon:GetTooltip("Main", "UpdateTooltip")
-- 
-- -- for getting the previously registered tooltip object
-- local tip = myAddon:GetTooltip("Main")
function iLib:GetTooltip(name, updateCallback)
	local name2 = tip_name(self, name)
	if self:IsTooltip(name) then
		return LibQTip:Acquire(name2)
	end
	tips[name2] = updateCallback
	tooltip_update(self, name, name2)
	name = LibQTip:Acquire(name2)
	name.OnRelease = tip_OnRelease;
	return name
end

--- Checks if a tooltip is currently displayed. This function becomes available on your addon table when you registered it via iLib:Register()!
-- @param name The name of your tooltip.
-- @return Returns true of your tooltip is displayed.
-- @usage if myAddon:IsTooltip("Main") then
--   -- do something
-- end
function iLib:IsTooltip(name)
	return LibQTip:IsAcquired(tip_name(self, name))
end

--- Checks if the given tooltips are currently displayed and if yes, fires their update callback. This function becomes available on your addon table when you registered it via iLib:Register()!
-- @param ... The names of the tooltips to be checked.
-- @usage -- A WoW API event got fired and several tooltips needs an update.
-- myAddon:CheckTooltips("Main", "Second", "Special", ...)
function iLib:CheckTooltips(...)
	local name
	for i = 1, select("#", ...) do
		name = select(i, ...)
		if self:IsTooltip(name) then
			tooltip_update(self, name)
		end
	end
end

--- Iterates over all LibQTip tooltips and hides them, if they are acquired by the iLib. This function becomes available on your addon table when you registered it via iLib:Register()!
-- @usage myAddon:HideAllTooltips();
-- -- All previously displayed tooltips are hidden now.
-- -- You may want to display a new one, now.
function iLib:HideAllTooltips()
	for k, v in LibQTip:IterateTooltips() do
		if type(k) == "string" and strsub(k, 1, 4) == "iLib" then
			v:Release()
		end
	end
end

local function tip_OnUpdate(self, elapsed)
	for i, v in ipairs(self.frames) do
		if v:IsMouseOver() then
			self.lastUpdate = 0
			break
		end
	end
	
	self.lastUpdate = self.lastUpdate + elapsed;
	if( self.lastUpdate >= self.delay ) then
		for i, v in ipairs(self.frames) do
			if v.key then -- qtips actually have a "key"-key
				v:Release()
			end
			v = nil
		end
		self.lastUpdate = nil
		self.frames[''] = 1
		self.frames[''] = nil
		self.frames = nil
		self:SetScript("OnUpdate", nil);
	end
end

--- Sets a shared AutoHideDelay for an infinite number of frames. This will result in none tooltips are hidden, if one of the frames is hovered with your mouse. The more frames are specified, the more CPU is required. The first frame should always be a LibQTip object, since for example anchors often have their own OnUpdate scripts. This function becomes available on your addon table when you registered it via iLib:Register()!
-- @param delay The time after all tooltips are hidden.
-- @param main The LibQTip object to which the OnUpdate script will be attached.
-- @param ... Infinite number of frames to check mouse hovering for.
-- @usage myAddon:SetSharedAutoHideDelay(0.25, tip1, anchor, tip2)
-- -- Neither tip1 nor tip2 are hidden
-- -- if one of the three frames is hovered with the cursor.
function iLib:SetSharedAutoHideDelay(delay, main, ...)
	main.delay = delay
	main.lastUpdate = 0
	main.frames = {main, ...}
	main:SetScript("OnUpdate", tip_OnUpdate)
end

collectgarbage() -- cheats, haha :)