extends Node3D

const METERS_TO_YARDS := 1.0936133
const VISUAL_BALL_RADIUS_M := 0.30
const TRAJECTORY_FILE := "res://course_data/test_hole/trajectory.json"
const FOG_FILE := "res://course_data/test_hole/probability_fog.json"

@export_category("Shot Playback")
@export_range(0.0, 5.0, 0.1) var pre_shot_pause_s := 0.0
@export_range(0.0, 5.0, 0.1) var finish_pause_s := 2.0

@export_category("Shot Follow Camera")
@export var camera_offset_m := Vector3(8.0, 6.0, 18.0)
@export var camera_look_ahead_m := 15.0
@export_range(0.5, 12.0, 0.5) var camera_follow_speed := 4.0

@export_category("Aim Selection Camera")
@export_range(10.0, 150.0, 5.0) var aim_camera_height_m := 90.0
@export_range(0.0, 120.0, 5.0) var aim_camera_behind_m := 55.0
@export_range(-120.0, 120.0, 5.0) var aim_camera_side_m := 50.0
@export_range(50.0, 350.0, 10.0) var aim_camera_focus_distance_m := 210.0

@export_category("Aim Guide")
@export_range(50.0, 450.0, 10.0) var aim_line_length_m := 320.0
@export_range(1.0, 12.0, 0.5) var aim_dash_length_m := 5.0
@export_range(1.0, 12.0, 0.5) var aim_dash_gap_m := 4.0

@onready var camera: Camera3D = $Camera
@onready var ball: MeshInstance3D = $Ball
@onready var trail: MeshInstance3D = $Trail
@onready var aim_line: MeshInstance3D = $AimLine
@onready var course_terrain: Terrain3D = $CourseTerrain
@onready var probability_fog: MeshInstance3D = $ProbabilityFog
@onready var probability_wisps: MultiMeshInstance3D = $ProbabilityWisps
@onready var aim_slider: HSlider = $Overlay/AimSlider
@onready var aim_label: Label = $Overlay/AimLabel
@onready var club_selector: OptionButton = $Overlay/ClubSelector
@onready var shoot_button: Button = $Overlay/ShootButton
@onready var preview_timer: Timer = $PreviewDebounce
@onready var physics_client: PhysicsClient = $PhysicsClient

var trajectory: Array[Vector3] = []
var sample_dt_s := 0.02
var animation_time_s := 0.0
var trail_mesh := ImmediateMesh.new()
var aim_line_mesh := ImmediateMesh.new()
var was_pre_shot := true
var latest_preview_request_id := -1
var shot_counter := 0
var shot_playing := false
var worker_is_ready := false
var preview_is_ready := false
var preview_cache: Dictionary = {}
var preview_request_keys: Dictionary = {}


func _ready() -> void:
	$Overlay/Units.text = "Course length: %.0f yd   |   simulation units: meters" % (420.0 * METERS_TO_YARDS)
	_configure_trail()
	_configure_aim_line()
	_reset_to_aiming_view(false)
	_configure_club_selector()
	aim_slider.value_changed.connect(_on_aim_changed)
	club_selector.item_selected.connect(_on_club_changed)
	preview_timer.timeout.connect(_request_live_preview)
	shoot_button.pressed.connect(_request_live_shot)
	physics_client.worker_ready.connect(_on_worker_ready)
	physics_client.preview_received.connect(_on_preview_received)
	physics_client.shot_received.connect(_on_shot_received)
	physics_client.worker_error.connect(_on_worker_error)
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
	_on_aim_changed(aim_slider.value)


func _on_aim_changed(value: float) -> void:
	aim_label.text = "Aim: %+.1f°   (left − / right +)" % value
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
		"aim_deg": aim_slider.value,
		"club": club_selector.get_item_metadata(club_selector.selected),
		"shot_type": "stock",
		"modifiers": {},
		"environment": {},
	}


func _preview_cache_key() -> String:
	# Include everything that changes the preview. This same boundary can later
	# include clubs, item modifiers, wind, and the preview context identifier.
	return JSON.stringify(
		{
			"preview_seed": 24681357,
			"sample_count": 500,
			"settings": _physics_settings(),
		}
	)


