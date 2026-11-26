extends Node3D
## Playable 3D view. Reads sim state, sends player commands to Season.
## No game rules live here; StadiumRenderer draws, OrbitCamera moves.

const NEW_STAND_LENGTH := 6
const EXTEND_STEP := 2
const SNAP_GAP := 4
const AUTOSAVE := "user://autosave.json"
const SAVE_SLOT := "user://save1.json"
const StadiumRenderer := preload("res://view/stadium_renderer.gd")
const OrbitCamera := preload("res://view/orbit_camera.gd")
const CrowdAudio := preload("res://view/crowd_audio.gd")
const GameUI := preload("res://view/ui/game_ui.gd")

var config: SimConfig
var game: Season
var tool := "select"   # nothing happens on a click until you pick something to build
var selected := -1            # selected stand index
var selected_fac := -1        # selected facility index
var layer := "stadium"        # stadium / concourse / underground
var level := 0                # concourse level being viewed (0 = ground)
var hover := Vector2i(-1, -1)
var last_report: MatchdayReport
var show_details := false

var renderer: StadiumRenderer
var camera: Camera3D
var crowd_audio: CrowdAudio
var env: Environment
var sky_mat: ProceduralSkyMaterial
var day_sky: PanoramaSkyMaterial
var sun: DirectionalLight3D
var md_tween: Tween
var ui: GameUI
var md_saved_cam := {}
var _world_sig := 0
var _static_plot := Rect2i()


func _ready() -> void:
	config = SimConfig.load_default()
	var saved := Season.load_file(config, AUTOSAVE)
	game = saved if saved != null else _new_game()
	_build_world()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = GameUI.new(self)
	canvas.add_child(ui)
	_refresh()
	if saved != null:
		_say("Welcome back! Season %d, %s fans." % [game.season_number, _n(game.club.fanbase)])
	else:
		if ui.guide_step < 0:
			_say("Pick a stand type, then drag out from the touchline to build your first stand.")


func _new_game() -> Season:
	return Season.create(config, Layout.create(config, "My Stadium"), int(Time.get_unix_time_from_system()))


func _set_game(g: Season) -> void:
	game = g
	selected = -1
	last_report = game.reports[-1] if not game.reports.is_empty() else null
	selected_fac = -1
	_world_sig = 0
	ui.rebuild_dock()
	_refresh()


func _autosave() -> void:
	game.save_file(AUTOSAVE)


# --- World ------------------------------------------------------------------

## Daytime sky presets: an HDRI (Poly Haven, CC0) that also lights the scene,
## and a sun that matches it. "haze" is how thick the far haze ring gets (0-1). Night and bad weather override these.
const SKIES := {
	"sunny": { "hdri": "partly_cloudy_1k", "sun_rot": Vector3(-38, -135, 0), "sun_col": Color(1.0, 0.92, 0.8), "sun": 1.35,
		"ambient": 0.45, "exposure": 0.8, "fog": Color(0.68, 0.74, 0.82), "haze": 0.75, "sky": 0.8, "shadow": 1.0 },
	"cloudy": { "hdri": "farm_field_puresky", "sun_rot": Vector3(-45, -125, 0), "sun_col": Color(1.0, 0.95, 0.88), "sun": 0.95,
		"ambient": 0.55, "exposure": 0.85, "fog": Color(0.7, 0.74, 0.78), "haze": 0.82, "sky": 0.9, "shadow": 0.8 },
	"overcast": { "hdri": "kloofendal_overcast_puresky", "sun_rot": Vector3(-60, -120, 0), "sun_col": Color(0.92, 0.94, 1.0), "sun": 0.35,
		"ambient": 0.85, "exposure": 0.95, "fog": Color(0.66, 0.68, 0.7), "haze": 0.9, "sky": 1.0, "shadow": 0.45 },
	"golden": { "hdri": "belfast_sunset_puresky", "sun_rot": Vector3(-14, -105, 0), "sun_col": Color(1.0, 0.72, 0.45), "sun": 1.6,
		"ambient": 0.4, "exposure": 0.75, "fog": Color(0.7, 0.62, 0.55), "haze": 0.7, "sky": 0.9, "shadow": 1.0 },
}

