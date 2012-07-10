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

--- **This function is only available on your addon table if you registered it with the iLib.**\\
-- Creates a LibQTip tooltip object and passes it a few settings. To fill the tooltip with content before showing, you must specify the UpdateTooltip(...) method in your addon table.\\
-- **Important**: The tooltip will also become available through myAddon.tooltip
-- @param anchor OPTIONAL: The desired anchor where LibQTip can SmartAnchor it to. Usually a frame.
-- @param noAutoHide OPTIONAL: Set this to true if LibQTip:SetAutoHideDelay shall not be set. If false, iLib requires you to set an anchor.
-- @param varToPass OPTIONAL: An additional value to be passed to myAddon.UpdateTooltip
-- @return Returns the tooltip object.
-- @usage -- Tooltip which is not anchored & hidden when leaving it with the mouse.
-- local tip = myAddon:GetTooltip()
-- @usage -- Tooltip which is SmartAnchored to PlayerFrame
-- -- and hidden when leaving both PlayerFrame or tooltip
-- local tip = myAddon:GetTooltip(PlayerFrame)
-- @usage -- Passing a var to UpdateTooltip
-- local tip = myAddon:GetTooltip(nil, nil, "Hello World!")
-- 
-- function myAddon:UpdateTooltip(tooltip, varToPass)
--   tooltip:AddHeader(varToPass)
-- end
function iLib:GetTooltip(anchor, noAutoHide, varToPass)
	if self:IsTooltip() then
		return LibQTip:Acquire("iAddon"..self.baseName), true
	end
	local tip = LibQTip:Acquire("iAddon"..self.baseName)
	if anchor then
		tip:SmartAnchorTo(anchor)
		if not noAutoHide then
			tip:SetAutoHideDelay(tipFadeAfter, anchor)
		end
	end
	if self.UpdateTooltip then
		self:UpdateTooltip(tip, varToPass)
	end
	tip:Show()
	return tip
end

local function tip_OnUpdate(self, elapsed)
	if (self.anchor and self.anchor:IsMouseOver()) or self:IsMouseOver() or self.tip2:IsMouseOver() then
		self.lastUpdate = 0
		return;
	end
	
	self.lastUpdate = self.lastUpdate + elapsed;
	if( self.lastUpdate >= tipFadeAfter ) then
		iLib:HideTooltip(false, self)
		iLib:HideTooltip(false, self.tip2)
		self.lastUpdate = nil;
		self.tip2 = nil
		self.anchor = nil;
		self[''] = 1
		self[''] = nil
		self:SetScript("OnUpdate", nil);
	end
end

--- **This function is only available on your addon table if you registered it with the iLib.**\\
-- Some addons may want to show two tooltips at once, which behave like one tooltip. The 2nd tooltip may also behave like a normal one, if no depMode is defined.\\
-- **Important**: The tooltip will also become available through myAddon.tooltip2
-- @param depMode If true, will merge tooltip1/tooltip2 and make them behave similar.
-- @param anchor OPTIONAL: The desired anchor where LibQTip can SmartAnchor it to. Usually a frame.
-- @param noAutoHide OPTIONAL: Set this to true if LibQTip:SetAutoHideDelay shall not be set. If false, iLib requires you to set an anchor.
-- @param varToPass OPTIONAL: An additional value to be passed to myAddon.UpdateTooltip
-- @return Returns the tooltip object.
-- @usage -- If anchor, tip1 and tip2 lost mouse focus, both tips will hide
-- myAddon:GetTooltip(anchor)
-- myAddon:Get2ndTooltip(true, anchor)
function iLib:Get2ndTooltip(depMode, anchor, noAutoHide, varToPass)
	if self:IsTooltip(true) then
		return LibQTip:Acquire("i2Addon"..self.baseName), true
	end
	local tip = LibQTip:Acquire("i2Addon"..self.baseName)
	if depMode and anchor then
		if not self:IsTooltip() then
			error("You need to use GetTooltip() before using depMode on Get2ndTooltip()!")
		end
		local maintip = self:GetTooltip()
		maintip.lastUpdate = 0
		maintip.tip2 = tip
		maintip.anchor = anchor
		maintip:SetScript("OnUpdate", tip_OnUpdate)
	else
		if anchor then
			tip:SmartAnchorTo(anchor)
		end
		if not noAutoHide then
			tip:SetAutoHideDelay(tipFadeAfter, anchor)
		end
	end
	if self.UpdateTooltip then
		self:UpdateTooltip(tip, varToPass)
	end
	tip:Show()
	return tip
end

--- **This function is only available on your addon table if you registered it with the iLib.**\\
-- Returns info whether the given tooltip is acquired or not.\\
-- @param second If true, will check for the 2ndTooltip instead of the normal one.
-- @return Returns true or false.
-- @usage if myAddon:IsTooltip() then
--   -- do something with tooltip
-- end
function iLib:IsTooltip(second)
	return LibQTip:IsAcquired("i"..(second and "2" or "").."Addon"..self.baseName)
end

--- **This function is only available on your addon table if you registered it with the iLib.**\\
-- Hides all tooltips which are shown by the iLib.
-- @usage myAddon:HideAllTooltips()
function iLib:HideAllTooltips()
	for k, v in LibQTip:IterateTooltips() do
		if type(k) == "string" and (strsub(k, 1, 6) == "iAddon" or strsub(k, 1, 7) == "i2Addon") then
			self:HideTooltip(false, v)
		end
	end
end

--- **This function is only available on your addon table if you registered it with the iLib.**\\
-- Hides a specific tooltip which was previously shown by the iLib.
-- @param second If true, hides the second tooltip, if false, hides the main tooltip
-- @param tip LibQTip tooltip object. This tooltip will be hidden instead of tip1/tip2.
-- @usage myAddon:HideTooltip() -- hides main tooltip
-- myAddon:HideTooltip(true) -- hides second tooltip
-- myAddon:HideTooltip(nil, LibQTip_object) -- hides the given tooltip
function iLib:HideTooltip(second, tip)
	if not second then
		if tip then
			tip:Release()
		else
			self:GetTooltip():Release()
		end
	else
		self:Get2ndTooltip():Release()
	end
end

--- **This function is only available on your addon table if you registered it with the iLib.**\\
-- Checks if both the main and the second tooltip are shown and executes myAddon:UpdateTooltip(...)
-- @param varToPass Gets passed to the main tooltip.
-- @param varToPass2 Gets passed to the second tooltip.
-- @usage myAddon:HideAllTooltips()
function iLib:CheckForTooltip(varToPass, varToPass2)
	if self.UpdateTooltip then
		if self:IsTooltip() then
			self:UpdateTooltip(self:GetTooltip(), varToPass)
		end
		if self:IsTooltip(true) then
			self:UpdateTooltip(self:Get2ndTooltip(), varToPass2)
		end
	end
end

local mixins = {
	"GetTooltip",
	"Get2ndTooltip",
	"IsTooltip",
	"CheckForTooltip",
	"HideAllTooltips",
	"HideTooltip"
}

function iLib:Embed(t, addon)
	for i, v in ipairs(mixins) do
		t[v] = self[v]
	end
	t.baseName = addon
end

collectgarbage() -- cheats, haha :)