extends Node3D

const METERS_TO_YARDS := 1.0936133
const YARDS_TO_METERS := 1.0 / METERS_TO_YARDS
const VISUAL_BALL_RADIUS_M := 0.021335
const COURSE_CONFIGS := {
	"test_hole": {"display_name": "Test Hole", "tee_xy_m": Vector2(5.0, 0.0), "cup_xy_m": Vector2(385.0, -5.0), "bounds": Rect2(0.0, -60.0, 420.0, 120.0), "length_m": 420.0},
	"water_carry": {"display_name": "Water Carry", "tee_xy_m": Vector2(5.0, 0.0), "cup_xy_m": Vector2(650.0, 70.0), "bounds": Rect2(0.0, -120.0, 700.0, 240.0), "length_m": 650.0},
}
const STATUS_AT_REST := 0
const STATUS_IN_WATER := 1
const STATUS_OUT_OF_BOUNDS := 2
const SURFACE_GREEN := 2
const PHASE_FLIGHT := 0
const PHASE_SKID := 1
const PHASE_ROLL := 2
const PHASE_DONE := 3
const PHASE_NAMES := ["FLIGHT", "SKID", "ROLL", "STOPPED"]
const PHASE_COLORS := [
	Color(0.15, 0.90, 1.00),
	Color(1.00, 0.72, 0.12),
	Color(0.25, 1.00, 0.35),
	Color(0.65, 0.68, 0.72),
]
const FOG_PLANNING_DENSITY := 0.30
const FOG_PLANNING_EMISSION := 1.80
const FOG_CLOUD_HEIGHT_M := 5.5
const POWER_SLIDER_MAX_PERCENT := 120
const CHIP_UNLOCK_MAX_PERCENT := 40
const SMOOTH_POWER_PERCENT := 80
const STOCK_POWER_PERCENT := 100
const FULL_POWER_PERCENT := 120
const BASE_MISHIT_CHANCE := 0.10
const MISHIT_DEBUG_OPTIONS := {
	"driver": [["slice", "Sliced"], ["hook", "Hooked"], ["top", "Topped"], ["popup", "Popped Up"]],
	"3wood": [["slice", "Sliced"], ["hook", "Hooked"], ["top", "Topped"], ["chunk", "Chunked"]],
	"5iron": [["slice", "Sliced"], ["hook", "Hooked"], ["chunk", "Chunked"], ["thin", "Thinned"], ["shank", "Shanked"]],
	"7iron": [["slice", "Sliced"], ["hook", "Hooked"], ["chunk", "Chunked"], ["thin", "Thinned"], ["shank", "Shanked"]],
	"pw": [["chunk", "Chunked"], ["blade", "Bladed"], ["shank", "Shanked"], ["popup", "Popped Up"]],
}
const TRAJECTORY_FILE := "res://course_data/test_hole/trajectory.json"
const FOG_FILE := "res://course_data/test_hole/probability_fog.json"

@export_category("Shot Playback")
@export_range(0.0, 5.0, 0.1) var pre_shot_pause_s := 0.0
@export_range(0.0, 5.0, 0.1) var finish_pause_s := 2.0
@export_range(0.25, 4.0, 0.25) var playback_speed := 2.0
@export_range(0.2, 3.0, 0.05) var post_shot_tactical_transition_s := 1.30

@export_category("Shot Follow Camera")
@export var camera_offset_m := Vector3(0.65, 0.55, 1.60)
@export var camera_look_ahead_m := 2.5
@export var camera_look_height_m := 0.12
@export_range(0.5, 12.0, 0.5) var camera_follow_speed := 4.0

@export_category("Selection Orbit Camera")
@export_range(-180.0, 180.0, 1.0) var default_orbit_yaw_deg := 11.0
@export_range(20.0, 75.0, 1.0) var default_orbit_elevation_deg := 25.0
@export_range(20.0, 450.0, 5.0) var default_orbit_distance_m := 90.0
@export_range(0.50, 0.99, 0.01) var tactical_probability_capture := 0.85
@export_range(1.0, 1.5, 0.05) var tactical_frame_margin := 1.10

@export_category("Aim Flyover")
@export_range(5.0, 80.0, 1.0) var flyover_speed_mps := 48.0
@export_range(5.0, 50.0, 1.0) var flyover_height_m := 18.0
@export_range(5.0, 60.0, 1.0) var flyover_start_behind_m := 24.0
@export_range(10.0, 100.0, 5.0) var flyover_look_ahead_m := 45.0
@export_range(0.0, 3.0, 0.1) var flyover_finish_hold_s := 0.8
@export_range(0.05, 0.5, 0.01) var orbit_mouse_sensitivity := 0.18
@export_range(1.0, 89.0, 1.0) var minimum_orbit_elevation_deg := 3.0
@export_range(45.0, 89.0, 1.0) var maximum_orbit_elevation_deg := 88.0
@export_range(5.0, 100.0, 1.0) var minimum_orbit_distance_m := 6.0
@export_range(200.0, 700.0, 10.0) var maximum_orbit_distance_m := 450.0
@export_range(100.0, 600.0, 10.0) var maximum_pan_distance_m := 380.0
@export_range(0.25, 5.0, 0.25) var camera_terrain_clearance_m := 1.25
@export_range(0.02, 1.0, 0.01) var aim_camera_drag_sensitivity_deg := 0.20
@export_range(30.0, 300.0, 5.0) var aim_camera_distance_m := 170.0
@export_range(20.0, 75.0, 1.0) var aim_camera_elevation_deg := 38.0
@export_category("Aim Guide")
@export_range(50.0, 450.0, 10.0) var aim_line_length_m := 320.0
@export_range(1.0, 12.0, 0.5) var aim_dash_length_m := 5.0
@export_range(1.0, 12.0, 0.5) var aim_dash_gap_m := 4.0

@export_category("Probability Fog Presentation")
@export_range(0.05, 1.0, 0.025) var playback_fog_density_multiplier := 0.275
@export_range(0.05, 1.0, 0.025) var playback_fog_emission_multiplier := 0.50
@export_range(0.1, 1.0, 0.05) var playback_fog_height_multiplier := 1.0
@export_range(0.0, 1.0, 0.025) var playback_bubble_opacity_multiplier := 0.40
@export_range(0.0, 3.0, 0.05) var bubble_bob_amplitude_m := 0.75
@export_range(2.0, 20.0, 0.25) var bubble_bob_period_s := 7.0
@export_range(0.0, 20.0, 0.5) var bubble_fade_in_span_m := 5.0
@export_range(5.0, 60.0, 0.5) var bubble_full_effect_span_m := 25.0
@export_range(0.0, 0.75, 0.025) var minimum_bubble_presence := 0.50
@export_range(0.05, 0.5, 0.025) var maximum_bubble_footprint_fraction := 0.25
@export_range(5.0, 50.0, 0.5) var fog_density_reference_span_m := 20.0
@export_range(1.0, 5.0, 0.1) var fog_small_footprint_density_cap := 2.5
@export_range(0.0, 3.0, 0.1) var fog_dispersal_delay_s := 1.0
@export_range(0.2, 2.0, 0.05) var fog_dispersal_duration_s := 0.75

@export_category("Terrain Grid")
@export_range(5.0, 50.0, 1.0) var terrain_grid_spacing_yd := 20.0
@export_range(0.5, 5.0, 0.5) var terrain_grid_curve_sample_m := 1.0
@export_range(0.25, 8.0, 0.25) var terrain_grid_dash_length_m := 2.0
@export_range(0.25, 8.0, 0.25) var terrain_grid_dash_gap_m := 1.5
@export_range(0.02, 0.5, 0.01) var terrain_grid_surface_lift_m := 0.12

@onready var camera: Camera3D = $Camera
@onready var minimap_camera: Camera3D = $Overlay/MinimapFrame/MinimapContainer/MinimapViewport/MinimapCamera
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var ball: MeshInstance3D = $Ball
@onready var trail: MeshInstance3D = $Trail
@onready var preview_trajectories: MeshInstance3D = $PreviewTrajectories
@onready var aim_line: MeshInstance3D = $AimLine
@onready var course_terrain: Terrain3D = $CourseTerrain
@onready var test_hole_terrain: Terrain3D = $CourseTerrain
var water_carry_terrain: Terrain3D
@onready var terrain_grid: MeshInstance3D = $TerrainGrid
@onready var probability_fog: MeshInstance3D = $ProbabilityFog
@onready var probability_volume: FogVolume = $ProbabilityVolume
@onready var probability_wisps: MultiMeshInstance3D = $ProbabilityWisps
@onready var aim_label: Label = $Overlay/AimLabel
@onready var club_selector: OptionButton = $Overlay/ClubSelector
@onready var shot_power_label: Label = $Overlay/ShotPowerLabel
@onready var shot_power_slider: ShotPowerRail = $Overlay/ShotPowerSlider
@onready var mishit_announcement: Label = $Overlay/MishitAnnouncement
@onready var mishit_chance_label: Label = $Overlay/MishitChanceLabel
@onready var shoot_button: Button = $Overlay/ShootButton
@onready var preview_timer: Timer = $PreviewDebounce
@onready var physics_client: PhysicsClient = $PhysicsClient
@onready var tactical_view_button: Button = $Overlay/TacticalViewButton
@onready var flyover_button: Button = $Overlay/FlyoverButton
@onready var reset_hole_button: Button = $Overlay/ResetHoleButton
@onready var test_hole_button: Button = $Overlay/TestHoleButton
@onready var water_carry_button: Button = $Overlay/WaterCarryButton
@onready var place_ball_button: Button = $Overlay/PlaceBallButton
@onready var phase_label: Label = $Overlay/PhaseLabel
@onready var outcome_label: Label = $Overlay/OutcomePanel/OutcomeLabel
@onready var stroke_label: Label = $Overlay/StrokeLabel
@onready var perks_menu_button: Button = $Overlay/PerksMenuButton
@onready var perks_panel: Panel = $Overlay/PerksPanel
@onready var power_perk: Button = $Overlay/PerksPanel/PowerPerk
@onready var consistency_perk: Button = $Overlay/PerksPanel/ConsistencyPerk
@onready var spin_perk: Button = $Overlay/PerksPanel/SpinPerk
@onready var mishit_debug_button: Button = $Overlay/MishitDebugButton
@onready var mishit_debug_panel: Panel = $Overlay/MishitDebugPanel
@onready var mishit_debug_options: VBoxContainer = $Overlay/MishitDebugPanel/Options
@onready var water_relief_panel: Panel = $Overlay/WaterReliefPanel
@onready var drop_button: Button = $Overlay/WaterReliefPanel/DropButton
@onready var replay_button: Button = $Overlay/WaterReliefPanel/ReplayButton

var trajectory: Array[Vector3] = []
var trajectory_phases: Array[int] = []
var trajectory_speeds_mps: Array[float] = []
var trajectory_spin_rpm: Array[float] = []
var sample_dt_s := 0.02
var animation_time_s := 0.0
var trail_mesh := ImmediateMesh.new()
var phase_materials: Array[StandardMaterial3D] = []
var ball_phase_material: StandardMaterial3D
var preview_trajectory_mesh := ImmediateMesh.new()
var aim_line_mesh := ImmediateMesh.new()
var terrain_grid_mesh := ImmediateMesh.new()
var probability_bubble_material: ShaderMaterial
var fog_footprint_density_multiplier := 1.0
var mishit_announcement_tween: Tween
var mishit_debug_group: ButtonGroup
var mishit_debug_mode := "random"
var was_pre_shot := true
var post_shot_camera_transition_started := false
var post_shot_camera_start_position := Vector3.ZERO
var post_shot_camera_start_target := Vector3.ZERO
var latest_preview_request_id := -1
var latest_shot_request_id := -1
var shot_counter := 0
var shot_playing := false
var worker_is_ready := false
var preview_is_ready := false
var probability_display_enabled := true
var preview_cache: Dictionary = {}
var preview_request_keys: Dictionary = {}
var selection_auto_focus := Vector3(0.0, 1.0, -210.0)
var selection_pan_offset := Vector3.ZERO
var selection_focus := Vector3(0.0, 1.0, -210.0)
var orbit_yaw_rad := 0.0
var orbit_elevation_rad := 0.0
var orbit_distance_m := 280.0
var tactical_orbit_distance_m := 90.0
var orbit_dragging := false
var pan_dragging := false
var aim_dragging := false
var aim_camera_locked := false
var aim_deg := 0.0
var shot_camera_forward := Vector3(0.0, 0.0, -1.0)
var current_course_id := "test_hole"
var current_ball_xy_m := Vector2(5.0, 0.0)
var current_ball_height_m := 0.0
var pending_rest_xy_m := Vector2(5.0, 0.0)
var pending_relief_xy_m := Vector2(5.0, 0.0)
var pending_shot_origin_xy_m := Vector2(5.0, 0.0)
var pending_status := STATUS_AT_REST
var pending_surface := 0
var stroke_count := 0
var penalty_count := 0
var hole_complete := false
var awaiting_water_relief := false
var placing_ball := false
var flyover_active := false
var flyover_elapsed_s := 0.0
var flyover_duration_s := 1.0
var flyover_start_distance_m := 0.0
var flyover_end_distance_m := 0.0
var character_button: Button
var character_panel: Panel
var character_text: RichTextLabel
var main_menu_button: Button
var upgrade_overlay: ColorRect
var upgrade_cards: HBoxContainer
var telemetry_label: Label
var scorecard_button: Button
var scorecard_panel: Panel
var scorecard_text: RichTextLabel