var sky_name := "sunny"


func _build_world() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.24, 0.45)
	sky_mat.sky_horizon_color = Color(0.85, 0.62, 0.45)
	sky_mat.ground_horizon_color = Color(0.35, 0.33, 0.3)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.12)
	sky_mat.sun_angle_max = 20.0
	day_sky = PanoramaSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = day_sky
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# filmic look: ACES, slightly lower saturation so nothing looks like plastic
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	# contact shadows and bounce light: everything sits in its own soft shadow
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	# haze as a ring: none around the ground, building up toward the horizon
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.6
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 0.8   # soft penumbra
	add_child(sun)
	_apply_sky(game.layout.sky)

	camera = OrbitCamera.new()
	camera.target = Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0)
	camera.bounds = Rect2(game.layout.plot)
	add_child(camera)

	crowd_audio = CrowdAudio.new()
	add_child(crowd_audio)
	crowd_audio.ambient(0.3)

	renderer = StadiumRenderer.new()
	add_child(renderer)
	renderer.build_static(game.layout)
	camera.ground = renderer.terrain_h
	camera.snap()


# --- Views, matchday ------------------------------------------------------

const KITS := [
	["Reds", Color(0.75, 0.08, 0.10), Color(0.97, 0.97, 0.97)],
	["Blues", Color(0.08, 0.25, 0.70), Color(0.97, 0.97, 0.97)],
	["Claret & Blue", Color(0.48, 0.08, 0.20), Color(0.45, 0.70, 0.90)],
	["Black & White", Color(0.08, 0.08, 0.08), Color(0.97, 0.97, 0.97)],
	["Yellow & Black", Color(0.98, 0.80, 0.10), Color(0.08, 0.08, 0.08)],
	["Greens", Color(0.05, 0.50, 0.25), Color(0.97, 0.97, 0.97)],
	["Tangerine", Color(0.96, 0.45, 0.08), Color(0.08, 0.08, 0.08)],
	["Sky Blue", Color(0.42, 0.68, 0.90), Color(0.97, 0.97, 0.97)],
]


func _max_tiers() -> int:
	var m := 1
	for s in game.layout.stands:
		m = maxi(m, s.tiers)
	return m


func _set_level(lv: int) -> void:
	level = lv
	renderer.set_layer(layer, level)
	_follow_level()
	_say("Concourse: %s" % ("ground level" if lv == 0 else "level %d" % lv))
	_refresh()


## Keep the camera orbiting the floor being worked on.


## Keep the camera orbiting the floor being worked on.
func _follow_level() -> void:
	var y := -2.5 if layer == "underground" else (StadiumRenderer.level_height(game.layout, level) if layer == "concourse" else 0.0)
	camera.set_height(y)


func _set_layer(id: String) -> void:
	layer = id
	ui.set_layer_button(id)
	tool = "select"
	selected = -1
	selected_fac = -1
	if id != "concourse":
		level = 0
	renderer.set_layer(id, level)
	_follow_level()
	ui.rebuild_dock()
	_say({ "stadium": "Stadium view", "concourse": "Concourse view: place food, bars, shops and restrooms on the paving", "underground": "Underground view: parking garages and the subway" }[id])
	_refresh()


func _matchday_show(r: MatchdayReport) -> void:
	ui.show_matchday(r)
	renderer.matchday_live = true
	_world_sig = 0
	crowd_audio.play_match(r)
	_set_night(r.evening)
	_set_weather(r.weather)
	if md_saved_cam.is_empty():
		md_saved_cam = { "yaw": camera.yaw, "pitch": camera.pitch, "distance": camera.distance, "target": camera.target }
	if md_tween:
		md_tween.kill()
	md_tween = create_tween().set_parallel(true)
	camera.target = Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0)
	camera.pitch = deg_to_rad(-24.0)
	camera.distance = 48.0
	md_tween.tween_method(_sweep, camera.yaw, camera.yaw + deg_to_rad(100.0), 7.0)


func _sweep(yaw: float) -> void:
	camera.yaw = yaw
	camera._apply()


