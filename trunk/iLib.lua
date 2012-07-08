local MAJOR_VERSION, MINOR_VERSION = "iLib", 2
if not LibStub then error(MAJOR_VERSION .. " requires LibStub") end

local iLib, oldLib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not iLib then
	return
end
LibStub("AceComm-3.0"):Embed(iLib)

local _G = _G

local ME_UPDATE, EQUAL, USER_UPDATE = 1, 2, 3

local inParty = false
local addonsChanged = false
local player = _G.GetUnitName("player")

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

function iLib:CommReceived(prefix, msg, chat, user)
	msg = msgdecode(msg)
	if user == player then
		return
	end
	
	local t = {strsplit(":", msg)}
	if t[1] == "?" or t[1] == "!" then
		local addon, version
		for i = 2, #t do
			addon, version = strsplit("-", t[i])
			if t[1] == "?" and self:Compare(addon, tonumber(version)) == USER_UPDATE then
				if not self.frame.warn[user] then
					self.frame.warn[user] = {}
				end
				if not _G.tContains(self.frame.warn[user], addon) then
					table.insert(self.frame.warn[user], addon)
					table.insert(self.frame.warn[user], self.mods[addon])
					table.insert(self.frame.warn[user], chat)
				end
			end
		end
	end
end
iLib:RegisterComm("iLib", "CommReceived")

local function iLib_OnEvent(self, event)
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" then
		if _G.IsInGuild() then
			send_ask_message("GUILD")
		end
	end
	if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
		if _G.IsInRaid() or _G.IsInGroup() then
			if not inParty then
				inParty = true
				send_ask_message("RAID")
			end
		else
			inParty = false
		end
	end
	if event == "PLAYER_ENTERING_WORLD" then
		if _G.UnitInBattleground("player") then
			send_ask_message("BATTLEGROUND")
		end
	end
end

local function iLib_OnUpdate(self, elapsed)
	self.warnTime = self.warnTime + elapsed
	if self.warn[1] and self.warnTime >= self.warn[2] then
		for k, v in pairs(self.warn) do
			if type(k) ~= "number" then
				send_update_message(k, unpack(self.warn[k]))
				self.warn[k] = nil
			end
		end
		self.warn[''] = 1
		self.warn[''] = nil
		self.warn[1] = false
	end
end

