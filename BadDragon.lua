local ADDON = 'BadDragon'
if select(2, UnitClass('player')) ~= 'EVOKER' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

BadDragon = {}
local Opt -- use this as a local table reference to BadDragon

SLASH_BadDragon1, SLASH_BadDragon2, SLASH_BadDragon3 = '/bd', '/bad', '/dragon'
BINDING_HEADER_BADDRAGON = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(BadDragon, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			devastation = false,
			preservation = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 8,
		pot = false,
		trinket = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	DEVASTATION = 1,
	PRESERVATION = 2,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
		pct = 0,
	},
	mana = {
		current = 0,
		deficit = 0,
		max = 100,
		regen = 0,
	},
	essence = {
		current = 0,
		deficit = 0,
		max = 5,
		regen = 0,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	main_freecast = false,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

local badDragonPanel = CreateFrame('Frame', 'badDragonPanel', UIParent)
badDragonPanel:SetPoint('CENTER', 0, -169)
badDragonPanel:SetFrameStrata('BACKGROUND')
badDragonPanel:SetSize(64, 64)
badDragonPanel:SetMovable(true)
badDragonPanel:Hide()
badDragonPanel.icon = badDragonPanel:CreateTexture(nil, 'BACKGROUND')
badDragonPanel.icon:SetAllPoints(badDragonPanel)
badDragonPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
badDragonPanel.border = badDragonPanel:CreateTexture(nil, 'ARTWORK')
badDragonPanel.border:SetAllPoints(badDragonPanel)
badDragonPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
badDragonPanel.border:Hide()
badDragonPanel.dimmer = badDragonPanel:CreateTexture(nil, 'BORDER')
badDragonPanel.dimmer:SetAllPoints(badDragonPanel)
badDragonPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
badDragonPanel.dimmer:Hide()
badDragonPanel.swipe = CreateFrame('Cooldown', nil, badDragonPanel, 'CooldownFrameTemplate')
badDragonPanel.swipe:SetAllPoints(badDragonPanel)
badDragonPanel.swipe:SetDrawBling(false)
badDragonPanel.swipe:SetDrawEdge(false)
badDragonPanel.text = CreateFrame('Frame', nil, badDragonPanel)
badDragonPanel.text:SetAllPoints(badDragonPanel)
badDragonPanel.text.tl = badDragonPanel.text:CreateFontString(nil, 'OVERLAY')
badDragonPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
badDragonPanel.text.tl:SetPoint('TOPLEFT', badDragonPanel, 'TOPLEFT', 2.5, -3)
badDragonPanel.text.tl:SetJustifyH('LEFT')
badDragonPanel.text.tr = badDragonPanel.text:CreateFontString(nil, 'OVERLAY')
badDragonPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
badDragonPanel.text.tr:SetPoint('TOPRIGHT', badDragonPanel, 'TOPRIGHT', -2.5, -3)
badDragonPanel.text.tr:SetJustifyH('RIGHT')
badDragonPanel.text.bl = badDragonPanel.text:CreateFontString(nil, 'OVERLAY')
badDragonPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
badDragonPanel.text.bl:SetPoint('BOTTOMLEFT', badDragonPanel, 'BOTTOMLEFT', 2.5, 3)
badDragonPanel.text.bl:SetJustifyH('LEFT')
badDragonPanel.text.br = badDragonPanel.text:CreateFontString(nil, 'OVERLAY')
badDragonPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
badDragonPanel.text.br:SetPoint('BOTTOMRIGHT', badDragonPanel, 'BOTTOMRIGHT', -2.5, 3)
badDragonPanel.text.br:SetJustifyH('RIGHT')
badDragonPanel.text.center = badDragonPanel.text:CreateFontString(nil, 'OVERLAY')
badDragonPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
badDragonPanel.text.center:SetAllPoints(badDragonPanel.text)
badDragonPanel.text.center:SetJustifyH('CENTER')
badDragonPanel.text.center:SetJustifyV('CENTER')
badDragonPanel.button = CreateFrame('Button', nil, badDragonPanel)
badDragonPanel.button:SetAllPoints(badDragonPanel)
badDragonPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local badDragonPreviousPanel = CreateFrame('Frame', 'badDragonPreviousPanel', UIParent)
badDragonPreviousPanel:SetFrameStrata('BACKGROUND')
badDragonPreviousPanel:SetSize(64, 64)
badDragonPreviousPanel:Hide()
badDragonPreviousPanel:RegisterForDrag('LeftButton')
badDragonPreviousPanel:SetScript('OnDragStart', badDragonPreviousPanel.StartMoving)
badDragonPreviousPanel:SetScript('OnDragStop', badDragonPreviousPanel.StopMovingOrSizing)
badDragonPreviousPanel:SetMovable(true)
badDragonPreviousPanel.icon = badDragonPreviousPanel:CreateTexture(nil, 'BACKGROUND')
badDragonPreviousPanel.icon:SetAllPoints(badDragonPreviousPanel)
badDragonPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
badDragonPreviousPanel.border = badDragonPreviousPanel:CreateTexture(nil, 'ARTWORK')
badDragonPreviousPanel.border:SetAllPoints(badDragonPreviousPanel)
badDragonPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local badDragonCooldownPanel = CreateFrame('Frame', 'badDragonCooldownPanel', UIParent)
badDragonCooldownPanel:SetSize(64, 64)
badDragonCooldownPanel:SetFrameStrata('BACKGROUND')
badDragonCooldownPanel:Hide()
badDragonCooldownPanel:RegisterForDrag('LeftButton')
badDragonCooldownPanel:SetScript('OnDragStart', badDragonCooldownPanel.StartMoving)
badDragonCooldownPanel:SetScript('OnDragStop', badDragonCooldownPanel.StopMovingOrSizing)
badDragonCooldownPanel:SetMovable(true)
badDragonCooldownPanel.icon = badDragonCooldownPanel:CreateTexture(nil, 'BACKGROUND')
badDragonCooldownPanel.icon:SetAllPoints(badDragonCooldownPanel)
badDragonCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
badDragonCooldownPanel.border = badDragonCooldownPanel:CreateTexture(nil, 'ARTWORK')
badDragonCooldownPanel.border:SetAllPoints(badDragonCooldownPanel)
badDragonCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
badDragonCooldownPanel.dimmer = badDragonCooldownPanel:CreateTexture(nil, 'BORDER')
badDragonCooldownPanel.dimmer:SetAllPoints(badDragonCooldownPanel)
badDragonCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
badDragonCooldownPanel.dimmer:Hide()
badDragonCooldownPanel.swipe = CreateFrame('Cooldown', nil, badDragonCooldownPanel, 'CooldownFrameTemplate')
badDragonCooldownPanel.swipe:SetAllPoints(badDragonCooldownPanel)
badDragonCooldownPanel.swipe:SetDrawBling(false)
badDragonCooldownPanel.swipe:SetDrawEdge(false)
badDragonCooldownPanel.text = badDragonCooldownPanel:CreateFontString(nil, 'OVERLAY')
badDragonCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
badDragonCooldownPanel.text:SetAllPoints(badDragonCooldownPanel)
badDragonCooldownPanel.text:SetJustifyH('CENTER')
badDragonCooldownPanel.text:SetJustifyV('CENTER')
local badDragonInterruptPanel = CreateFrame('Frame', 'badDragonInterruptPanel', UIParent)
badDragonInterruptPanel:SetFrameStrata('BACKGROUND')
badDragonInterruptPanel:SetSize(64, 64)
badDragonInterruptPanel:Hide()
badDragonInterruptPanel:RegisterForDrag('LeftButton')
badDragonInterruptPanel:SetScript('OnDragStart', badDragonInterruptPanel.StartMoving)
badDragonInterruptPanel:SetScript('OnDragStop', badDragonInterruptPanel.StopMovingOrSizing)
badDragonInterruptPanel:SetMovable(true)
badDragonInterruptPanel.icon = badDragonInterruptPanel:CreateTexture(nil, 'BACKGROUND')
badDragonInterruptPanel.icon:SetAllPoints(badDragonInterruptPanel)
badDragonInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
badDragonInterruptPanel.border = badDragonInterruptPanel:CreateTexture(nil, 'ARTWORK')
badDragonInterruptPanel.border:SetAllPoints(badDragonInterruptPanel)
badDragonInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
badDragonInterruptPanel.swipe = CreateFrame('Cooldown', nil, badDragonInterruptPanel, 'CooldownFrameTemplate')
badDragonInterruptPanel.swipe:SetAllPoints(badDragonInterruptPanel)
badDragonInterruptPanel.swipe:SetDrawBling(false)
badDragonInterruptPanel.swipe:SetDrawEdge(false)
local badDragonExtraPanel = CreateFrame('Frame', 'badDragonExtraPanel', UIParent)
badDragonExtraPanel:SetFrameStrata('BACKGROUND')
badDragonExtraPanel:SetSize(64, 64)
badDragonExtraPanel:Hide()
badDragonExtraPanel:RegisterForDrag('LeftButton')
badDragonExtraPanel:SetScript('OnDragStart', badDragonExtraPanel.StartMoving)
badDragonExtraPanel:SetScript('OnDragStop', badDragonExtraPanel.StopMovingOrSizing)
badDragonExtraPanel:SetMovable(true)
badDragonExtraPanel.icon = badDragonExtraPanel:CreateTexture(nil, 'BACKGROUND')
badDragonExtraPanel.icon:SetAllPoints(badDragonExtraPanel)
badDragonExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
badDragonExtraPanel.border = badDragonExtraPanel:CreateTexture(nil, 'ARTWORK')
badDragonExtraPanel.border:SetAllPoints(badDragonExtraPanel)
badDragonExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.DEVASTATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5'},
		{6, '6'},
		{7, '7+'},
	},
	[SPEC.PRESERVATION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	badDragonPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function BadDragon_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function BadDragon_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function BadDragon_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		essence_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if self:EssenceCost() > Player.essence.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - Player.execute_remains)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end