func _matchday_end() -> void:
	if md_tween:
		md_tween.kill()
	ui.hide_matchday()
	if renderer.matchday_live:
		renderer.matchday_live = false
		_world_sig = 0
		_sync_world()
	crowd_audio.stop_match()
	_set_night(false)
	_set_weather("clear")
	if not md_saved_cam.is_empty():
		camera.yaw = md_saved_cam["yaw"]
		camera.pitch = md_saved_cam["pitch"]
		camera.distance = md_saved_cam["distance"]
		camera.target = md_saved_cam["target"]
		camera._apply()
		md_saved_cam = {}


## Daylight preset (see SKIES).
func _apply_sky(name: String) -> void:
	sky_name = name if SKIES.has(name) else "sunny"
	var k: Dictionary = SKIES[sky_name]
	day_sky.panorama = load("res://assets/polyhaven/sky/%s.hdr" % k["hdri"])
	day_sky.energy_multiplier = k["sky"]
	env.sky.sky_material = day_sky
	env.background_energy_multiplier = 1.0
	sun.rotation_degrees = k["sun_rot"]
	sun.light_color = k["sun_col"]
	sun.light_energy = k["sun"]
	sun.shadow_opacity = k["shadow"]
	env.ambient_light_energy = k["ambient"]
	env.tonemap_exposure = k["exposure"]
	env.fog_light_color = k["fog"]
	env.fog_density = k["haze"]   # depth fog: how thick the haze gets at the horizon
	env.fog_depth_begin = 170.0
	env.fog_depth_end = 720.0
	env.glow_intensity = 0.35


func _set_weather(w: String) -> void:
	renderer.set_weather(w, game.layout)
	if w != "clear" and env.sky.sky_material == day_sky:
		_apply_sky("overcast")
		sky_name = game.layout.sky
		env.fog_density = 1.0
		env.fog_depth_begin = 50.0
		env.fog_depth_end = 420.0
	elif w == "clear" and env.sky.sky_material == day_sky:
		_apply_sky(game.layout.sky)


func _set_night(on: bool) -> void:
	if not on:
		_apply_sky(game.layout.sky)
		renderer.set_night(false)
		return
	env.sky.sky_material = sky_mat
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.08) if on else Color(0.16, 0.24, 0.45)
	sky_mat.sky_horizon_color = Color(0.12, 0.1, 0.18) if on else Color(0.85, 0.62, 0.45)
	sky_mat.ground_horizon_color = Color(0.05, 0.05, 0.06) if on else Color(0.35, 0.33, 0.3)
	sun.light_energy = 0.08 if on else 1.1
	env.ambient_light_energy = 0.25 if on else 0.6
	env.glow_intensity = 1.0 if on else 0.6
	env.fog_light_color = Color(0.02, 0.02, 0.04) if on else Color(0.6, 0.55, 0.55)
	env.background_energy_multiplier = 0.35 if on else 1.0
	renderer.set_night(on)


# --- Commands -------------------------------------------------------------

func _set_tool(id: String) -> void:
	tool = id
	_refresh()


func _change_price(type_id: String, dir: int) -> void:
	var step: float = maxf(1.0, roundf(config.stand_type(type_id).reference_price * 0.1))
	var p: float = game.club.price(type_id) + dir * step
	_report_err(game.set_ticket_price(type_id, max(0.0, p)))
	_refresh()


## roof "" = keep; seat "" = keep, "-" = reset to default.
func _restyle(roof: String, seat: String) -> void:
	if selected < 0 or selected >= game.layout.stands.size():
		return
	var s := game.layout.stands[selected]
	var new_seat := s.seat_color if seat == "" else ("" if seat == "-" else "#" + seat)
	_report_err(game.restyle_stand(selected, s.roof if roof == "" else roof, new_seat))
	_refresh()


func _set_colors(primary: Color, secondary: Color) -> void:
	game.club.primary_color = primary
	game.club.secondary_color = secondary
	_refresh()


func _set_stadium_name(text: String) -> void:
	var t := text.strip_edges()
	if t != "" and t != game.club.stadium_name:
		game.club.stadium_name = t
		_refresh()


func _set_club_name(text: String) -> void:
	var t := text.strip_edges()
	if t != "" and t != game.club.club_name:
		game.club.club_name = t
		_refresh()


