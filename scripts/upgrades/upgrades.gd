class_name Upgrades
extends Node
## Lives on the player as a node named "Upgrades". Handles:
##   - XP and levels: kills give XP (stronger enemy = more). Each level needs `xp_growth` times more.
##   - The upgrades picked so far (`stacks`) and applying them to the player, weapons and ability.
## The level-up screen is scripts/ui/upgrade_menu.gd. The upgrade list is scripts/upgrades/upgrade_list.gd.
## Everything resets on death (the level reloads).

signal leveled_up(new_level: int)

@export var xp_to_first_level := 100.0
@export var xp_growth := 1.25          ## Each level needs 25% more XP than the last.
@export var luck_rare_bonus := 8.0     ## Extra weight for rare upgrades per Luck pick.
@export var luck_epic_bonus := 4.0     ## Extra weight for epic upgrades per Luck pick.
@export var chainsaw_scene: PackedScene = preload("res://scenes/weapons/chainsaw.tscn")  ## Chainsaw upgrade.

var level := 1
var xp := 0.0
var xp_needed := 100.0
var pending_levels := 0                # Level ups waiting for an upgrade choice.
var stacks := {}                       # upgrade id -> times picked

# --- Bonuses other scripts read ---
var heal_mult := 1.0                   # Health packs.
var armor_pickup_mult := 1.0           # Armor plates.
var regen_per_second := 0.0
var lifesteal := 0.0                   # HP per kill.
var magnet_range := 0.0                # Metres. 0 = off.
var pickup_lifetime_bonus := 0.0       # Seconds added to dropped pickups.
var ability_charge_mult := 1.0
var bt_extend_per_kill := 0.0          # Seconds added to bullet time per kill.
var charge_per_10_damage := 0.0        # Ability bar fraction per 10 damage dealt.
var slam_damage := 0.0
var xp_mult := 1.0
var luck := 0
var dual_duration_bonus := 0.0
var chainsaw_ammo := false             # Chainsaw kills drop every ammo type.
var evasion := 0.0                     # Max chance to dodge a bullet (at full speed).
var drop_bonus := {}                   # "light"/"shells"/"heavy"/"health"/"armor"/"dual" -> extra chance (0.1 = +10%)

@onready var player: Node = get_parent()
@onready var health: Health = player.get_node("Health")
@onready var holder: WeaponHolder = player.find_child("WeaponHolder", true, false)
@onready var ability: Ability = player.get_node("Ability")
@onready var fury: Fury = player.get_node("Fury")

var _bases := {}                       # Original values, so stacked upgrades are always "base + total".


func _ready() -> void:
	xp_needed = xp_to_first_level
	WorldTime.sandevistan = false      # It's an upgrade: lost on death like the others.


# --- XP ------------------------------------------------------------------------

func add_xp(amount: float) -> void:
	xp += amount * xp_mult
	while xp >= xp_needed:
		xp -= xp_needed                # Leftover XP carries over.
		level += 1
		xp_needed *= xp_growth
		pending_levels += 1
		leveled_up.emit(level)


# --- Choosing --------------------------------------------------------------------

func stack_count(id: String) -> int:
	return stacks.get(id, 0)


## Up to `count` different upgrades that aren't maxed out. For each card, a rarity is rolled
## first (70% common, 25% rare, 5% epic, shifted by Luck), then an upgrade of that rarity.
func roll_choices(count: int = 3) -> Array[Dictionary]:
	var pools := [[], [], []]   # Available upgrades, grouped by rarity.
	for up in UpgradeList.all():
		if _is_offerable(up):
			pools[up.rarity].append(up)
	var picks: Array[Dictionary] = []
	while picks.size() < count:
		var rarity := _roll_rarity(pools)
		if rarity < 0:
			break   # Nothing left to offer.
		var pool: Array = pools[rarity]
		picks.append(pool.pop_at(randi() % pool.size()))
	return picks