func _enter_tree() -> void:
	# Detach the inactive course before its Terrain3D node enters the tree.
	# Waiting until _ready() is too late: Terrain3D has already created native
	# render meshes which can survive ordinary visibility/removal operations.
	water_carry_terrain = get_node("WaterCarryTerrain") as Terrain3D
	remove_child(water_carry_terrain)


func _ready() -> void:
	_configure_game_mode()
	_create_character_ui()
	_create_upgrade_ui()
	_configure_trail()
	_configure_preview_trajectories()
	_configure_aim_line()
	_configure_terrain_grid()
	_update_minimap_camera()
	_reset_orbit_parameters()
	_reset_to_aiming_view(false)
	_configure_club_selector()
	_configure_mishit_debug_options()
	club_selector.item_selected.connect(_on_club_changed)
	shot_power_slider.value_changed.connect(_on_shot_power_changed)
	preview_timer.timeout.connect(_request_live_preview)
	shoot_button.pressed.connect(_request_live_shot)
	physics_client.worker_ready.connect(_on_worker_ready)
	physics_client.preview_received.connect(_on_preview_received)
	physics_client.shot_received.connect(_on_shot_received)
	physics_client.worker_error.connect(_on_worker_error)
	tactical_view_button.pressed.connect(_on_tactical_view_pressed)
	flyover_button.pressed.connect(_on_flyover_pressed)
	reset_hole_button.pressed.connect(_on_reset_hole_pressed)
	test_hole_button.pressed.connect(_on_course_button_pressed.bind("test_hole"))
	water_carry_button.pressed.connect(_on_course_button_pressed.bind("water_carry"))
	place_ball_button.pressed.connect(_on_place_ball_pressed)
	perks_menu_button.pressed.connect(_on_perks_menu_pressed)
	mishit_debug_button.pressed.connect(_on_mishit_debug_button_pressed)
	power_perk.toggled.connect(_on_perk_toggled.bind(power_perk))
	consistency_perk.toggled.connect(_on_perk_toggled.bind(consistency_perk))
	spin_perk.toggled.connect(_on_perk_toggled.bind(spin_perk))
	drop_button.pressed.connect(_on_water_drop_pressed)
	replay_button.pressed.connect(_on_water_replay_pressed)
	shoot_button.disabled = true
	flyover_button.disabled = true
	_update_perk_button(power_perk)
	_update_perk_button(consistency_perk)
	_update_perk_button(spin_perk)
	physics_client.start()


func _configure_club_selector() -> void:
	var clubs := [
		["Driver", "driver"],
		["3-wood", "3wood"],
		["5-iron", "5iron"],
		["7-iron", "7iron"],
		["Pitching wedge", "pw"],
	]
	club_selector.clear()
	for club: Array in clubs:
		if RunState.is_campaign() and str(club[1]) not in RunState.unlocked_clubs:
			continue
		club_selector.add_item(club[0])
		club_selector.set_item_metadata(club_selector.item_count - 1, club[1])
	club_selector.select(0)


func _configure_game_mode() -> void:
	var sandbox := not RunState.is_campaign()
	perks_menu_button.visible = sandbox
	perks_panel.visible = false
	mishit_debug_button.visible = sandbox
	mishit_debug_panel.visible = false
	place_ball_button.visible = sandbox
	test_hole_button.visible = sandbox
	water_carry_button.visible = sandbox
	if RunState.is_campaign():
		mishit_debug_mode = "random"


func _create_character_ui() -> void:
	scorecard_button = Button.new()
	scorecard_button.name = "ScorecardButton"
	scorecard_button.text = "SCORECARD  [P]"
	scorecard_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	scorecard_button.position = Vector2(-980.0, 24.0)
	scorecard_button.size = Vector2(165.0, 35.0)
	scorecard_button.pressed.connect(_toggle_scorecard)
	$Overlay.add_child(scorecard_button)
	scorecard_button.visible = RunState.is_campaign()

	main_menu_button = Button.new()
	main_menu_button.name = "MainMenuButton"
	main_menu_button.text = "MAIN MENU"
	main_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	main_menu_button.position = Vector2(-805.0, 24.0)
	main_menu_button.size = Vector2(150.0, 35.0)
	main_menu_button.pressed.connect(_return_to_main_menu)
	$Overlay.add_child(main_menu_button)

	character_button = Button.new()
	character_button.name = "CharacterButton"
	character_button.text = "CHARACTER  [C]"
	character_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	character_button.position = Vector2(-645.0, 24.0)
	character_button.size = Vector2(155.0, 35.0)
	character_button.pressed.connect(_toggle_character_screen)
	$Overlay.add_child(character_button)
	character_button.visible = RunState.is_campaign()

	character_panel = Panel.new()
	character_panel.name = "CharacterPanel"
	character_panel.set_anchors_preset(Control.PRESET_CENTER)
	character_panel.position = Vector2(-310.0, -300.0)
	character_panel.size = Vector2(620.0, 600.0)
	character_panel.visible = false
	$Overlay.add_child(character_panel)

	var title := Label.new()
	title.position = Vector2(30.0, 22.0)
	title.size = Vector2(560.0, 48.0)
	title.text = "CHARACTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	character_panel.add_child(title)

	character_text = RichTextLabel.new()
	character_text.position = Vector2(42.0, 82.0)
	character_text.size = Vector2(536.0, 435.0)
	character_text.bbcode_enabled = true
	character_text.fit_content = false
	character_text.add_theme_font_size_override("normal_font_size", 19)
	character_panel.add_child(character_text)

	var close_button := Button.new()
	close_button.position = Vector2(210.0, 535.0)
	close_button.size = Vector2(200.0, 44.0)
	close_button.text = "CLOSE"
	close_button.pressed.connect(_toggle_character_screen)
	character_panel.add_child(close_button)
	_refresh_character_screen()

	scorecard_panel = Panel.new()
	scorecard_panel.name = "ScorecardPanel"
	scorecard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scorecard_panel.position = Vector2(-360.0, -285.0)
	scorecard_panel.size = Vector2(720.0, 570.0)
	scorecard_panel.visible = false
	$Overlay.add_child(scorecard_panel)

	var scorecard_title := Label.new()
	scorecard_title.position = Vector2(30.0, 22.0)
	scorecard_title.size = Vector2(660.0, 48.0)
	scorecard_title.text = "SCORECARD"
	scorecard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scorecard_title.add_theme_font_size_override("font_size", 30)
	scorecard_panel.add_child(scorecard_title)

	scorecard_text = RichTextLabel.new()
	scorecard_text.position = Vector2(55.0, 88.0)
	scorecard_text.size = Vector2(610.0, 390.0)
	scorecard_text.bbcode_enabled = true
	scorecard_text.add_theme_font_size_override("normal_font_size", 20)
	scorecard_panel.add_child(scorecard_text)

	var scorecard_close := Button.new()
	scorecard_close.position = Vector2(260.0, 500.0)
	scorecard_close.size = Vector2(200.0, 44.0)
	scorecard_close.text = "CLOSE"
	scorecard_close.pressed.connect(_toggle_scorecard)
	scorecard_panel.add_child(scorecard_close)
	_refresh_scorecard()

	telemetry_label = Label.new()
	telemetry_label.name = "ShotTelemetry"
	telemetry_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	telemetry_label.position = Vector2(-210.0, 135.0)
	telemetry_label.size = Vector2(420.0, 42.0)
	telemetry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	telemetry_label.add_theme_font_size_override("font_size", 22)
	telemetry_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	telemetry_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	telemetry_label.add_theme_constant_override("shadow_offset_x", 2)
	telemetry_label.add_theme_constant_override("shadow_offset_y", 2)
	telemetry_label.visible = false
	$Overlay.add_child(telemetry_label)
	shot_power_slider.set_action_unlocks(
		_is_shot_unlocked("smooth"),
		_is_shot_unlocked("stock"),
		_is_shot_unlocked("full")
	)


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://menu.tscn")


func _create_upgrade_ui() -> void:
	upgrade_overlay = ColorRect.new()
	upgrade_overlay.name = "UpgradeOverlay"
	upgrade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	upgrade_overlay.color = Color(0.02, 0.025, 0.04, 0.82)
	upgrade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	upgrade_overlay.visible = false
	$Overlay.add_child(upgrade_overlay)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-590.0, -250.0)
	panel.size = Vector2(1180.0, 500.0)
	upgrade_overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(30.0, 28.0)
	title.size = Vector2(1120.0, 52.0)
	title.text = "CHOOSE AN UPGRADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(30.0, 82.0)
	subtitle.size = Vector2(1120.0, 30.0)
	subtitle.text = "Select one. Your character keeps it for the rest of the run."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	upgrade_cards = HBoxContainer.new()
	upgrade_cards.position = Vector2(40.0, 135.0)
	upgrade_cards.size = Vector2(1100.0, 310.0)
	upgrade_cards.add_theme_constant_override("separation", 24)
	panel.add_child(upgrade_cards)


