extends Camera3D
## City-builder camera (like Cities: Skylines):
##   mouse wheel      zoom toward the point under the cursor
##   right-drag       rotate and tilt
##   middle-drag      pan; left-drag on empty ground pans too (see main.gd)
##   WASD / arrows    pan          Q / E   rotate      R / F   zoom
## Movement is smoothed: yaw/pitch/distance/target are where the camera is
## heading; it glides there every frame. Setting them directly still works.

var target := Vector3(30, 0, 20)
var yaw := deg_to_rad(-25.0)
var pitch := deg_to_rad(-38.0)
var distance := 58.0
var bounds := Rect2(0, 0, 60, 40)
## Ground height at (x, z), so the camera never dips into a hillside.
var ground := Callable()

const MIN_DIST := 6.0
const MAX_DIST := 200.0
const SMOOTH := 14.0          # higher = snappier

# where the camera actually is right now (glides toward the goal values)
var _t := Vector3(30, 0, 20)
var _yaw := 0.0
var _pitch := 0.0
var _dist := 58.0
var _rotating := false
var _panning := false
var _press_pos := Vector2.ZERO
var _rot_moved := 0.0


func _ready() -> void:
	fov = 50.0
	far = 1000.0
	snap()


## Jump straight to the goal values (no glide).
func snap() -> void:
	_t = target
	_yaw = yaw
	_pitch = pitch
	_dist = distance
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	var ui = get_parent().get("ui")
	if event is InputEventMouseButton:
		var wheel: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if wheel and ui and ui._over_ui(event.position):
			return   # the wheel over a panel scrolls the panel, never the view
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
				if event.pressed:
					_rot_moved = 0.0
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(event.position, 0.85)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(event.position, 1.0 / 0.85)
	elif event is InputEventMouseMotion:
		if _rotating:
			_rot_moved += event.relative.length()
			yaw -= event.relative.x * 0.006
			pitch = clampf(pitch - event.relative.y * 0.005, deg_to_rad(-85.0), deg_to_rad(-10.0))
		elif _panning:
			grab_pan(event.position - event.relative, event.position)


## True if the last right-button press was a click rather than a rotate-drag.
func right_was_click() -> bool:
	return _rot_moved < 6.0


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if not _typing():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
		var spin_dir := 0.0
		if Input.is_key_pressed(KEY_Q): spin_dir += 1
		if Input.is_key_pressed(KEY_E): spin_dir -= 1
		yaw += spin_dir * 1.6 * delta
		if Input.is_key_pressed(KEY_R): distance = clampf(distance * (1.0 - 1.5 * delta), MIN_DIST, MAX_DIST)
		if Input.is_key_pressed(KEY_F): distance = clampf(distance * (1.0 + 1.5 * delta), MIN_DIST, MAX_DIST)
	if move != Vector2.ZERO:
		_pan(move.normalized() * distance * 0.9 * delta)
	# glide toward the goal
	var k := 1.0 - exp(-SMOOTH * delta)
	_t = _t.lerp(target, k)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, distance, k)
	_apply()
	_focus()


var depth_of_field := false:
	set(v):
		depth_of_field = v
		if v and not attributes:
			attributes = CameraAttributesPractical.new()
		if attributes:
			(attributes as CameraAttributesPractical).dof_blur_far_enabled = v
			(attributes as CameraAttributesPractical).dof_blur_near_enabled = v


## Depth of field (an option): sharp at the point we look at, the distance
## melting away behind it. Only close in; from high up everything stays sharp.
func _focus() -> void:
	if not depth_of_field or not attributes:
		return
	var a := attributes as CameraAttributesPractical
	var close := _dist < 30.0
	a.dof_blur_far_enabled = close
	a.dof_blur_near_enabled = close and _dist < 12.0
	a.dof_blur_far_distance = _dist * 1.5
	a.dof_blur_far_transition = _dist * 2.0
	a.dof_blur_near_distance = _dist * 0.35
	a.dof_blur_near_transition = _dist * 0.3
	a.dof_blur_amount = 0.08


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Pan in screen terms: x = right, y = down the screen (toward the camera).
func _pan(d: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var back := Vector3(sin(yaw), 0, cos(yaw))
	target += right * d.x + back * d.y
	_clamp()


## Drag the ground: the point that was under `from` ends up under `to`.
func grab_pan(from: Vector2, to: Vector2) -> void:
	var a: Variant = ground_point(from)
	var b: Variant = ground_point(to)
	if a == null or b == null:
		return
	var d: Vector3 = (a as Vector3) - (b as Vector3)
	d.y = 0.0
	target += d
	_t += d   # move with the hand, no lag
	_clamp()
	_apply()


## Zoom toward (or away from) the point under the cursor.
func zoom_at(screen: Vector2, factor: float) -> void:
	var nd := clampf(distance * factor, MIN_DIST, MAX_DIST)
	var p: Variant = ground_point(screen)
	if p != null:
		var f := nd / distance
		var pt := p as Vector3
		pt.y = target.y
		target = pt + (target - pt) * f
	distance = nd
	# a lower, more cinematic angle close in; a map view far out
	var close := clampf((distance - MIN_DIST) / 60.0, 0.0, 1.0)
	pitch = lerpf(pitch, lerpf(deg_to_rad(-22.0), deg_to_rad(-45.0), close), 0.25)
	_clamp()


## Where a screen point hits the ground plane at the target's height (or null).
func ground_point(screen: Vector2) -> Variant:
	var from := project_ray_origin(screen)
	var dir := project_ray_normal(screen)
	if dir.y > -0.01:
		return null
	var t := (target.y - from.y) / dir.y
	if t < 0.0 or t > 2000.0:
		return null
	return from + dir * t


func _clamp() -> void:
	var b := bounds.grow(40.0)
	target.x = clampf(target.x, b.position.x, b.end.x)
	target.z = clampf(target.z, b.position.y, b.end.y)


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DIST, MAX_DIST)


func spin(radians: float) -> void:
	yaw += radians


func tilt(radians: float) -> void:
	pitch = clampf(pitch + radians, deg_to_rad(-85.0), deg_to_rad(-10.0))


func reset(centre: Vector3) -> void:
	target = centre
	yaw = deg_to_rad(-25.0)
	pitch = deg_to_rad(-38.0)
	distance = 58.0


## Raise or lower the point the camera orbits (follows concourse levels).
func set_height(y: float) -> void:
	target.y = y


func _apply() -> void:
	var p := _pitch
	var offset := Vector3(0, 0, _dist).rotated(Vector3.RIGHT, p).rotated(Vector3.UP, _yaw)
	if ground.is_valid():
		# tilt up (view only) until the eye clears the land with a little room
		for i in 40:
			var eye := _t + offset
			var g: float = ground.call(eye.x, eye.z)
			if eye.y > g + 4.0 or p < deg_to_rad(-80.0):
				break
			p -= deg_to_rad(2.0)
			offset = Vector3(0, 0, _dist).rotated(Vector3.RIGHT, p).rotated(Vector3.UP, _yaw)
	global_position = _t + offset
	look_at(_t, Vector3.UP)
	h_offset = 0.0
