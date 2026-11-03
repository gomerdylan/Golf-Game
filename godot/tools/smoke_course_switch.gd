extends SceneTree

## Headless regression check for Terrain3D hole switching.
## Run from the repository root with:
## godot --headless --path .\godot --script res://tools/smoke_course_switch.gd


func _initialize() -> void:
	var scene := load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	scene._on_course_button_pressed("water_carry")
	await process_frame
	assert(scene.current_course_id == "water_carry")
	assert(scene.course_terrain == scene.water_carry_terrain)
	assert(scene.course_terrain.get_parent() == scene)
	assert(scene.test_hole_terrain.get_parent() == null)

	scene._on_course_button_pressed("test_hole")
	await process_frame
	assert(scene.current_course_id == "test_hole")
	assert(scene.course_terrain == scene.test_hole_terrain)
	assert(scene.course_terrain.get_parent() == scene)
	assert(scene.water_carry_terrain.get_parent() == null)

	print("Course switch smoke test passed: test_hole -> water_carry -> test_hole")
	quit()
