extends Node3D

const METERS_TO_YARDS := 1.0936133
const YARDS_TO_METERS := 1.0 / METERS_TO_YARDS
const VISUAL_BALL_RADIUS_M := 0.30
const TEE_XY_M := Vector2(5.0, 0.0)
const STATUS_AT_REST := 0
const STATUS_IN_WATER := 1
const STATUS_OUT_OF_BOUNDS := 2
const SURFACE_GREEN := 2
const TRAJECTORY_FILE := "res://course_data/test_hole/trajectory.json"
const FOG_FILE := "res://course_data/test_hole/probability_fog.json"

@export_category("Shot Playback")
@export_range(0.0, 5.0, 0.1) var pre_shot_pause_s := 0.0
@export_range(0.0, 5.0, 0.1) var finish_pause_s := 2.0
@export_range(0.25, 4.0, 0.25) var playback_speed := 2.0

@export_category("Shot Follow Camera")
@export var camera_offset_m := Vector3(8.0, 6.0, 18.0)
@export var camera_look_ahead_m := 15.0
@export_range(0.5, 12.0, 0.5) var camera_follow_speed := 4.0

@export_category("Selection Orbit Camera")
@export_range(-180.0, 180.0, 1.0) var default_orbit_yaw_deg := 11.0
@export_range(20.0, 75.0, 1.0) var default_orbit_elevation_deg := 25.0
@export_range(50.0, 450.0, 5.0) var default_orbit_distance_m := 280.0
@export_range(0.05, 0.5, 0.01) var orbit_mouse_sensitivity := 0.18
@export_range(1.0, 89.0, 1.0) var minimum_orbit_elevation_deg := 3.0
@export_range(45.0, 89.0, 1.0) var maximum_orbit_elevation_deg := 88.0
@export_range(20.0, 200.0, 5.0) var minimum_orbit_distance_m := 55.0
@export_range(200.0, 700.0, 10.0) var maximum_orbit_distance_m := 450.0
@export_range(100.0, 600.0, 10.0) var maximum_pan_distance_m := 380.0
@export_range(0.25, 5.0, 0.25) var camera_terrain_clearance_m := 1.25
@export_range(0.02, 1.0, 0.01) var aim_camera_drag_sensitivity_deg := 0.20
@export_range(80.0, 300.0, 5.0) var aim_camera_distance_m := 180.0
@export_category("Aim Guide")
@export_range(50.0, 450.0, 10.0) var aim_line_length_m := 320.0
@export_range(1.0, 12.0, 0.5) var aim_dash_length_m := 5.0
@export_range(1.0, 12.0, 0.5) var aim_dash_gap_m := 4.0

@export_category("Terrain Grid")
@export_range(5.0, 50.0, 1.0) var terrain_grid_spacing_yd := 20.0
@export_range(0.5, 5.0, 0.5) var terrain_grid_curve_sample_m := 1.0
@export_range(0.25, 8.0, 0.25) var terrain_grid_dash_length_m := 2.0
@export_range(0.25, 8.0, 0.25) var terrain_grid_dash_gap_m := 1.5
@export_range(0.02, 0.5, 0.01) var terrain_grid_surface_lift_m := 0.12

@onready var camera: Camera3D = $Camera
@onready var ball: MeshInstance3D = $Ball
@onready var trail: MeshInstance3D = $Trail
@onready var preview_trajectories: MeshInstance3D = $PreviewTrajectories
@onready var aim_line: MeshInstance3D = $AimLine
@onready var course_terrain: Terrain3D = $CourseTerrain
@onready var terrain_grid: MeshInstance3D = $TerrainGrid
@onready var probability_fog: MeshInstance3D = $ProbabilityFog
@onready var probability_wisps: MultiMeshInstance3D = $ProbabilityWisps
@onready var aim_label: Label = $Overlay/AimLabel
@onready var club_selector: OptionButton = $Overlay/ClubSelector
@onready var shoot_button: Button = $Overlay/ShootButton
@onready var preview_timer: Timer = $PreviewDebounce
@onready var physics_client: PhysicsClient = $PhysicsClient
@onready var top_down_button: Button = $Overlay/TopDownButton
@onready var reset_view_button: Button = $Overlay/ResetViewButton
@onready var reset_hole_button: Button = $Overlay/ResetHoleButton
@onready var stroke_label: Label = $Overlay/StrokeLabel
@onready var water_relief_panel: Panel = $Overlay/WaterReliefPanel
@onready var drop_button: Button = $Overlay/WaterReliefPanel/DropButton
@onready var replay_button: Button = $Overlay/WaterReliefPanel/ReplayButton

