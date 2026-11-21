extends Node

const UpgradeDefinitionScript = preload("res://upgrade_definition.gd")

enum GameMode { SANDBOX, CAMPAIGN }

const BASE_STAT := 10
const POWER_SPEED_PER_POINT := 0.10
const CONTROL_DISPERSION_PER_POINT := 0.10
const SPIN_MULTIPLIER_PER_POINT := 0.20

var game_mode := GameMode.SANDBOX
var stats := {"power": BASE_STAT, "control": BASE_STAT, "spin": BASE_STAT}
var mishit_chance := 0.10
var unlocked_clubs: Array[String] = ["7iron"]
var unlocked_shots: Array[String] = ["chip", "stock"]
var collected_upgrades: Array[String] = []
var upgrade_counts: Dictionary = {}
var current_hole := 1
var total_score := 0
var hole_scores: Array[int] = []
var upgrade_rng := RandomNumberGenerator.new()

var upgrade_catalog: Array = [
	UpgradeDefinitionScript.new("power_1", "+1 Power", "+10% launch speed", "stat", "power", 1.0, 5),
	UpgradeDefinitionScript.new("control_1", "+1 Control", "-10% launch dispersion", "stat", "control", 1.0, 5),
	UpgradeDefinitionScript.new("spin_1", "+1 Spin", "+20% launch spin", "stat", "spin", 1.0, 5),
	UpgradeDefinitionScript.new("mishit_1", "-1% Mis-hit Chance", "Reduces mis-hit chance by 1%", "mishit", "", -0.01, 5),
	UpgradeDefinitionScript.new("club_pw", "Pitching Wedge", "Unlocks the pitching wedge", "club", "pw"),
	UpgradeDefinitionScript.new("club_5iron", "5-iron", "Unlocks the 5-iron", "club", "5iron"),
	UpgradeDefinitionScript.new("club_3wood", "3-wood", "Unlocks the 3-wood", "club", "3wood"),
	UpgradeDefinitionScript.new("club_driver", "Driver", "Unlocks the driver", "club", "driver"),
	UpgradeDefinitionScript.new("shot_smooth", "Smooth Shot", "Unlocks the controlled 80% shot", "shot", "smooth"),
	UpgradeDefinitionScript.new("shot_full", "Full Power Shot", "Unlocks the less-controlled 120% shot", "shot", "full"),
]


func start_sandbox() -> void:
	game_mode = GameMode.SANDBOX


func start_new_campaign() -> void:
	game_mode = GameMode.CAMPAIGN
	stats = {"power": BASE_STAT, "control": BASE_STAT, "spin": BASE_STAT}
	mishit_chance = 0.10
	unlocked_clubs = ["7iron"]
	unlocked_shots = ["chip", "stock"]
	collected_upgrades.clear()
	upgrade_counts.clear()
	current_hole = 1
	total_score = 0
	hole_scores.clear()
	upgrade_rng.randomize()


func is_campaign() -> bool:
	return game_mode == GameMode.CAMPAIGN


func resolved_modifiers() -> Dictionary:
	var power_delta := int(stats["power"]) - BASE_STAT
	var control_delta := int(stats["control"]) - BASE_STAT
	var spin_delta := int(stats["spin"]) - BASE_STAT
	return {
		"speed_multiplier": maxf(0.1, 1.0 + POWER_SPEED_PER_POINT * power_delta),
		"dispersion_multiplier": maxf(0.1, 1.0 - CONTROL_DISPERSION_PER_POINT * control_delta),
		"spin_multiplier": maxf(0.1, 1.0 + SPIN_MULTIPLIER_PER_POINT * spin_delta),
	}


func stat_effect_text(stat_name: String) -> String:
	var modifiers := resolved_modifiers()
	match stat_name:
		"power":
			return "%+.0f%% launch speed" % ((float(modifiers["speed_multiplier"]) - 1.0) * 100.0)
		"control":
			return "%+.0f%% dispersion" % ((float(modifiers["dispersion_multiplier"]) - 1.0) * 100.0)
		"spin":
			return "%+.0f%% spin" % ((float(modifiers["spin_multiplier"]) - 1.0) * 100.0)
	return ""


func available_upgrades() -> Array:
	var available: Array = []
	for upgrade in upgrade_catalog:
		if int(upgrade_counts.get(upgrade.id, 0)) < upgrade.max_stacks:
			available.append(upgrade)
	return available


func draw_upgrade_choices(count: int = 3) -> Array:
	var candidates := available_upgrades()
	var choices: Array = []
	# Removing each chosen definition guarantees three different upgrade IDs.
	# A stackable upgrade may recur in a later draft, never twice in this one.
	while not candidates.is_empty() and choices.size() < count:
		var index := upgrade_rng.randi_range(0, candidates.size() - 1)
		choices.append(candidates.pop_at(index))
	return choices


func apply_upgrade(upgrade) -> void:
	if int(upgrade_counts.get(upgrade.id, 0)) >= upgrade.max_stacks:
		return
	upgrade_counts[upgrade.id] = int(upgrade_counts.get(upgrade.id, 0)) + 1
	match upgrade.effect_type:
		"stat":
			stats[upgrade.effect_key] = int(stats[upgrade.effect_key]) + int(upgrade.amount)
		"mishit":
			mishit_chance = clampf(mishit_chance + upgrade.amount, 0.0, 1.0)
		"club":
			if upgrade.effect_key not in unlocked_clubs:
				unlocked_clubs.append(upgrade.effect_key)
		"shot":
			if upgrade.effect_key not in unlocked_shots:
				unlocked_shots.append(upgrade.effect_key)
	collected_upgrades.append(upgrade.title)
