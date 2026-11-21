class_name ShotPowerRail
extends Control

signal value_changed(value: float)

const MAX_POWER := 120.0
const CHIP_MAX := 40.0
const SMOOTH_POWER := 80.0
const STOCK_POWER := 100.0
const FULL_POWER := 120.0

const LOCKED_COLOR := Color(0.22, 0.24, 0.27, 0.92)
const CHIP_COLOR := Color(0.24, 0.72, 0.50, 0.95)
const SMOOTH_COLOR := Color(0.25, 0.72, 1.0, 1.0)
const STOCK_COLOR := Color(0.95, 0.78, 0.27, 1.0)
const FULL_COLOR := Color(1.0, 0.34, 0.10, 1.0)
const FUTURE_TICK_COLOR := Color(0.58, 0.60, 0.64, 0.85)
const POINTER_COLOR := Color(0.95, 0.20, 0.18, 1.0)
const POINTER_OUTLINE := Color(0.35, 0.04, 0.03, 1.0)

var value := 100.0
var smooth_unlocked := true
var stock_unlocked := true
var full_unlocked := true
var editable := true:
	set(next_value):
		editable = next_value
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if editable else Control.CURSOR_FORBIDDEN
		)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	queue_redraw()


func set_value_no_signal(next_value: float) -> void:
	value = clampf(roundf(next_value), 0.0, MAX_POWER)
	queue_redraw()


func set_action_unlocks(smooth: bool, stock: bool, full: bool) -> void:
	smooth_unlocked = smooth
	stock_unlocked = stock
	full_unlocked = full
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			accept_event()
			_set_value_from_x(mouse_button.position.x)
	elif event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			accept_event()
			_set_value_from_x(mouse_motion.position.x)
	elif event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_LEFT:
			accept_event()
			if value > STOCK_POWER:
				_set_value(STOCK_POWER)
			elif value > SMOOTH_POWER:
				_set_value(SMOOTH_POWER)
			elif value > CHIP_MAX:
				_set_value(CHIP_MAX)
			else:
				_set_value(value - 1.0)
		elif key_event.keycode == KEY_RIGHT:
			accept_event()
			if value < CHIP_MAX:
				_set_value(value + 1.0)
			elif value < SMOOTH_POWER:
				_set_value(SMOOTH_POWER)
			elif value < STOCK_POWER:
				_set_value(STOCK_POWER)
			elif value < FULL_POWER:
				_set_value(FULL_POWER)


func _set_value_from_x(local_x: float) -> void:
	_set_value(
		clampf((local_x - 7.0) / maxf(size.x - 14.0, 1.0), 0.0, 1.0)
		* MAX_POWER
	)


func _set_value(next_value: float) -> void:
	var rounded_value := clampf(roundf(next_value), 0.0, MAX_POWER)
	if is_equal_approx(rounded_value, value):
		return
	value = rounded_value
	queue_redraw()
	value_changed.emit(value)


func _draw() -> void:
	var bar_y := size.y - 9.0
	var rail_left := 7.0
	var rail_width := maxf(size.x - 14.0, 1.0)
	var bar_rect := Rect2(rail_left, bar_y, rail_width, 6.0)
	draw_rect(bar_rect, LOCKED_COLOR)
	draw_rect(
		Rect2(rail_left, bar_y, rail_width * CHIP_MAX / MAX_POWER, 6.0),
		CHIP_COLOR
	)

	# The 50% pitch remains a locked placeholder.
	for tick_power: float in [50.0]:
		var tick_x := rail_left + rail_width * tick_power / MAX_POWER
		draw_line(
			Vector2(tick_x, bar_y - 1.0),
			Vector2(tick_x, bar_y + 6.0),
			FUTURE_TICK_COLOR,
			1.0
		)

	# Discrete unlocked actions use distinct notches on the shared power rail.
	var smooth_x := rail_left + rail_width * SMOOTH_POWER / MAX_POWER
	draw_rect(Rect2(smooth_x - 3.0, bar_y - 2.0, 6.0, 10.0), SMOOTH_COLOR if smooth_unlocked else FUTURE_TICK_COLOR)
	var stock_x := rail_left + rail_width * STOCK_POWER / MAX_POWER
	draw_rect(Rect2(stock_x - 3.0, bar_y - 2.0, 6.0, 10.0), STOCK_COLOR if stock_unlocked else FUTURE_TICK_COLOR)
	var full_x := rail_left + rail_width * FULL_POWER / MAX_POWER
	draw_rect(Rect2(full_x - 3.0, bar_y - 2.0, 6.0, 10.0), FULL_COLOR if full_unlocked else FUTURE_TICK_COLOR)

	# One coordinate transform draws both the rail and its pointer, so the
	# selected value always lines up exactly with its availability zone.
	var pointer_x := rail_left + rail_width * value / MAX_POWER
	var triangle := PackedVector2Array([
		Vector2(pointer_x - 6.0, 2.0),
		Vector2(pointer_x + 6.0, 2.0),
		Vector2(pointer_x, bar_y - 2.0),
	])
	draw_colored_polygon(triangle, POINTER_COLOR)
	draw_polyline(
		PackedVector2Array([triangle[0], triangle[1], triangle[2], triangle[0]]),
		POINTER_OUTLINE,
		1.5,
		true
	)