func _stand_action(action: String) -> void:
	if selected < 0 or selected >= game.layout.stands.size():
		return
	var s := game.layout.stands[selected]
	var side_len := Stand.side_length(s.side, game.layout.pitch)
	var err := ""
	match action:
		"row":
			err = game.resize_stand(selected, s.offset, s.depth + 1 if s.is_corner() else s.length, s.depth + 1)
		"unrow":
			err = "a stand needs at least one row" if s.depth <= 1 else game.resize_stand(selected, s.offset, s.depth - 1 if s.is_corner() else s.length, s.depth - 1)
		"left":
			var new_off: int = max(0, s.offset - EXTEND_STEP)
			err = "already at the corner" if new_off == s.offset else game.resize_stand(selected, new_off, s.length + s.offset - new_off, s.depth)
		"right":
			var new_len: int = min(side_len - s.offset, s.length + EXTEND_STEP)
			err = "already at the corner" if new_len == s.length else game.resize_stand(selected, s.offset, new_len, s.depth)
		"tier":
			err = game.set_tiers(selected, s.tiers + 1)
		"untier":
			err = "already a single tier" if s.tiers <= 1 else game.set_tiers(selected, s.tiers - 1)
		"demolish":
			err = game.demolish_stand(selected)
			if err == "":
				selected = -1
	_report_err(err)
	_refresh()


func _on_play() -> void:
	_matchday_end()
	if game.is_over():
		var promoted := game.promotion_earned()
		game.start_next_season()
		last_report = null
		if promoted:
			_say("★ PROMOTED! Welcome to the %s: bigger crowds, TV money and tougher opponents." % config.division(game.club.division)["name"])
		else:
			_say("Season %d kicks off. Keep building!" % game.season_number)
		_autosave()
		_refresh()
		return
	if game.layout.stands.is_empty():
		_say("Build a stand first. Nobody comes to watch an empty field.")
		return
	last_report = game.play_next()
	_autosave()
	_say("")
	_matchday_show(last_report)
	_refresh()


func _click(tile: Vector2i) -> void:
	if ui.md_panel.visible:
		_matchday_end()
	var stand_tiles := game.layout.stand_tile_map()
	var concourse := game.layout.concourse_tile_map(config)
	if config.facility_types.has(tool):
		var nf := Facility.make(tool, tile)
		if config.facility_type(tool).layer == "concourse":
			nf.level = level
		var err := game.build_facility(nf)
		_report_err(err)
		if err == "":
			selected_fac = game.layout.facilities.size() - 1
			selected = -1
		_refresh()
		return
	match tool:
		"select":
			selected_fac = _facility_at(tile)
			selected = -1 if selected_fac >= 0 or layer != "stadium" else _stand_at(tile, stand_tiles, concourse)
		"demolish":
			var fi := _facility_at(tile)
			if fi >= 0:
				_report_err(game.demolish_facility(fi))
				selected_fac = -1
			elif layer == "stadium":
				var si := _stand_at(tile, stand_tiles, {})
				if si >= 0:
					_report_err(game.demolish_stand(si))
					selected = -1
		_:  # a stand type
			var existing := _stand_at(tile, stand_tiles, concourse)
			if existing >= 0:
				selected = existing
			else:
				var s := _placement(tile)
				if s == null:
					_say("Stands go right beside the pitch, on one of its four sides.")
				else:
					var join := _neighbour(s)
					if join >= 0:
						# Building next to a stand of the same type extends it into one bigger stand.
						var n := game.layout.stands[join]
						var lo: int = mini(n.offset, s.offset)
						var hi: int = maxi(n.offset + n.length, s.offset + s.length)
						var err := game.resize_stand(join, lo, hi - lo, n.depth)
						_report_err(err)
						if err == "":
							selected = join
					else:
						var err := game.build_stand(s)
						_report_err(err)
						if err == "":
							selected = game.layout.stands.size() - 1
	_refresh()


func _report_err(err: String) -> void:
	_say("" if err == "" else "Can't do that: " + err)


func _say(text: String) -> void:
	ui.toast(text)


func _deselect() -> void:
	selected = -1
	selected_fac = -1
	tool = "select"
	_refresh()


func _reset_camera() -> void:
	camera.reset(Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0))
	_follow_level()