func _show_upgrade_draft() -> void:
	if not RunState.is_campaign():
		return
	for child: Node in upgrade_cards.get_children():
		child.queue_free()
	var choices := RunState.draw_upgrade_choices(3)
	for upgrade in choices:
		var card := Button.new()
		card.custom_minimum_size = Vector2(350.0, 300.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.text = "%s\n\n%s" % [upgrade.title, upgrade.description]
		card.add_theme_font_size_override("font_size", 20)
		card.pressed.connect(_on_upgrade_selected.bind(upgrade))
		upgrade_cards.add_child(card)
	upgrade_overlay.visible = true


func _on_upgrade_selected(upgrade) -> void:
	RunState.apply_upgrade(upgrade)
	RunState.current_hole += 1
	upgrade_overlay.visible = false
	_refresh_character_screen()
	_refresh_scorecard()
	_configure_club_selector()
	shot_power_slider.set_action_unlocks(
		_is_shot_unlocked("smooth"),
		_is_shot_unlocked("stock"),
		_is_shot_unlocked("full")
	)
	_update_mishit_chance_label()
	_on_reset_hole_pressed()


func _toggle_character_screen() -> void:
	if not RunState.is_campaign():
		return
	character_panel.visible = not character_panel.visible
	if character_panel.visible:
		scorecard_panel.visible = false
		_refresh_character_screen()


func _toggle_scorecard() -> void:
	if not RunState.is_campaign():
		return
	scorecard_panel.visible = not scorecard_panel.visible
	if scorecard_panel.visible:
		character_panel.visible = false
		_refresh_scorecard()


func _refresh_scorecard() -> void:
	if scorecard_text == null:
		return
	var lines := PackedStringArray(["[b]HOLE        SCORE[/b]"])
	if RunState.hole_scores.is_empty():
		lines.append("No completed holes yet")
	else:
		for index: int in range(RunState.hole_scores.size()):
			lines.append("%2d             %d" % [index + 1, RunState.hole_scores[index]])
	lines.append("\n[b]CURRENT HOLE[/b]     %d" % RunState.current_hole)
	lines.append("[b]RUN TOTAL[/b]        %d" % RunState.total_score)
	scorecard_text.text = "\n".join(lines)


func _refresh_character_screen() -> void:
	if character_text == null:
		return
	var club_names: Array[String] = []
	for club_key: String in RunState.unlocked_clubs:
		club_names.append({"7iron": "7-iron", "5iron": "5-iron", "3wood": "3-wood", "driver": "Driver", "pw": "Pitching wedge"}.get(club_key, club_key))
	var shot_names: Array[String] = []
	for shot_key: String in RunState.unlocked_shots:
		shot_names.append({"chip": "Chip (0-40%)", "smooth": "Smooth (80%)", "stock": "Stock (100%)", "full": "Full Power (120%)"}.get(shot_key, shot_key))
	var upgrades := "None yet"
	if not RunState.collected_upgrades.is_empty():
		upgrades = "\n".join(RunState.collected_upgrades)
	character_text.text = (
		"[b]STATS[/b]\n"
		+ "Power       %d    %s\n" % [RunState.stats["power"], RunState.stat_effect_text("power")]
		+ "Control     %d    %s\n" % [RunState.stats["control"], RunState.stat_effect_text("control")]
		+ "Spin        %d    %s\n" % [RunState.stats["spin"], RunState.stat_effect_text("spin")]
		+ "Mis-hit chance     %.0f%%\n\n" % (RunState.mishit_chance * 100.0)
		+ "[b]CLUBS[/b]\n%s\n\n" % ", ".join(club_names)
		+ "[b]SHOT OPTIONS[/b]\n%s\n\n" % ", ".join(shot_names)
		+ "[b]COLLECTED UPGRADES[/b]\n%s" % upgrades
	)


func _on_club_changed(_index: int) -> void:
	# Club changes invalidate the same preview state as aim changes. Reusing
	# this path also gives cached club/aim combinations immediate display.
	_configure_mishit_debug_options()
	_on_aim_changed(aim_deg)


func _on_mishit_debug_button_pressed() -> void:
	mishit_debug_panel.visible = not mishit_debug_panel.visible
	if mishit_debug_panel.visible:
		perks_panel.visible = false
		perks_menu_button.text = "PERKS  ▸"
	mishit_debug_button.text = (
		"MIS-HIT DEBUG  ▾" if mishit_debug_panel.visible else "MIS-HIT DEBUG  ▸"
	)


func _configure_mishit_debug_options() -> void:
	var club_key: String = club_selector.get_item_metadata(club_selector.selected)
	var club_options: Array = MISHIT_DEBUG_OPTIONS[club_key]
	var available_modes := ["random", "clean"]
	for option: Array in club_options:
		available_modes.append(str(option[0]))
	if mishit_debug_mode not in available_modes:
		mishit_debug_mode = "random"

	for child: Node in mishit_debug_options.get_children():
		child.queue_free()
	mishit_debug_group = ButtonGroup.new()
	var options: Array = [["random", "Random (10%)"], ["clean", "No mis-hit"]]
	options.append_array(club_options)
	for option: Array in options:
		var mode := str(option[0])
		var radio := CheckBox.new()
		radio.text = str(option[1])
		radio.button_group = mishit_debug_group
		radio.button_pressed = mode == mishit_debug_mode
		radio.toggled.connect(_on_mishit_debug_option_toggled.bind(mode, str(option[1])))
		mishit_debug_options.add_child(radio)
	_update_mishit_chance_label()


func _on_mishit_debug_option_toggled(
	pressed: bool, mode: String, display_name: String
) -> void:
	if not pressed:
		return
	mishit_debug_mode = mode
	_update_mishit_chance_label(display_name)


func _update_mishit_chance_label(forced_display_name := "") -> void:
	if RunState.is_campaign():
		mishit_chance_label.text = "Mis-hit chance: %.0f%%" % (RunState.mishit_chance * 100.0)
		return
	match mishit_debug_mode:
		"random":
			mishit_chance_label.text = "Mis-hit chance: 10%"
		"clean":
			mishit_chance_label.text = "Mis-hit chance: 0% (debug)"
		_:
			if forced_display_name.is_empty():
				var club_key: String = club_selector.get_item_metadata(club_selector.selected)
				for option: Array in MISHIT_DEBUG_OPTIONS[club_key]:
					if str(option[0]) == mishit_debug_mode:
						forced_display_name = str(option[1])
						break
			mishit_chance_label.text = "Forced mis-hit: %s" % forced_display_name


func _on_shot_power_changed(value: float) -> void:
	var snapped_power := _snap_to_unlocked_power(roundi(value))
	if snapped_power != roundi(value):
		shot_power_slider.set_value_no_signal(snapped_power)
	_update_shot_power_label(snapped_power)
	_on_aim_changed(aim_deg)


func _step_shot_power(direction: int) -> void:
	var current := _shot_power_percent()
	var next_power := current
	if direction > 0:
		if current < CHIP_UNLOCK_MAX_PERCENT:
			next_power = current + 1
		elif current < SMOOTH_POWER_PERCENT and _is_shot_unlocked("smooth"):
			next_power = SMOOTH_POWER_PERCENT
		elif current < STOCK_POWER_PERCENT and _is_shot_unlocked("stock"):
			next_power = STOCK_POWER_PERCENT
		elif current < FULL_POWER_PERCENT and _is_shot_unlocked("full"):
			next_power = FULL_POWER_PERCENT
	elif direction < 0:
		if current > STOCK_POWER_PERCENT and _is_shot_unlocked("stock"):
			next_power = STOCK_POWER_PERCENT
		elif current > SMOOTH_POWER_PERCENT and _is_shot_unlocked("smooth"):
			next_power = SMOOTH_POWER_PERCENT
		elif current > CHIP_UNLOCK_MAX_PERCENT:
			next_power = CHIP_UNLOCK_MAX_PERCENT
		elif current > 0:
			next_power = current - 1
	if next_power == current:
		return
	shot_power_slider.set_value_no_signal(next_power)
	_update_shot_power_label(next_power)
	_on_aim_changed(aim_deg)


func _step_club(direction: int) -> void:
	var next_index := clampi(
		club_selector.selected + direction, 0, club_selector.item_count - 1
	)
	if next_index == club_selector.selected:
		return
	club_selector.select(next_index)
	_on_club_changed(next_index)


func _snap_to_unlocked_power(requested_power: int) -> int:
	var bounded := clampi(requested_power, 0, POWER_SLIDER_MAX_PERCENT)
	if bounded <= CHIP_UNLOCK_MAX_PERCENT:
		return bounded
	var nearest_power := CHIP_UNLOCK_MAX_PERCENT
	var discrete_powers: Array[int] = []
	if _is_shot_unlocked("smooth"):
		discrete_powers.append(SMOOTH_POWER_PERCENT)
	if _is_shot_unlocked("stock"):
		discrete_powers.append(STOCK_POWER_PERCENT)
	if _is_shot_unlocked("full"):
		discrete_powers.append(FULL_POWER_PERCENT)
	for unlocked_power: int in discrete_powers:
		if abs(bounded - unlocked_power) < abs(bounded - nearest_power):
			nearest_power = unlocked_power
	return nearest_power


func _is_shot_unlocked(shot_key: String) -> bool:
	return not RunState.is_campaign() or shot_key in RunState.unlocked_shots


func _shot_power_percent() -> int:
	return roundi(shot_power_slider.value)


func _selected_shot_type() -> String:
	match _shot_power_percent():
		SMOOTH_POWER_PERCENT:
			return "smooth"
		STOCK_POWER_PERCENT:
			return "stock"
		FULL_POWER_PERCENT:
			return "full"
		_:
			return "chip"


func _update_shot_power_label(power_percent: int) -> void:
	match power_percent:
		SMOOTH_POWER_PERCENT:
			shot_power_label.text = "Smooth shot · 80%"
		STOCK_POWER_PERCENT:
			shot_power_label.text = "Stock shot · 100%"
		FULL_POWER_PERCENT:
			shot_power_label.text = "Full Power shot · 120%"
		_:
			shot_power_label.text = "Chip shot · %d%%" % power_percent


func _on_perks_menu_pressed() -> void:
	perks_panel.visible = not perks_panel.visible
	if perks_panel.visible:
		mishit_debug_panel.visible = false
		mishit_debug_button.text = "MIS-HIT DEBUG  ▸"
	perks_menu_button.text = "PERKS  ▾" if perks_panel.visible else "PERKS  ▸"


func _on_perk_toggled(_active: bool, button: Button) -> void:
	_update_perk_button(button)
	# Modifiers are part of the settings and cache key, so toggling a perk uses
	# the same deterministic preview cases with new physics.
	_on_aim_changed(aim_deg)


func _update_perk_button(button: Button) -> void:
	button.modulate = (
		Color(0.62, 1.0, 0.55, 1.0)
		if button.button_pressed
		else Color(0.62, 0.66, 0.72, 0.88)
	)


func _set_perk_controls_disabled(disabled: bool) -> void:
	power_perk.disabled = disabled
	consistency_perk.disabled = disabled
	spin_perk.disabled = disabled


func _on_aim_changed(value: float) -> void:
	# Keep the guide continuous. Physics requests quantize separately so nearby
	# cursor positions can still reuse cached previews.
	aim_deg = wrapf(value, -180.0, 180.0)
	aim_label.text = "Aim: %+.1f°   (right-drag to turn)" % aim_deg
	if hole_complete or awaiting_water_relief:
		return
	_stop_flyover(false)
	shot_playing = false
	trajectory.clear()
	trail_mesh.clear_surfaces()
	preview_is_ready = false
	_reset_to_aiming_view(false)
	shoot_button.disabled = true
	flyover_button.disabled = true
	if _shot_power_percent() == 0:
		preview_timer.stop()
		latest_preview_request_id = -1
		probability_fog.visible = false
		probability_volume.visible = false
		probability_wisps.visible = false
		preview_trajectory_mesh.clear_surfaces()
		outcome_label.text = "OUTCOME CHANCES\nSelect power above 0%"
		$Overlay/PreviewStatus.text = "0% power — no shot selected"
		return
	if worker_is_ready:
		var cache_key := _preview_cache_key()
		if preview_cache.has(cache_key):
			latest_preview_request_id = -1
			_apply_preview_payload(preview_cache[cache_key], true)
		else:
			preview_timer.start()


func _physics_settings() -> Dictionary:
	var mishit_chance := (
		RunState.mishit_chance
		if RunState.is_campaign()
		else (BASE_MISHIT_CHANCE if mishit_debug_mode == "random" else 0.0)
	)
	var forced_mishit := (
		"" if mishit_debug_mode in ["random", "clean"] else mishit_debug_mode
	)
	var resolved_modifiers := RunState.resolved_modifiers()
	if not RunState.is_campaign():
		resolved_modifiers = {
			"speed_multiplier": 1.1 if power_perk.button_pressed else 1.0,
			"dispersion_multiplier": 0.8 if consistency_perk.button_pressed else 1.0,
			"spin_multiplier": 1.5 if spin_perk.button_pressed else 1.0,
		}
	return {
		"course_id": current_course_id,
		"aim_deg": snappedf(aim_deg, 0.25),
		"club": club_selector.get_item_metadata(club_selector.selected),
		"shot_type": _selected_shot_type(),
		"shot_power": (
			float(_shot_power_percent()) / 100.0
			if _selected_shot_type() == "chip"
			else 1.0
		),
		"mishit_chance": mishit_chance,
		"forced_mishit": forced_mishit,
		"start_xy_m": [current_ball_xy_m.x, current_ball_xy_m.y],
		"modifiers": resolved_modifiers,
		"environment": {},
	}


func _preview_cache_key() -> String:
	# Include everything that changes the preview. This same boundary can later
	# include clubs, item modifiers, wind, and the preview context identifier.
	return JSON.stringify(
		{
			"preview_seed": _current_preview_seed(),
			"sample_count": 500,
			"settings": _physics_settings(),
		}
	)


func _current_preview_seed() -> int:
	# Each stroke is a new decision context, but revisiting settings within that
	# decision reuses the same underlying random cases.
	return 24681357 + stroke_count * 1009


func _on_worker_ready() -> void:
	worker_is_ready = true
	$Overlay/Hint.text = "Live Python worker ready — adjust aim, then press Shoot"
	_request_live_preview()


func _request_live_preview() -> void:
	if not worker_is_ready:
		return
	var cache_key := _preview_cache_key()
	latest_preview_request_id = physics_client.request_preview(
		_physics_settings(), _current_preview_seed(), 500
	)
	preview_request_keys[latest_preview_request_id] = cache_key
	$Overlay/PreviewStatus.text = "Calculating 500-shot preview…"


func _on_preview_received(response: Dictionary) -> void:
	var request_id: int = response.get("request_id", -1)
	var cache_key: String = preview_request_keys.get(request_id, "")
	if not cache_key.is_empty():
		preview_cache[cache_key] = response["payload"]
		preview_request_keys.erase(request_id)
	if request_id != latest_preview_request_id:
		return
	_apply_preview_payload(response["payload"], false)


func _apply_preview_payload(payload: Dictionary, from_cache: bool) -> void:
	_apply_fog_grid(payload["grid"])
	_apply_preview_trajectories(payload.get("preview_paths_xyz_m", []))
	_update_outcome_panel(payload.get("statistics", {}))
	var lie_name: String = payload.get("lie", "unknown")
	var source_text := "Cached preview" if from_cache else "Preview ready"
	$Overlay/PreviewStatus.text = "%s - %s lie" % [source_text, lie_name.capitalize()]
	preview_is_ready = true
	shoot_button.disabled = false
	flyover_button.disabled = false


func _update_outcome_panel(statistics: Dictionary) -> void:
	if statistics.is_empty():
		outcome_label.text = "OUTCOME CHANCES\nCalculating…"
		return
	var rows := [
		["Fairway", "fairway_pct"],
		["Rough", "rough_pct"],
		["Green", "green_pct"],
		["Bunker", "bunker_pct"],
		["Water", "water_pct"],
		["Out of bounds", "ob_pct"],
	]
	var lines := PackedStringArray(["OUTCOME CHANCES"])
	for row: Array in rows:
		lines.append("%-14s %5.1f%%" % [row[0], float(statistics.get(row[1], 0.0))])
	outcome_label.text = "\n".join(lines)


func _apply_fog_grid(grid: Dictionary) -> void:
	var x_values: Array = grid["x_m"]
	var y_values: Array = grid["y_m"]
	var heights: Array = grid["height_m"]
	var densities: Array = grid["density"]
	_update_selection_focus(x_values, y_values, heights, densities)
	# The main camera gets volumetric fog and wisps. A separate emissive surface
	# on visibility layer 2 makes the same density legible from the tiny top-down
	# minimap without making the close main-camera fog ten times brighter.
	_build_minimap_probability_mesh(x_values, y_values, heights, densities)
	probability_fog.visible = probability_display_enabled
	_build_probability_volume(x_values, y_values, heights, densities)
	_build_probability_wisps(x_values, y_values, heights, densities)
	probability_wisps.visible = probability_display_enabled
	if aim_line.visible and not shot_playing:
		_update_selection_camera()


func _request_live_shot() -> void:
	_stop_flyover(false)
	perks_panel.visible = false
	perks_menu_button.text = "PERKS  ▸"
	_set_fog_playback_mode(true)
	shoot_button.disabled = true
	tactical_view_button.disabled = true
	flyover_button.disabled = true
	aim_line.visible = false
	preview_trajectories.visible = false
	club_selector.disabled = true
	shot_power_slider.editable = false
	_set_perk_controls_disabled(true)
	shot_counter += 1
	pending_shot_origin_xy_m = current_ball_xy_m
	latest_shot_request_id = physics_client.request_shot(
		_physics_settings(), 97531000 + shot_counter
	)
	$Overlay/PreviewStatus.text = "Calculating independent shot…"


func _on_shot_received(response: Dictionary) -> void:
	if response.get("request_id", -1) != latest_shot_request_id:
		return
	latest_shot_request_id = -1
	var payload: Dictionary = response["payload"]
	if bool(payload.get("mishit", false)):
		_show_mishit_announcement(str(payload.get("mishit_name", "Mis-hit")))
	trajectory.clear()
	trajectory_phases.clear()
	trajectory_speeds_mps.clear()
	trajectory_spin_rpm.clear()
	sample_dt_s = payload["sample_dt_s"]
	for point: Array in payload["positions_xyz_m"]:
		trajectory.append(Vector3(-point[1], point[2] + VISUAL_BALL_RADIUS_M, -point[0]))
	for phase_value in payload.get("phases", []):
		trajectory_phases.append(int(phase_value))
	for speed_value in payload.get("speeds_mps", []):
		trajectory_speeds_mps.append(float(speed_value))
	for spin_value in payload.get("spin_rpm", []):
		trajectory_spin_rpm.append(float(spin_value))
	if trajectory_phases.size() != trajectory.size():
		trajectory_phases.resize(trajectory.size())
		trajectory_phases.fill(PHASE_FLIGHT)
	if trajectory.size() >= 2:
		var launch_travel := trajectory[mini(5, trajectory.size() - 1)] - trajectory[0]
		launch_travel.y = 0.0
		if launch_travel.length_squared() > 0.0001:
			shot_camera_forward = launch_travel.normalized()
		else:
			shot_camera_forward = _aim_direction()
	var rest: Array = payload["rest_xy_m"]
	pending_rest_xy_m = Vector2(rest[0], rest[1])
	var relief: Array = payload["relief_xy_m"]
	pending_relief_xy_m = Vector2(relief[0], relief[1])
	pending_status = payload["status"]
	pending_surface = payload["surface"]
	animation_time_s = 0.0
	was_pre_shot = true
	post_shot_camera_transition_started = false
	shot_playing = true
	telemetry_label.visible = true
	trail_mesh.clear_surfaces()
	ball.position = trajectory[0]
	_set_phase_display(PHASE_FLIGHT)
	_place_camera_immediately()
	$Overlay/PreviewStatus.text = "Independent shot %d" % shot_counter


func _show_mishit_announcement(mishit_name: String) -> void:
	if mishit_announcement_tween != null:
		mishit_announcement_tween.kill()
	mishit_announcement.text = "Mis-hit: %s!" % mishit_name
	mishit_announcement.visible = true
	mishit_announcement.pivot_offset = mishit_announcement.size * 0.5
	mishit_announcement.scale = Vector2(0.30, 0.30)
	mishit_announcement.modulate.a = 0.0
	mishit_announcement_tween = create_tween()
	mishit_announcement_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	mishit_announcement_tween.tween_property(
		mishit_announcement, "scale", Vector2(1.18, 1.18), 0.20
	)
	mishit_announcement_tween.parallel().tween_property(
		mishit_announcement, "modulate:a", 1.0, 0.10
	)
	mishit_announcement_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	mishit_announcement_tween.tween_property(
		mishit_announcement, "scale", Vector2.ONE, 0.10
	)
	mishit_announcement_tween.tween_interval(1.20)
	mishit_announcement_tween.tween_property(
		mishit_announcement, "modulate:a", 0.0, 0.35
	)
	mishit_announcement_tween.tween_callback(mishit_announcement.hide)


func _on_worker_error(message: String) -> void:
	_set_fog_playback_mode(false)
	$Overlay/PreviewStatus.text = "Physics error: " + message
	push_error(message)


func _process(delta: float) -> void:
	if flyover_active:
		_update_flyover(delta)
		return
	if not shot_playing or trajectory.size() < 2:
		return
	animation_time_s += delta
	var duration := (trajectory.size() - 1) * sample_dt_s
	var rest_start_s := pre_shot_pause_s + duration / playback_speed
	var rest_elapsed_s := maxf(animation_time_s - rest_start_s, 0.0)
	var dispersal_start_s := maxf(
		fog_dispersal_delay_s, post_shot_tactical_transition_s
	)
	var dispersal_progress := clampf(
		(rest_elapsed_s - dispersal_start_s) / fog_dispersal_duration_s,
		0.0,
		1.0
	)
	_set_fog_dispersal(dispersal_progress)
	var shot_time := (animation_time_s - pre_shot_pause_s) * playback_speed
	var is_pre_shot := shot_time < 0.0
	var sample_position := clampf(shot_time / sample_dt_s, 0.0, trajectory.size() - 1)
	var index := mini(floori(sample_position), trajectory.size() - 2)
	var fraction := sample_position - index
	ball.position = trajectory[index].lerp(trajectory[index + 1], fraction)
	var current_phase := trajectory_phases[index] if index < trajectory_phases.size() else PHASE_FLIGHT
	_set_phase_display(current_phase)
	_update_shot_telemetry(index, fraction)
	_update_trail(index)

	if rest_elapsed_s > 0.0:
		_update_post_shot_tactical_camera(rest_elapsed_s)
	else:
		# A damped chase camera gives the ball room to travel into the frame.
		if is_pre_shot and not was_pre_shot:
			# Treat each replay like a broadcast cut back to the tee.
			_place_camera_immediately()
		var desired_position := ball.position + _shot_camera_world_offset()
		var follow_terrain_height := course_terrain.data.get_height(desired_position)
		if not is_nan(follow_terrain_height):
			desired_position.y = maxf(
				desired_position.y, follow_terrain_height + 0.20
			)
		var camera_blend := 1.0 - exp(-camera_follow_speed * delta)
		camera.position = camera.position.lerp(desired_position, camera_blend)
		camera.look_at(
			ball.position
			+ Vector3.UP * camera_look_height_m
			+ shot_camera_forward * camera_look_ahead_m,
			Vector3.UP
		)
	_update_volumetric_fog_range()
	was_pre_shot = is_pre_shot
	var required_post_shot_pause_s := maxf(
		finish_pause_s, dispersal_start_s + fog_dispersal_duration_s
	)
	if animation_time_s >= rest_start_s + required_post_shot_pause_s:
		_finish_shot()


func _update_shot_telemetry(index: int, fraction: float) -> void:
	if trajectory_speeds_mps.is_empty() or trajectory_spin_rpm.is_empty():
		telemetry_label.text = ""
		return
	var speed_index := mini(index, trajectory_speeds_mps.size() - 1)
	var speed_next := mini(speed_index + 1, trajectory_speeds_mps.size() - 1)
	var spin_index := mini(index, trajectory_spin_rpm.size() - 1)
	var spin_next := mini(spin_index + 1, trajectory_spin_rpm.size() - 1)
	var speed_mps := lerpf(
		trajectory_speeds_mps[speed_index],
		trajectory_speeds_mps[speed_next],
		fraction
	)
	var spin := lerpf(
		trajectory_spin_rpm[spin_index],
		trajectory_spin_rpm[spin_next],
		fraction
	)
	telemetry_label.text = "BALL SPEED  %3.0f mph     TOTAL SPIN  %4.0f rpm" % [
		speed_mps * 2.236936, spin
	]


func _update_post_shot_tactical_camera(rest_elapsed_s: float) -> void:
	var ball_target := ball.position + Vector3.UP * camera_look_height_m
	if not post_shot_camera_transition_started:
		post_shot_camera_transition_started = true
		post_shot_camera_start_position = camera.position
		post_shot_camera_start_target = ball_target

	var progress := clampf(
		rest_elapsed_s / maxf(post_shot_tactical_transition_s, 0.001), 0.0, 1.0
	)
	var eased := smoothstep(0.0, 1.0, progress)
	var tactical_yaw := -deg_to_rad(aim_deg) + deg_to_rad(default_orbit_yaw_deg)
	var tactical_elevation := deg_to_rad(default_orbit_elevation_deg)
	var horizontal_distance := tactical_orbit_distance_m * cos(tactical_elevation)
	var tactical_offset := Vector3(
		sin(tactical_yaw) * horizontal_distance,
		sin(tactical_elevation) * tactical_orbit_distance_m,
		cos(tactical_yaw) * horizontal_distance
	)
	var tactical_position := selection_auto_focus + tactical_offset
	camera.position = post_shot_camera_start_position.lerp(tactical_position, eased)
	var look_target := post_shot_camera_start_target.lerp(selection_auto_focus, eased)
	camera.look_at(look_target, Vector3.UP)


func _finish_shot() -> void:
	shot_playing = false
	telemetry_label.visible = false
	stroke_count += 1
	_update_score_label()

	if pending_status == STATUS_IN_WATER:
		_show_water_relief_choices()
		return

	if pending_status == STATUS_OUT_OF_BOUNDS:
		penalty_count += 1
		current_ball_xy_m = pending_shot_origin_xy_m
		_update_score_label()
		_prepare_next_shot("Out of bounds - one-stroke penalty; replay from the previous lie")
		return

	current_ball_xy_m = pending_rest_xy_m
	if not trajectory.is_empty():
		current_ball_height_m = trajectory[-1].y - VISUAL_BALL_RADIUS_M
	if pending_status == STATUS_AT_REST and pending_surface == SURFACE_GREEN:
		hole_complete = true
		shoot_button.disabled = true
		club_selector.disabled = true
		shot_power_slider.editable = false
		_set_perk_controls_disabled(true)
		$Overlay/PreviewStatus.text = "Green reached - score %d" % (stroke_count + penalty_count)
		if RunState.is_campaign():
			var completed_score := stroke_count + penalty_count
			RunState.hole_scores.append(completed_score)
			RunState.total_score += completed_score
			_refresh_scorecard()
			$Overlay/Hint.text = "Hole complete - choose an upgrade"
			_show_upgrade_draft()
		else:
			$Overlay/Hint.text = "Hole complete - press RESET HOLE to play again"
		return
	_prepare_next_shot("Stroke %d - choose the next shot" % (stroke_count + 1))


func _show_water_relief_choices() -> void:
	awaiting_water_relief = true
	shoot_button.disabled = true
	club_selector.disabled = true
	shot_power_slider.editable = false
	_set_perk_controls_disabled(true)
	water_relief_panel.visible = true
	$Overlay/PreviewStatus.text = "Water - choose penalty relief"
	$Overlay/Hint.text = "Both options add one penalty stroke"


func _on_water_drop_pressed() -> void:
	if not awaiting_water_relief:
		return
	penalty_count += 1
	current_ball_xy_m = pending_relief_xy_m
	_update_score_label()
	_prepare_next_shot("Water penalty - dropped beside the entry point")


func _on_water_replay_pressed() -> void:
	if not awaiting_water_relief:
		return
	penalty_count += 1
	current_ball_xy_m = pending_shot_origin_xy_m
	_update_score_label()
	_prepare_next_shot("Water penalty - replay from the previous lie")


func _prepare_next_shot(message: String) -> void:
	telemetry_label.visible = false
	awaiting_water_relief = false
	water_relief_panel.visible = false
	preview_is_ready = false
	probability_fog.visible = false
	probability_volume.visible = false
	probability_wisps.visible = false
	preview_trajectory_mesh.clear_surfaces()
	club_selector.disabled = false
	shot_power_slider.editable = true
	_set_perk_controls_disabled(false)
	_on_aim_changed(aim_deg)
	$Overlay/Hint.text = message


func _update_score_label() -> void:
	var prefix := "Hole %d (Test Hole)   " % RunState.current_hole if RunState.is_campaign() else ""
	stroke_label.text = prefix + "Shots: %d   Penalties: %d   Score: %d" % [
		stroke_count, penalty_count, stroke_count + penalty_count
	]


func _on_reset_hole_pressed() -> void:
	shot_playing = false
	telemetry_label.visible = false
	latest_shot_request_id = -1
	hole_complete = false
	awaiting_water_relief = false
	water_relief_panel.visible = false
	stroke_count = 0
	penalty_count = 0
	_update_score_label()
	var tee_xy: Vector2 = COURSE_CONFIGS[current_course_id]["tee_xy_m"]
	current_ball_xy_m = tee_xy
	current_ball_height_m = 0.0
	aim_deg = 0.0
	pending_rest_xy_m = tee_xy
	pending_relief_xy_m = tee_xy
	pending_shot_origin_xy_m = tee_xy
	preview_is_ready = false
	trajectory.clear()
	trajectory_phases.clear()
	placing_ball = false
	_stop_flyover(false)
	place_ball_button.button_pressed = false
	phase_label.visible = false
	flyover_button.disabled = true
	outcome_label.text = "OUTCOME CHANCES\nCalculating…"
	trail_mesh.clear_surfaces()
	probability_fog.visible = false
	probability_volume.visible = false
	probability_wisps.visible = false
	preview_trajectory_mesh.clear_surfaces()
	club_selector.disabled = false
	shot_power_slider.editable = true
	_set_perk_controls_disabled(false)
	_reset_orbit_parameters()
	_on_aim_changed(aim_deg)
	$Overlay/Hint.text = "New hole — choose a club and aim"


func _on_course_button_pressed(course_id: String) -> void:
	if course_id == current_course_id:
		_on_reset_hole_pressed()
		return
	current_course_id = course_id
	# Reassigning Terrain3D.data_directory at runtime crashes Terrain3D 1.1.2 on
	# Windows. Both terrains are preloaded, but only the selected one is attached
	# to the scene tree, preventing both overlap and unsafe native mutation.
	remove_child(course_terrain)
	course_terrain = test_hole_terrain if course_id == "test_hole" else water_carry_terrain
	add_child(course_terrain)
	preview_cache.clear()
	preview_request_keys.clear()
	latest_preview_request_id = -1
	_update_minimap_camera()
	_build_terrain_grid_mesh()
	_on_reset_hole_pressed()


func _place_camera_immediately() -> void:
	var desired_position := ball.position + _shot_camera_world_offset()
	var terrain_height := course_terrain.data.get_height(desired_position)
	if not is_nan(terrain_height):
		desired_position.y = maxf(desired_position.y, terrain_height + 0.20)
	camera.position = desired_position
	camera.look_at(
		ball.position
		+ Vector3.UP * camera_look_height_m
		+ shot_camera_forward * camera_look_ahead_m,
		Vector3.UP
	)


func _aim_direction() -> Vector3:
	var angle := deg_to_rad(aim_deg)
	return Vector3(sin(angle), 0.0, -cos(angle))


func _shot_camera_world_offset() -> Vector3:
	# camera_offset_m is expressed in the shot's local frame: X is to the
	# player's right, Y is up, and positive Z is behind the shot.
	var shot_right := Vector3(-shot_camera_forward.z, 0.0, shot_camera_forward.x)
	return (
		shot_right * camera_offset_m.x
		+ Vector3.UP * camera_offset_m.y
		- shot_camera_forward * camera_offset_m.z
	)


func _update_selection_focus(
	x_values: Array, y_values: Array, heights: Array, densities: Array
) -> void:
	if x_values.is_empty() or y_values.is_empty():
		return
	var total := 0.0
	var weighted_x := 0.0
	var weighted_y := 0.0
	var weighted_height := 0.0
	var density_values := PackedFloat32Array()
	for i in x_values.size():
		for j in y_values.size():
			var weight: float = densities[i][j]
			density_values.append(weight)
			total += weight
			weighted_x += x_values[i] * weight
			weighted_y += y_values[j] * weight
			weighted_height += heights[i][j] * weight
	if total > 0.0:
		selection_auto_focus = Vector3(
			-weighted_y / total,
			weighted_height / total + 2.0,
			-weighted_x / total
		)
		# Find a highest-density region containing the requested fraction of the
		# approximate probability mass. Unlike the full fog bounds, this ignores
		# isolated low-density outliers but retains meaningful secondary lobes.
		density_values.sort()
		var target_mass := tactical_probability_capture * total
		var captured_mass := 0.0
		var density_cutoff := 0.0
		for sorted_index in range(density_values.size() - 1, -1, -1):
			captured_mass += density_values[sorted_index]
			density_cutoff = density_values[sorted_index]
			if captured_mass >= target_mass:
				break

		var framing_radius := 0.0
		for i in x_values.size():
			for j in y_values.size():
				if float(densities[i][j]) < density_cutoff:
					continue
				var point := Vector3(-y_values[j], heights[i][j], -x_values[i])
				framing_radius = maxf(
					framing_radius, point.distance_to(selection_auto_focus)
				)
		var cell_padding := 0.0
		if x_values.size() > 1:
			cell_padding += 0.5 * absf(float(x_values[1]) - float(x_values[0]))
		if y_values.size() > 1:
			cell_padding += 0.5 * absf(float(y_values[1]) - float(y_values[0]))
		framing_radius += cell_padding + 0.5 * FOG_CLOUD_HEIGHT_M
		var half_fov := deg_to_rad(camera.fov * 0.5)
		var fitted_distance := (
			framing_radius * tactical_frame_margin / maxf(sin(half_fov), 0.1)
		)
		tactical_orbit_distance_m = clampf(
			maxf(default_orbit_distance_m, fitted_distance),
			minimum_orbit_distance_m,
			maximum_orbit_distance_m
		)
		if aim_camera_locked:
			_set_aim_aligned_focus()
		else:
			selection_focus = selection_auto_focus + selection_pan_offset
			orbit_distance_m = tactical_orbit_distance_m
			_update_selection_camera()


func _reset_orbit_parameters() -> void:
	aim_camera_locked = false
	orbit_yaw_rad = deg_to_rad(default_orbit_yaw_deg)
	orbit_elevation_rad = deg_to_rad(default_orbit_elevation_deg)
	orbit_distance_m = tactical_orbit_distance_m
	selection_pan_offset = Vector3.ZERO
	selection_focus = selection_auto_focus


func _update_selection_camera() -> void:
	var horizontal_distance := orbit_distance_m * cos(orbit_elevation_rad)
	var offset := Vector3(
		sin(orbit_yaw_rad) * horizontal_distance,
		sin(orbit_elevation_rad) * orbit_distance_m,
		cos(orbit_yaw_rad) * horizontal_distance
	)
	var desired_position := selection_focus + offset
	var terrain_height := course_terrain.data.get_height(desired_position)
	if not is_nan(terrain_height):
		desired_position.y = maxf(
			desired_position.y, terrain_height + camera_terrain_clearance_m
		)
	camera.position = desired_position
	camera.look_at(selection_focus, Vector3.UP)
	_update_volumetric_fog_range()


func _update_volumetric_fog_range() -> void:
	if not probability_volume.visible or world_environment.environment == null:
		return
	# Volumetric fog has a hard camera-relative range. Track the far edge of
	# this local volume so zooming out never silently clips the preview, while
	# avoiding a permanently huge range that would waste depth resolution.
	var volume_radius := probability_volume.size.length() * 0.5
	var required_range := (
		camera.global_position.distance_to(probability_volume.global_position)
		+ volume_radius
		+ 30.0
	)
	world_environment.environment.volumetric_fog_length = clampf(
		required_range, 120.0, 800.0
	)


func _set_aim_aligned_focus() -> void:
	var ball_ground := _current_ball_position() - Vector3(0.0, VISUAL_BALL_RADIUS_M, 0.0)
	var aim_direction := Vector3(sin(deg_to_rad(aim_deg)), 0.0, -cos(deg_to_rad(aim_deg)))
	var fog_distance := Vector2(
		selection_auto_focus.x - ball_ground.x,
		selection_auto_focus.z - ball_ground.z
	).length()
	# Focus partway into the shot while keeping the camera itself behind the
	# ball. The aiming view is intentionally wider than the close ball-follow
	# camera so the outcome cloud remains useful while lining up a shot.
	var focus_distance := clampf(fog_distance * 0.5, 50.0, 130.0)
	var horizontal_camera_distance := orbit_distance_m * cos(orbit_elevation_rad)
	focus_distance = minf(
		focus_distance, maxf(horizontal_camera_distance * 0.86, 2.0)
	)
	selection_focus = ball_ground + aim_direction * focus_distance
	var terrain_height := course_terrain.data.get_height(selection_focus)
	if not is_nan(terrain_height):
		selection_focus.y = terrain_height + 2.0


func _align_camera_behind_aim(reset_pitch_and_zoom: bool) -> void:
	aim_camera_locked = true
	selection_pan_offset = Vector3.ZERO
	orbit_yaw_rad = -deg_to_rad(aim_deg)
	if reset_pitch_and_zoom:
		orbit_elevation_rad = deg_to_rad(aim_camera_elevation_deg)
		orbit_distance_m = aim_camera_distance_m
	_set_aim_aligned_focus()
	_update_selection_camera()


func _return_to_distribution_view() -> void:
	# Right-drag is a temporary aiming camera. On release, return to the useful
	# tactical framing: centered on the probability distribution, viewed from
	# behind the shot with the familiar slight offset to the player's right.
	aim_camera_locked = false
	selection_pan_offset = Vector3.ZERO
	selection_focus = selection_auto_focus
	orbit_yaw_rad = -deg_to_rad(aim_deg) + deg_to_rad(default_orbit_yaw_deg)
	orbit_elevation_rad = deg_to_rad(default_orbit_elevation_deg)
	orbit_distance_m = tactical_orbit_distance_m
	_update_selection_camera()


func _on_tactical_view_pressed() -> void:
	if shot_playing or not aim_line.visible:
		return
	_stop_flyover(false)
	aim_camera_locked = false
	_reset_orbit_parameters()
	_update_selection_camera()


func _on_flyover_pressed() -> void:
	if shot_playing or not preview_is_ready:
		return
	if flyover_active:
		_stop_flyover(true)
		return
	placing_ball = false
	place_ball_button.button_pressed = false
	aim_camera_locked = false
	orbit_dragging = false
	pan_dragging = false
	aim_dragging = false
	var ball_ground := _current_ball_position() - Vector3.UP * VISUAL_BALL_RADIUS_M
	var direction := _aim_direction()
	var distribution_offset := selection_auto_focus - ball_ground
	var distribution_distance := maxf(distribution_offset.dot(direction), 40.0)
	flyover_start_distance_m = -flyover_start_behind_m
	flyover_end_distance_m = distribution_distance + 45.0
	flyover_duration_s = maxf(
		(flyover_end_distance_m - flyover_start_distance_m)
		/ maxf(flyover_speed_mps, 1.0),
		2.0
	)
	flyover_elapsed_s = 0.0
	flyover_active = true
	flyover_button.text = "STOP FLYOVER"
	$Overlay/Hint.text = "Guided flyover along the current aim line"
	_update_flyover(0.0)


func _update_flyover(delta: float) -> void:
	flyover_elapsed_s += delta
	if flyover_elapsed_s >= flyover_duration_s + flyover_finish_hold_s:
		_stop_flyover(true)
		return
	var travel_progress := clampf(
		flyover_elapsed_s / maxf(flyover_duration_s, 0.001), 0.0, 1.0
	)
	var distance := lerpf(
		flyover_start_distance_m, flyover_end_distance_m, travel_progress
	)
	var ball_ground := _current_ball_position() - Vector3.UP * VISUAL_BALL_RADIUS_M
	var direction := _aim_direction()
	var drone_ground := ball_ground + direction * distance
	var terrain_height := course_terrain.data.get_height(drone_ground)
	if is_nan(terrain_height):
		terrain_height = ball_ground.y
	camera.position = Vector3(
		drone_ground.x, terrain_height + flyover_height_m, drone_ground.z
	)
	var look_ground := drone_ground + direction * flyover_look_ahead_m
	var look_height := course_terrain.data.get_height(look_ground)
	if is_nan(look_height):
		look_height = terrain_height
	camera.look_at(
		Vector3(look_ground.x, look_height + 2.0, look_ground.z), Vector3.UP
	)
	_update_volumetric_fog_range()


func _stop_flyover(return_to_tactical: bool) -> void:
	if not flyover_active and not return_to_tactical:
		return
	flyover_active = false
	flyover_button.text = "FLYOVER"
	if return_to_tactical and preview_is_ready:
		_return_to_distribution_view()
		$Overlay/Hint.text = "500-shot physics preview — one outcome animates through the probability fog"


func _update_minimap_camera() -> void:
	var config: Dictionary = COURSE_CONFIGS[current_course_id]
	var bounds: Rect2 = config["bounds"]
	var physics_center := bounds.get_center()
	var target := Vector3(-physics_center.y, 0.0, -physics_center.x)
	minimap_camera.position = target + Vector3.UP * 800.0
	var tee_xy: Vector2 = config["tee_xy_m"]
	var cup_xy: Vector2 = config["cup_xy_m"]
	var tee_to_cup := (cup_xy - tee_xy).normalized()
	# Python (x downrange, y left) maps to Godot (-y, y-up, -x). Using the
	# tee-to-cup vector as camera-up puts the tee at the bottom and cup at top,
	# while preserving a dogleg as a readable lateral bend.
	var map_up := Vector3(-tee_to_cup.y, 0.0, -tee_to_cup.x).normalized()
	minimap_camera.look_at(target, map_up)

	# Fit the rotated bounds rather than the unrotated width/length; otherwise a
	# diagonal hole can clip a corner after adopting the tee-to-cup orientation.
	var map_right := Vector3(-map_up.z, 0.0, map_up.x)
	var min_up := INF
	var max_up := -INF
	var min_right := INF
	var max_right := -INF
	for physics_corner: Vector2 in [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]:
		var world_corner := Vector3(-physics_corner.y, 0.0, -physics_corner.x)
		var relative := world_corner - target
		var up_distance := relative.dot(map_up)
		var right_distance := relative.dot(map_right)
		min_up = minf(min_up, up_distance)
		max_up = maxf(max_up, up_distance)
		min_right = minf(min_right, right_distance)
		max_right = maxf(max_right, right_distance)
	var minimap_aspect := 1.0
	minimap_camera.size = maxf(
		max_up - min_up + 20.0,
		(max_right - min_right) / minimap_aspect + 20.0
	)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and RunState.is_campaign()
		and (event.keycode == KEY_C or event.keycode == KEY_I)
	):
		_toggle_character_screen()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and RunState.is_campaign()
		and event.keycode == KEY_P
	):
		_toggle_scorecard()
		get_viewport().set_input_as_handled()
		return
	if character_panel != null and character_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_toggle_character_screen()
			get_viewport().set_input_as_handled()
		return
	if scorecard_panel != null and scorecard_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_toggle_scorecard()
			get_viewport().set_input_as_handled()
		return
	# Tab is captured before Control focus traversal so hold-to-inspect works even
	# after the player has interacted with a selector or button.
	if (
		event is InputEventKey
		and event.keycode == KEY_TAB
		and not event.echo
	):
		_set_probability_display_enabled(not event.pressed)
		get_viewport().set_input_as_handled()
		return
	# Capture Space before a focused UI button can treat it as a click. This
	# prevents RESET HOLE (or any other previously clicked button) from firing.
	if (
		event is InputEventKey
		and event.keycode == KEY_SPACE
		and event.pressed
		and not event.echo
	):
		if not shoot_button.disabled:
			_request_live_shot()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and not club_selector.disabled
		and aim_line.visible
	):
		if event.keycode == KEY_W or event.keycode == KEY_UP:
			_step_club(-1)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_S or event.keycode == KEY_DOWN:
			_step_club(1)
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventMouseButton
		and event.pressed
		and (event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN)
		and not shot_playing
		and not flyover_active
		and aim_line.visible
	):
		var wheel_direction := (
			1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		)
		if event.shift_pressed:
			_zoom_at_cursor(event.position, 0.88 if wheel_direction > 0 else 1.0 / 0.88)
		else:
			_step_shot_power(wheel_direction)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if shot_playing or flyover_active or not aim_line.visible:
		orbit_dragging = false
		pan_dragging = false
		aim_dragging = false
		return
	if event is InputEventMouseButton:
		if placing_ball and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_place_ball_from_screen(event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			orbit_dragging = event.pressed
			if event.pressed:
				aim_camera_locked = false
				pan_dragging = false
				aim_dragging = false
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var was_aim_dragging := aim_dragging
			aim_dragging = event.pressed
			if event.pressed:
				orbit_dragging = false
				pan_dragging = false
				_align_camera_behind_aim(true)
			elif was_aim_dragging:
				_return_to_distribution_view()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			pan_dragging = event.pressed
			if event.pressed:
				aim_camera_locked = false
				orbit_dragging = false
				aim_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if aim_dragging:
			_on_aim_changed(
				aim_deg + event.relative.x * aim_camera_drag_sensitivity_deg
			)
			_align_camera_behind_aim(false)
			get_viewport().set_input_as_handled()
		elif orbit_dragging:
			orbit_yaw_rad -= deg_to_rad(event.relative.x * orbit_mouse_sensitivity)
			orbit_elevation_rad = clampf(
				orbit_elevation_rad - deg_to_rad(event.relative.y * orbit_mouse_sensitivity),
				deg_to_rad(minimum_orbit_elevation_deg),
				deg_to_rad(maximum_orbit_elevation_deg)
			)
			_update_selection_camera()
			get_viewport().set_input_as_handled()
		elif pan_dragging:
			_pan_selection_camera(event.relative)
			get_viewport().set_input_as_handled()


func _zoom_at_cursor(screen_position: Vector2, distance_factor: float) -> void:
	# Intersect the cursor ray with a horizontal plane through the current focus.
	# After changing orbit distance, shift the focus by the difference between
	# the old and new intersections. The pointed-at world location therefore
	# stays under the cursor instead of sliding toward the center of the screen.
	var focus_plane := Plane(Vector3.UP, selection_focus.y)
	var before: Variant = focus_plane.intersects_ray(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position)
	)
	var old_distance := orbit_distance_m
	orbit_distance_m = clampf(
		orbit_distance_m * distance_factor,
		minimum_orbit_distance_m,
		maximum_orbit_distance_m
	)
	if is_equal_approx(old_distance, orbit_distance_m):
		return
	aim_camera_locked = false
	_update_selection_camera()
	if before == null:
		return
	var after: Variant = focus_plane.intersects_ray(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position)
	)
	if after == null:
		return
	var focus_shift: Vector3 = (before as Vector3) - (after as Vector3)
	focus_shift.y = 0.0
	selection_focus += focus_shift
	selection_pan_offset = selection_focus - selection_auto_focus
	if selection_pan_offset.length() > maximum_pan_distance_m:
		selection_pan_offset = (
			selection_pan_offset.normalized() * maximum_pan_distance_m
		)
		selection_focus = selection_auto_focus + selection_pan_offset
	_update_selection_camera()