## Not maxed out, its "needs" upgrade is owned, and it hasn't been made useless ("replaced_by").
func _is_offerable(up: Dictionary) -> bool:
	if stack_count(up.id) >= up.max:
		return false
	if up.has("needs") and stack_count(up.needs) == 0:
		return false
	if up.has("replaced_by") and stack_count(up.replaced_by) > 0:
		return false
	return true


## Picks a rarity tier by weight, skipping tiers with nothing left. -1 if all are empty.
func _roll_rarity(pools: Array) -> int:
	var total := 0.0
	for r in 3:
		if not pools[r].is_empty():
			total += _rarity_weight(r)
	if total <= 0.0:
		return -1
	var roll := randf() * total
	for r in 3:
		if pools[r].is_empty():
			continue
		roll -= _rarity_weight(r)
		if roll <= 0.0:
			return r
	for r in range(2, -1, -1):
		if not pools[r].is_empty():
			return r
	return -1


func _rarity_weight(rarity: int) -> float:
	var w: float = UpgradeList.RARITY_WEIGHTS[rarity]
	if rarity == UpgradeList.Rarity.RARE:
		w += luck * luck_rare_bonus
	elif rarity == UpgradeList.Rarity.EPIC:
		w += luck * luck_epic_bonus
	return w


## Card text: what it does, and the stacked total before -> after.
func describe(up: Dictionary) -> String:
	var n := stack_count(up.id)
	var text: String = up.text.replace("{v}", UpgradeList.format_value(up.per, up.unit))
	if up.max == 1:
		return text + "\n\nOne-time unlock"
	var now := UpgradeList.format_value(up.per * n, up.unit) if n > 0 else "none"
	var after := UpgradeList.format_value(up.per * (n + 1), up.unit)
	return "%s\n\nOwned %d / %d\nTotal: %s  ->  %s" % [text, n, up.max, now, after]


func pick(up: Dictionary) -> void:
	stacks[up.id] = stack_count(up.id) + 1
	pending_levels = maxi(pending_levels - 1, 0)
	_apply(up.id, stacks[up.id], up.per / 100.0, up.per)


# --- Applying --------------------------------------------------------------------
# n = times picked, pct = one pick as a fraction (10% -> 0.1), per = one pick as written.