## Hover preview while dragging a tile from the build bar.
func _hover_at(pos: Vector2) -> void:
	var t := _mouse_tile(pos)
	if t != hover:
		hover = t
		_update_hover()


## Short hover info for whatever is under the mouse (stand or facility).
func _info_at(tile: Vector2i) -> String:
	var fi := _facility_at(tile)
	if fi >= 0:
		return config.facility_type(game.layout.facilities[fi].type_id).display_name
	if layer != "stadium":
		return ""
	var si := _stand_at(tile, game.layout.stand_tile_map(), {})
	if si < 0:
		return ""
	var s := game.layout.stands[si]
	var t := config.stand_type(s.type_id)
	var cap := s.capacity(t)
	var crowd := ""
	if last_report != null and si < last_report.stands.size() and last_report.stands[si]["capacity"] == cap:
		crowd = "%s / " % _n(last_report.stands[si]["attendance"])
	return "%s stand\n%s%s places · click to edit" % [t.display_name, crowd, _n(cap)]


func _buy_land(side: String) -> void:
	var err := game.buy_land(side)
	_report_err(err)
	if err == "":
		_say("Bought land to the %s. The plot is now %d × %d." % [{ "N": "north", "S": "south", "E": "east", "W": "west" }[side], game.layout.plot.size.x, game.layout.plot.size.y])
	_refresh()


func _save_slot() -> void:
	_say("Saved." if game.save_file(SAVE_SLOT) == OK else "Couldn't write the save file.")


func _load_slot() -> void:
	var g := Season.load_file(config, SAVE_SLOT)
	if g == null:
		_say("No saved game yet.")
	else:
		_set_game(g)
		_say("Loaded.")


func _new_game_clicked() -> void:
	_set_game(_new_game())
	_autosave()
	_say("New club, empty plot. Build your first stand!")


# --- Geometry helpers (view-side; read-only on sim state) -----------------

## Which side/u a tile falls on, or {} for corners and the pitch itself.
func _side_of(tile: Vector2i) -> Dictionary:
	var p := game.layout.pitch
	if tile.x >= p.position.x and tile.x < p.end.x:
		if tile.y < p.position.y:
			return { "side": "N", "u": tile.x - p.position.x }
		if tile.y >= p.end.y:
			return { "side": "S", "u": tile.x - p.position.x }
	if tile.y >= p.position.y and tile.y < p.end.y:
		if tile.x < p.position.x:
			return { "side": "W", "u": tile.y - p.position.y }
		if tile.x >= p.end.x:
			return { "side": "E", "u": tile.y - p.position.y }
	return {}


## The new stand a click would build at this tile (largest free run up to
## NEW_STAND_LENGTH, centred on the click), or null.
func _placement(tile: Vector2i) -> Stand:
	if not game.layout.in_plot(tile):
		return null
	var at := _side_of(tile)
	if at.is_empty():
		return _corner_placement(tile)
	var side: String = at["side"]
	var u: int = at["u"]
	var side_len := Stand.side_length(side, game.layout.pitch)
	var taken := game.layout.stand_tile_map()
	if taken.has(Stand.local_to_grid(side, game.layout.pitch, u, 0)):
		return null
	var lo := u
	var hi := u
	while hi - lo + 1 < NEW_STAND_LENGTH:
		var grew := false
		if hi + 1 < side_len and not taken.has(Stand.local_to_grid(side, game.layout.pitch, hi + 1, 0)):
			hi += 1
			grew = true
		if hi - lo + 1 < NEW_STAND_LENGTH and lo - 1 >= 0 and not taken.has(Stand.local_to_grid(side, game.layout.pitch, lo - 1, 0)):
			lo -= 1
			grew = true
		if not grew:
			break
	# Snap across a small gap to a same-type stand on this side, so clicking
	# a little past the end of a stand extends it instead of starting another.
	for n in game.layout.stands:
		if n.side != side or n.type_id != tool:
			continue
		var gap_lo := n.offset + n.length          # gap between n and us, if n is to our left
		var gap_hi := n.offset - 1                 # ... if n is to our right
		if gap_lo <= lo and lo - gap_lo <= SNAP_GAP and _free_run(side, gap_lo, lo - 1, taken):
			lo = gap_lo
		elif gap_hi >= hi and gap_hi - hi <= SNAP_GAP and _free_run(side, hi + 1, gap_hi, taken):
			hi = gap_hi
	return Stand.make(side, tool, lo, hi - lo + 1, 1)