func _pan_selection_camera(mouse_delta: Vector2) -> void:
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var world_per_pixel := (
		2.0 * orbit_distance_m * tan(deg_to_rad(camera.fov) * 0.5) / viewport_height
	)
	var camera_right := camera.global_transform.basis.x
	var camera_up := camera.global_transform.basis.y
	var ground_right := Vector3(camera_right.x, 0.0, camera_right.z).normalized()
	var ground_up := Vector3(camera_up.x, 0.0, camera_up.z)
	if ground_up.length_squared() < 1e-6:
		ground_up = Vector3(-ground_right.z, 0.0, ground_right.x)
	else:
		ground_up = ground_up.normalized()
	selection_pan_offset += (
		-ground_right * mouse_delta.x + ground_up * mouse_delta.y
	) * world_per_pixel
	if selection_pan_offset.length() > maximum_pan_distance_m:
		selection_pan_offset = selection_pan_offset.normalized() * maximum_pan_distance_m
	selection_focus = selection_auto_focus + selection_pan_offset
	_update_selection_camera()


func _configure_trail() -> void:
	trail.mesh = trail_mesh
	phase_materials.clear()
	for color in PHASE_COLORS:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		phase_materials.append(material)
	ball_phase_material = StandardMaterial3D.new()
	ball_phase_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_phase_material.emission_enabled = true
	ball.material_override = ball_phase_material
	_set_phase_display(PHASE_DONE)