function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.max) or 0
end

function Ability:EssenceCost()
	return self.essence_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		autoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		badDragonPreviousPanel.ability = self
		badDragonPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		badDragonPreviousPanel.icon:SetTexture(self.icon)
		badDragonPreviousPanel:SetShown(badDragonPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and badDragonPreviousPanel.ability == self then
		badDragonPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

-- Evoker Abilities
---- Baseline
local AzureStrike = Ability:Add(362969, false, true)
AzureStrike.mana_cost = 0.9
AzureStrike.max_range = 25
AzureStrike.triggers_combat = true
AzureStrike:AutoAoe()
local DeepBreath = Ability:Add(357210, true, true)
DeepBreath.cooldown_duration = 120
DeepBreath.buff_duration = 6
DeepBreath.triggers_combat = true
DeepBreath.dot = Ability:Add(353759, false, true)
DeepBreath.dot:AutoAoe(false, 'apply')
local BlessingOfTheBronze = Ability:Add(364342, true, false, 381748)
BlessingOfTheBronze.buff_duration = 3600
local Disintegrate = Ability:Add(356995, false, true)
Disintegrate.essence_cost = 3
Disintegrate.buff_duration = 3
Disintegrate.tick_interval = 1
Disintegrate.max_range = 25
Disintegrate.hasted_ticks = true
Disintegrate.hasted_duration = true
Disintegrate.triggers_combat = true
local EssenceBurst = Ability:Add(359565, true, true, 359618)
EssenceBurst.buff_duration = 15
local FireBreath = Ability:Add(382266, false, true)
FireBreath.mana_cost = 2.6
FireBreath.cooldown_duration = 30
FireBreath.triggers_combat = true
FireBreath.learn_spellId = 357208
FireBreath:AutoAoe()
FireBreath.dot = Ability:Add(357209, false, true)
FireBreath.dot.buff_duration = 24
local LivingFlame = Ability:Add(361469, false, true, 361500)
LivingFlame.mana_cost = 2
LivingFlame.max_range = 25
LivingFlame.triggers_combat = true
LivingFlame:AutoAoe()
-- Talents
local ArcaneVigor = Ability:Add(386342, true, true)
local Burnout = Ability:Add(375801, true, true, 375802)
Burnout.buff_duration = 15
local ChargedBlast = Ability:Add(370455, true, true, 370454)
ChargedBlast.buff_duration = 30
local DenseEnergy = Ability:Add(370962, true, true)
local Dragonrage = Ability:Add(375087, true, true)
Dragonrage.cooldown_duration = 120
Dragonrage.buff_duration = 14
Dragonrage.triggers_combat = true
local EngulfingBlaze = Ability:Add(370837, true, true)
local EssenceAttunement = Ability:Add(375722, true, true)
local EternitySurge = Ability:Add(382411, false, true, 359077)
EternitySurge.cooldown_duration = 30
EternitySurge.max_range = 25
EternitySurge.triggers_combat = true
EternitySurge.learn_spellId = 359073
EternitySurge:AutoAoe()
local EternitysSpan = Ability:Add(375757, true, true)
local EverburningFlame = Ability:Add(370819, true, true)
local FeedTheFlames = Ability:Add(369846, true, true)
local Firestorm = Ability:Add(368847, false, true)
Firestorm.cooldown_duration = 20
Firestorm.buff_duration = 12
Firestorm.max_range = 25
Firestorm.triggers_combat = true
Firestorm:AutoAoe()
Firestorm:TrackAuras()
local Pyre = Ability:Add(357211, false, true, 357212)
Pyre.essence_cost = 3
Pyre.triggers_combat = true
Pyre:AutoAoe()
local Quell = Ability:Add(351338, false, true)
Quell.cooldown_duration = 40
Quell.buff_duration = 4
Quell.max_range = 25
local RubyEmbers = Ability:Add(365937, false, true)
RubyEmbers.buff_duration = 12
local Scintillation = Ability:Add(370821, false, true)
local ShatteringStar = Ability:Add(370452, false, true)
ShatteringStar.cooldown_duration = 15
ShatteringStar.buff_duration = 4
ShatteringStar.max_range = 25
ShatteringStar.triggers_combat = true
ShatteringStar:AutoAoe()
local TipTheScales = Ability:Add(370553, true, true)
TipTheScales.cooldown_duration = 120
-- Covenant abilities
local BoonOfTheCovenants = Ability:Add(387168, true, true)
BoonOfTheCovenants.cooldown_duration = 120
BoonOfTheCovenants.buff_duration = 12
BoonOfTheCovenants.check_usable = true
local SummonSteward = Ability:Add(324739, false, true) -- Kyrian
SummonSteward.cooldown_duration = 300
SummonSteward.check_usable = true
-- Soulbind conduits

-- Legendary effects

-- Racials

-- PvP talents

-- Trinket Effects

-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local EternalAugmentRune = InventoryItem:Add(190384)
EternalAugmentRune.buff = Ability:Add(367405, true, true)
local EternalFlask = InventoryItem:Add(171280)
EternalFlask.buff = Ability:Add(307166, true, true)
local PhialOfSerenity = InventoryItem:Add(177278) -- Provided by Summon Steward
PhialOfSerenity.max_charges = 3
local PotionOfPhantomFire = InventoryItem:Add(171349)
PotionOfPhantomFire.buff = Ability:Add(307495, true, true)
local PotionOfSpectralIntellect = InventoryItem:Add(171273)
PotionOfSpectralIntellect.buff = Ability:Add(307162, true, true)
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.SoleahsSecretTechnique = InventoryItem:Add(190958)
Trinket.SoleahsSecretTechnique.buff = Ability:Add(368512, true, true)
-- End Inventory Items

-- Start Player API

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.ability_casting and self.ability_casting.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740 or -- Drums of the Maelstrom (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateAbilities()
	self.rescan_abilities = false
	self.mana.max = UnitPowerMax('player', 0)
	self.essence.max = UnitPowerMax('player', 19)

	local node
	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node then
					if node.conduitID == 0 then
						self.rescan_abilities = true -- rescan on next target, conduit data has not finished loading
					else
						ability.known = node.state == 3
						ability.rank = node.conduitRank
					end
				end
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	DeepBreath.dot.known = DeepBreath.known
	FireBreath.dot.known = FireBreath.known

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateThreat()
	self.gcd = 1.5 * self.haste_factor
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.ability_casting then
		self.mana.current = self.mana.current - self.ability_casting:ManaCost()
	end
	self.mana.current = min(max(self.mana.current, 0), self.mana.max)
	self.essence.regen = GetPowerRegenForPowerType(19)
	self.essence.current = UnitPower('player', 19)
	self.essence.deficit = self.essence.max - self.essence.current

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	badDragonPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			badDragonPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			badDragonPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		badDragonPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function ChargedBlast:MaxStack()
	return 20
end

function EssenceBurst:Remains()
	if LivingFlame:Casting() and Dragonrage:Up() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function EssenceBurst:Stack()
	local stack = Ability.Stack(self)
	if LivingFlame:Casting() and Dragonrage:Up() then
		stack = stack + 1
	end
	return min(self:MaxStack(), stack)
end

function EssenceBurst:MaxStack()
	return 1 + (EssenceAttunement.known and 1 or 0)
end

function Disintegrate:EssenceCost()
	if EssenceBurst:Up() then
		return 0
	end
	return Ability.EssenceCost(self)
end

function Pyre:EssenceCost()
	if EssenceBurst:Up() then
		return 0
	end
	local cost = Ability.EssenceCost(self)
	if DenseEnergy.known then
		cost = cost - 1
	end
	return max(0, cost)
end

function LivingFlame:Free()
	return Burnout:Up()
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.DEVASTATION] = {},
	[SPEC.PRESERVATION] = {},
}

