local MAJOR_VERSION, MINOR_VERSION = "iLib", 5
if not LibStub then error(MAJOR_VERSION .. " requires LibStub") end

local iLib, oldLib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not iLib then
	return
end
LibStub("AceComm-3.0"):Embed(iLib)

local _G = _G

local ME_UPDATE, EQUAL, USER_UPDATE = 1, 2, 3

local inGroup = false
local addonsChanged = false
local player = _G.GetUnitName("player")

local askGuild = true
local askGroup = true
local askPVP   = true

iLib.mods = iLib.mods or {}
setmetatable(iLib.mods, {__newindex = function(t, k, v)
	rawset(t, k, v)
	addonsChanged = true
end})

iLib.update = iLib.update or {}

local function msgencode(msg)
	return LibStub("LibCompress"):CompressHuffman(msg)
end

local function msgdecode(msg)
	return LibStub("LibCompress"):DecompressHuffman(msg)
end

local send_ask_message
do
	local ask_str
	send_ask_message = function(chat)
		if addonsChanged then
			ask_str = "?"
			for k, v in pairs(iLib.mods) do
				ask_str = ask_str..":"..k.."-"..v
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
		for i = 1, select("#", ...), 3 do
			addon, version, chat = select(i, ...), select(i+1, ...), select(i+2, ...)
			if not t[chat] then
				t[chat] = {}
			end
			table.insert(t[chat], addon.."-"..version)
		end
		
		for chat, mods in pairs(t) do
			iLib:SendCommMessage("iLib", msgencode("!:"..table.concat(mods, ":")), chat, (chat == "WHISPER" and user or nil))
			t[chat] = nil
		end
		t[''] = 1
		t[''] = nil
	end
end

-- adds a user to the warnlist
function add_user_warn(user, addon, chat)
	if not iLib.frame.warn[user] then
		iLib.frame.warn[user] = {}
	end
	if not _G.tContains(iLib.frame.warn[user], addon) then
		table.insert(iLib.frame.warn[user], addon)
		table.insert(iLib.frame.warn[user], iLib.mods[addon])
		table.insert(iLib.frame.warn[user], chat)
	end
end

function iLib:CommReceived(prefix, msg, chat, user)
	msg = msgdecode(msg)
	--@do-not-package@
	print(user.." ("..chat..") - "..msg)
	--@end-do-not-package@
	if user == player then
		return
	end
	local addon, version
	local t = {strsplit(":", msg)}
	
	if t[1] == "?" or t[1] == "!" then
		for i = 2, #t do
			addon, version = strsplit("-", t[i])
			if self:Compare(addon, tonumber(version)) == USER_UPDATE then
				add_user_warn(user, addon, chat)
			end
		end
	end
end
iLib:RegisterComm("iLib", "CommReceived")

-- Event Handler
-- If we are logging in, we send Ask querys to guild (if in guild), group (if in group), pvp (if in pvp)
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

-- The OnUpdate scripts, which currently just can warn users for a new addon version
local warnTime, warnExec
local function iLib_OnUpdate(self, elapsed)
	self.warnElapsed = self.warnElapsed + elapsed
	if warnExec and self.warnElapsed >= warnTime then
		for user, v in pairs(self.warn) do
			send_update_message(user, unpack(self.warn[user]))
			self.warn[user] = nil
		end
		self.warn[''] = 1
		self.warn[''] = nil
		warnExec = false
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
-- If not, we bet that it is a string in the format major.minor.rev or at least major.minor
local function smart_version_number(addon)
	local aver = _G.GetAddOnMetadata(addon, "Version") or 0
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
-- @param addonName The name of your addon. It is good-practise to use the name of your addons TOC file (without .toc).
-- @param version The version as number. If its a string, iLib trys to create a number from it (e.g. 2.1.0 => 21000)
-- @param addonTable Your addon table. Only use if you want to let iLib handle your tooltips.
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
	
	if not self:Checkout(addonName) then
		-- no version provided by addon, so we create it by ourselves
		if not tonumber(version) then
			version = smart_version_number(addonName)
		end
		self.mods[addonName] = version
		
		if type(addonTable) == "table" then
			self:Embed(addonTable, addonName)
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
-- @usage if LibStub("iLib"):Checkout("MyAddon") then
--   -- do something
-- end
function iLib:Checkout(addonName)
	if not addonName then
		error("Usage: Checkout( \"AddonName\" )")
	end
	
	if self.mods[addonName] then
		return true
	end
	return false
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
		error("Usage: Checkout( \"AddonName\" , version)")
	end
	
	if not self:Checkout(addonName) then
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

function iLib:Embed(t, addon)
	for i, v in ipairs(mixins) do
		t[v] = self[v]
	end
	t.baseName = addon
end

local function tip_name(t, name)
	return "iAddon"..(t.baseName or "Anonymous")..(name or "")
end

local function tooltip_update(t, name, name2)
	if not name2 then
		name2 = tip_name(t, name)
	end
	if type(t[tips[name2]]) == "function" then
		t[tips[name2]](t, t:GetTooltip(name))
	end
end

local function tip_OnRelease(tip)
	tips[tip.key] = nil
end

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

function iLib:IsTooltip(name)
	return LibQTip:IsAcquired(tip_name(self, name))
end

function iLib:CheckTooltips(...)
	local name
	for i = 1, select("#", ...) do
		name = select(i, ...)
		if self:IsTooltip(name) then
			tooltip_update(self, name)
		end
	end
end

function iLib:HideAllTooltips()
	for k, v in LibQTip:IterateTooltips() do
		if type(k) == "string" and strsub(k, 1, 6) == "iAddon" then
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

function iLib:SetSharedAutoHideDelay(delay, main, ...)
	main.delay = delay
	main.lastUpdate = 0
	main.frames = {main, ...}
	main:SetScript("OnUpdate", tip_OnUpdate)
end

collectgarbage() -- cheats, haha :)