local function init_frame()
	local f = _G.CreateFrame("Frame")	
	f.warn = {false, 0}
	f.warnTime = 0
	setmetatable(f.warn, {__newindex = function(t, k, v)
		t[1] = true
		t[2] = (random(8, 50) / 10)
		f.warnTime = 0
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
local function smart_version_number(addon)
	local aver = _G.GetAddOnMetadata(addon, "Version")
	if tonumber(aver) then
		return aver
	end
	local _, _, major, minor, rev = string.find(aver, "(%d).(%d).(%d)");
	major = tonumber(major) and major or 0
	minor = tonumber(minor) and minor or 0
	rev   = tonumber( rev ) and  rev  or 0
	return (major * 10000) + (minor * 1000) + rev
end

--- Registers an addon with the iLib
-- @param addonName The name of your addon. It is good-practise to use the name of your addons TOC file (without .toc).
-- @param version The version as number. If its a string, iLib trys to create a number from it (e.g. 2.1.0 => 21000)
-- @param addonTable Your addon table. Only use if you want to let iLib handle your tooltips.
-- @return Returns a boolean which indicates whether the registering was successful or not.
-- @usage -- without tooltip  handling
-- LibStub("iLib"):Register("MyAddon")
-- LibStub("iLib"):Register("MyAddon", 10200)
-- @usage -- with tooltip handling
-- LibStub("iLib"):Register("MyAddon", nil, myAddon)
function iLib:Register(addonName, version, addonTable)
	if( not addonName ) then
		error("Usage: Register(addonName [, version [, addonTable]])");
	end
	
	-- no version provided by addon, so we create it by ourselves
	if not tonumber(version) then
		version = smart_version_number(addonName)
	end
	
	if not self:Checkout(addonName) then-- and _G.GetAddOnMetadata(addonName, "Author") == 'grdn' then
		self.mods[addonName] = version
		if type(addonTable) == "table" then
			self:Embed(addonTable, addonName)
		end
		return true
	end
	return false
end

--- Checks if the given addon is registered with the iLib.
-- @param addonName The name of your addon.
-- @return Returns a boolean which indicates whether the addon is registered or not.
-- @usage if LibStub("iLib"):Checkout("MyAddon") then
--   -- do something
-- end
function iLib:Checkout(addonName)
	if( not addonName ) then
		error("Usage: Checkout( \"AddonName\" )");
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
-- @usage if LibStub("iLib"):Compare("MyAddon", 2034) == USER_UPDATE then
--   SendChatMessage("you should update your addon "..addonName, "WHISPER", nil, "user")
-- end
function iLib:Compare(addonName, version)
	if( not addonName or not version ) then
		error("Usage: Checkout( \"AddonName\" , version)");
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

local LibQTip = LibStub("LibQTip-1.0")

-- We want to get a tooltip
function iLib:GetTooltip(anchor, noAutoHide, varToPass)
	local tip = LibQTip:Acquire("iAddon"..self.baseName)
	self.tooltip = tip
	if anchor then
		tip:SmartAnchorTo(anchor)
	end
	if not noAutoHide then
		tip:SetAutoHideDelay(0.25, anchor)
	end
	if self.UpdateTooltip then
		self:UpdateTooltip(tip, varToPass)
	end
	tip:Show()
	return tip
end

local function tip_OnUpdate(self, elapsed)
	if (self.anchor and self.anchor:IsMouseOver()) or self:IsMouseOver() or self.tip2:IsMouseOver() then
		self.lastUpdate = 0;
		return;
	end
	
	self.lastUpdate = self.lastUpdate + elapsed;
	if( self.lastUpdate >= 0.25 ) then
		self.anchor = nil;
		self.lastUpdate = 0;
		self:SetScript("OnUpdate", nil);
		self:Hide();
		self:Release();
		self.tip2:Hide();
		self.tip2:Release();
	end
end

function iLib:Get2ndTooltip(depMode, anchor, noAutoHide, varToPass)
	local tip = LibQTip:Acquire("iAddon"..self.baseName.."2")
	self.tooltip2 = tip
	if depMode then
		tip:SetPoint("TOPLEFT", self.tooltip, "BOTTOMLEFT", 0, 0)
		self.tooltip.tip2 = tip
		self.tooltip.anchor = anchor
		self.tooltip.lastUpdate = 0
		self.tooltip:SetScript("OnUpdate", tip_OnUpdate)
	else
		if anchor then
			tip:SmartAnchorTo(anchor)
		end
		if not noAutoHide then
			tip:SetAutoHideDelay(0.25, anchor)
		end
	end
	if self.UpdateTooltip then
		self:UpdateTooltip(tip, varToPass)
	end
	tip:Show()
	return tip
end

function iLib:IsTooltip(second)
	return LibQTip:IsAcquired("iAddon"..self.baseName..(second and "2" or ""))
end

-- We want to hide other iTooltips
function iLib:HideAllTooltips()
	for k, v in LibQTip:IterateTooltips() do
		if type(k) == "string" and strsub(k, 1, 6) == "iAddon"  then
			v:Release(k)
		end
	end
end

function iLib:CheckForTooltip(varToPass, varToPass2)
	if self.UpdateTooltip then
		if self:IsTooltip() then
			self:UpdateTooltip(self.tooltip, varToPass)
		end
		if self:IsTooltip(true) then
			self:UpdateTooltip(self.tooltip2, varToPass2)
		end
	end
end

local mixins = {
	"GetTooltip",
	"Get2ndTooltip",
	"IsTooltip",
	"CheckForTooltip",
	"HideAllTooltips"
}

function iLib:Embed(t, addon)
	for i, v in ipairs(mixins) do
		t[v] = self[v]
	end
	t.baseName = addon
end

collectgarbage() -- cheats, haha :)