APL[SPEC.DEVASTATION].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/use_item,name=shadowed_orb_of_torment
actions.precombat+=/firestorm,if=talent.firestorm
actions.precombat+=/living_flame,if=!talent.firestorm
# Evaluates both trinkets cooldowns to see if they can be evenly divided by the cooldown of Dragonrage, prioritizes trinkets that will sync with this cooldown
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=trinket.1.has_use_buff&(trinket.1.cooldown.duration%%cooldown.dragonrage.duration=0)
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=trinket.2.has_use_buff&(trinket.2.cooldown.duration%%cooldown.dragonrage.duration=0)
# Estimates a trinkets value by comparing the cooldown of the trinket, divided by the duration of the buff it provides. Has a intellect modifier (currently 1.5x) to give a higher priority to intellect trinkets. The intellect modifier should be changed as intellect priority increases or decreases. As well as a modifier for if a trinket will or will not sync with cooldowns.
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!trinket.1.has_use_buff&trinket.2.has_use_buff|trinket.2.has_use_buff&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.intellect)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.intellect)*(variable.trinket_1_sync))
]]
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseCooldown(SummonSteward)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 300 then
			return BlessingOfTheBronze
		end
		if Firestorm:Usable() then
			return Firestorm
		end
		if LivingFlame:Usable() then
			return LivingFlame
		end
	else
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 10 then
			UseExtra(BlessingOfTheBronze)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
