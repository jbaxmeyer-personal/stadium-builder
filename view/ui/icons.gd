extends Control
## A flat pictogram for anything you can build or pick, drawn in code so
## every icon shares one style. Set `id`; `tint` is the foreground colour.
## Generic actions use Kenney's CC0 game icons (see `kenney()`).

var id := ""
var tint := Color(1, 1, 1)
var accent := Color(1.0, 0.78, 0.25)


static func kenney(name: String) -> Texture2D:
	return load("res://assets/kenney/game-icons/%s.png" % name)


func _init(p_id := "", p_tint := Color(1, 1, 1)) -> void:
	id = p_id
	tint = p_tint
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_texture()


func set_id(p_id: String) -> void:
	id = p_id
	_sync_texture()
	queue_redraw()


## Kenney icons are shown with a TextureRect child rather than drawn: textured
## draws inside some 2D batches came out as solid quads.
var _tex_rect: TextureRect


func _sync_texture() -> void:
	var name := "trashcan" if id == "demolish" else id
	var tex: Texture2D = kenney(name) if (name != "" and not _drawn(name) and ResourceLoader.exists("res://assets/kenney/game-icons/%s.png" % name)) else null
	if tex == null:
		if _tex_rect:
			_tex_rect.queue_free()
			_tex_rect = null
		return
	if _tex_rect == null:
		_tex_rect = TextureRect.new()
		_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tex_rect)
	_tex_rect.texture = tex
	_tex_rect.self_modulate = tint


func _drawn(name: String) -> bool:
	return name in DRAWN or name.begins_with("grass_") or name.begins_with("goal_") or name.begins_with("net_") \
		or name.begins_with("ads_") or name.begins_with("dug_") or name.begins_with("sur_")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _tex_rect:
		_tex_rect.self_modulate = tint


