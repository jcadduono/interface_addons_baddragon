local ADDON = 'BadDragon'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_BADDRAGON = ADDON
BINDING_NAME_BADDRAGON_TARGETMORE = "Toggle Targets +"
BINDING_NAME_BADDRAGON_TARGETLESS = "Toggle Targets -"
BINDING_NAME_BADDRAGON_TARGET1 = "Set Targets to 1"
BINDING_NAME_BADDRAGON_TARGET2 = "Set Targets to 2"
BINDING_NAME_BADDRAGON_TARGET3 = "Set Targets to 3"
BINDING_NAME_BADDRAGON_TARGET4 = "Set Targets to 4"
BINDING_NAME_BADDRAGON_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'EVOKER' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

BadDragon = {}
local Opt -- use this as a local table reference to BadDragon

SLASH_BadDragon1, SLASH_BadDragon2, SLASH_BadDragon3 = '/bd', '/bad', '/dragon'

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
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			devastation = false,
			preservation = false,
			augmentation = false,
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
		heal = 60,
		use_early_chaining = true,
		use_clipping = true,
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
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	DEVASTATION = 1,
	PRESERVATION = 2,
	AUGMENTATION = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.DEVASTATION] = {},
	[SPEC.PRESERVATION] = {},
	[SPEC.AUGMENTATION] = {},
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
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		base = 0,
		current = 0,
		max = 100,
		pct = 100,
		regen = 0,
	},
	essence = {
		current = 0,
		deficit = 0,
		max = 5,
		regen = 0,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	empower = {
		start = 0,
		ends = 0,
		rank = 0,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Scales of the Awakened
		t30 = 0, -- Legacy of Obsidian Secrets
		t31 = 0, -- Werynkeeper's Timeless Vigil
		t32 = 0, -- Scales of the Awakened (Awakened)
		t33 = 0, -- Destroyer's Scarred Wards
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
}

-- base mana pool max for each level
Player.BaseMana = {
	260,	270,	285,	300,	310,	--  5
	330,	345,	360,	380,	400,	-- 10
	430,	465,	505,	550,	595,	-- 15
	645,	700,	760,	825,	890,	-- 20
	965,	1050,	1135,	1230,	1335,	-- 25
	1445,	1570,	1700,	1845,	2000,	-- 30
	2165,	2345,	2545,	2755,	2990,	-- 35
	3240,	3510,	3805,	4125,	4470,	-- 40
	4845,	5250,	5690,	6170,	6685,	-- 45
	7245,	7855,	8510,	9225,	10000,	-- 50
	11745,	13795,	16205,	19035,	22360,	-- 55
	26265,	30850,	36235,	42565,	50000,	-- 60
	58730,	68985,	81030,	95180,	111800,	-- 65
	131325,	154255,	181190,	212830,	250000,	-- 70
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
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

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
}

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
	[SPEC.AUGMENTATION] = {
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

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
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

function AutoAoe:Purge()
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
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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

function Ability:Usable(seconds)
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
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
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
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.base) or 0
end

function Ability:EssenceCost()
	return self.essence_cost
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self or (self.empowered_spell and Player.empower.ability == self)
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
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
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if self.empower_to then
		self.empower_to = nil
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
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and badDragonPreviousPanel.ability == self then
		badDragonPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

-- Evoker Abilities
---- Class
------ Baseline
local AzureStrike = Ability:Add(362969, false, true)
AzureStrike.mana_cost = 0.9
AzureStrike.max_range = 25
AzureStrike.color = 'blue'
AzureStrike.triggers_combat = true
AzureStrike:AutoAoe()
local BlessingOfTheBronze = Ability:Add(364342, true, false, 381748)
BlessingOfTheBronze.buff_duration = 3600
BlessingOfTheBronze.color = 'bronze'
local DeepBreath = Ability:Add(357210, true, true)
DeepBreath.cooldown_duration = 120
DeepBreath.buff_duration = 6
DeepBreath.color = 'black'
DeepBreath.triggers_combat = true
DeepBreath.dot = Ability:Add(353759, false, true)
DeepBreath.dot:AutoAoe(false, 'apply')
local Disintegrate = Ability:Add(356995, false, true)
Disintegrate.essence_cost = 3
Disintegrate.buff_duration = 3
Disintegrate.tick_interval = 1
Disintegrate.max_range = 25
Disintegrate.hasted_ticks = true
Disintegrate.hasted_duration = true
Disintegrate.color = 'blue'
Disintegrate.triggers_combat = true
local EmeraldBlossom = Ability:Add(355913, true, true)
EmeraldBlossom.mana_cost = 4.8
EmeraldBlossom.cooldown_duration = 30
EmeraldBlossom.color = 'green'
local FireBreath = Ability:Add(357208, false, true)
FireBreath.mana_cost = 2.6
FireBreath.cooldown_duration = 30
FireBreath.triggers_combat = true
FireBreath.learn_spellId = 357208
FireBreath.spellId_fom = 382266
FireBreath.empowered_spell = true
FireBreath.max_empower = 3
FireBreath.color = 'red'
FireBreath.dot = Ability:Add(357209, false, true)
FireBreath.dot.buff_duration = 24
FireBreath.dot:AutoAoe()
local Hover = Ability:Add(358267, true, true)
Hover.buff_duration = 6
Hover.cooldown_duration = 35
Hover.requires_charge = true
local LivingFlame = Ability:Add(361469, false, true, 361500)
LivingFlame.mana_cost = 2
LivingFlame.max_range = 25
LivingFlame.color = 'red'
LivingFlame.triggers_combat = true
------ Talents
local AncientFlame = Ability:Add(369990, true, true, 375583)
local BlastFurnace = Ability:Add(375510, true, true)
BlastFurnace.talent_node = 68667
local FontOfMagic = Ability:Add({375783, 408083, 411212}, true, true)
local LeapingFlames = Ability:Add(369939, true, true, 370901)
LeapingFlames.buff_duration = 30
local NaturalConvergence = Ability:Add(369913, false, true)
local Quell = Ability:Add(351338, false, true)
Quell.cooldown_duration = 40
Quell.buff_duration = 4
Quell.max_range = 25
local ScarletAdaptation = Ability:Add(372469, true, true, 372470)
local TipTheScales = Ability:Add(370553, true, true)
TipTheScales.cooldown_duration = 120
TipTheScales.color = 'bronze'
local VerdantEmbrace = Ability:Add(360995, true, true)
VerdantEmbrace.mana_cost = 3
VerdantEmbrace.cooldown_duration = 24
VerdantEmbrace.color = 'green'
------ Procs
local LimitlessPotential = Ability:Add(394402, true, true)
LimitlessPotential.buff_duration = 6
---- Devastation
------ Talents
local Animosity = Ability:Add(375797, true, true)
local ArcaneVigor = Ability:Add(386342, true, true)
local Burnout = Ability:Add(375801, true, true, 375802)
Burnout.buff_duration = 15
Burnout.talent_node = 68633
local Causality = Ability:Add(375777, false, true)
local ChargedBlast = Ability:Add(370455, true, true, 370454)
ChargedBlast.buff_duration = 30
local DenseEnergy = Ability:Add(370962, true, true)
local Dragonrage = Ability:Add(375087, true, true)
Dragonrage.cooldown_duration = 120
Dragonrage.buff_duration = 14
Dragonrage.color = 'red'
Dragonrage.triggers_combat = true
local EngulfingBlaze = Ability:Add(370837, true, true)
local EssenceAttunement = Ability:Add(375722, true, true)
local EternitySurge = Ability:Add(359073, false, true, 359077)
EternitySurge.cooldown_duration = 30
EternitySurge.max_range = 25
EternitySurge.triggers_combat = true
EternitySurge.learn_spellId = 359073
EternitySurge.spellId_fom = 382411
EternitySurge.color = 'blue'
EternitySurge.empowered_spell = true
EternitySurge.max_empower = 3
EternitySurge:AutoAoe()
local EternitysSpan = Ability:Add(375757, true, true)
local EverburningFlame = Ability:Add(370819, true, true)
local EyeOfInfinity = Ability:Add(411165, false, true)
local FeedTheFlames = Ability:Add(369846, true, true, 405874)
FeedTheFlames.buff_duration = 120
FeedTheFlames.buff = Ability:Add(411288, true, true)
FeedTheFlames.buff.buff_duration = 60
local Firestorm = Ability:Add(368847, false, true)
Firestorm.cooldown_duration = 20
Firestorm.buff_duration = 12
Firestorm.max_range = 25
Firestorm.color = 'red'
Firestorm.triggers_combat = true
Firestorm:AutoAoe()
Firestorm:TrackAuras()
local Iridescence = Ability:Add(370867, true, true)
Iridescence.blue = Ability:Add(386399, true, true)
Iridescence.blue.buff_duration = 10
Iridescence.blue.max_stack = 2
Iridescence.blue.color = 'blue'
Iridescence.red = Ability:Add(386353, true, true)
Iridescence.red.buff_duration = 10
Iridescence.red.max_stack = 2
Iridescence.red.color = 'red'
local PowerSwell = Ability:Add(370839, true, true, 376850)
PowerSwell.buff_duration = 4
local Pyre = Ability:Add(357211, false, true, 357212)
Pyre.essence_cost = 3
Pyre.color = 'red'
Pyre.triggers_combat = true
Pyre:AutoAoe()
local RagingInferno = Ability:Add(405659, false, true)
local RubyEmbers = Ability:Add(365937, false, true)
RubyEmbers.buff_duration = 12
local Scintillation = Ability:Add(370821, false, true)
Scintillation.talent_node = 68629
local ShatteringStar = Ability:Add(370452, false, true)
ShatteringStar.cooldown_duration = 15
ShatteringStar.buff_duration = 4
ShatteringStar.max_range = 25
ShatteringStar.color = 'blue'
ShatteringStar.triggers_combat = true
ShatteringStar:AutoAoe()
local Snapfire = Ability:Add(370783, true, true, 370818)
Snapfire.buff_duration = 15
local Volatility = Ability:Add(369089, false, true)
Volatility.talent_node = 68647
------ Procs
local EssenceBurstDevastation = Ability:Add(359565, true, true, 359618)
EssenceBurstDevastation.buff_duration = 15
---- Preservation
------ Talents
local BlisteringScales = Ability:Add(360827, true, true)
BlisteringScales.cooldown_duration = 30
BlisteringScales.buff_duration = 600
BlisteringScales.color = 'black'
local BreathOfEons = Ability:Add(403631, true, true)
BreathOfEons.cooldown_duration = 120
BreathOfEons.buff_duration = 6
BreathOfEons.color = 'bronze'
BreathOfEons.triggers_combat = true
local EbonMight = Ability:Add(395152, true, true, 395296)
EbonMight.cooldown_duration = 30
EbonMight.buff_duration = 10
EbonMight.color = 'black'
EbonMight.mana_cost = 1
local Eruption = Ability:Add(395160, false, true)
Eruption.essence_cost = 3
Eruption.max_range = 25
Eruption.color = 'black'
Eruption.triggers_combat = true
Eruption:AutoAoe()
local InterwovenThreads = Ability:Add(412713, true, true)
local Prescience = Ability:Add(409311, true, true, 410089)
Prescience.cooldown_duration = 12
Prescience.color = 'bronze'
local PupilOfAlexstrasza = Ability:Add(407814, false, true)
local TemporalWound = Ability:Add(409560, false, true) -- applied by Breath of Eons
TemporalWound.buff_duration = 10
TemporalWound.color = 'bronze'
TemporalWound:AutoAoe(false, 'apply')
local TimeSkip = Ability:Add(404977, false, true)
TimeSkip.cooldown_duration = 180
TimeSkip.buff_duration = 2
TimeSkip.tick_interval = 2
TimeSkip.color = 'bronze'
local Upheaval = Ability:Add(396286, false, true, 396288)
Upheaval.cooldown_duration = 40
Upheaval.triggers_combat = true
Upheaval.empowered_spell = true
Upheaval.max_empower = 3
Upheaval.spellId_fom = 408092
Upheaval.color = 'black'
Upheaval.triggers_combat = true
Upheaval:AutoAoe()
local Volcanism = Ability:Add(406904, false, true)
------ Procs
local EssenceBurstAugmentation = Ability:Add(396187, true, true, 392268)
EssenceBurstAugmentation.buff_duration = 15
---- Augmentation
------ Talents

------ Procs

-- Tier set bonuses
local BlazingShards = Ability:Add(409848, true, true) -- Devastation T30/T32 4pc
BlazingShards.buff_duration = 5
-- Racials
local TailSwipe = Ability:Add(368970, false, true)
TailSwipe.cooldown_duration = 90
local WingBuffet = Ability:Add(357214, false, true)
WingBuffet.cooldown_duration = 90
-- PvP talents

-- Trinket effects
local SolarMaelstrom = Ability:Add(422146, false, true) -- Belor'relos
SolarMaelstrom:AutoAoe()
-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 15
PowerInfusion.cooldown_duration = 120
-- Aliases
local EssenceBurst = EssenceBurstDevastation
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
		off_gcd = true,
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
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
-- Equipment
local DreambinderLoomOfTheGreatCycle = InventoryItem:Add(208616)
DreambinderLoomOfTheGreatCycle.cooldown_duration = 120
DreambinderLoomOfTheGreatCycle.off_gcd = false
local IridalTheEarthsMaster = InventoryItem:Add(208321)
IridalTheEarthsMaster.cooldown_duration = 180
IridalTheEarthsMaster.off_gcd = false
local KharnalexTheFirstLight = InventoryItem:Add(195519)
KharnalexTheFirstLight.cooldown_duration = 180
KharnalexTheFirstLight.off_gcd = false
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.BelorrelosTheSuncaller = InventoryItem:Add(207172)
Trinket.BelorrelosTheSuncaller.cast_spell = SolarMaelstrom
Trinket.BelorrelosTheSuncaller.cooldown_duration = 120
Trinket.BelorrelosTheSuncaller.off_gcd = false
Trinket.NymuesUnravelingSpindle = InventoryItem:Add(208615)
Trinket.NymuesUnravelingSpindle.cooldown_duration = 120
Trinket.NymuesUnravelingSpindle.off_gcd = false
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ManaTimeToMax()
	local deficit = self.mana.max - self.mana.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.mana.regen
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
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
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Exhausted()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HARMFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 57724 or -- Sated (Alliance Shaman)
			aura.spellId == 57723 or -- Exhaustion (Horde Shaman)
			aura.spellId == 80354 or -- Temporal Displacement (Mage)
			aura.spellId == 264689 or-- Fatigued (Hunter)
			aura.spellId == 390435   -- Exhaustion (Evoker)
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

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			info = GetSpellInfo(spellId)
			if info then
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
			end
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	EssenceBurst = (
		(EssenceBurstAugmentation.known and EssenceBurstAugmentation) or
		(EssenceBurstDevastation.known and EssenceBurstDevastation)
	)
	DeepBreath.dot.known = DeepBreath.known
	FireBreath.dot.known = FireBreath.known
	if FontOfMagic.known then
		FireBreath.spellId = FireBreath.spellId_fom
		EternitySurge.spellId = EternitySurge.spellId_fom
		Upheaval.spellId = Upheaval.spellId_fom
	end
	BlazingShards.known = Player.spec == SPEC.DEVASTATION and (self.set_bonus.t30 >= 4 or self.set_bonus.t32 >= 4)
	if InterwovenThreads.known then
		TimeSkip.known = false
	end

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateEmpowerInfo()
	local empower = self.empower
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	local ability = spellId and Abilities.bySpellId[spellId]
	if not (ability and ability.empowered_spell) then
		empower.ability = nil
		empower.start = 0
		empower.ends = 0
		empower.rank = 0
		return
	end
	empower.ability = ability
	empower.start = start / 1000
	empower.ends = ends / 1000
	empower.rank = 0
	empower.haste_factor = 1 / (1 + (UnitSpellHaste('player') + (FontOfMagic.known and (FontOfMagic.spellId == 408083 or FontOfMagic.spellId == 411212) and 20 or 0)) / 100)
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	if self.empower.ability then
		self.empower.rank = floor(clamp((self.ctime - self.empower.start - (0.250 * self.empower.haste_factor)) / (0.750 * self.empower.haste_factor), 0, self.empower.ability:MaxEmpower()))
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.cast.ability and self.cast.ability.mana_cost > 0 then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.mana.pct = self.mana.current / self.mana.max * 100
	self.essence.regen = GetPowerRegenForPowerType(19)
	self.essence.current = UnitPower('player', 19)
	if self.cast.ability and self.cast.ability.essence_cost > 0 then
		self.essence.current = self.essence.current - self.cast.ability:EssenceCost()
	end
	self.essence.current = clamp(self.essence.current, 0, self.essence.max)
	self.essence.deficit = self.essence.max - self.essence.current
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
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
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
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
	self.timeToDieMax = self.health.current / Player.health.max * (Player.spec == SPEC.DEVASTATION and 20 or 10)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
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
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		badDragonPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

-- End Target Functions

-- Start Ability Modifications

function Ability:MaxEmpower()
	if self.empowered_spell then
		return (self.max_empower or 0) + (FontOfMagic.known and 1 or 0)
	end
	return 0
end

function EssenceBurstDevastation:Remains()
	if Dragonrage.known and LivingFlame:Casting() and Dragonrage:Up() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function EssenceBurstDevastation:Stack()
	local stack = Ability.Stack(self)
	if Dragonrage.known and LivingFlame:Casting() and Dragonrage:Up() then
		stack = stack + 1
		if LeapingFlames.known then
			stack = stack + min(Player.enemies - 1, Ability.Stack(LeapingFlames))
		end
	end
	return clamp(stack, 0, self:MaxStack())
end

function EssenceBurstDevastation:MaxStack()
	return 1 + (EssenceAttunement.known and 1 or 0)
end

function EssenceBurstAugmentation:Remains()
	if self:Stack() == 0 then
		return 0
	end
	return Ability.Remains(self)
end

function EssenceBurstAugmentation:Stack()
	local stack = Ability.Stack(self)
	if Eruption.known and Eruption:Casting() then
		stack = stack - 1
	end
	return clamp(stack, 0, self:MaxStack())
end

EssenceBurstAugmentation.MaxStack = EssenceBurstDevastation.MaxStack

function Disintegrate:EssenceCost()
	if EssenceBurst:Up() then
		return 0
	end
	return Ability.EssenceCost(self)
end

function Disintegrate:Duration()
	return Player.haste_factor * self.buff_duration * (NaturalConvergence.known and 0.80 or 1)
end

function Disintegrate:TickTime()
	return Player.haste_factor * self.tick_interval * (NaturalConvergence.known and 0.80 or 1)
end

function Eruption:EssenceCost()
	if EssenceBurst:Up() then
		return 0
	end
	local cost = Ability.EssenceCost(self)
	if Volcanism.known then
		cost = cost - 1
	end
	return max(0, cost)
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

function Firestorm:Free()
	return Snapfire.known and Snapfire:Up()
end

function LivingFlame:Free()
	return Burnout:Up()
end

function LeapingFlames:Remains()
	if self.known and FireBreath:Channeling() then
		return self:Duration()
	end
	if LivingFlame:Casting() then
		return 0
	end
	return Ability.Remains(self)
end

function TipTheScales:Cooldown()
	if self:Up() then
		return self:CooldownDuration()
	end
	return Ability.Cooldown(self)
end

function Iridescence.blue:Remains()
	if Player.empower.ability and Player.empower.ability.color == self.color then
		return self:Duration()
	end
	local stack = self:Stack()
	if stack == 0 then
		return 0
	end
	return Ability.Remains(self)
end
Iridescence.red.Remains = Iridescence.blue.Remains

function Iridescence.blue:Stack()
	if Player.empower.ability and Player.empower.ability.color == self.color then
		return self.max_stack
	end
	local stack = Ability.Stack(self)
	if Player.cast.ability and not Player.cast.ability.empowered_spell and Player.cast.ability.color == self.color then
		stack = stack - 1
	end
	return max(0, stack)
end
Iridescence.red.Stack = Iridescence.blue.Stack

function PowerSwell:Remains()
	if Player.empower.ability then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function EbonMight:Remains()
	local remains = Ability.Remains(self)
	if remains > 0 then
		if Eruption:Casting() then
			remains = remains + 1
		end
		if FireBreath:Channeling() or Upheaval:Channeling() then
			remains = remains + 2
		end
	end
	return remains
end

function BlisteringScales:CastSuccess(dstGUID)
	Ability.CastSuccess(self, dstGUID)
	local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(dstGUID)
	if name and #name > 0 then
		if realm and #realm > 0 then
			self.aura_target = name .. '-' .. realm
		else
			self.aura_target = name
		end
	else
		self.aura_target = 'player'
	end
end

function IridalTheEarthsMaster:Usable(...)
	return Target.health.pct < 35 and InventoryItem.Usable(self, ...)
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

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.DEVASTATION].Main = function(self)
	if Player.health.pct < Opt.heal then
		if EmeraldBlossom:Usable() then
			UseExtra(EmeraldBlossom)
		elseif VerdantEmbrace:Usable() then
			UseExtra(VerdantEmbrace)
		elseif LivingFlame:Usable() and Burnout:Up() then
			UseExtra(LivingFlame)
		end
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/snapshot_stats
actions.precombat+=/variable,name=trinket_1_buffs,value=trinket.1.has_buff.intellect|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit
actions.precombat+=/variable,name=trinket_2_buffs,value=trinket.2.has_buff.intellect|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_1_buffs&(trinket.1.cooldown.duration%%cooldown.dragonrage.duration=0|cooldown.dragonrage.duration%%trinket.1.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_2_buffs&(trinket.2.cooldown.duration%%cooldown.dragonrage.duration=0|cooldown.dragonrage.duration%%trinket.2.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_1_manual,value=trinket.1.is.spoils_of_neltharus
actions.precombat+=/variable,name=trinket_2_manual,value=trinket.2.is.spoils_of_neltharus
actions.precombat+=/variable,name=trinket_1_exclude,value=trinket.1.is.ruby_whelp_shell|trinket.1.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_2_exclude,value=trinket.2.is.ruby_whelp_shell|trinket.2.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!variable.trinket_1_buffs&variable.trinket_2_buffs|variable.trinket_2_buffs&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.intellect)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.intellect)*(variable.trinket_1_sync))
actions.precombat+=/variable,name=r1_cast_time,value=1.0*spell_haste
actions.precombat+=/variable,name=dr_prep_time_aoe,default=4,op=reset
actions.precombat+=/variable,name=dr_prep_time_st,default=13,op=reset
actions.precombat+=/variable,name=has_external_pi,value=cooldown.invoke_power_infusion_0.duration>0
actions.precombat+=/verdant_embrace,if=talent.scarlet_adaptation|talent.ancient_flame
actions.precombat+=/use_item,name=shadowed_orb_of_torment
actions.precombat+=/firestorm,if=talent.firestorm
actions.precombat+=/living_flame,if=!talent.firestorm
]]
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 300 then
			return BlessingOfTheBronze
		end
		if Firestorm:Usable() and Dragonrage:Down() then
			return Firestorm
		end
		if Target.boss and LivingFlame:Usable() and Dragonrage:Down() then
			return LivingFlame
		end
	else
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 10 then
			UseExtra(BlessingOfTheBronze)
		end
		if Player.moving and Hover:Usable() and Hover:Down() then
			UseExtra(Hover)
		end
	end