--[[
actions=potion,if=buff.dragonrage.up|time>=300&fight_remains<35
actions+=/use_item,name=shadowed_orb_of_torment
actions+=/use_item,name=crimson_aspirants_badge_of_ferocity,if=cooldown.dragonrage.remains>=55
actions+=/call_action_list,name=trinkets
actions+=/deep_breath,if=spell_targets.deep_breath>1&buff.dragonrage.down
actions+=/dragonrage,if=cooldown.eternity_surge.remains<=(buff.dragonrage.duration+6)&(cooldown.fire_breath.remains<=2*gcd.max|!talent.feed_the_flames)
actions+=/tip_the_scales,if=buff.dragonrage.up&(cooldown.eternity_surge.up|cooldown.fire_breath.up)&buff.dragonrage.remains<=gcd.max
actions+=/eternity_surge,empower_to=1,if=buff.dragonrage.up&(buff.bloodlust.up|buff.power_infusion.up)&talent.feed_the_flames
actions+=/tip_the_scales,if=buff.dragonrage.up&cooldown.fire_breath.up&talent.everburning_flame&talent.firestorm
actions+=/fire_breath,empower_to=1,if=talent.everburning_flame&(cooldown.firestorm.remains>=2*gcd.max|!dot.firestorm.ticking)|cooldown.dragonrage.remains>=10&talent.feed_the_flames|!talent.everburning_flame&!talent.feed_the_flames
actions+=/fire_breath,empower_to=2,if=talent.everburning_flame
actions+=/firestorm,if=talent.everburning_flame&(cooldown.fire_breath.up|dot.fire_breath_damage.remains>=cast_time&dot.fire_breath_damage.remains<cooldown.fire_breath.remains)|buff.snapfire.up|spell_targets.firestorm>1
actions+=/eternity_surge,empower_to=4,if=spell_targets.pyre>3*(1+talent.eternitys_span)
actions+=/eternity_surge,empower_to=3,if=spell_targets.pyre>2*(1+talent.eternitys_span)
actions+=/eternity_surge,empower_to=2,if=spell_targets.pyre>(1+talent.eternitys_span)
actions+=/eternity_surge,empower_to=1,if=(cooldown.eternity_surge.duration-cooldown.dragonrage.remains)<(buff.dragonrage.duration+6-gcd.max)
actions+=/shattering_star,if=!talent.arcane_vigor|essence+1<essence.max|buff.dragonrage.up
actions+=/azure_strike,if=essence<essence.max&!buff.burnout.up&spell_targets.azure_strike>(2-buff.dragonrage.up)&buff.essence_burst.stack<buff.essence_burst.max_stack&(!talent.ruby_embers|spell_targets.azure_strike>2)
actions+=/pyre,if=spell_targets.pyre>(2+talent.scintillation*talent.eternitys_span)|buff.charged_blast.stack=buff.charged_blast.max_stack&cooldown.dragonrage.remains>20&spell_targets.pyre>2
actions+=/living_flame,if=essence<essence.max&buff.essence_burst.stack<buff.essence_burst.max_stack&(buff.burnout.up|!talent.engulfing_blaze&!talent.shattering_star&buff.dragonrage.up&target.health.pct>80)
actions+=/disintegrate,chain=1,if=buff.dragonrage.up,interrupt_if=buff.dragonrage.up&ticks>=2,interrupt_immediate=1
actions+=/disintegrate,chain=1,if=essence=essence.max|buff.essence_burst.stack=buff.essence_burst.max_stack|debuff.shattering_star_debuff.up|cooldown.shattering_star.remains>=3*gcd.max|!talent.shattering_star
actions+=/use_item,name=kharnalex_the_first_light,if=!debuff.shattering_star_debuff.up&!buff.dragonrage.up&spell_targets.pyre=1
actions+=/azure_strike,if=spell_targets.azure_strike>2|(talent.engulfing_blaze|talent.feed_the_flames)&buff.dragonrage.up
actions+=/living_flame
]]
	if DeepBreath:Usable() and Player.enemies > 1 and Dragonrage:Down() then
		UseCooldown(DeepBreath)
	end
	if Dragonrage:Usable() and Dragonrage:Down() and EternitySurge:Ready(Dragonrage:Duration() + 6) and (not FeedTheFlames.known or FireBreath:Ready(2 * Player.gcd)) then
		UseCooldown(Dragonrage)
	end
	if BoonOfTheCovenants:Usable() and Dragonrage:Up() then
		UseCooldown(BoonOfTheCovenants)
	end
	if TipTheScales:Usable() and Dragonrage:Up() and ((Player.enemies > 4 and EternitySurge:Ready()) or ((EternitySurge:Ready() or FireBreath:Ready()) and Dragonrage:Remains() < (Player.gcd * 2))) then
		UseCooldown(TipTheScales)
	end
	if FeedTheFlames.known and EternitySurge:Usable() and Dragonrage:Up() and (Player:BloodlustActive() or PowerInfusion:Up()) then
		EternitySurge.empower_to = 1
		UseCooldown(EternitySurge)
	end
	if TipTheScales:Usable() and EverburningFlame.known and Firestorm.known and Dragonrage:Up() and FireBreath:Ready() then
		UseCooldown(TipTheScales)
	end
	if FireBreath:Usable() then
		if (
			(EverburningFlame.known and (not Firestorm:Ready(2 * Player.gcd) or not Firestorm:Ticking())) or
			(FeedTheFlames.known and not Dragonrage:Ready(10)) or
			(not EverburningFlame.known and not FeedTheFlames.known)
		) then
			FireBreath.empower_to = 1
			return FireBreath
		end
		if EverburningFlame.known then
			FireBreath.empower_to = 2
			return FireBreath
		end
	end
	if Firestorm:Usable() and (
		Player.enemies > 1 or
		Snapfire:Up() or
		(EverburningFlame.known and (FireBreath:Ready() or (FireBreath.dot:Remains() >= Firestorm:CastTime() and FireBreath.dot:Remains() < FireBreath:Cooldown())))
	) then
		return Firestorm
	end
	if EternitySurge:Usable() then
		if Player.enemies > (3 * (EternitysSpan.known and 2 or 1)) then
			EternitySurge.empower_to = 4
			UseCooldown(EternitySurge)
		elseif Player.enemies > (2 * (EternitysSpan.known and 2 or 1)) then
			EternitySurge.empower_to = 3
			UseCooldown(EternitySurge)
		elseif Player.enemies > (EternitysSpan.known and 2 or 1) then
			EternitySurge.empower_to = 2
			UseCooldown(EternitySurge)
		elseif (EternitySurge:CooldownDuration() - Dragonrage:Cooldown()) < (Dragonrage:Duration() + 6 - Player.gcd) then
			EternitySurge.empower_to = 1
			UseCooldown(EternitySurge)
		end
	end
	if ShatteringStar:Usable() and (not ArcaneVigor.known or (Player.essence.current + 1) < Player.essence.max or Dragonrage:Up()) then
		return ShatteringStar
	end
	if Pyre:Usable() and Player.enemies > 2 and (Player.essence.deficit == 0 or EssenceBurst:Up() or ShatteringStar:Up()) and ChargedBlast:Stack() >= ChargedBlast:MaxStack() and (not ShatteringStar.known or not ShatteringStar:Ready(Player.gcd * 2) or ShatteringStar:Up()) and (not Dragonrage:Ready(20) or Target.timeToDie < 30) then
		return Pyre
	end
	if AzureStrike:Usable() and Player.essence.deficit > 0 and Burnout:Down() and Player.enemies > (Dragonrage:Up() and 1 or 2) and EssenceBurst:Stack() < EssenceBurst:MaxStack() and (not RubyEmbers.known or Player.enemies > 2) then
		return AzureStrike
	end
	if Pyre:Usable() and (Player.enemies > ((Scintillation.known and EternitysSpan.known) and 3 or 2) or (ChargedBlast:Stack() >= ChargedBlast:MaxStack() and (not Dragonrage:Ready(20) or Target.timeToDie < 30) and Player.enemies > 2)) then
		return Pyre
	end
	if LivingFlame:Usable() and Player.essence.deficit > 0 and EssenceBurst:Stack() < EssenceBurst:MaxStack() and (Burnout:Up() or (not EngulfingBlaze.known and not ShatteringStar.known and Dragonrage:Up() and Target.health.pct > 80)) then
		return LivingFlame
	end
	if Disintegrate:Usable() and Dragonrage:Up() then
		return Disintegrate
	end
	if Disintegrate:Usable() and (Player.essence.deficit == 0 or EssenceBurst:Stack() >= EssenceBurst:MaxStack() or not ShatteringStar.known or ShatteringStar:Up() or not ShatteringStar:Ready(3 * Player.gcd)) then
		return Disintegrate
	end
	if AzureStrike:Usable() and (Player.enemies > 2 or (Dragonrage:Up() and (EngulfingBlaze.known or FeedTheFlames.known))) then
		return AzureStrike
	end
	if LivingFlame:Usable() then
		return LivingFlame
	end