const DRAWN := ["terrace", "seated", "premium", "family", "safe_standing", "video_board", "ribbon_board", "scoreboard", "sound_system",
	"exec_boxes", "car_park", "garage", "bus_stop", "train_station", "subway", "statue", "ticket_office", "museum", "hotel", "kiosk", "bar",
	"restroom", "first_aid", "merch", "fan_zone", "select", "stands_cat", "bowl_cat", "transport_cat", "around_cat", "food_cat",
	"services_cat", "shops_cat", "land_cat", "looks_cat", "layer_stadium", "layer_concourse", "layer_underground", "crest", "coin", "fans",
	"mood_good", "mood_ok", "mood_bad", "ball", "capacity", "night", "rain", "snow", "big", "pylons", "roof", "masts", "stripes",
	"wide_stripes", "checks", "plain", "town", "suburban", "city", "city_edge", "riverside", "lakeside", "mountains", "fields", "forest",
	"land_N", "land_S", "land_E", "land_W", "rotate", "rotate_l", "shirt", "sunny", "cloudy", "overcast", "golden", "history", "diagonal", "diamonds", "circles"]


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	# everything is drawn on a 100x100 grid
	var k := s / 100.0
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var R := func(x: float, y: float, w: float, h: float) -> Rect2: return Rect2(o + Vector2(x, y) * k, Vector2(w, h) * k)
	var c := tint
	var dim := Color(tint, 0.55)
	var a := accent
	var lw := maxf(1.5, 5.0 * k)
	match id:
		"terrace", "seated", "premium", "family", "safe_standing":
			# stepped stand in profile
			for i in 4:
				draw_rect(R.call(14 + i * 18, 72 - i * 14, 72 - i * 18, 14), dim)
			match id:
				"terrace":
					for i in 3:
						draw_line(P.call(20 + i * 22, 58 - i * 14), P.call(20 + i * 22, 44 - i * 14), c, lw)
						draw_circle(P.call(20 + i * 22, 38 - i * 14), 6 * k, c)
				"seated", "family", "premium":
					for i in 3:
						var x := 22 + i * 20
						var y := 58 - i * 14
						draw_rect(R.call(x - 7, y - 4, 14, 4), a if id == "seated" else c)
						draw_rect(R.call(x + 4, y - 14, 4, 14), a if id == "seated" else c)
					if id == "premium":
						_star(P.call(74, 22), 14 * k, a)
					if id == "family":
						draw_circle(P.call(70, 22), 8 * k, a)
						draw_circle(P.call(86, 30), 5 * k, a)
				"safe_standing":
					for i in 3:
						draw_line(P.call(14 + i * 18, 64 - i * 14), P.call(86, 64 - i * 14), a, lw * 0.8)
						draw_circle(P.call(30 + i * 20, 48 - i * 14), 6 * k, c)
		"video_board":
			draw_rect(R.call(12, 18, 76, 46), c)
			draw_rect(R.call(18, 24, 64, 34), Color(0.1, 0.12, 0.16))
			draw_rect(R.call(22, 32, 56, 12), a)
			draw_line(P.call(36, 64), P.call(36, 86), c, lw)
			draw_line(P.call(64, 64), P.call(64, 86), c, lw)
		"ribbon_board":
			draw_rect(R.call(6, 40, 88, 20), c)
			for i in 4:
				draw_rect(R.call(12 + i * 20, 45, 14, 10), a if i % 2 == 0 else Color(0.2, 0.4, 0.9))
		"scoreboard":
			draw_rect(R.call(14, 22, 72, 44), c)
			draw_rect(R.call(20, 28, 60, 32), Color(0.1, 0.12, 0.16))
			_text("1-0", P.call(50, 52), 26 * k, a)
			draw_line(P.call(50, 66), P.call(50, 88), c, lw)
		"sound_system":
			draw_rect(R.call(20, 22, 30, 56), c)
			draw_circle(P.call(35, 38), 8 * k, Color(0.1, 0.12, 0.16))
			draw_circle(P.call(35, 62), 11 * k, Color(0.1, 0.12, 0.16))
			for i in 3:
				draw_arc(P.call(52, 50), (14 + i * 11) * k, -0.8, 0.8, 12, a, lw * 0.8)
		"exec_boxes":
			draw_rect(R.call(8, 30, 84, 40), dim)
			for i in 4:
				draw_rect(R.call(13 + i * 20, 36, 15, 24), a)
			draw_rect(R.call(8, 70, 84, 6), c)
		"car_park", "garage":
			draw_rect(R.call(18, 18, 64, 64), Color(0.2, 0.45, 0.9), true)
			_text("P", P.call(50, 66), 52 * k, Color.WHITE)
			if id == "garage":
				draw_line(P.call(18, 88), P.call(82, 88), c, lw)
				draw_line(P.call(26, 94), P.call(74, 94), c, lw)
		"bus_stop":
			draw_rect(R.call(14, 28, 72, 40), c)
			draw_rect(R.call(20, 34, 18, 14), Color(0.2, 0.3, 0.4))
			draw_rect(R.call(42, 34, 18, 14), Color(0.2, 0.3, 0.4))
			draw_rect(R.call(64, 34, 16, 26), Color(0.2, 0.3, 0.4))
			draw_circle(P.call(30, 70), 7 * k, Color(0.15, 0.15, 0.15))
			draw_circle(P.call(70, 70), 7 * k, Color(0.15, 0.15, 0.15))
		"train_station", "subway":
			draw_rect(R.call(22, 14, 56, 62), c, true)
			draw_rect(R.call(28, 22, 44, 22), Color(0.2, 0.3, 0.4))
			draw_circle(P.call(36, 60), 5 * k, a)
			draw_circle(P.call(64, 60), 5 * k, a)
			draw_line(P.call(30, 76), P.call(18, 92), c, lw)
			draw_line(P.call(70, 76), P.call(82, 92), c, lw)
			if id == "subway":
				draw_rect(R.call(36, 0, 28, 14), Color(0.9, 0.2, 0.2))
				_text("M", P.call(50, 12), 14 * k, Color.WHITE)
		"statue":
			draw_rect(R.call(30, 70, 40, 16), dim)
			draw_circle(P.call(50, 22), 9 * k, c)
			draw_line(P.call(50, 30), P.call(50, 56), c, lw * 1.6)
			draw_line(P.call(50, 36), P.call(32, 20), c, lw)
			draw_line(P.call(50, 36), P.call(68, 20), c, lw)
			draw_line(P.call(50, 56), P.call(40, 70), c, lw)
			draw_line(P.call(50, 56), P.call(60, 70), c, lw)
		"ticket_office":
			draw_rect(R.call(14, 30, 72, 40), a)
			draw_circle(P.call(14, 50), 8 * k, Color(0, 0, 0, 0))
			draw_line(P.call(62, 30), P.call(62, 70), Color(0.1, 0.1, 0.1, 0.5), lw * 0.6)
			_text("TICKET", P.call(38, 55), 12 * k, Color(0.1, 0.1, 0.1))
		"museum":
			draw_colored_polygon(PackedVector2Array([P.call(10, 34), P.call(50, 12), P.call(90, 34)]), c)
			for i in 5:
				draw_rect(R.call(16 + i * 15, 38, 8, 36), c)
			draw_rect(R.call(10, 76, 80, 8), c)
		"hotel":
			draw_rect(R.call(26, 10, 48, 80), c)
			for yy in 5:
				for xx in 3:
					draw_rect(R.call(32 + xx * 13, 18 + yy * 14, 8, 8), a)
		"kiosk":
			# burger
			draw_arc(P.call(50, 50), 30 * k, PI, TAU, 16, a, 12 * k)
			draw_rect(R.call(20, 52, 60, 8), Color(0.45, 0.25, 0.12))
			draw_rect(R.call(18, 61, 64, 5), Color(0.3, 0.7, 0.3))
			draw_rect(R.call(22, 67, 56, 10), a)
		"bar":
			draw_colored_polygon(PackedVector2Array([P.call(28, 20), P.call(72, 20), P.call(66, 84), P.call(34, 84)]), Color(1.0, 0.75, 0.2, 0.9))
			draw_rect(R.call(28, 14, 44, 12), Color(1, 1, 1, 0.95))
			draw_line(P.call(72, 36), P.call(84, 40), c, lw)
			draw_line(P.call(84, 40), P.call(82, 64), c, lw)
			draw_line(P.call(82, 64), P.call(68, 66), c, lw)
		"restroom":
			_text("WC", P.call(50, 64), 44 * k, c)
		"first_aid":
			draw_rect(R.call(16, 16, 68, 68), Color.WHITE)
			draw_rect(R.call(42, 26, 16, 48), Color(0.85, 0.1, 0.1))
			draw_rect(R.call(26, 42, 48, 16), Color(0.85, 0.1, 0.1))
		"merch":
			# shirt
			draw_colored_polygon(PackedVector2Array([P.call(34, 16), P.call(14, 28), P.call(22, 44), P.call(30, 40), P.call(30, 86),
				P.call(70, 86), P.call(70, 40), P.call(78, 44), P.call(86, 28), P.call(66, 16), P.call(58, 22), P.call(42, 22)]), a)
			draw_rect(R.call(46, 30, 8, 40), Color(1, 1, 1, 0.8))
		"fan_zone":
			draw_line(P.call(30, 88), P.call(30, 14), c, lw)
			draw_colored_polygon(PackedVector2Array([P.call(30, 14), P.call(80, 26), P.call(30, 40)]), a)
			draw_circle(P.call(62, 66), 9 * k, c)
			draw_circle(P.call(80, 72), 7 * k, dim)
		"select":
			draw_colored_polygon(PackedVector2Array([P.call(26, 12), P.call(26, 80), P.call(42, 64), P.call(54, 90), P.call(64, 86), P.call(52, 60), P.call(74, 60)]), c)
		"stands_cat":
			for i in 3:
				draw_rect(R.call(10 + i * 26, 70 - i * 20, 80 - i * 26, 18), c)
			draw_rect(R.call(6, 18, 88, 6), a)
		"bowl_cat":
			draw_rect(R.call(10, 18, 80, 44), c)
			draw_rect(R.call(16, 24, 68, 32), Color(0.1, 0.12, 0.16))
			draw_rect(R.call(22, 34, 56, 12), a)
			draw_line(P.call(50, 62), P.call(50, 86), c, lw)
		"transport_cat":
			draw_rect(R.call(10, 30, 80, 38), c)
			draw_rect(R.call(16, 36, 18, 14), Color(0.2, 0.3, 0.4))
			draw_rect(R.call(40, 36, 18, 14), Color(0.2, 0.3, 0.4))
			draw_rect(R.call(64, 36, 18, 14), Color(0.2, 0.3, 0.4))
			draw_circle(P.call(28, 72), 8 * k, a)
			draw_circle(P.call(72, 72), 8 * k, a)
		"around_cat":
			draw_rect(R.call(18, 30, 30, 58), c)
			draw_rect(R.call(52, 16, 30, 72), dim)
			for yy in 4:
				draw_rect(R.call(58, 24 + yy * 14, 6, 6), a)
				draw_rect(R.call(70, 24 + yy * 14, 6, 6), a)
		"food_cat":
			draw_arc(P.call(50, 50), 30 * k, PI, TAU, 16, a, 12 * k)
			draw_rect(R.call(20, 52, 60, 8), Color(0.45, 0.25, 0.12))
			draw_rect(R.call(22, 62, 56, 10), a)
		"services_cat":
			_text("WC", P.call(50, 64), 40 * k, c)
		"shops_cat":
			draw_colored_polygon(PackedVector2Array([P.call(34, 16), P.call(14, 28), P.call(22, 44), P.call(30, 40), P.call(30, 86),
				P.call(70, 86), P.call(70, 40), P.call(78, 44), P.call(86, 28), P.call(66, 16), P.call(58, 22), P.call(42, 22)]), a)
		"land_cat":
			draw_rect(R.call(14, 14, 72, 72), Color(0, 0, 0, 0), false, lw)
			draw_rect(R.call(30, 30, 40, 40), Color(0.35, 0.7, 0.3))
			for d in [[50, 4, 50, 22], [50, 96, 50, 78], [4, 50, 22, 50], [96, 50, 78, 50]]:
				draw_line(P.call(d[0], d[1]), P.call(d[2], d[3]), a, lw)
		"looks_cat":
			draw_circle(P.call(50, 50), 34 * k, c)
			for i in 5:
				var ang := TAU * i / 5.0 - PI / 2
				draw_circle(P.call(50 + cos(ang) * 18, 50 + sin(ang) * 18), 9 * k,
					[Color(0.9, 0.2, 0.2), Color(1, 0.8, 0.2), Color(0.2, 0.7, 0.3), Color(0.2, 0.5, 0.95), Color(0.8, 0.3, 0.8)][i])
		"layer_stadium":
			draw_arc(P.call(50, 62), 38 * k, PI, TAU, 20, c, lw * 1.6)
			draw_rect(R.call(20, 60, 60, 16), Color(0.35, 0.7, 0.3))
			draw_line(P.call(12, 62), P.call(12, 82), c, lw)
			draw_line(P.call(88, 62), P.call(88, 82), c, lw)
		"layer_concourse":
			for i in 3:
				draw_rect(R.call(14, 24 + i * 22, 72, 12), c if i == 1 else dim)
			draw_circle(P.call(40, 48), 6 * k, a)
			draw_circle(P.call(60, 48), 6 * k, a)
		"layer_underground":
			draw_rect(R.call(8, 30, 84, 6), Color(0.35, 0.7, 0.3))
			draw_rect(R.call(8, 38, 84, 50), Color(0.45, 0.32, 0.22))
			draw_rect(R.call(30, 52, 40, 26), Color(0.2, 0.45, 0.9))
			_text("P", P.call(50, 74), 24 * k, Color.WHITE)
		"crest":
			draw_colored_polygon(PackedVector2Array([P.call(14, 10), P.call(86, 10), P.call(86, 50), P.call(50, 92), P.call(14, 50)]), a)
			draw_colored_polygon(PackedVector2Array([P.call(22, 18), P.call(78, 18), P.call(78, 48), P.call(50, 82), P.call(22, 48)]), c)
			draw_rect(R.call(44, 18, 12, 64), a)
		"coin":
			draw_circle(P.call(50, 50), 38 * k, Color(1.0, 0.78, 0.25))
			draw_circle(P.call(50, 50), 30 * k, Color(0.95, 0.68, 0.15))
			_text("£", P.call(50, 66), 42 * k, Color(1, 0.95, 0.7))
		"fans":
			for i in 3:
				var x := 26 + i * 24
				draw_circle(P.call(x, 34), 11 * k, c if i == 1 else dim)
				draw_arc(P.call(x, 80), 20 * k, PI, TAU, 12, c if i == 1 else dim, 14 * k)
		"mood_good", "mood_ok", "mood_bad":
			var col: Color = { "mood_good": Color(0.4, 0.9, 0.4), "mood_ok": Color(1.0, 0.82, 0.3), "mood_bad": Color(1.0, 0.45, 0.35) }[id]
			draw_circle(P.call(50, 50), 40 * k, col)
			draw_circle(P.call(36, 40), 5 * k, Color(0.1, 0.1, 0.1))
			draw_circle(P.call(64, 40), 5 * k, Color(0.1, 0.1, 0.1))
			match id:
				"mood_good": draw_arc(P.call(50, 54), 18 * k, 0.3, PI - 0.3, 12, Color(0.1, 0.1, 0.1), lw)
				"mood_ok": draw_line(P.call(34, 64), P.call(66, 64), Color(0.1, 0.1, 0.1), lw)
				_: draw_arc(P.call(50, 76), 18 * k, PI + 0.3, TAU - 0.3, 12, Color(0.1, 0.1, 0.1), lw)
		"ball":
			draw_circle(P.call(50, 50), 38 * k, Color.WHITE)
			draw_colored_polygon(PackedVector2Array([P.call(50, 36), P.call(63, 45), P.call(58, 60), P.call(42, 60), P.call(37, 45)]), Color(0.1, 0.1, 0.1))
		"capacity":
			for i in 3:
				draw_rect(R.call(12 + i * 26, 70 - i * 18, 76 - i * 26, 14), c)
		"night":
			draw_circle(P.call(50, 50), 34 * k, Color(0.95, 0.92, 0.7))
			draw_circle(P.call(64, 40), 30 * k, Color(0.12, 0.14, 0.2))
		"sunny":
			draw_circle(P.call(50, 50), 22 * k, Color(1.0, 0.82, 0.3))
			for i in 8:
				var ang := TAU * i / 8.0
				draw_line(P.call(50 + cos(ang) * 30, 50 + sin(ang) * 30), P.call(50 + cos(ang) * 42, 50 + sin(ang) * 42), Color(1.0, 0.82, 0.3), lw)
		"cloudy":
			draw_circle(P.call(64, 38), 18 * k, Color(1.0, 0.82, 0.3))
			draw_circle(P.call(38, 58), 18 * k, c)
			draw_circle(P.call(58, 54), 22 * k, c)
			draw_rect(R.call(22, 58, 60, 18), c)
		"overcast":
			draw_circle(P.call(36, 50), 18 * k, dim)
			draw_circle(P.call(60, 44), 24 * k, c)
			draw_rect(R.call(18, 50, 66, 22), c)
		"golden":
			draw_rect(R.call(8, 62, 84, 4), a)
			draw_arc(P.call(50, 64), 24 * k, PI, TAU, 16, Color(1.0, 0.6, 0.25), 14 * k)
		"rain":
			draw_circle(P.call(40, 40), 20 * k, c)
			draw_circle(P.call(60, 36), 24 * k, c)
			for i in 3:
				draw_line(P.call(32 + i * 16, 66), P.call(26 + i * 16, 84), Color(0.4, 0.65, 1.0), lw)
		"snow":
			for i in 3:
				var ang := PI * i / 3.0
				draw_line(P.call(50 - cos(ang) * 34, 50 - sin(ang) * 34), P.call(50 + cos(ang) * 34, 50 + sin(ang) * 34), Color(0.85, 0.92, 1.0), lw)
		"big":
			_star(P.call(50, 52), 38 * k, a)
		"pylons", "roof", "masts":
			draw_rect(R.call(46, 30, 8, 62), c)
			if id == "roof":
				draw_rect(R.call(6, 26, 88, 8), dim)
				for i in 4:
					draw_rect(R.call(14 + i * 20, 34, 12, 8), a)
			elif id == "masts":
				for xx in [18, 74]:
					draw_rect(R.call(xx + 2, 30, 6, 62), c)
					draw_rect(R.call(xx - 6, 18, 22, 12), a)
				draw_rect(R.call(38, 18, 24, 12), a)
			else:
				draw_rect(R.call(30, 8, 40, 24), a)
		"stripes", "wide_stripes", "checks", "plain":
			draw_rect(R.call(10, 18, 80, 64), Color(0.3, 0.6, 0.28))
			match id:
				"stripes":
					for i in 4:
						draw_rect(R.call(10 + i * 20, 18, 10, 64), Color(0.38, 0.7, 0.34))
				"wide_stripes":
					for i in 2:
						draw_rect(R.call(10 + i * 40, 18, 20, 64), Color(0.38, 0.7, 0.34))
				"checks":
					for xx in 4:
						for yy in 3:
							if (xx + yy) % 2 == 0:
								draw_rect(R.call(10 + xx * 20, 18 + yy * 21.3, 20, 21.3), Color(0.38, 0.7, 0.34))
			draw_rect(R.call(10, 18, 80, 64), Color.WHITE, false, lw * 0.6)
			draw_line(P.call(50, 18), P.call(50, 82), Color.WHITE, lw * 0.6)
		"town", "suburban", "city", "city_edge":
			draw_rect(R.call(0, 82, 100, 18), Color(0.35, 0.6, 0.3))
			var hs: Array = { "town": [30, 44, 26, 38], "suburban": [18, 20, 18, 22], "city": [52, 76, 44, 64], "city_edge": [70, 40, 22, 18] }[id]
			for i in 4:
				draw_rect(R.call(6 + i * 23, 82 - hs[i], 18, hs[i]), c if i % 2 == 0 else dim)
		"riverside":
			draw_rect(R.call(0, 50, 100, 50), Color(0.35, 0.6, 0.3))
			draw_rect(R.call(0, 62, 100, 18), Color(0.25, 0.5, 0.75))
			draw_rect(R.call(40, 58, 20, 26), dim)
			draw_rect(R.call(12, 30, 18, 20), c)
			draw_rect(R.call(66, 26, 20, 24), c)
		"lakeside":
			draw_rect(R.call(0, 50, 100, 50), Color(0.35, 0.6, 0.3))
			draw_circle(P.call(62, 72), 26 * k, Color(0.25, 0.5, 0.75))
			draw_circle(P.call(22, 40), 12 * k, Color(0.3, 0.55, 0.28))
		"mountains":
			draw_colored_polygon(PackedVector2Array([P.call(0, 90), P.call(34, 20), P.call(60, 64), P.call(76, 38), P.call(100, 90)]), Color(0.5, 0.5, 0.52))
			draw_colored_polygon(PackedVector2Array([P.call(26, 36), P.call(34, 20), P.call(42, 36)]), Color.WHITE)
		"fields":
			for i in 4:
				draw_rect(R.call(4 + (i % 2) * 48, 24 + (i / 2) * 38, 44, 34), [Color(0.85, 0.75, 0.35), Color(0.45, 0.65, 0.3), Color(0.55, 0.4, 0.25), Color(0.6, 0.72, 0.35)][i])
		"forest":
			for i in 5:
				var x := 12 + i * 19
				draw_colored_polygon(PackedVector2Array([P.call(x - 12, 86), P.call(x, 30 + (i % 2) * 12), P.call(x + 12, 86)]), Color(0.25, 0.5, 0.28))
		"land_N", "land_S", "land_E", "land_W":
			draw_rect(R.call(28, 28, 44, 44), dim)
			var d: Vector2 = { "land_N": Vector2(0, -1), "land_S": Vector2(0, 1), "land_E": Vector2(1, 0), "land_W": Vector2(-1, 0) }[id]
			var c0: Vector2 = Vector2(50, 50) + d * 14
			var tip: Vector2 = Vector2(50, 50) + d * 44
			var side: Vector2 = Vector2(-d.y, d.x) * 14
			draw_colored_polygon(PackedVector2Array([P.call(tip.x, tip.y), P.call(c0.x + side.x, c0.y + side.y), P.call(c0.x - side.x, c0.y - side.y)]), Color(0.5, 0.9, 0.4))
		"rotate":
			draw_arc(P.call(50, 50), 30 * k, 0.4, TAU - 0.6, 24, c, lw)
			draw_colored_polygon(PackedVector2Array([P.call(80, 40), P.call(92, 62), P.call(68, 60)]), c)
		"rotate_l":
			draw_arc(P.call(50, 50), 30 * k, PI + 0.6, PI + TAU - 0.4, 24, c, lw)
			draw_colored_polygon(PackedVector2Array([P.call(20, 40), P.call(8, 62), P.call(32, 60)]), c)
		"diagonal", "diamonds", "circles":
			draw_rect(R.call(10, 18, 80, 64), Color(0.27, 0.5, 0.22))
			match id:
				"circles":
					for r in [12, 22, 32]:
						draw_arc(P.call(50, 50), r * k, 0, TAU, 24, Color(0.4, 0.66, 0.3), 5 * k)
				_:
					for i in range(-4, 5):
						draw_line(P.call(10 + i * 16, 82), P.call(42 + i * 16, 18), Color(0.4, 0.66, 0.3), 7 * k)
					if id == "diamonds":
						for i in range(-4, 5):
							draw_line(P.call(10 + i * 16, 18), P.call(42 + i * 16, 82), Color(0.4, 0.66, 0.3), 7 * k)
					draw_rect(R.call(0, 10, 10, 80), Color(0, 0, 0, 0))
		_ when id.begins_with("grass_"):
			var gcol: Color = { "grass_classic": Color(0.34, 0.51, 0.21), "grass_lush": Color(0.27, 0.53, 0.18), "grass_emerald": Color(0.17, 0.46, 0.22),
				"grass_summer": Color(0.47, 0.52, 0.25), "grass_hybrid": Color(0.21, 0.39, 0.15) }.get(id, Color.GREEN)
			draw_rect(R.call(10, 18, 80, 64), gcol)
			for i in 4:
				draw_rect(R.call(10 + i * 20, 18, 10, 64), gcol.lightened(0.15))
		_ when id.begins_with("ads_"):
			for i in 3:
				var bc: Color = Color.from_hsv(i / 3.0, 0.7, 0.9)
				match id:
					"ads_club": bc = Color(0.8, 0.1, 0.1) if i % 2 == 0 else Color.WHITE
					"ads_sponsor": bc = Color(0.1, 0.35, 0.8)
					"ads_dark": bc = Color(0.08, 0.08, 0.1)
				draw_rect(R.call(8 + i * 29, 40, 26, 20), bc)
				if id == "ads_dark":
					draw_line(P.call(12 + i * 29, 50), P.call(30 + i * 29, 50), Color.from_hsv(i / 3.0, 0.6, 1.0), 3 * k)
		_ when id.begins_with("dug_"):
			var dc := { "dug_perspex": Color(0.75, 0.85, 0.95, 0.7), "dug_brick": Color(0.62, 0.3, 0.22), "dug_stadium": Color(0.8, 0.1, 0.1) }.get(id, Color.WHITE) as Color
			if id == "dug_stadium":
				draw_arc(P.call(50, 70), 36 * k, PI, TAU, 16, dc, 8 * k)
			else:
				draw_rect(R.call(12, 34, 76, 8), dc)
				draw_rect(R.call(12, 34, 8, 40), dc)
				draw_rect(R.call(80, 34, 8, 40), dc)
			for i in 5:
				draw_rect(R.call(22 + i * 12, 62, 8, 10), Color(0.8, 0.1, 0.1))
		_ when id.begins_with("sur_"):
			var sc := { "sur_grass": Color(0.3, 0.45, 0.2), "sur_artificial": Color(0.16, 0.45, 0.22), "sur_track": Color(0.72, 0.26, 0.2), "sur_gravel": Color(0.62, 0.58, 0.52) }.get(id, Color.WHITE) as Color
			draw_rect(R.call(8, 18, 84, 64), sc)
			draw_rect(R.call(24, 32, 52, 36), Color(0.3, 0.55, 0.25))
			if id == "sur_track":
				draw_rect(R.call(14, 24, 72, 52), Color(1, 1, 1, 0.8), false, 1.5 * k)
		_ when id.begins_with("goal_"):
			draw_line(P.call(14, 80), P.call(14, 30), Color.WHITE, lw)
			draw_line(P.call(86, 80), P.call(86, 30), Color.WHITE, lw)
			draw_line(P.call(14, 30), P.call(86, 30), Color.WHITE, lw)
			var depth := { "goal_classic": 10, "goal_box": 18, "goal_stanchion": 24 }.get(id, 10) as int
			for i in range(1, 6):
				draw_line(P.call(14 + i * 12, 30 + depth * 0.3), P.call(14 + i * 12, 80), Color(1, 1, 1, 0.45), 1.5 * k)
			draw_line(P.call(20, 30 + depth * 0.3), P.call(80, 30 + depth * 0.3), Color(1, 1, 1, 0.45), 1.5 * k)
			if id == "goal_stanchion":
				draw_arc(P.call(14, 80), 50 * k, -PI / 2.0, -0.2, 10, Color(0.75, 0.76, 0.78), 2.5 * k)
		_ when id.begins_with("net_"):
			var key := id.substr(4)
			if Color.html_is_valid(key):
				var ncol := Color.html(key)
				draw_rect(R.call(14, 14, 72, 72), Color(0.2, 0.3, 0.2))
				for i in 7:
					draw_line(P.call(14 + i * 12, 14), P.call(14 + i * 12, 86), ncol, 3 * k)
					draw_line(P.call(14, 14 + i * 12), P.call(86, 14 + i * 12), ncol, 3 * k)
			else:
				draw_rect(R.call(14, 14, 72, 72), Color(0.2, 0.3, 0.2))
				match key:
					"hexagon":
						for yy in 4:
							for xx in 4:
								draw_arc(P.call(24 + xx * 17 + (8 if yy % 2 else 0), 24 + yy * 16), 8 * k, 0, TAU, 6, Color.WHITE, 2 * k)
					"striped":
						for i in 6:
							draw_rect(R.call(14 + i * 12, 14, 6, 72), Color(0.85, 0.15, 0.15) if i % 2 == 0 else Color.WHITE)
					_:
						for i in 7:
							draw_line(P.call(14 + i * 12, 14), P.call(14 + i * 12, 86), Color.WHITE, 2 * k)
							draw_line(P.call(14, 14 + i * 12), P.call(86, 14 + i * 12), Color.WHITE, 2 * k)
		"history":
			for i in 4:
				var hh: float = [26.0, 44.0, 36.0, 62.0][i]
				draw_rect(R.call(16 + i * 18, 84 - hh, 13, hh), c)
			draw_polyline(PackedVector2Array([P.call(20, 50), P.call(40, 36), P.call(58, 42), P.call(82, 16)]), Color(1.0, 0.78, 0.25), lw)
		"shirt":
			draw_colored_polygon(PackedVector2Array([P.call(34, 16), P.call(14, 28), P.call(22, 44), P.call(30, 40), P.call(30, 86),
				P.call(70, 86), P.call(70, 40), P.call(78, 44), P.call(86, 28), P.call(66, 16), P.call(58, 22), P.call(42, 22)]), c)
		_:
			pass  # Kenney icons: see _sync_texture()


func _star(centre: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(centre + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, col)


func _text(t: String, baseline_centre: Vector2, px: float, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var fs := maxi(6, int(px))
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, baseline_centre - Vector2(w / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