func _configure_preview_trajectories() -> void:
	preview_trajectories.mesh = preview_trajectory_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.72, 0.75, 0.78, 0.34)
	material.emission_enabled = true
	material.emission = Color(0.20, 0.21, 0.22, 1.0)
	preview_trajectories.material_override = material


func _apply_preview_trajectories(paths: Array) -> void:
	preview_trajectory_mesh.clear_surfaces()
	for path: Array in paths:
		if path.size() < 2:
			continue
		preview_trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point: Array in path:
			preview_trajectory_mesh.surface_add_vertex(
				Vector3(-point[1], point[2] + 0.10, -point[0])
			)
		preview_trajectory_mesh.surface_end()
	preview_trajectories.visible = true


func _configure_aim_line() -> void:
	aim_line.mesh = aim_line_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.0, 0.95, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.0, 0.95, 1.0, 1.0)
	aim_line.material_override = material
	_update_aim_line()


func _configure_terrain_grid() -> void:
	terrain_grid.mesh = terrain_grid_mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.08, 0.13, 0.09, 0.20)
	material.no_depth_test = false
	terrain_grid.material_override = material
	_build_terrain_grid_mesh()


func _build_terrain_grid_mesh() -> void:
	terrain_grid_mesh.clear_surfaces()
	if course_terrain.data == null:
		return
	terrain_grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var bounds: Rect2 = COURSE_CONFIGS[current_course_id]["bounds"]
	var physics_x_min := bounds.position.x
	var physics_x_max := bounds.end.x
	var physics_y_min := bounds.position.y
	var physics_y_max := bounds.end.y
	var grid_spacing_m := terrain_grid_spacing_yd * YARDS_TO_METERS
	var x := -physics_y_max
	while x <= -physics_y_min:
		_add_draped_grid_line(Vector3(x, 0.0, -physics_x_max), Vector3(x, 0.0, -physics_x_min))
		x += grid_spacing_m
	var z := -physics_x_max
	while z <= -physics_x_min:
		_add_draped_grid_line(Vector3(-physics_y_max, 0.0, z), Vector3(-physics_y_min, 0.0, z))
		z += grid_spacing_m
	terrain_grid_mesh.surface_end()