--[[
actions=potion,if=buff.dragonrage.up&(!cooldown.shattering_star.up|active_enemies>=2)|fight_remains<35
actions+=/variable,name=next_dragonrage,value=cooldown.dragonrage.remains<?(cooldown.eternity_surge.remains-2*gcd.max)<?(cooldown.fire_breath.remains-gcd.max)
actions+=/invoke_external_buff,name=power_infusion,if=buff.dragonrage.up&!buff.power_infusion.up&!cooldown.fire_breath.up&!cooldown.shattering_star.up
actions+=/quell,use_off_gcd=1,if=target.debuff.casting.react
actions+=/call_action_list,name=trinkets
actions+=/run_action_list,name=aoe,if=active_enemies>=3
actions+=/run_action_list,name=st
]]
	self.dr_prep_time_aoe = 4
	self.dr_prep_time_st = 13
	self.use_dragonrage = Target.player or (Target.boss and Target.timeToDie < 30) or Target.timeToDie > (35 - (3 * Player.enemies))
	self.next_dragonrage = max(Dragonrage:Cooldown(), EternitySurge:Cooldown() - (2 * Player.gcd), FireBreath:Cooldown() - Player.gcd)
	self.r1_cast_time = 1.0 * Player.haste_factor
	self:trinkets()
	if Player.enemies >= 3 then
		return self:aoe()
	end
	return self:st()
