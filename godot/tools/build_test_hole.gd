extends SceneTree

## One-shot conversion from Python's compact course export to Terrain3D regions.
## Run from godot/: godot --headless --path . --script res://tools/build_test_hole.gd

const COURSE_IDS := ["test_hole", "water_carry"]
const REGION_SIZE := 256


func _initialize() -> void:
	for course_id: String in COURSE_IDS:
		var succeeded := await _build_course(course_id)
		if not succeeded:
			quit(1)
			return
	quit()


func _build_course(course_id: String) -> bool:
	var source_dir := "res://course_data/%s" % course_id
	var terrain_dir := "res://terrain_data/%s" % course_id
	var metadata := _read_json(source_dir + "/course.json")
	if metadata.is_empty():
		return false

	var terrain := Terrain3D.new()
	var spacing: float = metadata["spacing_m"]
	terrain.vertex_spacing = spacing
	root.add_child(terrain)
	# Terrain3D creates its owned data resource after entering the scene tree.
	await process_frame
	var data: Terrain3DData = terrain.data
	if data == null:
		push_error("Terrain3D did not initialize its data resource")
		return false
	var nx: int = metadata["nx"]
	var ny: int = metadata["ny"]
	var x0: float = metadata["x0_m"]
	var y0: float = metadata["y0_m"]
	var heights := FileAccess.open(source_dir + "/height_f32.bin", FileAccess.READ)
	var surfaces := FileAccess.open(source_dir + "/surface_u8.bin", FileAccess.READ)
	if heights == null or surfaces == null:
		push_error("Could not open exported course arrays")
		return false
	heights.big_endian = false

	# Terrain3D stores square regions. Add only the regions touched by this hole.
	var region_locations := {}
	for i in nx:
		var physics_x := x0 + i * spacing
		for j in ny:
			var physics_y := y0 + j * spacing
			var world_x := -physics_y
			var world_z := -physics_x
			var region_world_size := REGION_SIZE * spacing
			region_locations[Vector2i(floori(world_x / region_world_size), floori(world_z / region_world_size))] = true
	for location: Vector2i in region_locations:
		data.add_region_blank(location)

	var palette: Array[Color] = []
	for surface: Dictionary in metadata["surfaces"]:
		var rgb: Array = surface["rgb"]
		var srgb_color := Color(rgb[0], rgb[1], rgb[2], 1.0)
		# The 3D lighting makes these correctly converted colors darker than the
		# flat Streamlit swatches. Small display-only lifts keep probability fog
		# readable while preserving the shared palette's relationships.
		if surface["name"] == "rough":
			srgb_color = srgb_color.lerp(Color.WHITE, 0.30)
		elif surface["name"] == "fairway" or surface["name"] == "tee":
			srgb_color = srgb_color.lerp(Color.WHITE, 0.30)
		elif surface["name"] == "green":
			srgb_color = srgb_color.lerp(Color.WHITE, 0.20)
		elif surface["name"] == "water":
			srgb_color = srgb_color.lerp(Color.WHITE, 0.20)
		# Python/Matplotlib hex colors are authored in sRGB, while Terrain3D's
		# vertex colormap expects linear values. Treating the sRGB channels as
		# linear made every surface substantially brighter in the game.
		palette.append(srgb_color.srgb_to_linear())

	for i in nx:
		var physics_x := x0 + i * spacing
		for j in ny:
			var physics_y := y0 + j * spacing
			var height := heights.get_float()
			var surface_id := surfaces.get_8()
			var position := Vector3(-physics_y, height, -physics_x)
			data.set_height(position, height)
			data.set_color(position, palette[surface_id])

	data.update_maps()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(terrain_dir))
	data.save_directory(terrain_dir)
	print("Built %d Terrain3D regions in %s (Godot units = meters)" % [region_locations.size(), terrain_dir])
	terrain.queue_free()
	await process_frame
	return true


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Invalid JSON in %s" % path)
		return {}
	return parsed