func _add_draped_grid_line(start: Vector3, end: Vector3) -> void:
	var horizontal_length := Vector2(end.x - start.x, end.z - start.z).length()
	var direction := (end - start) / horizontal_length
	var stride := terrain_grid_dash_length_m + terrain_grid_dash_gap_m
	var distance := 0.0
	while distance < horizontal_length:
		var next_distance := minf(
			distance + terrain_grid_curve_sample_m, horizontal_length
		)
		var midpoint := 0.5 * (distance + next_distance)
		if fmod(midpoint, stride) < terrain_grid_dash_length_m:
			var segment_start := start + direction * distance
			var segment_end := start + direction * next_distance
			var start_height := course_terrain.data.get_height(segment_start)
			var end_height := course_terrain.data.get_height(segment_end)
			if not is_nan(start_height) and not is_nan(end_height):
				segment_start.y = start_height + terrain_grid_surface_lift_m
				segment_end.y = end_height + terrain_grid_surface_lift_m
				terrain_grid_mesh.surface_add_vertex(segment_start)
				terrain_grid_mesh.surface_add_vertex(segment_end)
		distance = next_distance


func _update_aim_line() -> void:
	aim_line_mesh.clear_surfaces()
	if course_terrain.data == null:
		return
	var angle := deg_to_rad(aim_deg)
	var direction := Vector3(sin(angle), 0.0, -cos(angle))
	var tee_ground := Vector3(-current_ball_xy_m.y, 0.0, -current_ball_xy_m.x)
	var stride := aim_dash_length_m + aim_dash_gap_m
	aim_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var distance := 0.0
	while distance < aim_line_length_m:
		var dash_end := minf(distance + aim_dash_length_m, aim_line_length_m)
		var start := tee_ground + direction * distance
		var end := tee_ground + direction * dash_end
		var start_height := course_terrain.data.get_height(start)
		var end_height := course_terrain.data.get_height(end)
		if is_nan(start_height) or is_nan(end_height):
			break
		start.y = start_height + 0.18
		end.y = end_height + 0.18
		aim_line_mesh.surface_add_vertex(start)
		aim_line_mesh.surface_add_vertex(end)
		distance += stride
	aim_line_mesh.surface_end()


