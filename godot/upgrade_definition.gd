class_name UpgradeDefinition
extends RefCounted

var id: String
var title: String
var description: String
var effect_type: String
var effect_key: String
var amount: float
var max_stacks: int


func _init(
	upgrade_id: String,
	upgrade_title: String,
	upgrade_description: String,
	upgrade_effect_type: String,
	upgrade_effect_key: String,
	upgrade_amount: float = 1.0,
	upgrade_max_stacks: int = 1
) -> void:
	id = upgrade_id
	title = upgrade_title
	description = upgrade_description
	effect_type = upgrade_effect_type
	effect_key = upgrade_effect_key
	amount = upgrade_amount
	max_stacks = upgrade_max_stacks