end

APL[SPEC.PRESERVATION].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseCooldown(SummonSteward)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 300 then
			return BlessingOfTheBronze
		end
	else
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 10 then
			UseExtra(BlessingOfTheBronze)
		end
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
end

APL.Interrupt = function(self)
	if Quell:Usable() then
		return Quell
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard and actionButton.overlay then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	badDragonPanel:EnableMouse(Opt.aoe or not Opt.locked)
	badDragonPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		badDragonPanel:SetScript('OnDragStart', nil)
		badDragonPanel:SetScript('OnDragStop', nil)
		badDragonPanel:RegisterForDrag('')
		badDragonPreviousPanel:EnableMouse(false)
		badDragonCooldownPanel:EnableMouse(false)
		badDragonInterruptPanel:EnableMouse(false)
		badDragonExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			badDragonPanel:SetScript('OnDragStart', badDragonPanel.StartMoving)
			badDragonPanel:SetScript('OnDragStop', badDragonPanel.StopMovingOrSizing)
			badDragonPanel:RegisterForDrag('LeftButton')
		end
		badDragonPreviousPanel:EnableMouse(true)
		badDragonCooldownPanel:EnableMouse(true)
		badDragonInterruptPanel:EnableMouse(true)
		badDragonExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	badDragonPanel:SetAlpha(Opt.alpha)
	badDragonPreviousPanel:SetAlpha(Opt.alpha)
	badDragonCooldownPanel:SetAlpha(Opt.alpha)
	badDragonInterruptPanel:SetAlpha(Opt.alpha)
	badDragonExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	badDragonPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	badDragonPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	badDragonCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	badDragonInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	badDragonExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	badDragonPreviousPanel:ClearAllPoints()
	badDragonPreviousPanel:SetPoint('TOPRIGHT', badDragonPanel, 'BOTTOMLEFT', -3, 40)
	badDragonCooldownPanel:ClearAllPoints()
	badDragonCooldownPanel:SetPoint('TOPLEFT', badDragonPanel, 'BOTTOMRIGHT', 3, 40)
	badDragonInterruptPanel:ClearAllPoints()
	badDragonInterruptPanel:SetPoint('BOTTOMLEFT', badDragonPanel, 'TOPRIGHT', 3, -21)
	badDragonExtraPanel:ClearAllPoints()
	badDragonExtraPanel:SetPoint('BOTTOMRIGHT', badDragonPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.DEVASTATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.PRESERVATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.DEVASTATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.PRESERVATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		badDragonPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		badDragonPanel:ClearAllPoints()
		badDragonPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.DEVASTATION and Opt.hide.devastation) or
		(Player.spec == SPEC.PRESERVATION and Opt.hide.preservation))