func _current_ball_position() -> Vector3:
	var position := Vector3(-current_ball_xy_m.y, 0.0, -current_ball_xy_m.x)
	var terrain_height := course_terrain.data.get_height(position)
	if is_nan(terrain_height):
		terrain_height = current_ball_height_m
	position.y = terrain_height + VISUAL_BALL_RADIUS_M
	return position


func _reset_to_aiming_view(clear_old_trajectory: bool) -> void:
	shot_playing = false
	_set_fog_playback_mode(false)
	if clear_old_trajectory:
		trajectory.clear()
		trail_mesh.clear_surfaces()
	ball.position = _current_ball_position()
	aim_line.visible = true
	preview_trajectories.visible = true
	_update_aim_line()
	_update_selection_camera()
	shoot_button.disabled = not preview_is_ready
	tactical_view_button.disabled = false
	flyover_button.disabled = not preview_is_ready
	if clear_old_trajectory:
		$Overlay/PreviewStatus.text = "Ready for next shot"


func _load_probability_fog() -> void:
	var file := FileAccess.open(FOG_FILE, FileAccess.READ)
	if file == null:
		push_error("Missing probability fog export: %s" % FOG_FILE)
		return
	var payload = JSON.parse_string(file.get_as_text())
	if not payload is Dictionary:
		push_error("Invalid probability fog JSON")
		return
	var grid: Dictionary = payload["grid"]
	var x_values: Array = grid["x_m"]
	var y_values: Array = grid["y_m"]
	var heights: Array = grid["height_m"]
	var densities: Array = grid["density"]
	# Retain the legacy mesh node for scene compatibility, but do not display
	# horizontal density sheets. FogVolume supplies the continuous body and the
	# billboard population below supplies only stylized probability bubbles.
	probability_fog.visible = false
	_build_probability_volume(x_values, y_values, heights, densities)
	_build_probability_wisps(x_values, y_values, heights, densities)
	probability_wisps.visible = probability_display_enabled
	$Overlay/Hint.text = "500-shot physics preview — one outcome animates through the probability fog"


