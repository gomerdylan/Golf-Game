extends Control


func _ready() -> void:
	$Center/Panel/Layout/CampaignButton.pressed.connect(_start_campaign)
	$Center/Panel/Layout/SandboxButton.pressed.connect(_start_sandbox)
	$Center/Panel/Layout/QuitButton.pressed.connect(get_tree().quit)


func _start_campaign() -> void:
	RunState.start_new_campaign()
	get_tree().change_scene_to_file("res://main.tscn")


func _start_sandbox() -> void:
	RunState.start_sandbox()
	get_tree().change_scene_to_file("res://main.tscn")