var trajectory: Array[Vector3] = []
var sample_dt_s := 0.02
var animation_time_s := 0.0
var trail_mesh := ImmediateMesh.new()
var preview_trajectory_mesh := ImmediateMesh.new()
var aim_line_mesh := ImmediateMesh.new()
var terrain_grid_mesh := ImmediateMesh.new()
var was_pre_shot := true
var latest_preview_request_id := -1
var latest_shot_request_id := -1
var shot_counter := 0
var shot_playing := false
var worker_is_ready := false
var preview_is_ready := false
var preview_cache: Dictionary = {}
var preview_request_keys: Dictionary = {}
var selection_auto_focus := Vector3(0.0, 1.0, -210.0)
var selection_pan_offset := Vector3.ZERO
var selection_focus := Vector3(0.0, 1.0, -210.0)
var orbit_yaw_rad := 0.0
var orbit_elevation_rad := 0.0
var orbit_distance_m := 280.0
var orbit_dragging := false
var pan_dragging := false
var aim_dragging := false
var aim_camera_locked := false
var aim_deg := 0.0
var shot_camera_forward := Vector3(0.0, 0.0, -1.0)
var current_ball_xy_m := TEE_XY_M
var current_ball_height_m := 0.0
var pending_rest_xy_m := TEE_XY_M
var pending_relief_xy_m := TEE_XY_M
var pending_shot_origin_xy_m := TEE_XY_M
var pending_status := STATUS_AT_REST
var pending_surface := 0
var stroke_count := 0
var penalty_count := 0
var hole_complete := false
var awaiting_water_relief := false


func _ready() -> void:
	$Overlay/Units.text = "Course length: %.0f yd   |   simulation units: meters" % (420.0 * METERS_TO_YARDS)
	_configure_trail()
	_configure_preview_trajectories()
	_configure_aim_line()
	_configure_terrain_grid()
	_reset_orbit_parameters()
	_reset_to_aiming_view(false)
	_configure_club_selector()
	club_selector.item_selected.connect(_on_club_changed)
	preview_timer.timeout.connect(_request_live_preview)
	shoot_button.pressed.connect(_request_live_shot)
	physics_client.worker_ready.connect(_on_worker_ready)
	physics_client.preview_received.connect(_on_preview_received)
	physics_client.shot_received.connect(_on_shot_received)
	physics_client.worker_error.connect(_on_worker_error)
	top_down_button.pressed.connect(_on_top_down_pressed)
	reset_view_button.pressed.connect(_on_reset_view_pressed)
	reset_hole_button.pressed.connect(_on_reset_hole_pressed)
	drop_button.pressed.connect(_on_water_drop_pressed)
	replay_button.pressed.connect(_on_water_replay_pressed)
	shoot_button.disabled = true
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
		club_selector.add_item(club[0])
		club_selector.set_item_metadata(club_selector.item_count - 1, club[1])
	club_selector.select(0)


func _on_club_changed(_index: int) -> void:
	# Club changes invalidate the same preview state as aim changes. Reusing
	# this path also gives cached club/aim combinations immediate display.
	_on_aim_changed(aim_deg)


func _on_aim_changed(value: float) -> void:
	# Keep the guide continuous. Physics requests quantize separately so nearby
	# cursor positions can still reuse cached previews.
	aim_deg = wrapf(value, -180.0, 180.0)
	aim_label.text = "Aim: %+.1f°   (left-drag to turn)" % aim_deg
	if hole_complete or awaiting_water_relief:
		return
	shot_playing = false
	trajectory.clear()
	trail_mesh.clear_surfaces()
	preview_is_ready = false
	_reset_to_aiming_view(false)
	shoot_button.disabled = true
	if worker_is_ready:
		var cache_key := _preview_cache_key()
		if preview_cache.has(cache_key):
			latest_preview_request_id = -1
			_apply_preview_payload(preview_cache[cache_key], true)
		else:
			preview_timer.start()