func _apply(id: String, n: int, pct: float, per: float) -> void:
	match id:
		# Survival
		"max_health":
			_set_added(health, "max_health", per * n)
			health.heal(per)           # The new HP comes filled.
		"max_armor": _set_added(health, "max_armor", per * n)
		"regen": regen_per_second = per * n
		"armor_eff": health.armor_absorb = minf(_base(health, "armor_absorb") + pct * n, 0.95)
		"heal_bonus": heal_mult = 1.0 + pct * n
		"armor_bonus": armor_pickup_mult = 1.0 + pct * n
		"lifesteal": lifesteal = per * n
		"last_stand": health.last_stands += 1
		"magnet": magnet_range = per * n
		"pickup_life": pickup_lifetime_bonus = per * n
		# Weapons
		"fire_rate": holder.fire_rate_mult = 1.0 + pct * n
		"damage": holder.damage_mult = 1.0 + pct * n
		"dmg_pencil": holder.weapon_damage_mult["Pencil"] = 1.0 + pct * n
		"dmg_pistol": holder.weapon_damage_mult["Pistol"] = 1.0 + pct * n
		"dmg_shotgun": holder.weapon_damage_mult["Shotgun"] = 1.0 + pct * n
		"dmg_minigun": holder.weapon_damage_mult["Minigun"] = 1.0 + pct * n
		"max_light": _set_max_ammo("light", 1.0 + pct * n)
		"max_shells": _set_max_ammo("shells", 1.0 + pct * n)
		"max_heavy": _set_max_ammo("heavy", 1.0 + pct * n)
		"ammo_save": holder.ammo_save_chance = pct * n
		"pellets": holder.bonus_pellets["Shotgun"] = int(per) * n
		"spread": holder.spread_mult["Shotgun"] = maxf(1.0 + pct * n, 0.1)
		"spin_up": holder.spin_up_mult = maxf(1.0 + pct * n, 0.1)
		"pencil_reach": holder.melee_reach_mult = 1.0 + pct * n
		"crit": holder.crit_chance = pct * n
		"switch_speed":
			_set_scaled(holder, "switch_down_time", 1.0 / (1.0 + pct * n))
			_set_scaled(holder, "switch_up_time", 1.0 / (1.0 + pct * n))
		"dual_fire": holder.dual_fire_all = true
		# Ability
		"ability_duration": _set_added(ability, "duration", per * n)
		"ability_charge": ability_charge_mult = 1.0 + pct * n
		"bt_depth":
			if "world_speed" in ability:
				ability.set("world_speed", maxf(_base(ability, "world_speed") + pct * n, 0.05))
		"bt_extend": bt_extend_per_kill = per * n
		"dmg_charge": charge_per_10_damage = pct * n
		"sandevistan": WorldTime.sandevistan = true
		"fury_duration": _set_added(fury, "duration", per * n)
		"fury_dual": fury.dual_wield_on_fury = true
		# Movement
		"move_speed": _set_scaled(player, "move_speed", 1.0 + pct * n)
		"jump": _set_scaled(player, "jump_velocity", 1.0 + pct * n)
		"air_jump": player.set("max_air_jumps", int(per) * n)
		"dash_distance": _set_scaled(player, "dash_duration", 1.0 + pct * n)
		"dash_cooldown": _set_scaled(player, "dash_recharge_time", maxf(1.0 + pct * n, 0.1))
		"dash_charge": _set_added(player, "max_dash_charges", per * n)
		"slide_speed": _set_scaled(player, "slide_speed", 1.0 + pct * n)
		"slam_wave": slam_damage = per * n
		"wall_jump": _set_added(player, "max_wall_jumps", per * n)
		"air_control": _set_scaled(player, "air_accel", 1.0 + pct * n)
		# Drops / economy
		"drop_light": drop_bonus["light"] = pct * n
		"drop_shells": drop_bonus["shells"] = pct * n
		"drop_heavy": drop_bonus["heavy"] = pct * n
		"drop_health": drop_bonus["health"] = pct * n
		"drop_armor": drop_bonus["armor"] = pct * n
		"drop_dual": drop_bonus["dual"] = pct * n
		"dual_duration": dual_duration_bonus = per * n
		"xp_gain": xp_mult = 1.0 + pct * n
		"evasive": evasion = pct * n
		"chainsaw": holder.replace_weapon(chainsaw_scene)
		"chainsaw_damage": holder.weapon_damage_mult["Chainsaw"] = 1.0 + pct * n
		"chainsaw_ammo": chainsaw_ammo = true
		"luck": luck = n
		_:
			push_warning("Upgrade '%s' has no effect yet" % id)


## The value a property had before any upgrade touched it.
func _base(obj: Object, prop: String) -> float:
	var key := "%d:%s" % [obj.get_instance_id(), prop]
	if not _bases.has(key):
		_bases[key] = obj.get(prop)
	return _bases[key]


func _set_scaled(obj: Object, prop: String, factor: float) -> void:
	_store(obj, prop, _base(obj, prop) * factor)


func _set_added(obj: Object, prop: String, amount: float) -> void:
	_store(obj, prop, _base(obj, prop) + amount)


## Keeps whole-number properties (like dash charges) whole.
func _store(obj: Object, prop: String, value: float) -> void:
	if typeof(obj.get(prop)) == TYPE_INT:
		obj.set(prop, roundi(value))
	else:
		obj.set(prop, value)


func _set_max_ammo(type: String, factor: float) -> void:
	var key := "max_ammo:" + type
	if not _bases.has(key):
		_bases[key] = holder.max_ammo.get(type, 0)
	holder.max_ammo[type] = roundi(_bases[key] * factor)