func _free_run(side: String, from_u: int, to_u: int, taken: Dictionary) -> bool:
	for u in range(from_u, to_u + 1):
		if taken.has(Stand.local_to_grid(side, game.layout.pitch, u, 0)):
			return false
	return true


## A corner stand for a click in a corner gap, as deep as the deepest
## neighbouring side stand (at least 2), or null.
func _corner_placement(tile: Vector2i) -> Stand:
	var p := game.layout.pitch
	if p.has_point(tile):
		return null
	var corner := ("N" if tile.y < p.position.y else "S") + ("W" if tile.x < p.position.x else "E")
	for s in game.layout.stands:
		if s.side == corner:
			return null
	var depth := 2
	for s in game.layout.stands:
		if not s.is_corner() and corner.contains(s.side):
			depth = maxi(depth, s.depth)
	var c := Stand.make_corner(corner, tool, mini(depth, config.integer("layout/max_depth")))
	c.shape = "rounded"
	return c


## Index of an existing stand of the same type, side and setback that touches s end-to-end, or -1.
func _neighbour(s: Stand) -> int:
	if s.is_corner():
		return -1
	for i in game.layout.stands.size():
		var n := game.layout.stands[i]
		if n.side == s.side and n.type_id == s.type_id and n.setback == s.setback \
				and (n.offset + n.length == s.offset or s.offset + s.length == n.offset):
			return i
	return -1


func _stand_at(tile: Vector2i, stand_tiles: Dictionary, concourse: Dictionary) -> int:
	if stand_tiles.has(tile):
		return stand_tiles[tile]
	if concourse.has(tile):
		return concourse[tile]
	return -1


## The facility under this tile in the current layer (bowl items count when
## clicking anywhere on their stand), or -1.
func _facility_at(tile: Vector2i) -> int:
	var layers: Array = { "stadium": ["bowl", "outside"], "concourse": ["concourse"], "underground": ["underground"] }[layer]
	var stand_tiles := game.layout.stand_tile_map()
	for i in range(game.layout.facilities.size() - 1, -1, -1):
		var f := game.layout.facilities[i]
		var ft := config.facility_type(f.type_id)
		if not ft.layer in layers:
			continue
		if ft.layer == "bowl":
			continue  # managed from the stand's editor
		if ft.layer == "concourse" and f.level != level:
			continue
		if tile in f.tiles(ft):
			return i
	return -1


# --- Input -----------------------------------------------------------------

# Mouse: a click (press and release without moving) uses the tool; a left-drag
# from a stand spot draws a stand (length along the pitch, depth outward);
# any other left-drag grabs and pans the map. Right-click or Esc drops the tool.
var _lmb := false
var _press_pos := Vector2.ZERO
var _press_tile := Vector2i(-1, -1)
var _drag := ""             # "", "pan", "build"
var _drag_ok := false       # the press was on a spot where a stand can start
var _ghost: Stand = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _lmb:
			if _drag == "" and event.position.distance_to(_press_pos) > 6.0:
				_drag = "build" if _drag_ok else "pan"
			if _drag == "pan":
				camera.grab_pan(event.position - event.relative, event.position)
				return
			if _drag == "build":
				_drag_stand(_mouse_tile(event.position))
				return
		var t := _mouse_tile(event.position)
		if t != hover:
			hover = t
			_update_hover()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_lmb = true
			_press_pos = event.position
			_press_tile = _mouse_tile(event.position)
			_drag = ""
			_drag_ok = config.stand_types.has(tool) and _stand_at(_press_tile, game.layout.stand_tile_map(), {}) < 0 \
				and not _side_of(_press_tile).is_empty() and _placement(_press_tile) != null
			_ghost = null
		elif _lmb:
			_lmb = false
			match _drag:
				"":
					if game.layout.in_plot(_press_tile):
						_click(_press_tile)
				"build":
					_build_ghost()
			_drag = ""
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if camera.right_was_click():
			_drop_tool()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_drop_tool()


