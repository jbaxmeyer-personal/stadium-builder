extends Camera3D
## Orbit camera: right-drag rotates, middle-drag or WASD/arrows pans,
## wheel zooms, Q/E rotate. Target stays inside the plot.

var target := Vector3(30, 0, 20)
var yaw := deg_to_rad(-25.0)
var pitch := deg_to_rad(-38.0)
var distance := 58.0
var bounds := Rect2(0, 0, 60, 40)
## Ground height at (x, z), so the camera never dips into a hillside.
var ground := Callable()

var _rotating := false
var _panning := false


func _ready() -> void:
	fov = 50.0
	far = 1000.0
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# the wheel over a panel scrolls the panel, never the view
		var ui = get_parent().get("ui")
		if ui and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN) and ui._over_ui(event.position):
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = max(10.0, distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = min(130.0, distance * 1.1)
		_apply()
	elif event is InputEventMouseMotion:
		if _rotating:
			yaw -= event.relative.x * 0.006
			pitch = clampf(pitch - event.relative.y * 0.005, deg_to_rad(-85.0), deg_to_rad(-8.0))
			_apply()
		elif _panning:
			_pan(Vector2(-event.relative.x, -event.relative.y) * distance * 0.0016)


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
	if move != Vector2.ZERO:
		_pan(move * distance * 0.9 * delta)
	var spin := 0.0
	if Input.is_key_pressed(KEY_Q): spin += 1
	if Input.is_key_pressed(KEY_E): spin -= 1
	if spin != 0.0:
		yaw += spin * 1.5 * delta
		_apply()


## Pan in screen terms: x = right, y = down the screen (toward the camera).
func _pan(d: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var back := Vector3(sin(yaw), 0, cos(yaw))
	target += right * d.x + back * d.y
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	_apply()


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, 10.0, 130.0)
	_apply()


func spin(radians: float) -> void:
	yaw += radians
	_apply()


func tilt(radians: float) -> void:
	pitch = clampf(pitch + radians, deg_to_rad(-85.0), deg_to_rad(-8.0))
	_apply()


func reset(centre: Vector3) -> void:
	target = centre
	yaw = deg_to_rad(-25.0)
	pitch = deg_to_rad(-38.0)
	distance = 58.0
	_apply()


## Raise or lower the point the camera orbits (follows concourse levels).
func set_height(y: float) -> void:
	target.y = y
	_apply()


func _apply() -> void:
	var p := pitch
	var offset := Vector3(0, 0, distance).rotated(Vector3.RIGHT, p).rotated(Vector3.UP, yaw)
	if ground.is_valid():
		# tilt up (view only) until the eye clears the land with a little room
		for i in 40:
			var eye := target + offset
			var g: float = ground.call(eye.x, eye.z)
			if eye.y > g + 4.0 or p < deg_to_rad(-80.0):
				break
			p -= deg_to_rad(2.0)
			offset = Vector3(0, 0, distance).rotated(Vector3.RIGHT, p).rotated(Vector3.UP, yaw)
	global_position = target + offset
	look_at(target, Vector3.UP)
	h_offset = distance * 0.16  # keep the target centred in the area left of the side panel