end

APL[SPEC.DEVASTATION].aoe = function(self)
--[[
actions.aoe=shattering_star,target_if=max:target.health.pct,if=cooldown.dragonrage.up
actions.aoe+=/dragonrage,if=target.time_to_die>=32|fight_remains<30
actions.aoe+=/tip_the_scales,if=buff.dragonrage.up&(active_enemies<=3+3*talent.eternitys_span|!cooldown.fire_breath.up)
actions.aoe+=/call_action_list,name=fb,if=(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_aoe|!talent.animosity)&(buff.power_swell.remains<variable.r1_cast_time&buff.blazing_shards.remains<variable.r1_cast_time|buff.dragonrage.up)&(target.time_to_die>=8|fight_remains<30)
actions.aoe+=/call_action_list,name=es,if=buff.dragonrage.up|!talent.dragonrage|(cooldown.dragonrage.remains>variable.dr_prep_time_aoe&buff.power_swell.remains<variable.r1_cast_time&buff.blazing_shards.remains<variable.r1_cast_time)&(target.time_to_die>=8|fight_remains<30)
actions.aoe+=/deep_breath,if=!buff.dragonrage.up
actions.aoe+=/shattering_star,target_if=max:target.health.pct,if=buff.essence_burst.stack<buff.essence_burst.max_stack|!talent.arcane_vigor
actions.aoe+=/firestorm
actions.aoe+=/living_flame,target_if=max:target.health.pct,if=buff.burnout.up&buff.leaping_flames.up&!buff.essence_burst.up&(essence.deficit>=2|buff.burnout.remains<gcd*2|buff.leaping_flames.remains<gcd*2)
actions.aoe+=/pyre,target_if=max:target.health.pct,if=talent.volatility&(active_enemies>=4|(talent.charged_blast&!buff.essence_burst.up&!buff.iridescence_blue.up)|(!talent.charged_blast&(!buff.essence_burst.up|!buff.iridescence_blue.up))|(buff.charged_blast.stack>=15)|(talent.raging_inferno&debuff.in_firestorm.up))
actions.aoe+=/pyre,target_if=max:target.health.pct,if=(talent.raging_inferno&debuff.in_firestorm.up)|(active_enemies==3&buff.charged_blast.stack>=15)|active_enemies>=4
actions.aoe+=/living_flame,target_if=max:target.health.pct,if=buff.leaping_flames.remains>cast_time&!buff.essence_burst.up&essence.deficit>=2&(!talent.burnout|buff.burnout.up|(!dot.fire_breath.ticking|cooldown.fire_breath.remains<gcd*2)&(active_enemies>=4|buff.scarlet_adaptation.up&(buff.ancient_flame.up|buff.dragonrage.down)))
actions.aoe+=/use_item,name=kharnalex_the_first_light,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down&active_enemies<=5
actions.aoe+=/disintegrate,target_if=max:target.health.pct,chain=1,early_chain_if=evoker.use_early_chaining&(buff.dragonrage.up|essence.deficit<=1)&ticks>=2&(raid_event.movement.in>2|buff.hover.up),interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(raid_event.movement.in>2|buff.hover.up),if=raid_event.movement.in>2|buff.hover.up
actions.aoe+=/living_flame,target_if=max:target.health.pct,if=talent.snapfire&buff.burnout.up
actions.aoe+=/azure_strike,target_if=max:target.health.pct
]]
	if self.use_dragonrage and Dragonrage:Down() then
		if ShatteringStar:Usable() and Dragonrage:Ready(Player.gcd) and (ArcaneVigor.known or EssenceBurst:Up()) then
			return ShatteringStar
		end
		if Dragonrage:Usable() then
			UseCooldown(Dragonrage)
		end
	end
	if TipTheScales:Usable() and Dragonrage:Up() and (Player.enemies <= (3 + (EternitysSpan.known and 3 or 0)) or not FireBreath:Ready()) then
		UseCooldown(TipTheScales)
	end
	if FireBreath:Usable() and (not Dragonrage.known or self.next_dragonrage > self.dr_prep_time_aoe or not Animosity.known) and (Dragonrage:Up() or ((not PowerSwell.known or PowerSwell:Remains() < self.r1_cast_time) and (not BlazingShards.known or BlazingShards:Remains() < self.r1_cast_time))) then
		local apl = self:fb()
		if apl then return apl end
	end
	if EternitySurge:Usable() and (not Dragonrage.known or Dragonrage:Up() or (self.next_dragonrage > self.dr_prep_time_aoe and (not PowerSwell.known or PowerSwell:Remains() < self.r1_cast_time) and (not BlazingShards.known or BlazingShards:Remains() < self.r1_cast_time))) then
		local apl = self:es()
		if apl then return apl end
	end
	if DeepBreath:Usable() and Dragonrage:Down() then
		UseCooldown(DeepBreath)
	end
	if ShatteringStar:Usable() and (not ArcaneVigor.known or EssenceBurst:Stack() < EssenceBurst:MaxStack()) then
		return ShatteringStar
	end
	if Firestorm:Usable() then
		return Firestorm
	end
	if Burnout.known and LeapingFlames.known and LivingFlame:Usable() and Burnout:Up() and LeapingFlames:Up() and EssenceBurst:Down() and (Player.essence.deficit >= 2 or Burnout:Remains() < (Player.gcd * 2) or LeapingFlames:Remains() < (Player.gcd * 2)) then
		return LivingFlame
	end
	if Pyre:Usable() and (
		Player.enemies >= 4 or
		(ChargedBlast.known and Player.enemies == 3 and ChargedBlast:Stack() >= 15) or
		(RagingInferno.known and Firestorm:Up()) or
		(Volatility.known and ((ChargedBlast.known and (ChargedBlast:Stack() >= 15 or (EssenceBurst:Down() and Iridescence.blue:Down()))) or (not ChargedBlast.known and (EssenceBurst:Down() or Iridescence.blue:Down()))))
	) then
		return Pyre
	end
	if LeapingFlames.known and LivingFlame:Usable() and LeapingFlames:Remains() > LivingFlame:CastTime() and EssenceBurst:Down() and Player.essence.deficit >= 2 and (not Burnout.known or Burnout:Up() or ((FireBreath.dot:Down() or FireBreath:Ready(Player.gcd * 2)) and (Player.enemies >= 4 or (ScarletAdaptation:Up() and (AncientFlame:Up() or Dragonrage:Down()))))) then
		return LivingFlame
	end
	if KharnalexTheFirstLight:Usable() and Dragonrage:Down() and ShatteringStar:Down() and Player.enemies <= 5 then
		UseCooldown(KharnalexTheFirstLight)
	end
	if Disintegrate:Usable() and (not Player.moving or Hover:Up()) then
		Player.channel.interrupt_if = self.channel_interrupt[3]
		Player.channel.early_chain_if = self.channel_early_chain[3]
		return Disintegrate
	end
	if Snapfire.known and Burnout.known and LivingFlame:Usable() and Burnout:Up() then
		return LivingFlame
	end
	if AzureStrike:Usable() then
		return AzureStrike
	end