## Right-click / Esc: put the tool down first; a second press clears the selection.
func _drop_tool() -> void:
	if tool != "select":
		_set_tool("select")
		ui.tool_dropped()
		renderer.clear_overlay()
		ui.hover_tip("")
	else:
		_deselect()


## While dragging out a new stand: along the pitch sets its length, outward its depth.
func _drag_stand(cur: Vector2i) -> void:
	var at := _side_of(_press_tile)
	if at.is_empty():
		return
	var side: String = at["side"]
	var p := game.layout.pitch
	var side_len := Stand.side_length(side, p)
	var u0: int = at["u"]
	var u1: int = (cur.x - p.position.x) if side in ["N", "S"] else (cur.y - p.position.y)
	u1 = clampi(u1, 0, side_len - 1)
	var out := 1
	match side:
		"N": out = p.position.y - cur.y
		"S": out = cur.y - p.end.y + 1
		"W": out = p.position.x - cur.x
		"E": out = cur.x - p.end.x + 1
	var depth := clampi(out, 1, config.integer("layout/max_depth"))
	# stop at the first tile that's already built on
	var taken := game.layout.stand_tile_map()
	var step := 1 if u1 >= u0 else -1
	var u := u0
	while u != u1 and not taken.has(Stand.local_to_grid(side, p, u + step, 0)):
		u += step
	var lo := mini(u0, u)
	var hi := maxi(u0, u)
	_ghost = Stand.make(side, tool, lo, hi - lo + 1, depth)
	var t := config.stand_type(tool)
	var cost := Layout.stand_cost(_ghost, config)
	renderer.show_ghost_stand(_ghost, p, cost <= game.club.cash)
	ui.hover_tip("%d long x %d rows · %s places · %s" % [_ghost.length, _ghost.depth, _n(_ghost.capacity(t)), Season.money(cost)])


func _build_ghost() -> void:
	if _ghost == null:
		return
	var err := game.build_stand(_ghost)
	_report_err(err)
	if err == "":
		selected = game.layout.stands.size() - 1
		selected_fac = -1
	_ghost = null
	renderer.clear_overlay()
	_refresh()