func _on_worker_ready() -> void:
	worker_is_ready = true
	$Overlay/Hint.text = "Live Python worker ready — adjust aim, then press Shoot"
	_request_live_preview()


func _request_live_preview() -> void:
	if not worker_is_ready:
		return
	var cache_key := _preview_cache_key()
	latest_preview_request_id = physics_client.request_preview(_physics_settings(), 24681357, 500)
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
	$Overlay/PreviewStatus.text = "Cached preview" if from_cache else "Preview ready"
	preview_is_ready = true
	shoot_button.disabled = false


func _apply_fog_grid(grid: Dictionary) -> void:
	var x_values: Array = grid["x_m"]
	var y_values: Array = grid["y_m"]
	var heights: Array = grid["height_m"]
	var densities: Array = grid["density"]
	probability_fog.mesh = _build_fog_mesh(x_values, y_values, heights, densities)
	if probability_fog.material_override == null:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = load("res://probability_fog.gdshader")
		probability_fog.material_override = shader_material
	_build_probability_wisps(x_values, y_values, heights, densities)


func _request_live_shot() -> void:
	shoot_button.disabled = true
	aim_line.visible = false
	shot_counter += 1
	physics_client.request_shot(_physics_settings(), 97531000 + shot_counter)
	$Overlay/PreviewStatus.text = "Calculating independent shot…"


func _on_shot_received(response: Dictionary) -> void:
	var payload: Dictionary = response["payload"]
	trajectory.clear()
	sample_dt_s = payload["sample_dt_s"]
	for point: Array in payload["positions_xyz_m"]:
		trajectory.append(Vector3(-point[1], point[2] + VISUAL_BALL_RADIUS_M, -point[0]))
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
	var shot_time := animation_time_s - pre_shot_pause_s
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
	var desired_position := ball.position + camera_offset_m
	var camera_blend := 1.0 - exp(-camera_follow_speed * delta)
	camera.position = camera.position.lerp(desired_position, camera_blend)
	camera.look_at(
		ball.position + Vector3(0.0, 1.5, -camera_look_ahead_m), Vector3.UP
	)
	was_pre_shot = is_pre_shot
	if shot_time >= duration + finish_pause_s:
		_reset_to_aiming_view(true)


func _place_camera_immediately() -> void:
	camera.position = ball.position + camera_offset_m
	camera.look_at(
		ball.position + Vector3(0.0, 1.5, -camera_look_ahead_m), Vector3.UP
	)


func _place_aim_camera_immediately() -> void:
	var angle := deg_to_rad(aim_slider.value)
	var downrange := Vector3(sin(angle), 0.0, -cos(angle))
	var right := Vector3(cos(angle), 0.0, sin(angle))
	var tee := _tee_ball_position()
	camera.position = (
		tee
		- downrange * aim_camera_behind_m
		+ right * aim_camera_side_m
		+ Vector3.UP * aim_camera_height_m
	)
	camera.look_at(tee + downrange * aim_camera_focus_distance_m, Vector3.UP)


func _configure_trail() -> void:
	trail.mesh = trail_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.9, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.15, 0.9, 1.0, 1.0)
	trail.material_override = material


func _configure_aim_line() -> void:
	aim_line.mesh = aim_line_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.0, 0.95, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.0, 0.95, 1.0, 1.0)
	aim_line.material_override = material
	_update_aim_line()


func _update_aim_line() -> void:
	aim_line_mesh.clear_surfaces()
	if course_terrain.data == null:
		return
	var angle := deg_to_rad(aim_slider.value)
	var direction := Vector3(sin(angle), 0.0, -cos(angle))
	var tee_ground := Vector3(0.0, 0.0, -5.0)
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


func _tee_ball_position() -> Vector3:
	var tee := Vector3(0.0, 0.0, -5.0)
	tee.y = course_terrain.data.get_height(tee) + VISUAL_BALL_RADIUS_M
	return tee


func _reset_to_aiming_view(clear_old_trajectory: bool) -> void:
	shot_playing = false
	if clear_old_trajectory:
		trajectory.clear()
		trail_mesh.clear_surfaces()
	ball.position = _tee_ball_position()
	aim_line.visible = true
	_update_aim_line()
	_place_aim_camera_immediately()
	shoot_button.disabled = not preview_is_ready
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