func _physics_settings() -> Dictionary:
	return {
		"aim_deg": snappedf(aim_deg, 0.25),
		"club": club_selector.get_item_metadata(club_selector.selected),
		"shot_type": "stock",
		"start_xy_m": [current_ball_xy_m.x, current_ball_xy_m.y],
		"modifiers": {},
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
	$Overlay/PreviewStatus.text = "Cached preview" if from_cache else "Preview ready"
	preview_is_ready = true
	shoot_button.disabled = false


func _apply_fog_grid(grid: Dictionary) -> void:
	var x_values: Array = grid["x_m"]
	var y_values: Array = grid["y_m"]
	var heights: Array = grid["height_m"]
	var densities: Array = grid["density"]
	_update_selection_focus(x_values, y_values, heights, densities)
	probability_fog.mesh = _build_fog_mesh(x_values, y_values, heights, densities)
	probability_fog.visible = true
	if probability_fog.material_override == null:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = load("res://probability_fog.gdshader")
		probability_fog.material_override = shader_material
	_build_probability_wisps(x_values, y_values, heights, densities)
	probability_wisps.visible = true
	if aim_line.visible and not shot_playing:
		_update_selection_camera()


func _request_live_shot() -> void:
	shoot_button.disabled = true
	top_down_button.disabled = true
	reset_view_button.disabled = true
	aim_line.visible = false
	preview_trajectories.visible = false
	club_selector.disabled = true
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
	trajectory.clear()
	sample_dt_s = payload["sample_dt_s"]
	for point: Array in payload["positions_xyz_m"]:
		trajectory.append(Vector3(-point[1], point[2] + VISUAL_BALL_RADIUS_M, -point[0]))
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
	shot_playing = true
	trail_mesh.clear_surfaces()
	ball.position = trajectory[0]
	_place_camera_immediately()
	$Overlay/PreviewStatus.text = "Independent shot %d" % shot_counter


func _on_worker_error(message: String) -> void:
	$Overlay/PreviewStatus.text = "Physics error: " + message
	push_error(message)


func _process(delta: float) -> void:
	if not shot_playing or trajectory.size() < 2:
		return
	animation_time_s += delta
	var duration := (trajectory.size() - 1) * sample_dt_s
	var shot_time := (animation_time_s - pre_shot_pause_s) * playback_speed
	var is_pre_shot := shot_time < 0.0
	var sample_position := clampf(shot_time / sample_dt_s, 0.0, trajectory.size() - 1)
	var index := mini(floori(sample_position), trajectory.size() - 2)
	var fraction := sample_position - index
	ball.position = trajectory[index].lerp(trajectory[index + 1], fraction)
	_update_trail(index)

	# A damped chase camera gives the ball room to travel into the frame.
	if is_pre_shot and not was_pre_shot:
		# Treat each replay like a broadcast cut back to the tee.
		_place_camera_immediately()
	var desired_position := ball.position + _shot_camera_world_offset()
	var camera_blend := 1.0 - exp(-camera_follow_speed * delta)
	camera.position = camera.position.lerp(desired_position, camera_blend)
	camera.look_at(
		ball.position + Vector3.UP * 1.5 + shot_camera_forward * camera_look_ahead_m,
		Vector3.UP
	)
	was_pre_shot = is_pre_shot
	if animation_time_s >= pre_shot_pause_s + duration / playback_speed + finish_pause_s:
		_finish_shot()


func _finish_shot() -> void:
	shot_playing = false
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
		$Overlay/PreviewStatus.text = "Green reached - score %d" % (stroke_count + penalty_count)
		$Overlay/Hint.text = "Hole complete - press RESET HOLE to play again"
		return
	_prepare_next_shot("Stroke %d - choose the next shot" % (stroke_count + 1))


func _show_water_relief_choices() -> void:
	awaiting_water_relief = true
	shoot_button.disabled = true
	club_selector.disabled = true
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
	awaiting_water_relief = false
	water_relief_panel.visible = false
	preview_is_ready = false
	probability_fog.visible = false
	probability_wisps.visible = false
	preview_trajectory_mesh.clear_surfaces()
	club_selector.disabled = false
	_on_aim_changed(aim_deg)
	$Overlay/Hint.text = message


func _update_score_label() -> void:
	stroke_label.text = "Shots: %d   Penalties: %d   Score: %d" % [
		stroke_count, penalty_count, stroke_count + penalty_count
	]


func _on_reset_hole_pressed() -> void:
	shot_playing = false
	latest_shot_request_id = -1
	hole_complete = false
	awaiting_water_relief = false
	water_relief_panel.visible = false
	stroke_count = 0
	penalty_count = 0
	_update_score_label()
	current_ball_xy_m = TEE_XY_M
	current_ball_height_m = 0.0
	aim_deg = 0.0
	pending_rest_xy_m = TEE_XY_M
	pending_relief_xy_m = TEE_XY_M
	pending_shot_origin_xy_m = TEE_XY_M
	preview_is_ready = false
	trajectory.clear()
	trail_mesh.clear_surfaces()
	probability_fog.visible = false
	probability_wisps.visible = false
	preview_trajectory_mesh.clear_surfaces()
	club_selector.disabled = false
	_reset_orbit_parameters()
	_on_aim_changed(aim_deg)
	$Overlay/Hint.text = "New hole — choose a club and aim"


func _place_camera_immediately() -> void:
	camera.position = ball.position + _shot_camera_world_offset()
	camera.look_at(
		ball.position + Vector3.UP * 1.5 + shot_camera_forward * camera_look_ahead_m,
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
	var total := 0.0
	var weighted_x := 0.0
	var weighted_y := 0.0
	var weighted_height := 0.0
	for i in x_values.size():
		for j in y_values.size():
			var weight: float = densities[i][j]
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
		if aim_camera_locked:
			_set_aim_aligned_focus()
		else:
			selection_focus = selection_auto_focus + selection_pan_offset


func _reset_orbit_parameters() -> void:
	aim_camera_locked = false
	orbit_yaw_rad = deg_to_rad(default_orbit_yaw_deg)
	orbit_elevation_rad = deg_to_rad(default_orbit_elevation_deg)
	orbit_distance_m = default_orbit_distance_m
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


func _set_aim_aligned_focus() -> void:
	var ball_ground := _current_ball_position() - Vector3(0.0, VISUAL_BALL_RADIUS_M, 0.0)
	var aim_direction := Vector3(sin(deg_to_rad(aim_deg)), 0.0, -cos(deg_to_rad(aim_deg)))
	var fog_distance := Vector2(
		selection_auto_focus.x - ball_ground.x,
		selection_auto_focus.z - ball_ground.z
	).length()
	# Focus partway into the shot while keeping the camera itself behind the
	# ball. This frames both the launch and the outcome cloud.
	var focus_distance := clampf(fog_distance * 0.5, 50.0, 130.0)
	var horizontal_camera_distance := orbit_distance_m * cos(orbit_elevation_rad)
	focus_distance = minf(focus_distance, maxf(horizontal_camera_distance - 10.0, 10.0))
	selection_focus = ball_ground + aim_direction * focus_distance
	var terrain_height := course_terrain.data.get_height(selection_focus)
	if not is_nan(terrain_height):
		selection_focus.y = terrain_height + 2.0


func _align_camera_behind_aim(reset_pitch_and_zoom: bool) -> void:
	aim_camera_locked = true
	selection_pan_offset = Vector3.ZERO
	orbit_yaw_rad = -deg_to_rad(aim_deg)
	if reset_pitch_and_zoom:
		orbit_elevation_rad = deg_to_rad(default_orbit_elevation_deg)
		orbit_distance_m = aim_camera_distance_m
	_set_aim_aligned_focus()
	_update_selection_camera()


func _on_top_down_pressed() -> void:
	if shot_playing or not aim_line.visible:
		return
	aim_camera_locked = false
	orbit_elevation_rad = deg_to_rad(maximum_orbit_elevation_deg)
	_update_selection_camera()


func _on_reset_view_pressed() -> void:
	if shot_playing or not aim_line.visible:
		return
	aim_camera_locked = false
	_reset_orbit_parameters()
	_update_selection_camera()


func _unhandled_input(event: InputEvent) -> void:
	if shot_playing or not aim_line.visible:
		orbit_dragging = false
		pan_dragging = false
		aim_dragging = false
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbit_dragging = event.pressed
			if event.pressed:
				aim_camera_locked = false
				pan_dragging = false
				aim_dragging = false
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			aim_dragging = event.pressed
			if event.pressed:
				orbit_dragging = false
				pan_dragging = false
				_align_camera_behind_aim(true)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			pan_dragging = event.pressed
			if event.pressed:
				aim_camera_locked = false
				orbit_dragging = false
				aim_dragging = false
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_cursor(event.position, 0.88)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_cursor(event.position, 1.0 / 0.88)
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
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.9, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.15, 0.9, 1.0, 1.0)
	trail.material_override = material


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
	# Current prototype course bounds in Godot coordinates: X is right/left and
	# negative Z is downrange. These can move into course metadata when holes
	# stop being hard-coded.
	var grid_spacing_m := terrain_grid_spacing_yd * YARDS_TO_METERS
	var x := -60.0
	while x <= 60.0:
		_add_draped_grid_line(Vector3(x, 0.0, -420.0), Vector3(x, 0.0, 0.0))
		x += grid_spacing_m
	var z := -420.0
	while z <= 0.0:
		_add_draped_grid_line(Vector3(-60.0, 0.0, z), Vector3(60.0, 0.0, z))
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
	if clear_old_trajectory:
		trajectory.clear()
		trail_mesh.clear_surfaces()
	ball.position = _current_ball_position()
	aim_line.visible = true
	preview_trajectories.visible = true
	_update_aim_line()
	_update_selection_camera()
	shoot_button.disabled = not preview_is_ready
	top_down_button.disabled = false
	reset_view_button.disabled = false
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
	probability_fog.mesh = _build_fog_mesh(x_values, y_values, heights, densities)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = load("res://probability_fog.gdshader")
	probability_fog.material_override = shader_material
	_build_probability_wisps(x_values, y_values, heights, densities)
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


func _build_probability_wisps(
	x_values: Array, y_values: Array, heights: Array, densities: Array
) -> void:
	var origins := PackedVector3Array()
	var sizes := PackedFloat32Array()
	var fog_colors := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 240519

	# Random placement hides the source grid. Dense cells emit more and taller
	# wisps, so the vertical silhouette still communicates probability.
	for i in x_values.size():
		for j in y_values.size():
			var density: float = densities[i][j]
			if density < 0.025:
				continue
			var count := 1 + floori(3.0 * sqrt(density))
			for unused in count:
				var height_m := rng.randf_range(0.7, 2.2 + 4.8 * density)
				origins.append(
					Vector3(
						-y_values[j] + rng.randf_range(-1.4, 1.4),
						heights[i][j] + height_m,
						-x_values[i] + rng.randf_range(-1.4, 1.4)
					)
				)
				sizes.append(rng.randf_range(2.8, 5.2) * lerpf(0.8, 1.45, density))
				var core := pow(density, 0.58)
				var color := Color(0.08, 0.01, 0.28, 0.10).lerp(
					Color(1.0, 0.30, 0.02, 0.27), core
				)
				fog_colors.append(color)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _make_soft_fog_texture()
	quad.material = material

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
				Basis.IDENTITY.scaled(Vector3(size_m, size_m, size_m)), origins[index]
			)
		)
		multimesh.set_instance_color(index, fog_colors[index])
	probability_wisps.multimesh = multimesh


func _make_soft_fog_texture() -> ImageTexture:
	var texture_size := 64
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for y in texture_size:
		for x in texture_size:
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / texture_size
			var radius := (uv - Vector2(0.5, 0.5)).length() * 2.0
			var alpha := smoothstep(1.0, 0.08, radius)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _update_trail(last_index: int) -> void:
	trail_mesh.clear_surfaces()
	if last_index < 1:
		return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(last_index + 1):
		trail_mesh.surface_add_vertex(trajectory[index])
	trail_mesh.surface_end()


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