## Tile under the mouse: stands are hit on their raised steps, everything else on the ground.
func _mouse_tile(pos: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var best_t := INF
	var best := Vector2i(-1, -1)
	for s in game.layout.stands if layer == "stadium" else []:
		var hit: Variant = StadiumRenderer.stand_aabb(s, game.layout.pitch).intersects_ray(from, dir)
		if hit != null:
			var t: float = ((hit as Vector3) - from).length()
			if t < best_t:
				var p: Vector3 = (hit as Vector3) + dir * 0.01
				best_t = t
				best = Vector2i(floori(p.x), floori(p.z))
	var floor_y := StadiumRenderer.level_height(game.layout, level) if layer == "concourse" else 0.0
	if absf(dir.y) > 1e-5:
		var t := (floor_y - from.y) / dir.y
		if t > 0.0 and t < best_t:
			var p := from + dir * t
			best = Vector2i(floori(p.x), floori(p.z))
	return best


func _update_hover() -> void:
	if _drag != "":
		return
	ui.hover_tip("")
	if not game.layout.in_plot(hover):
		renderer.clear_overlay()
		return
	var concourse := game.layout.concourse_tile_map(config)
	if config.stand_types.has(tool) and _stand_at(hover, game.layout.stand_tile_map(), concourse) < 0:
		var ghost := _placement(hover)
		if ghost != null:
			var t := config.stand_type(tool)
			var join := _neighbour(ghost)
			if join >= 0:
				ghost.depth = game.layout.stands[join].depth
			renderer.show_ghost_stand(ghost, game.layout.pitch, ghost.capacity(t) * t.build_cost_per_place <= game.club.cash)
			ui.hover_tip("%s+%s places · %s" % ["Extend · " if join >= 0 else "", _n(ghost.capacity(t)), Season.money(ghost.capacity(t) * t.build_cost_per_place)])
		else:
			renderer.show_ghost_tile(hover, false)
			ui.hover_tip("Stands go beside the pitch or in a corner")
	elif config.facility_types.has(tool):
		var ft := config.facility_type(tool)
		var probe := Facility.make(tool, hover)
		if ft.layer == "concourse":
			probe.level = level
		var ctx := game.layout.placement_context(config)
		for f in game.layout.facilities:
			game.layout.facility_error(f, config, ctx)
		var ok := game.layout.facility_error(probe, config, ctx) == "" and ft.build_cost <= game.club.cash
		if ft.layer == "bowl":
			var si := _stand_at(hover, game.layout.stand_tile_map(), {})
			if si >= 0:
				var r := StadiumRenderer.stand_aabb(game.layout.stands[si], game.layout.pitch)
				renderer.show_ghost_tile(Vector2i(int(r.position.x), int(r.position.z)), ok, Vector2i(int(r.size.x), int(r.size.z)))
			else:
				renderer.clear_overlay()
		else:
			renderer.show_ghost_tile(hover, ok, ft.size, ft.layer == "underground", StadiumRenderer.level_height(game.layout, level) if ft.layer == "concourse" else 0.0)
		ui.hover_tip("%s · %s" % [Season.money(ft.build_cost), "drop here" if ok else "can't go here"])
	else:
		renderer.show_hover_tile(hover)
		ui.hover_tip(_info_at(hover))


# --- Refresh / text --------------------------------------------------------

func _refresh() -> void:
	ui.refresh()
	_sync_world()
	_autosave()  # cheap; keeps every build and setting safe


func _sync_world() -> void:
	var c := game.club
	if game.layout.plot != _static_plot or renderer.surroundings != game.layout.surroundings:
		_static_plot = game.layout.plot
		renderer.pitch_pattern = game.layout.pitch_pattern
		renderer.surroundings = game.layout.surroundings
		renderer.build_static(game.layout)
		camera.bounds = Rect2(game.layout.plot)
	var prices := {}
	for side in Layout.LAND_SIDES:
		prices[side] = game.land_cost(side)
	renderer.show_land_offers(game.layout, prices)
	var sig := hash([game.layout.to_dict(), selected, last_report.seed if last_report else -1, game.reports.size(),
		c.club_name, c.primary_color, c.secondary_color, c.ground_name(config)])
	if sig != _world_sig:
		_world_sig = sig
		renderer.ground_name = c.ground_name(config)
		renderer.build_layout(game.layout, config, last_report, selected, c)
	_update_hover()


func _facility_blurb(f: FacilityType) -> String:
	var bits := PackedStringArray()
	bits.append("%s: %s, upkeep %s/match." % [f.display_name, Season.money(f.build_cost), Season.money(f.upkeep_per_match)])
	if f.service_rate_per_min > 0:
		bits.append("Serves %d fans/min at halftime%s." % [roundi(f.service_rate_per_min), "" if f.spend_per_customer <= 0 else ", ~£%d each" % roundi(f.spend_per_customer)])
	if f.capacity > 0:
		bits.append("Brings %s more fans to the ground." % _n(f.capacity))
	if f.atmosphere_bonus > 0:
		bits.append("+%d atmosphere." % roundi(f.atmosphere_bonus))
	if f.sponsor_per_match > 0:
		bits.append("Sponsors ~%s/match." % Season.money(f.sponsor_per_match))
	if f.income_per_match > 0:
		bits.append("Earns ~%s/match." % Season.money(f.income_per_match))
	if f.box_price > 0:
		bits.append("Corporate boxes along the stand, ~%s each when sold." % Season.money(f.box_price))
	if f.requires_tiers > 1:
		bits.append("Needs a stand with %d tiers." % f.requires_tiers)
	if f.mood_bonus > 0:
		bits.append("Happier fans (covers %s)." % _n(f.coverage))
	if f.size != Vector2i.ONE:
		bits.append("%dx%d tiles." % [f.size.x, f.size.y])
	bits.append({ "concourse": "Place on the paving behind a stand.", "bowl": "Click a stand to mount it.",
		"outside": "Place on open ground.", "underground": "Dig anywhere except under the pitch." }[f.layer])
	return " ".join(bits)


static func _n(v: float) -> String:
	return Season.money(v).substr(1)
