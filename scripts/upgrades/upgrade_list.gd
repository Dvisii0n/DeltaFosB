class_name UpgradeList
extends Object
## Every upgrade the player can be offered on level up. Edit numbers here to rebalance.
##
## Fields:
##   id      - unique name, used by Upgrades.gd to apply it
##   title   - card title
##   text    - what one pick does; "{v}" is replaced by the value (e.g. "+20")
##   per     - value of ONE pick (stacks add up: 3 picks of +20 = +60)
##   unit    - "" plain number, "%" percent, "s" seconds, "m" metres
##   rarity  - COMMON / RARE / EPIC (rarer = offered less often, usually stronger)
##   max     - how many times it can be picked (1 = one-time unlock)
##   needs   - (optional) only offered once you own this upgrade id
##   replaced_by - (optional) no longer offered once you own this upgrade id

enum Rarity { COMMON, RARE, EPIC }

const RARITY_NAMES := ["Common", "Rare", "Epic"]
const RARITY_COLORS := [Color(0.75, 0.75, 0.75), Color(0.3, 0.6, 1.0), Color(0.75, 0.35, 1.0)]
const RARITY_WEIGHTS := [70.0, 25.0, 5.0]      ## Base chance weights per rarity.


static func all() -> Array[Dictionary]:
	var C := Rarity.COMMON
	var R := Rarity.RARE
	var E := Rarity.EPIC
	return [
		# --- Survival ---
		{id = "max_health", title = "Thick Skin", text = "{v} max health", per = 20, unit = "", rarity = C, max = 10},
		{id = "max_armor", title = "Armor Plating", text = "{v} armor capacity", per = 25, unit = "", rarity = C, max = 10},
		{id = "regen", title = "Coffee IV Drip", text = "{v} HP per second (after 3 s without damage)", per = 1, unit = "", rarity = C, max = 5},
		{id = "armor_eff", title = "Reinforced Vest", text = "{v} of each hit taken by armor", per = 8, unit = "%", rarity = R, max = 3},
		{id = "heal_bonus", title = "First Aid Training", text = "{v} healing from health packs", per = 25, unit = "%", rarity = C, max = 4},
		{id = "armor_bonus", title = "Duct Tape", text = "{v} armor from armor plates", per = 25, unit = "%", rarity = C, max = 4},
		{id = "lifesteal", title = "Hostile Takeover", text = "{v} HP healed per kill", per = 3, unit = "", rarity = C, max = 5},
		{id = "last_stand", title = "Last Stand", text = "Survive one lethal hit with 1 HP", per = 1, unit = "", rarity = E, max = 1},
		{id = "magnet", title = "Sticky Fingers", text = "{v} pickup magnet range", per = 4, unit = "m", rarity = C, max = 3},
		{id = "pickup_life", title = "Long Shelf Life", text = "{v} before pickups vanish", per = 10, unit = "s", rarity = C, max = 3},

		{id = "evasive", title = "Evasive", text = "{v} chance to dodge bullets at high speed (scales with how fast you move)", per = 15, unit = "%", rarity = R, max = 3},

		# --- Chainsaw (replaces the pencil) ---
		{id = "chainsaw", title = "Chainsaw", text = "Your pencil is replaced by a chainsaw (hold to saw)", per = 1, unit = "", rarity = R, max = 1},
		{id = "chainsaw_damage", title = "Sharpened Chain", text = "{v} chainsaw damage", per = 20, unit = "%", rarity = C, max = 5, needs = "chainsaw"},
		{id = "chainsaw_ammo", title = "Rip and Tear", text = "Chainsaw kills drop every ammo type", per = 1, unit = "", rarity = R, max = 1, needs = "chainsaw"},

		# --- Weapons ---
		{id = "fire_rate", title = "Overtime", text = "{v} fire rate (all weapons)", per = 10, unit = "%", rarity = C, max = 5},
		{id = "damage", title = "Performance Review", text = "{v} damage (all weapons)", per = 10, unit = "%", rarity = C, max = 5},
		{id = "dmg_pencil", title = "Sharpened Pencil", text = "{v} pencil damage", per = 20, unit = "%", rarity = C, max = 5, replaced_by = "chainsaw"},
		{id = "dmg_pistol", title = "Hollow Points", text = "{v} pistol damage", per = 20, unit = "%", rarity = C, max = 5},
		{id = "dmg_shotgun", title = "Buckshot", text = "{v} shotgun damage", per = 20, unit = "%", rarity = C, max = 5},
		{id = "dmg_minigun", title = "Heavy Rounds", text = "{v} minigun damage", per = 20, unit = "%", rarity = C, max = 5},
		{id = "max_light", title = "Bigger Pockets", text = "{v} max light ammo", per = 25, unit = "%", rarity = C, max = 4},
		{id = "max_shells", title = "Shell Bandolier", text = "{v} max shells", per = 25, unit = "%", rarity = C, max = 4},
		{id = "max_heavy", title = "Ammo Backpack", text = "{v} max heavy ammo", per = 25, unit = "%", rarity = C, max = 4},
		{id = "ammo_save", title = "Budget Cuts", text = "{v} chance a shot uses no ammo", per = 10, unit = "%", rarity = R, max = 3},
		{id = "pellets", title = "Extra Buckshot", text = "{v} shotgun pellets", per = 1, unit = "", rarity = R, max = 3},
		{id = "spread", title = "Choke", text = "{v} shotgun spread", per = -15, unit = "%", rarity = C, max = 3},
		{id = "spin_up", title = "Greased Barrels", text = "{v} minigun spin-up time", per = -20, unit = "%", rarity = C, max = 3},
		{id = "pencil_reach", title = "Long Reach", text = "{v} melee reach (pencil / chainsaw)", per = 25, unit = "%", rarity = C, max = 3},
		{id = "crit", title = "Lucky Shot", text = "{v} chance to deal double damage", per = 5, unit = "%", rarity = R, max = 5},
		{id = "switch_speed", title = "Quick Hands", text = "{v} weapon switch speed", per = 20, unit = "%", rarity = C, max = 3},
		{id = "dual_fire", title = "Ambidextrous", text = "When dual wielding, both guns fire together", per = 1, unit = "", rarity = E, max = 1},

		# --- Ability ---
		{id = "ability_duration", title = "Extended Break", text = "{v} bullet time duration", per = 1.5, unit = "s", rarity = C, max = 5},
		{id = "ability_charge", title = "Adrenaline", text = "{v} bullet time charge from kills", per = 20, unit = "%", rarity = C, max = 5},
		{id = "bt_depth", title = "Deep Focus", text = "{v} world speed in bullet time", per = -5, unit = "%", rarity = R, max = 3},
		{id = "bt_extend", title = "Momentum", text = "{v} bullet time per kill while active", per = 0.5, unit = "s", rarity = R, max = 3},
		{id = "dmg_charge", title = "Rage", text = "{v} bullet time charge per 10 damage dealt", per = 1, unit = "%", rarity = R, max = 3},
		{id = "fury_duration", title = "Short Fuse", text = "{v} Fury duration", per = 2, unit = "s", rarity = C, max = 5},
		{id = "fury_dual", title = "Two-Fisted Fury", text = "Fury also gives you dual wield", per = 1, unit = "", rarity = E, max = 1},
		{id = "sandevistan", title = "Sandevistan", text = "You move at full speed during bullet time", per = 1, unit = "", rarity = R, max = 1},

		# --- Movement ---
		{id = "move_speed", title = "Running Late", text = "{v} move speed", per = 8, unit = "%", rarity = C, max = 5},
		{id = "jump", title = "Spring Shoes", text = "{v} jump power", per = 10, unit = "%", rarity = C, max = 3},
		{id = "air_jump", title = "Double Jump", text = "{v} jump in mid-air", per = 1, unit = "", rarity = R, max = 2},
		{id = "dash_distance", title = "Long Dash", text = "{v} dash distance", per = 15, unit = "%", rarity = C, max = 3},
		{id = "dash_cooldown", title = "Quick Recovery", text = "{v} dash recharge time", per = -15, unit = "%", rarity = C, max = 3},
		{id = "dash_charge", title = "Extra Dash", text = "{v} dash charge", per = 1, unit = "", rarity = R, max = 2},
		{id = "slide_speed", title = "Waxed Floors", text = "{v} slide speed", per = 10, unit = "%", rarity = C, max = 3},
		{id = "slam_wave", title = "Ground Pound", text = "{v} slam shockwave damage (4 m radius)", per = 30, unit = "", rarity = R, max = 3},
		{id = "wall_jump", title = "Parkour", text = "{v} wall jump", per = 1, unit = "", rarity = C, max = 3},
		{id = "air_control", title = "Air Steering", text = "{v} air control", per = 25, unit = "%", rarity = C, max = 3},

		# --- Drops / economy ---
		{id = "drop_light", title = "Light Ammo Finder", text = "{v} light ammo drop chance", per = 10, unit = "%", rarity = C, max = 5},
		{id = "drop_shells", title = "Shell Finder", text = "{v} shells drop chance", per = 10, unit = "%", rarity = C, max = 5},
		{id = "drop_heavy", title = "Heavy Ammo Finder", text = "{v} heavy ammo drop chance", per = 10, unit = "%", rarity = C, max = 5},
		{id = "drop_health", title = "Medical Benefits", text = "{v} health pack drop chance", per = 8, unit = "%", rarity = C, max = 5},
		{id = "drop_armor", title = "Scavenger", text = "{v} armor drop chance (armored enemies)", per = 8, unit = "%", rarity = C, max = 5},
		{id = "drop_dual", title = "Two-Handed Policy", text = "{v} dual wield drop chance", per = 3, unit = "%", rarity = R, max = 5},
		{id = "dual_duration", title = "Extended Contract", text = "{v} dual wield duration", per = 5, unit = "s", rarity = C, max = 5},
		{id = "xp_gain", title = "Fast Learner", text = "{v} XP gain", per = 15, unit = "%", rarity = C, max = 5},
		{id = "luck", title = "Lucky Tie", text = "{v} luck (rare and epic upgrades show up more)", per = 1, unit = "", rarity = C, max = 3},
	]


## "+20", "-15%", "+1.5 s", "+4 m"
static func format_value(value: float, unit: String) -> String:
	var number := str(snappedf(value, 0.01))
	if number.ends_with(".0"):
		number = number.left(-2)
	var sign := "+" if value >= 0.0 else ""
	match unit:
		"%": return "%s%s%%" % [sign, number]
		"s": return "%s%s s" % [sign, number]
		"m": return "%s%s m" % [sign, number]
	return sign + number