end

APL[SPEC.DEVASTATION].st = function(self)
--[[
actions.st=use_item,name=kharnalex_the_first_light,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down&raid_event.movement.in>6
actions.st+=/hover,use_off_gcd=1,if=raid_event.movement.in<2&!buff.hover.up
actions.st+=/firestorm,if=buff.snapfire.up
actions.st+=/dragonrage,if=cooldown.fire_breath.remains<4&cooldown.eternity_surge.remains<10&target.time_to_die>=32|fight_remains<30
actions.st+=/tip_the_scales,if=buff.dragonrage.up&(((!talent.font_of_magic|talent.everburning_flame)&cooldown.fire_breath.up&!cooldown.eternity_surge.up)|(!talent.everburning_flame&talent.font_of_magic&cooldown.eternity_surge.up&!cooldown.fire_breath.up)|buff.dragonrage.remains<variable.r1_cast_time&(cooldown.fire_breath.remains<buff.dragonrage.remains|cooldown.eternity_surge.remains<buff.dragonrage.remains))
actions.st+=/call_action_list,name=fb,if=set_bonus.tier30_4pc&(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_st|!talent.animosity)&((buff.power_swell.remains<variable.r1_cast_time|buff.bloodlust.up|buff.power_infusion.up)&(buff.blazing_shards.remains<variable.r1_cast_time|buff.dragonrage.up))&(active_enemies>=2|target.time_to_die>=8|fight_remains<30)
actions.st+=/call_action_list,name=fb,if=!set_bonus.tier30_4pc&(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_st|!talent.animosity)&((buff.limitless_potential.remains<variable.r1_cast_time|!buff.power_infusion.up)&buff.power_swell.remains<variable.r1_cast_time&buff.blazing_shards.remains<variable.r1_cast_time)&(active_enemies>=2|target.time_to_die>=8|fight_remains<30)
actions.st+=/shattering_star,if=buff.essence_burst.stack<buff.essence_burst.max_stack|!talent.arcane_vigor
actions.st+=/call_action_list,name=es,if=set_bonus.tier30_4pc&(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_st|!talent.animosity)&((buff.power_swell.remains<variable.r1_cast_time|buff.bloodlust.up|buff.power_infusion.up)&(buff.blazing_shards.remains<variable.r1_cast_time|buff.dragonrage.up))&(active_enemies>=2|target.time_to_die>=8|fight_remains<30)
actions.st+=/call_action_list,name=es,if=!set_bonus.tier30_4pc&(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_st|!talent.animosity)&((buff.limitless_potential.remains<variable.r1_cast_time|!buff.power_infusion.up)&buff.power_swell.remains<variable.r1_cast_time&buff.blazing_shards.remains<variable.r1_cast_time)&(active_enemies>=2|target.time_to_die>=8|fight_remains<30)
actions.st+=/wait,sec=cooldown.fire_breath.remains,if=talent.animosity&buff.dragonrage.up&buff.dragonrage.remains<gcd.max+variable.r1_cast_time*buff.tip_the_scales.down&buff.dragonrage.remains-cooldown.fire_breath.remains>=variable.r1_cast_time*buff.tip_the_scales.down
actions.st+=/wait,sec=cooldown.eternity_surge.remains,if=talent.animosity&buff.dragonrage.up&buff.dragonrage.remains<gcd.max+variable.r1_cast_time&buff.dragonrage.remains-cooldown.eternity_surge.remains>variable.r1_cast_time*buff.tip_the_scales.down
actions.st+=/living_flame,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max&buff.burnout.up
actions.st+=/azure_strike,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max
actions.st+=/living_flame,if=buff.burnout.up&(buff.leaping_flames.up&!buff.essence_burst.up|!buff.leaping_flames.up&buff.essence_burst.stack<buff.essence_burst.max_stack)&essence.deficit>=2
actions.st+=/pyre,if=debuff.in_firestorm.up&talent.raging_inferno&buff.charged_blast.stack==20&active_enemies>=2
actions.st+=/disintegrate,chain=1,early_chain_if=evoker.use_early_chaining&ticks>=2&buff.dragonrage.up&!(buff.power_infusion.up&buff.bloodlust.up)&(raid_event.movement.in>2|buff.hover.up),interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(!(buff.power_infusion.up&buff.bloodlust.up)|cooldown.fire_breath.up|cooldown.eternity_surge.up)&(raid_event.movement.in>2|buff.hover.up),if=set_bonus.tier30_4pc&raid_event.movement.in>2|buff.hover.up
actions.st+=/disintegrate,chain=1,early_chain_if=evoker.use_early_chaining&buff.dragonrage.up&ticks>=2&(raid_event.movement.in>2|buff.hover.up),interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(raid_event.movement.in>2|buff.hover.up),if=!set_bonus.tier30_4pc&raid_event.movement.in>2|buff.hover.up
actions.st+=/firestorm,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down
actions.st+=/deep_breath,if=!buff.dragonrage.up&active_enemies>=2&((raid_event.adds.in>=120&!talent.onyx_legacy)|(raid_event.adds.in>=60&talent.onyx_legacy))
actions.st+=/deep_breath,if=!buff.dragonrage.up&talent.imminent_destruction&!debuff.shattering_star_debuff.up
actions.st+=/verdant_embrace,if=talent.ancient_flame&talent.scarlet_adaptation&!buff.dragonrage.up&!buff.ancient_flame.up
actions.st+=/living_flame,if=!buff.dragonrage.up|(buff.iridescence_red.remains>execute_time|buff.scarlet_adaptation.up&buff.ancient_flame.up|buff.iridescence_blue.up)&active_enemies==1
actions.st+=/azure_strike
actions.st+=/living_flame
]]
	if KharnalexTheFirstLight:Usable() and Dragonrage:Down() and ShatteringStar:Down() then
		UseCooldown(KharnalexTheFirstLight)
	end
	if Snapfire.known and Firestorm:Usable() and Snapfire:Up() then
		return Firestorm
	end
	if Dragonrage:Usable() and Dragonrage:Down() and ((FireBreath:Ready(4) and EternitySurge:Ready(10) and Target.timeToDie >= 32) or (Target.boss and Target.timeToDie < 30)) then
		UseCooldown(Dragonrage)
	end
	if TipTheScales:Usable() and Dragonrage:Up() and (((not FontOfMagic.known or EverburningFlame.known) and FireBreath:Ready() and not EternitySurge:Ready()) or (not EverburningFlame.known and FontOfMagic.known and EternitySurge:Ready() and not FireBreath:Ready()) or (Dragonrage:Remains() < self.r1_cast_time and (FireBreath:Ready(Dragonrage:Remains()) or EternitySurge:Ready(Dragonrage:Remains())))) then
		UseCooldown(TipTheScales)
	end
	if FireBreath:Usable() and (not Dragonrage.known or self.next_dragonrage > self.dr_prep_time_st or not Animosity.known) and (Player.enemies >= 2 or Target.timeToDie >= 8 or (Target.boss and Target.timeToDie < 30)) and (
		(BlazingShards.known and ((PowerSwell:Remains() < self.r1_cast_time or Player:BloodlustActive() or PowerInfusion:Up()) and (BlazingShards:Remains() < self.r1_cast_time or Dragonrage:Up()))) or
		(not BlazingShards.known and ((LimitlessPotential:Remains() < self.r1_cast_time or PowerInfusion:Down()) and PowerSwell:Remains() < self.r1_cast_time and BlazingShards:Remains() < self.r1_cast_time))
	) then
		local apl = self:fb()
		if apl then return apl end
	end
	if ShatteringStar:Usable() and (not ArcaneVigor.known or EssenceBurst:Stack() < EssenceBurst:MaxStack()) then
		return ShatteringStar
	end
	if EternitySurge:Usable() and (not Dragonrage.known or self.next_dragonrage > self.dr_prep_time_st or not Animosity.known) and (Player.enemies >= 2 or Target.timeToDie >= 8 or (Target.boss and Target.timeToDie < 30)) and (
		(BlazingShards.known and ((PowerSwell:Remains() < self.r1_cast_time or Player:BloodlustActive() or PowerInfusion:Up()) and (BlazingShards:Remains() < self.r1_cast_time or Dragonrage:Up()))) or
		(not BlazingShards.known and ((LimitlessPotential:Remains() < self.r1_cast_time or PowerInfusion:Down()) and PowerSwell:Remains() < self.r1_cast_time and BlazingShards:Remains() < self.r1_cast_time))
	) then
		local apl = self:es()
		if apl then return apl end
	end
	if Animosity.known and Dragonrage:Up() and Dragonrage:Remains() < (Player.gcd + self.r1_cast_time * (TipTheScales:Down() and 1 or 0)) and (Dragonrage:Remains() - FireBreath:Cooldown()) >= (self.r1_cast_time * (TipTheScales:Down() and 1 or 0)) then
		return WaitFor(FireBreath)
	end
	if Animosity.known and Dragonrage:Up() and Dragonrage:Remains() < (Player.gcd + self.r1_cast_time) and (Dragonrage:Remains() - EternitySurge:Cooldown()) >= (self.r1_cast_time * (TipTheScales:Down() and 1 or 0)) then
		return WaitFor(EternitySurge)
	end
	if Burnout.known and LivingFlame:Usable() and Burnout:Up() and Dragonrage:Up() and Dragonrage:Remains() < ((EssenceBurst:MaxStack() - EssenceBurst:Stack()) * Player.gcd) then
		return LivingFlame
	end
	if AzureStrike:Usable() and Dragonrage:Up() and Dragonrage:Remains() < ((EssenceBurst:MaxStack() - EssenceBurst:Stack()) * Player.gcd) then
		return AzureStrike
	end
	if RagingInferno.known and ChargedBlast.known and Pyre:Usable() and Firestorm:Up() and ChargedBlast:Stack() == 20 and Player.enemies >= 2 then
		return Pyre
	end
	if Disintegrate:Usable() then
		Player.channel.interrupt_if = self.channel_interrupt[BlazingShards.known and 1 or 2]
		Player.channel.early_chain_if = self.channel_early_chain[BlazingShards.known and 1 or 2]
		return Disintegrate
	end
	if Firestorm:Usable() and ((Dragonrage:Down() and (not ShatteringStar.known or ShatteringStar:Down()))) then
		return Firestorm
	end
	if DeepBreath:Usable() and Player.enemies > 1 and Dragonrage:Down() and (not ShatteringStar.known or ShatteringStar:Down()) then
		UseCooldown(DeepBreath)
	end
	if AncientFlame.known and ScarletAdaptation.known and VerdantEmbrace:Usable() and Dragonrage:Down() and AncientFlame:Down() then
		UseExtra(VerdantEmbrace)
	end
	if LivingFlame:Usable() and (Dragonrage:Down() or (Player.enemies <= 1 and (Iridescence.red:Remains() > LivingFlame:CastTime() or (ScarletAdaptation:Up() and AncientFlame:Up()) or Iridescence.blue:Up()))) then
		return LivingFlame
	end
	if AzureStrike:Usable() then
		return AzureStrike
	end
	if LivingFlame:Usable() then
		return LivingFlame
	end