func _build_fog_mesh(
	x_values: Array, y_values: Array, heights: Array, densities: Array
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var nx := x_values.size()
	var ny := y_values.size()
	var layer_heights := [0.35, 1.10, 2.10, 3.35]
	var layer_opacities := [1.0, 0.72, 0.46, 0.24]

	for layer in layer_heights.size():
		var vertex_offset := vertices.size()
		for i in nx:
			for j in ny:
				var density: float = densities[i][j]
				vertices.append(
					Vector3(-y_values[j], heights[i][j] + layer_heights[layer], -x_values[i])
				)
				colors.append(Color(density, 1.0, 1.0, layer_opacities[layer]))
		for i in range(nx - 1):
			for j in range(ny - 1):
				var a := vertex_offset + i * ny + j
				var b := a + ny
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_probability_volume(
	x_values: Array, y_values: Array, heights: Array, densities: Array
) -> void:
	if x_values.is_empty() or y_values.is_empty():
		probability_volume.visible = false
		return

	var nx := x_values.size()
	var ny := y_values.size()
	var terrain_min := INF
	var terrain_max := -INF
	for i in nx:
		for j in ny:
			terrain_min = minf(terrain_min, float(heights[i][j]))
			terrain_max = maxf(terrain_max, float(heights[i][j]))
	var terrain_span := maxf(terrain_max - terrain_min, 0.001)
	var span_x_m := absf(float(x_values[nx - 1]) - float(x_values[0]))
	var span_y_m := absf(float(y_values[ny - 1]) - float(y_values[0]))
	var footprint_m := maxf(Vector2(span_x_m, span_y_m).length(), 0.01)
	# Optical depth falls with the distance a camera ray travels through fog.
	# Modestly compensate compact distributions so their continuous body remains
	# legible, without allowing a tiny cloud to become an opaque solid.
	fog_footprint_density_multiplier = clampf(
		sqrt(fog_density_reference_span_m / footprint_m),
		1.0,
		fog_small_footprint_density_cap
	)

	# Texture X/Z match the FogVolume's UVW.xz. Godot X and Z are the
	# negatives of physics left and downrange, hence both reversed indices.
	var map_image := Image.create(ny, nx, false, Image.FORMAT_RGBA8)
	for i in nx:
		for j in ny:
			var density := clampf(float(densities[i][j]), 0.0, 1.0)
			var normalized_height := clampf(
				(float(heights[i][j]) - terrain_min) / terrain_span, 0.0, 1.0
			)
			map_image.set_pixel(
				ny - 1 - j, nx - 1 - i,
				Color(density, normalized_height, 0.0, 1.0)
			)

	var shader_material := ShaderMaterial.new()
	shader_material.shader = load("res://probability_volume.gdshader")
	shader_material.set_shader_parameter(
		"probability_map", ImageTexture.create_from_image(map_image)
	)
	shader_material.set_shader_parameter("terrain_min_m", terrain_min)
	shader_material.set_shader_parameter("terrain_max_m", terrain_max)
	shader_material.set_shader_parameter(
		"density_scale", FOG_PLANNING_DENSITY * fog_footprint_density_multiplier
	)
	shader_material.set_shader_parameter("emission_strength", FOG_PLANNING_EMISSION)
	shader_material.set_shader_parameter("cloud_height_m", FOG_CLOUD_HEIGHT_M)
	probability_volume.material = shader_material

	var x_min := float(x_values[0])
	var x_max := float(x_values[nx - 1])
	var y_min := float(y_values[0])
	var y_max := float(y_values[ny - 1])
	var volume_bottom := terrain_min - 0.5
	var volume_top := terrain_max + FOG_CLOUD_HEIGHT_M + 0.5
	probability_volume.position = Vector3(
		-(y_min + y_max) * 0.5,
		(volume_bottom + volume_top) * 0.5,
		-(x_min + x_max) * 0.5
	)
	probability_volume.size = Vector3(
		maxf(y_max - y_min, 0.5),
		volume_top - volume_bottom,
		maxf(x_max - x_min, 0.5)
	)
	probability_volume.visible = probability_display_enabled


func _set_fog_playback_mode(is_playback: bool) -> void:
	var fog_material := probability_volume.material as ShaderMaterial
	if fog_material != null:
		var density_multiplier := playback_fog_density_multiplier if is_playback else 1.0
		var emission_multiplier := playback_fog_emission_multiplier if is_playback else 1.0
		fog_material.set_shader_parameter(
			"density_scale",
			FOG_PLANNING_DENSITY
			* fog_footprint_density_multiplier
			* density_multiplier
		)
		fog_material.set_shader_parameter(
			"emission_strength", FOG_PLANNING_EMISSION * emission_multiplier
		)
		fog_material.set_shader_parameter(
			"cloud_height_m",
			FOG_CLOUD_HEIGHT_M * playback_fog_height_multiplier
			if is_playback
			else FOG_CLOUD_HEIGHT_M
		)
	if probability_bubble_material != null:
		probability_bubble_material.set_shader_parameter(
			"opacity_multiplier",
			playback_bubble_opacity_multiplier if is_playback else 1.0
		)
	_set_fog_dispersal(0.0)


func _set_fog_dispersal(progress: float) -> void:
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var fog_material := probability_volume.material as ShaderMaterial
	if fog_material != null:
		fog_material.set_shader_parameter("disperse_progress", clamped_progress)
	if probability_bubble_material != null:
		probability_bubble_material.set_shader_parameter(
			"disperse_progress", clamped_progress
		)


func _set_probability_display_enabled(enabled: bool) -> void:
	probability_display_enabled = enabled
	var should_show := probability_display_enabled and preview_is_ready
	probability_volume.visible = should_show
	probability_wisps.visible = should_show
	probability_fog.visible = should_show


func _build_minimap_probability_mesh(
	x_values: Array, y_values: Array, heights: Array, densities: Array
) -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var nx := x_values.size()
	var ny := y_values.size()
	for i in nx:
		for j in ny:
			var density := clampf(float(densities[i][j]), 0.0, 1.0)
			var core := pow(density, 0.58)
			var color: Color
			if core < 0.55:
				color = Color(0.55, 0.025, 1.0).lerp(
					Color(1.0, 0.16, 0.025), core / 0.55
				)
			elif core < 0.90:
				color = Color(1.0, 0.16, 0.025).lerp(
					Color(1.0, 0.42, 0.025), (core - 0.55) / 0.35
				)
			else:
				color = Color(1.0, 0.42, 0.025).lerp(
					Color(1.0, 0.78, 0.06), smoothstep(0.90, 1.0, core)
				)
			color.a = 0.92 * pow(density, 0.48)
			vertices.append(
				Vector3(-y_values[j], heights[i][j] + 1.5, -x_values[i])
			)
			colors.append(color)
	for i in range(nx - 1):
		for j in range(ny - 1):
			var a := i * ny + j
			var b := a + ny
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	probability_fog.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = load("res://minimap_probability.gdshader")
	probability_fog.material_override = material


func _build_probability_wisps(
	x_values: Array, y_values: Array, heights: Array, densities: Array
) -> void:
	var origins := PackedVector3Array()
	var sizes := PackedVector2Array()
	var fog_colors := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 240519
	var span_x_m := absf(float(x_values[x_values.size() - 1]) - float(x_values[0]))
	var span_y_m := absf(float(y_values[y_values.size() - 1]) - float(y_values[0]))
	var footprint_m := Vector2(span_x_m, span_y_m).length()
	var bubble_ramp := smoothstep(
		bubble_fade_in_span_m,
		maxf(bubble_full_effect_span_m, bubble_fade_in_span_m + 0.01),
		footprint_m
	)
	# Billboard bubbles remain legible when a distant compact FogVolume falls
	# below the renderer's froxel resolution. Keep a sparse minimum population,
	# then smoothly grow toward the full decorative effect.
	var bubble_effect := lerpf(minimum_bubble_presence, 1.0, bubble_ramp)
	# Double only the smallest cloud's population, then taper back to the normal
	# count. Size and opacity continue to use bubble_effect independently.
	var bubble_count_effect := bubble_effect * lerpf(2.0, 1.0, bubble_ramp)
	var bubble_scale := lerpf(0.28, 1.0, bubble_effect)
	var maximum_bubble_size_m := maxf(
		0.10, footprint_m * maximum_bubble_footprint_fraction
	)
	var cell_width_m := (
		absf(float(x_values[1]) - float(x_values[0]))
		if x_values.size() > 1 else span_x_m
	)
	var cell_depth_m := (
		absf(float(y_values[1]) - float(y_values[0]))
		if y_values.size() > 1 else span_y_m
	)
	# Bubble spawning used to be calibrated on 2 m × 2 m fog cells. Adaptive
	# short-shot grids can have many more cells per square meter, so partially
	# normalize the population by physical cell area instead of grid-cell count.
	var bubble_cell_density_scale := sqrt(clampf(
		cell_width_m * cell_depth_m / 4.0, 0.01, 1.0
	))
	# Do not let a highly refined tiny grid reduce the fallback billboard count
	# below a useful distant marker. This floor vanishes as the cloud approaches
	# full bubble scale, where physical cell-area normalization takes over.
	bubble_cell_density_scale = maxf(
		bubble_cell_density_scale, lerpf(0.25, 0.0, bubble_ramp)
	)

	# This is the usual real-time VFX compromise between visible particles and
	# an expensive ray-marched volume: thousands of tiny, faint mist sprites
	# overlap into a continuous translucent body, while a few larger wisps break
	# up its silhouette. Everything remains in one GPU-instanced draw call.
	for i in x_values.size():
		for j in y_values.size():
			var density: float = densities[i][j]
			if density < 0.008:
				continue
			var core := pow(density, 0.58)
			var bubble_rgb: Color
			var low_rgb := Color(0.55, 0.025, 1.0)
			var mid_rgb := Color(1.0, 0.16, 0.025)
			var warm_rgb := Color(1.0, 0.42, 0.025)
			var high_rgb := Color(1.0, 0.78, 0.06)
			if core < 0.55:
				bubble_rgb = low_rgb.lerp(mid_rgb, core / 0.55)
			elif core < 0.90:
				bubble_rgb = mid_rgb.lerp(warm_rgb, (core - 0.55) / 0.35)
			else:
				bubble_rgb = warm_rgb.lerp(
					high_rgb, smoothstep(0.90, 1.0, core)
				)
			var max_height_m := (1.5 + 5.0 * density) * bubble_scale

			# Fine mist: individually subtle, collectively fog-like. Fractional
			# stochastic counts avoid outlining the source density grid.
			var expected_count := (
				(0.10 + 1.4 * pow(density, 0.72))
				* bubble_count_effect
				* bubble_cell_density_scale
			)
			var count := floori(expected_count)
			if rng.randf() < expected_count - count:
				count += 1
			for unused in count:
				var height_m := 0.12 + pow(rng.randf(), 1.25) * max_height_m
				origins.append(
					Vector3(
						-y_values[j] + rng.randf_range(-1.9, 1.9) * bubble_scale,
						heights[i][j] + height_m,
						-x_values[i] + rng.randf_range(-1.9, 1.9) * bubble_scale
					)
				)
				var mist_size := (
					rng.randf_range(0.45, 1.0)
					* lerpf(0.85, 1.2, density)
					* bubble_scale
				)
				var mist_dimensions := Vector2(
					mist_size * rng.randf_range(0.75, 1.45), mist_size
				)
				var mist_largest_dimension := maxf(
					mist_dimensions.x, mist_dimensions.y
				)
				if mist_largest_dimension > maximum_bubble_size_m:
					mist_dimensions *= maximum_bubble_size_m / mist_largest_dimension
				sizes.append(mist_dimensions)
				fog_colors.append(
					Color(
						bubble_rgb.r,
						bubble_rgb.g,
						bubble_rgb.b,
						lerpf(0.20, 0.42, core) * lerpf(0.45, 1.0, bubble_effect)
					)
				)

			# Broad wisps provide low-frequency shape, but stay faint enough that
			# none reads as a discrete glowing ball.
			var broad_expected := (
				(0.08 + 1.1 * pow(density, 0.78))
				* bubble_count_effect
				* bubble_cell_density_scale
			)
			var broad_count := floori(broad_expected)
			if rng.randf() < broad_expected - broad_count:
				broad_count += 1
			for unused in broad_count:
				origins.append(
					Vector3(
						-y_values[j] + rng.randf_range(-2.0, 2.0) * bubble_scale,
						heights[i][j] + 0.18 + pow(rng.randf(), 1.4) * max_height_m,
						-x_values[i] + rng.randf_range(-2.0, 2.0) * bubble_scale
					)
				)
				var broad_size := (
					rng.randf_range(1.0, 2.1)
					* lerpf(0.85, 1.3, density)
					* bubble_scale
				)
				var broad_dimensions := Vector2(
					broad_size * rng.randf_range(1.15, 2.0), broad_size
				)
				var broad_largest_dimension := maxf(
					broad_dimensions.x, broad_dimensions.y
				)
				if broad_largest_dimension > maximum_bubble_size_m:
					broad_dimensions *= maximum_bubble_size_m / broad_largest_dimension
				sizes.append(broad_dimensions)
				fog_colors.append(
					Color(
						bubble_rgb.r,
						bubble_rgb.g,
						bubble_rgb.b,
						lerpf(0.14, 0.32, core) * lerpf(0.45, 1.0, bubble_effect)
					)
				)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	probability_bubble_material = ShaderMaterial.new()
	probability_bubble_material.shader = load("res://probability_bubble.gdshader")
	probability_bubble_material.set_shader_parameter(
		"bubble_texture", _make_soft_fog_texture()
	)
	probability_bubble_material.set_shader_parameter(
		"bob_amplitude_m", bubble_bob_amplitude_m
	)
	probability_bubble_material.set_shader_parameter("bob_period_s", bubble_bob_period_s)
	quad.material = probability_bubble_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = origins.size()
	for index in origins.size():
		var size_m := sizes[index]
		multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(size_m.x, size_m.y, 1.0)), origins[index]
			)
		)
		multimesh.set_instance_color(index, fog_colors[index])
	probability_wisps.multimesh = multimesh
	# Shader displacement is not included in automatic mesh bounds.
	probability_wisps.extra_cull_margin = 7.0


func _make_soft_fog_texture() -> ImageTexture:
	var texture_size := 64
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for y in texture_size:
		for x in texture_size:
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / texture_size
			var radius := (uv - Vector2(0.5, 0.5)).length() * 2.0
			var alpha := 1.0 - smoothstep(0.08, 1.0, radius)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _update_trail(last_index: int) -> void:
	trail_mesh.clear_surfaces()
	if last_index < 1:
		return
	var segment_start := 0
	while segment_start < last_index:
		var phase_code := trajectory_phases[segment_start] if segment_start < trajectory_phases.size() else PHASE_FLIGHT
		var segment_end := segment_start + 1
		while segment_end < last_index and trajectory_phases[segment_end] == phase_code:
			segment_end += 1
		trail_mesh.surface_begin(
			Mesh.PRIMITIVE_LINE_STRIP,
			phase_materials[clampi(phase_code, PHASE_FLIGHT, PHASE_DONE)]
		)
		for index in range(segment_start, segment_end + 1):
			trail_mesh.surface_add_vertex(trajectory[index])
		trail_mesh.surface_end()
		segment_start = segment_end


func _set_phase_display(phase_code: int) -> void:
	var safe_phase := clampi(phase_code, PHASE_FLIGHT, PHASE_DONE)
	var color: Color = PHASE_COLORS[safe_phase]
	if ball_phase_material != null:
		ball_phase_material.albedo_color = color
		ball_phase_material.emission = color
	phase_label.text = "Phase: %s" % PHASE_NAMES[safe_phase]
	phase_label.modulate = color
	phase_label.visible = shot_playing


func _on_place_ball_pressed() -> void:
	if shot_playing:
		return
	placing_ball = not placing_ball
	place_ball_button.button_pressed = placing_ball
	$Overlay/Hint.text = (
		"DEBUG PLACE BALL: click the terrain" if placing_ball
		else "500-shot physics preview — one outcome animates through the probability fog"
	)


func _place_ball_from_screen(screen_position: Vector2) -> void:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var world_position_variant: Variant = _intersect_terrain_heightfield(
		ray_origin, ray_direction
	)
	if world_position_variant == null:
		$Overlay/Hint.text = "No terrain under cursor — try a steeper view"
		return
	var world_position: Vector3 = world_position_variant as Vector3
	var bounds: Rect2 = COURSE_CONFIGS[current_course_id]["bounds"]
	var physics_xy := Vector2(-world_position.z, -world_position.x)
	if not bounds.has_point(physics_xy):
		$Overlay/Hint.text = "That point is outside the playable course"
		return
	current_ball_xy_m = physics_xy
	current_ball_height_m = world_position.y
	ball.position = world_position + Vector3.UP * VISUAL_BALL_RADIUS_M
	hole_complete = false
	placing_ball = false
	place_ball_button.button_pressed = false
	preview_cache.clear()
	_prepare_next_shot("Debug ball placed — choose a club and aim")


func _intersect_terrain_heightfield(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	# Terrain3D is rendered from its heightfield but this prototype does not
	# create a physics collision body. March the camera ray against the same
	# rendered height data, then bisect the first crossing for an accurate click.
	# This keeps debug placement independent of optional Terrain3D collision setup.
	var previous_t := 0.0
	var previous_gap := NAN
	var step_m := 1.0
	var max_distance_m := 2000.0
	var steps := ceili(max_distance_m / step_m)
	for step_index in range(steps + 1):
		var ray_t := step_index * step_m
		var point := ray_origin + ray_direction * ray_t
		var terrain_height := course_terrain.data.get_height(point)
		if is_nan(terrain_height):
			previous_gap = NAN
			previous_t = ray_t
			continue
		var gap := point.y - terrain_height
		if not is_nan(previous_gap) and previous_gap > 0.0 and gap <= 0.0:
			var low_t := previous_t
			var high_t := ray_t
			for _iteration in range(16):
				var middle_t := 0.5 * (low_t + high_t)
				var middle := ray_origin + ray_direction * middle_t
				var middle_height := course_terrain.data.get_height(middle)
				if is_nan(middle_height) or middle.y > middle_height:
					low_t = middle_t
				else:
					high_t = middle_t
			var hit := ray_origin + ray_direction * high_t
			hit.y = course_terrain.data.get_height(hit)
			return hit
		previous_gap = gap
		previous_t = ray_t
	return null


func _load_trajectory() -> void:
	var file := FileAccess.open(TRAJECTORY_FILE, FileAccess.READ)
	if file == null:
		push_error("Missing trajectory export: %s" % TRAJECTORY_FILE)
		return
	var payload = JSON.parse_string(file.get_as_text())
	if not payload is Dictionary:
		push_error("Invalid trajectory JSON")
		return
	sample_dt_s = payload["sample_dt_s"]
	for point: Array in payload["positions_xyz_m"]:
		# Physics: x downrange, y left, z up. Godot: X right, Y up, Z back.
		trajectory.append(
			Vector3(-point[1], point[2] + VISUAL_BALL_RADIUS_M, -point[0])
		)
	animation_time_s = 0.0
	was_pre_shot = true