end

function UI:Disappear()
	badDragonPanel:Hide()
	badDragonPanel.icon:Hide()
	badDragonPanel.border:Hide()
	badDragonCooldownPanel:Hide()
	badDragonInterruptPanel:Hide()
	badDragonExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, dim_cd, text_center, text_cd, text_tl, text_tr

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.empower_to then
			text_center = format('RANK %d', Player.main.empower_to)
		elseif Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
	end
	if Player.cd then
		if Player.cd.empower_to then
			text_cd = format('RANK %d', Player.cd.empower_to)
		elseif Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.main and Player.main_freecast then
		if not badDragonPanel.freeCastOverlayOn then
			badDragonPanel.freeCastOverlayOn = true
			badDragonPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif badDragonPanel.freeCastOverlayOn then
		badDragonPanel.freeCastOverlayOn = false
		badDragonPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	badDragonPanel.dimmer:SetShown(dim)
	badDragonPanel.text.center:SetText(text_center)
	badDragonPanel.text.tl:SetText(text_tl)
	badDragonPanel.text.tr:SetText(text_tr)
	--badDragonPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	badDragonCooldownPanel.text:SetText(text_cd)
	badDragonCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:Main()
	if Player.main then
		badDragonPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Player.main.essence_cost > 0 and Player.main:EssenceCost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		badDragonCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			badDragonCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		badDragonExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			badDragonInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			badDragonInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		badDragonInterruptPanel.icon:SetShown(Player.interrupt)
		badDragonInterruptPanel.border:SetShown(Player.interrupt)
		badDragonInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and badDragonPreviousPanel.ability then
		if (Player.time - badDragonPreviousPanel.ability.last_used) > 10 then
			badDragonPreviousPanel.ability = nil
			badDragonPreviousPanel:Hide()
		end
	end

	badDragonPanel.icon:SetShown(Player.main)
	badDragonPanel.border:SetShown(Player.main)
	badDragonCooldownPanel:SetShown(Player.cd)
	badDragonExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = BadDragon
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_BadDragon1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		autoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end
	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
	if Player.rescan_abilities then
		Player:UpdateAbilities()
	end
end

function events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

--[[
function events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
end
]]

function events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		badDragonPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end

	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	badDragonPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	UI.OnResourceFrameShow()
	Player:Update()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		badDragonPanel.swipe:SetCooldown(start, duration)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
end

badDragonPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

badDragonPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

badDragonPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
for event in next, events do
	badDragonPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				badDragonPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'h') then
				Opt.hide.devastation = not Opt.hide.devastation
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Devastation specialization', not Opt.hide.devastation)
			end
			if startsWith(msg[2], 'v') then
				Opt.hide.preservation = not Opt.hide.preservation
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Preservation specialization', not Opt.hide.preservation)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000devastation|r/|cFFFFD000preservation|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if msg[1] == 'reset' then
		badDragonPanel:ClearAllPoints()
		badDragonPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000devastation|r/|cFFFFD000preservation|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_BadDragon1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