end

APL[SPEC.DEVASTATION].channel_interrupt = {
	[1] = function() -- Disintegrate (st with Blazing Shards)
		--interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(!(buff.power_infusion.up&buff.bloodlust.up)|cooldown.fire_breath.up|cooldown.eternity_surge.up)&(raid_event.movement.in>2|buff.hover.up)
		return Opt.use_clipping and Player.channel.ticks >= 2 and Dragonrage:Up() and (not (PowerInfusion:Up() and Player:BloodlustActive()) or FireBreath:Ready() or EternitySurge:Ready())
	end,
	[2] = function() -- Disintegrate (st without Blazing Shards)
		--interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(raid_event.movement.in>2|buff.hover.up)
		return Opt.use_clipping and Player.channel.ticks >= 2 and Dragonrage:Up()
	end,
	[3] = function() -- Disintegrate (aoe)
		--interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(raid_event.movement.in>2|buff.hover.up)
		return Opt.use_clipping and Player.channel.ticks >= 2 and Dragonrage:Up()
	end,
}

APL[SPEC.DEVASTATION].channel_early_chain = {
	[1] = function() -- Disintegrate (st with Blazing Shards)
		--early_chain_if=evoker.use_early_chaining&ticks>=2&buff.dragonrage.up&!(buff.power_infusion.up&buff.bloodlust.up)&(raid_event.movement.in>2|buff.hover.up)
		return Opt.use_early_chaining and Player.channel.ticks >= 2 and Dragonrage:Up() and not (PowerInfusion:Up() and Player:BloodlustActive())
	end,
	[2] = function() -- Disintegrate (st without Blazing Shards)
		--evoker.use_early_chaining&buff.dragonrage.up&ticks>=2&(raid_event.movement.in>2|buff.hover.up)
		return Opt.use_early_chaining and Player.channel.ticks >= 2 and Dragonrage:Up()
	end,
	[3] = function() -- Disintegrate (aoe)
		--early_chain_if=evoker.use_early_chaining&(buff.dragonrage.up|essence.deficit<=1)&ticks>=2&(raid_event.movement.in>2|buff.hover.up)
		return Opt.use_early_chaining and Player.channel.ticks >= 2 and (Dragonrage:Up() or Player.essence.deficit <= 1)
	end,
}

