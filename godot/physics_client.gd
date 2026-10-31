class_name PhysicsClient
extends Node

signal worker_ready
signal preview_received(response: Dictionary)
signal shot_received(response: Dictionary)
signal worker_error(message: String)

const PROTOCOL_VERSION := 1

var _stdio: FileAccess
var _stderr: FileAccess
var _pid := -1
var _next_request_id := 1


func start() -> void:
	var python_path := ProjectSettings.globalize_path("res://../.venv/Scripts/python.exe")
	var worker_path := ProjectSettings.globalize_path("res://../physics_worker.py")
	var process := OS.execute_with_pipe(python_path, PackedStringArray(["-u", worker_path]), false)
	if process.is_empty():
		worker_error.emit("Could not start Python physics worker")
		return
	_stdio = process["stdio"]
	_stderr = process["stderr"]
	_pid = process["pid"]
	set_process(true)


func request_preview(settings: Dictionary, preview_seed: int, sample_count: int) -> int:
	return _send_request("preview", settings, {"preview_seed": preview_seed, "sample_count": sample_count})


func request_shot(settings: Dictionary, shot_seed: int) -> int:
	return _send_request("shoot", settings, {"shot_seed": shot_seed})


func _send_request(type: String, settings: Dictionary, extra: Dictionary) -> int:
	if _stdio == null:
		return -1
	var request_id := _next_request_id
	_next_request_id += 1
	var message := {
		"protocol_version": PROTOCOL_VERSION,
		"type": type,
		"request_id": request_id,
		"settings": settings,
	}
	message.merge(extra)
	_stdio.store_string(JSON.stringify(message) + "\n")
	_stdio.flush()
	return request_id


func _process(_delta: float) -> void:
	if _stdio == null:
		return
	# Non-blocking pipe reads return an empty string when no complete line is
	# available. Worker protocol messages are always one non-empty JSON line.
	for unused in 8:
		var line := _stdio.get_line()
		if line.is_empty():
			break
		_handle_line(line)
	if _stderr != null:
		var diagnostic := _stderr.get_line()
		if not diagnostic.is_empty():
			push_warning("Physics worker: " + diagnostic)


func _handle_line(line: String) -> void:
	var message = JSON.parse_string(line)
	if not message is Dictionary:
		worker_error.emit("Invalid response from physics worker")
		return
	match message.get("type", ""):
		"ready":
			if message.get("protocol_version") == PROTOCOL_VERSION:
				worker_ready.emit()
			else:
				worker_error.emit("Physics worker protocol mismatch")
		"preview":
			preview_received.emit(message)
		"shoot":
			shot_received.emit(message)
		"error":
			worker_error.emit(message.get("message", "Unknown physics error"))


func shutdown() -> void:
	if _stdio != null:
		_stdio.store_string(JSON.stringify({"type": "shutdown"}) + "\n")
		_stdio.flush()
		_stdio = null
		_stderr = null
	if _pid > 0 and OS.is_process_running(_pid):
		# execute_with_pipe children outlive Godot by default. Force termination
		# after closing the protocol pipe so an abnormal worker cannot be orphaned.
		OS.kill(_pid)
	_pid = -1


func _exit_tree() -> void:
	shutdown()