APL[SPEC.DEVASTATION].es = function(self)
--[[
actions.es=eternity_surge,empower_to=1,if=active_enemies<=1+talent.eternitys_span|buff.dragonrage.remains<1.75*spell_haste&buff.dragonrage.remains>=1*spell_haste|buff.dragonrage.up&(active_enemies==5|!talent.eternitys_span&active_enemies>=6|talent.eternitys_span&active_enemies>=8)
actions.es+=/eternity_surge,empower_to=2,if=active_enemies<=2+2*talent.eternitys_span|buff.dragonrage.remains<2.5*spell_haste&buff.dragonrage.remains>=1.75*spell_haste
actions.es+=/eternity_surge,empower_to=3,if=active_enemies<=3+3*talent.eternitys_span|!talent.font_of_magic|buff.dragonrage.remains<=3.25*spell_haste&buff.dragonrage.remains>=2.5*spell_haste
actions.es+=/eternity_surge,empower_to=4
]]
	if EternitySurge:Usable() then
		if Player.enemies <= (1 + (EternitysSpan.known and 1 or 0)) or between(Dragonrage:Remains(), 1 * Player.haste_factor, 1.75 * Player.haste_factor) then
			EternitySurge.empower_to = 1
		elseif Player.enemies <= (2 + (EternitysSpan.known and 2 or 0)) or between(Dragonrage:Remains(), 1.75 * Player.haste_factor, 2.5 * Player.haste_factor) then
			EternitySurge.empower_to = 2
		elseif not FontOfMagic.known or Player.enemies <= (3 + (EternitysSpan.known and 3 or 0)) or between(Dragonrage:Remains(), 2.5 * Player.haste_factor, 3.25 * Player.haste_factor) then
			EternitySurge.empower_to = 3
		else
			EternitySurge.empower_to = 4
		end
		if Dragonrage:Up() then
			return EternitySurge
		else
			UseCooldown(EternitySurge)
		end
	end
end

APL[SPEC.DEVASTATION].fb = function(self)
--[[
actions.fb=fire_breath,empower_to=1,if=(buff.dragonrage.up&active_enemies<=2)|(active_enemies=1&!talent.everburning_flame)|(buff.dragonrage.remains<1.75*spell_haste&buff.dragonrage.remains>=1*spell_haste)
actions.fb+=/fire_breath,empower_to=2,if=(!debuff.in_firestorm.up&talent.everburning_flame&active_enemies<=3)|(active_enemies=2&!talent.everburning_flame)|(buff.dragonrage.remains<2.5*spell_haste&buff.dragonrage.remains>=1.75*spell_haste)
actions.fb+=/fire_breath,empower_to=3,if=!talent.font_of_magic|(debuff.in_firestorm.up&talent.everburning_flame&active_enemies<=3)|(buff.dragonrage.remains<=3.25*spell_haste&buff.dragonrage.remains>=2.5*spell_haste)
actions.fb+=/fire_breath,empower_to=4
]]
	if FireBreath:Usable() then
		if (Player.enemies <= 2 and Dragonrage:Up()) or (not EverburningFlame.known and Player.enemies <= 1) or between(Dragonrage:Remains(), 1 * Player.haste_factor, 1.75 * Player.haste_factor) then
			FireBreath.empower_to = 1
		elseif (EverburningFlame.known and Player.enemies <= 3 and Firestorm:Down()) or (not EverburningFlame.known and Player.enemies == 2) or between(Dragonrage:Remains(), 1.75 * Player.haste_factor, 2.5 * Player.haste_factor) then
			FireBreath.empower_to = 2
		elseif not FontOfMagic.known or (EverburningFlame.known and Player.enemies <= 3 and Firestorm:Up()) or between(Dragonrage:Remains(), 2.5 * Player.haste_factor, 3.25 * Player.haste_factor) then
			FireBreath.empower_to = 3
		else
			FireBreath.empower_to = 4
		end
		if Dragonrage:Up() then
			return FireBreath
		else
			UseCooldown(FireBreath)
		end
	end
end

APL[SPEC.DEVASTATION].trinkets = function(self)
--[[
# Try and get spoils to prvide haste or mastery stats, but if dragonrage gets too short just use it anyway.
actions.trinkets=use_item,name=spoils_of_neltharus,if=buff.dragonrage.up&(buff.spoils_of_neltharus_mastery.up|buff.spoils_of_neltharus_haste.up|buff.dragonrage.remains+6*(cooldown.eternity_surge.remains<=gcd.max*2+cooldown.fire_breath.remains<=gcd.max*2)<=18)|fight_remains<=20
# The trinket with the highest estimated value, will be used first and paired with Dragonrage.
actions.trinkets+=/use_item,slot=trinket1,if=buff.dragonrage.up&(!trinket.2.has_cooldown|trinket.2.cooldown.remains|variable.trinket_priority=1|variable.trinket_2_exclude)&!variable.trinket_1_manual|trinket.1.proc.any_dps.duration>=fight_remains|trinket.1.cooldown.duration<=60&(variable.next_dragonrage>20|!talent.dragonrage)&(!buff.dragonrage.up|variable.trinket_priority=1)
actions.trinkets+=/use_item,slot=trinket2,if=buff.dragonrage.up&(!trinket.1.has_cooldown|trinket.1.cooldown.remains|variable.trinket_priority=2|variable.trinket_1_exclude)&!variable.trinket_2_manual|trinket.2.proc.any_dps.duration>=fight_remains|trinket.2.cooldown.duration<=60&(variable.next_dragonrage>20|!talent.dragonrage)&(!buff.dragonrage.up|variable.trinket_priority=2)
# If only one on use trinket provides a buff, use the other on cooldown. Or if neither trinket provides a buff, use both on cooldown.
actions.trinkets+=/use_item,slot=trinket1,if=!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)&(variable.next_dragonrage>20|!talent.dragonrage)&!variable.trinket_1_manual
actions.trinkets+=/use_item,slot=trinket2,if=!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs)&(variable.next_dragonrage>20|!talent.dragonrage)&!variable.trinket_2_manual
]]
end

APL[SPEC.PRESERVATION].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 300 then
			return BlessingOfTheBronze
		end
	else
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 10 then
			UseExtra(BlessingOfTheBronze)
		end
		if Player.moving and Hover:Usable() and Hover:Down() then
			UseExtra(Hover)
		end
	end
end

APL[SPEC.AUGMENTATION].Main = function(self)
	if Player.health.pct < Opt.heal then
		if EmeraldBlossom:Usable() then
			UseExtra(EmeraldBlossom)
		elseif VerdantEmbrace:Usable() then
			UseExtra(VerdantEmbrace)
		elseif LivingFlame:Usable() and Burnout:Up() then
			UseExtra(LivingFlame)
		end
	end
	if Player:TimeInCombat() == 0 then
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 300 then
			return BlessingOfTheBronze
		end
	else
		if BlessingOfTheBronze:Usable() and BlessingOfTheBronze:Remains() < 10 then
			UseExtra(BlessingOfTheBronze)
		end
		if Player.moving and Hover:Usable() and Hover:Down() then
			UseExtra(Hover)
		end
	end
	if EbonMight:Down() then
		if Prescience:Usable() then
			UseCooldown(Prescience)
		end
		if BlisteringScales:Usable() and (BlisteringScales:Stack() < 5 or BlisteringScales:Remains() < 30) then
			UseCooldown(BlisteringScales)
		end
	end
	if EbonMight:Usable() and EbonMight:Refreshable() and (EssenceBurst:Stack() >= EssenceBurst:MaxStack() or Player.essence.deficit <= (2 + EssenceBurst:Stack()) or (Player.essence.current >= 2 and (FireBreath:Ready(Player.gcd * 2) or Upheaval:Ready(Player.gcd * 2)))) then
		UseCooldown(EbonMight)
	end
	if Prescience:Usable() and (Player.group_size > 1 or Prescience:Refreshable()) then
		UseCooldown(Prescience)
	end
	local apl
	apl = self:fb()
	if apl then return apl end
	apl = self:upheaval()
	if apl then return apl end
	if BreathOfEons:Usable() and EbonMight:Up() then
		UseCooldown(BreathOfEons)
	end
	if TimeSkip:Usable() and not FireBreath:Ready(12) and not Upheaval:Ready(12) and not BreathOfEons:Ready(20) and not EbonMight:Ready(12) then
		UseCooldown(TimeSkip)
	end
	if Eruption:Usable() and EbonMight:Remains() > Eruption:CastTime() and EbonMight:Remains() < (3 * Player.gcd) and not EbonMight:Ready(5) then
		return Eruption
	end
	if LeapingFlames.known and LivingFlame:Usable() and LeapingFlames:Remains() > LivingFlame:CastTime() and (LeapingFlames:Remains() < (2 * Player.gcd) or (EssenceBurst:Down() and Player.essence.deficit >= 2)) then
		return LivingFlame
	end
	if BlisteringScales:Usable() and BlisteringScales:Down() then
		UseCooldown(BlisteringScales)
	end
	if Eruption:Usable() and (
		Player.essence.deficit <= 1 or
		(EbonMight:Remains() > Eruption:CastTime() and (EbonMight:Remains() > 5 or not EbonMight:Ready(5))) or
		(EssenceBurst:Stack() >= EssenceBurst:MaxStack() and (EbonMight:Remains() > Eruption:CastTime() or not EbonMight:Ready(2 * Player.gcd))) or
		(EssenceBurst:Up() and EssenceBurst:Remains() < (2 * Player.gcd))
	) then
		return Eruption
	end
	if BlisteringScales:Usable() and (BlisteringScales:Stack() < 3 or BlisteringScales:Remains() < 10) then
		UseCooldown(BlisteringScales)
	end
	if LivingFlame:Usable() and (not Player.moving or Hover:Up() or Burnout:Up()) and (Player.enemies <= 1 or PupilOfAlexstrasza.known or (ScarletAdaptation:Up() and AncientFlame:Up())) then
		return LivingFlame
	end
	if AzureStrike:Usable() then
		return AzureStrike
	end
	if LivingFlame:Usable() then
		return LivingFlame
	end
end

APL[SPEC.AUGMENTATION].fb = function(self)
	if TipTheScales:Usable() and EbonMight:Remains() > 5 and (FireBreath:Ready() or (FireBreath:Ready(2) and FireBreath:Cooldown() < Upheaval:Cooldown())) then
		UseCooldown(TipTheScales)
	end
	if FireBreath:Usable() and ((TipTheScales.known and TipTheScales:Up()) or EbonMight:Remains() > (1 * Player.haste_factor)) and (EbonMight:Remains() > 5 or not EbonMight:Ready(10)) then
		if between(EbonMight:Remains(), 1 * Player.haste_factor, 1.75 * Player.haste_factor) or (not LeapingFlames.known and Target.timeToDie > 20) then
			FireBreath.empower_to = 1
		elseif between(EbonMight:Remains(), 1.75 * Player.haste_factor, 2.5 * Player.haste_factor) or (not LeapingFlames.known and Target.timeToDie > 14) then
			FireBreath.empower_to = 2
		elseif not FontOfMagic.known or between(EbonMight:Remains(), 2.5 * Player.haste_factor, 3.25 * Player.haste_factor) or (not LeapingFlames.known and Target.timeToDie > 8) then
			FireBreath.empower_to = 3
		else
			FireBreath.empower_to = 4
		end
		if EbonMight:Up() then
			return FireBreath
		else
			UseCooldown(FireBreath)
		end
	end
end

APL[SPEC.AUGMENTATION].upheaval = function(self)
	if Upheaval:Usable() and EbonMight:Remains() > (1 * Player.haste_factor) and (EbonMight:Remains() > 5 or not EbonMight:Ready(10)) then
		if Player.enemies <= 4 or between(EbonMight:Remains(), 1 * Player.haste_factor, 1.75 * Player.haste_factor) then
			Upheaval.empower_to = 1
		else
			Upheaval.empower_to = 2
		end
		if EbonMight:Up() then
			return Upheaval
		else
			UseCooldown(Upheaval)
		end
	end
end

APL.Interrupt = function(self)
	if Quell:Usable() then
		return Quell
	end
	if Target.stunnable then
		if TailSwipe:Usable() then
			return TailSwipe
		end
		if WingBuffet:Usable() then
			return WingBuffet
		end
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
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
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	self:UpdateGlowColorAndScale()
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	badDragonPanel:SetMovable(not Opt.snap)
	badDragonPreviousPanel:SetMovable(not Opt.snap)
	badDragonCooldownPanel:SetMovable(not Opt.snap)
	badDragonInterruptPanel:SetMovable(not Opt.snap)
	badDragonExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		badDragonPanel:SetUserPlaced(true)
		badDragonPreviousPanel:SetUserPlaced(true)
		badDragonCooldownPanel:SetUserPlaced(true)
		badDragonInterruptPanel:SetUserPlaced(true)
		badDragonExtraPanel:SetUserPlaced(true)
	end
	badDragonPanel:EnableMouse(draggable or Opt.aoe)
	badDragonPanel.button:SetShown(Opt.aoe)
	badDragonPreviousPanel:EnableMouse(draggable)
	badDragonCooldownPanel:EnableMouse(draggable)
	badDragonInterruptPanel:EnableMouse(draggable)
	badDragonExtraPanel:EnableMouse(draggable)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.PRESERVATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.AUGMENTATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.DEVASTATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.PRESERVATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.AUGMENTATION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
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
		(Player.spec == SPEC.PRESERVATION and Opt.hide.preservation) or
		(Player.spec == SPEC.AUGMENTATION and Opt.hide.augmentation))
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
	self:UpdateGlows()
end

function UI:Reset()
	badDragonPanel:ClearAllPoints()
	badDragonPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_cd, text_center
	local channel = Player.channel
	local empower = Player.empower

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
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
		if Player.main_freecast then
			border = 'freecast'
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
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if empower.ability then
		dim = Opt.dimmer
		local ctime = GetTime()
		empower.rank = floor(clamp((ctime - empower.start - (0.250 * empower.haste_factor)) / (0.750 * empower.haste_factor), 0, empower.ability:MaxEmpower()))
		if empower.ability.empower_to then
			text_center = format('RANK %d', empower.ability.empower_to)
			if empower.rank >= empower.ability.empower_to then
				text_center = '|cFF00FF00' .. text_center
				dim = false
			end
		elseif empower.rank >= 1 then
			dim = false
		end
	elseif channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if border ~= badDragonPanel.border.overlay then
		badDragonPanel.border.overlay = border
		badDragonPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	badDragonPanel.dimmer:SetShown(dim)
	badDragonPanel.text.center:SetText(text_center)
	--badDragonPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	badDragonCooldownPanel.text:SetText(text_cd)
	badDragonCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		badDragonPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Player.main.essence_cost > 0 and Player.main:EssenceCost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		badDragonCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			badDragonCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
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
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = BadDragon
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_BadDragon1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
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
	   e == 'SPELL_ABSORBED' or
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
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end
	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--log(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
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
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitLevel(unitId)
		Player.mana.base = Player.BaseMana[Player.level]
		Player.mana.max = UnitPowerMax(unitId, 0)
		Player.essence.max = UnitPowerMax(unitId, 19)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:UNIT_SPELLCAST_EMPOWER_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateEmpowerInfo()
	end
end
Events.UNIT_SPELLCAST_EMPOWER_START = Events.UNIT_SPELLCAST_EMPOWER_UPDATE
Events.UNIT_SPELLCAST_EMPOWER_STOP = Events.UNIT_SPELLCAST_EMPOWER_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		badDragonPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
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

	Player.set_bonus.t29 = (Player:Equipped(200378) and 1 or 0) + (Player:Equipped(200380) and 1 or 0) + (Player:Equipped(200381) and 1 or 0) + (Player:Equipped(200382) and 1 or 0) + (Player:Equipped(200383) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202486) and 1 or 0) + (Player:Equipped(202487) and 1 or 0) + (Player:Equipped(202488) and 1 or 0) + (Player:Equipped(202489) and 1 or 0) + (Player:Equipped(202491) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207225) and 1 or 0) + (Player:Equipped(207226) and 1 or 0) + (Player:Equipped(207227) and 1 or 0) + (Player:Equipped(207228) and 1 or 0) + (Player:Equipped(207230) and 1 or 0)
	Player.set_bonus.t32 = (Player:Equipped(217176) and 1 or 0) + (Player:Equipped(217177) and 1 or 0) + (Player:Equipped(217178) and 1 or 0) + (Player:Equipped(217179) and 1 or 0) + (Player:Equipped(217180) and 1 or 0)
	Player.set_bonus.t33 = (Player:Equipped(212027) and 1 or 0) + (Player:Equipped(212028) and 1 or 0) + (Player:Equipped(212029) and 1 or 0) + (Player:Equipped(212030) and 1 or 0) + (Player:Equipped(212032) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	badDragonPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		badDragonPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

badDragonPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
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
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
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
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
			if startsWith(msg[2], 'd') then
				Opt.hide.devastation = not Opt.hide.devastation
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Devastation specialization', not Opt.hide.devastation)
			end
			if startsWith(msg[2], 'p') then
				Opt.hide.preservation = not Opt.hide.preservation
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Preservation specialization', not Opt.hide.preservation)
			end
			if startsWith(msg[2], 'a') then
				Opt.hide.augmentation = not Opt.hide.augmentation
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Augmentation specialization', not Opt.hide.augmentation)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000devastation|r/|cFFFFD000preservation|r/|cFFFFD000augmentation|r')
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
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal .. '%')
	end
	if startsWith(msg[1], 'cl') then
		if msg[2] then
			Opt.use_clipping = msg[2] == 'on'
		end
		return Status('Allow clipping channeled spells', Opt.use_clipping)
	end
	if startsWith(msg[1], 'ea') then
		if msg[2] then
			Opt.use_early_chaining = msg[2] == 'on'
		end
		return Status('Allow early chaining channeled spells', Opt.use_early_chaining)
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000devastation|r/|cFFFFD000preservation|r/|cFFFFD000augmentation|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'clipping |cFF00C000on|r/|cFFC00000off|r - allow clipping channeled spells',
		'early |cFF00C000on|r/|cFFC00000off|r - allow early chaining channeled spells',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_BadDragon1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
