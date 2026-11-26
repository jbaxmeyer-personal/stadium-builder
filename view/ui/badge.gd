extends Control
## The club crest, drawn from ClubState.badge: an outline shape split by a
## pattern in the club's colours, a band with the initials, a symbol, stars
## over the top, and the founding year. Or the player's own uploaded PNG.
## Badge.bake(club) renders it to a texture for the 3D world (roof crests,
## video boards, seat mosaics, flags).

const SHAPES := ["shield", "round", "classic", "diamond", "square", "pennant"]
const PATTERNS := ["plain", "halves", "quarters", "stripes", "hoops", "chevron", "sash", "cross", "border"]
const SYMBOLS := ["none", "ball", "star", "crown", "lion", "bird", "tower", "anchor", "oak", "rose", "bolt", "wheel"]

var club: ClubState
var _logo: Texture2D


func _init(p_club: ClubState = null) -> void:
	club = p_club
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh() -> void:
	_logo = null
	queue_redraw()


static func load_logo(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Outline of a shape in a unit box (0..1).
static func outline(shape: String) -> PackedVector2Array:
	var p := PackedVector2Array()
	match shape:
		"round":
			for i in 48:
				var a := TAU * i / 48.0
				p.append(Vector2(0.5 + cos(a) * 0.48, 0.5 + sin(a) * 0.48))
		"diamond":
			p = PackedVector2Array([Vector2(0.5, 0.02), Vector2(0.95, 0.5), Vector2(0.5, 0.98), Vector2(0.05, 0.5)])
		"square":
			p = PackedVector2Array([Vector2(0.08, 0.08), Vector2(0.92, 0.08), Vector2(0.92, 0.92), Vector2(0.08, 0.92)])
		"pennant":
			p = PackedVector2Array([Vector2(0.1, 0.05), Vector2(0.9, 0.05), Vector2(0.9, 0.55), Vector2(0.5, 0.97), Vector2(0.1, 0.55)])
		"classic":
			# a curly-topped heater shield
			p.append(Vector2(0.06, 0.12))
			for i in 9:
				var t := float(i) / 8.0
				p.append(Vector2(0.06 + t * 0.88, 0.12 - sin(t * PI * 2.0) * 0.05 + (0.05 if i % 4 == 2 else 0.0)))
			for i in 13:
				var t := float(i) / 12.0
				var a := t * PI
				p.append(Vector2(0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.47 * (0.6 + 0.4 * t)))
		_:  # shield
			p.append(Vector2(0.08, 0.06))
			p.append(Vector2(0.92, 0.06))
			p.append(Vector2(0.92, 0.5))
			for i in 13:
				var t := float(i) / 12.0
				var a := t * PI
				p.append(Vector2(0.5 + cos(a) * 0.42, 0.5 + sin(a) * 0.46))
			p.append(Vector2(0.08, 0.5))
	return p


func _draw() -> void:
	if club == null:
		return
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var logo_path: String = club.badge.get("logo", "")
	if logo_path != "":
		if _logo == null:
			_logo = load_logo(logo_path)
		if _logo:
			draw_texture_rect(_logo, Rect2(o, Vector2(s, s)), false)
			return
	draw_badge(self, club, Rect2(o, Vector2(s, s)))


## Draws the badge into any CanvasItem, filling rect r.
static func draw_badge(ci: CanvasItem, club: ClubState, r: Rect2) -> void:
	var b := club.badge
	var shape: String = b.get("shape", "shield")
	var swap: bool = b.get("swap", false)
	var c1 := club.secondary_color if swap else club.primary_color
	var c2 := club.primary_color if swap else club.secondary_color
	var c3 := club.third_color
	var P := func(v: Vector2) -> Vector2: return r.position + v * r.size
	var shp := outline(shape)
	var pts := PackedVector2Array()
	for v in shp:
		pts.append(P.call(v))
	# rim, then the field
	var rim := PackedVector2Array()
	var c: Vector2 = P.call(Vector2(0.5, 0.5))
	for v in pts:
		rim.append(c + (v - c) * 1.06)
	ci.draw_colored_polygon(rim, c3)
	ci.draw_colored_polygon(pts, c1)
	# the pattern: the second colour, clipped to the shape
	var pat: String = b.get("pattern", "plain")
	var clip := func(poly: PackedVector2Array) -> void:
		for piece in Geometry2D.intersect_polygons(poly, pts):
			ci.draw_colored_polygon(piece, c2)
	var R := func(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
		return PackedVector2Array([P.call(Vector2(x0, y0)), P.call(Vector2(x1, y0)), P.call(Vector2(x1, y1)), P.call(Vector2(x0, y1))])
	match pat:
		"halves": clip.call(R.call(0.5, 0, 1, 1))
		"quarters":
			clip.call(R.call(0.5, 0, 1, 0.5))
			clip.call(R.call(0, 0.5, 0.5, 1))
		"stripes":
			for i in range(1, 10, 2):
				clip.call(R.call(i * 0.1, 0, i * 0.1 + 0.1, 1))
		"hoops":
			for i in range(1, 10, 2):
				clip.call(R.call(0, i * 0.1, 1, i * 0.1 + 0.1))
		"chevron":
			clip.call(PackedVector2Array([P.call(Vector2(0, 0.55)), P.call(Vector2(0.5, 0.3)), P.call(Vector2(1, 0.55)), P.call(Vector2(1, 0.72)), P.call(Vector2(0.5, 0.47)), P.call(Vector2(0, 0.72))]))
		"sash":
			clip.call(PackedVector2Array([P.call(Vector2(0, 0.0)), P.call(Vector2(0.2, 0.0)), P.call(Vector2(1, 0.8)), P.call(Vector2(1, 1.0)), P.call(Vector2(0.8, 1.0)), P.call(Vector2(0, 0.2))]))
		"cross":
			clip.call(R.call(0.42, 0, 0.58, 1))
			clip.call(R.call(0, 0.36, 1, 0.52))
		"border":
			var inner := PackedVector2Array()
			for v in pts:
				inner.append(c + (v - c) * 0.82)
			ci.draw_colored_polygon(pts, c2)
			ci.draw_colored_polygon(inner, c1)
	# symbol in the middle
	var sym: String = b.get("symbol", "ball")
	_symbol(ci, sym, P.call(Vector2(0.5, 0.6)), r.size.x * 0.2, c2 if pat == "plain" or pat == "border" else c3, c1)
	# the initials on a band near the top
	var text := club.initials()
	if text != "":
		var band: PackedVector2Array = R.call(0.12, 0.16, 0.88, 0.34)
		for piece in Geometry2D.intersect_polygons(band, pts):
			ci.draw_colored_polygon(piece, c3)
		var font := ThemeDB.fallback_font
		var fs := int(r.size.y * (0.14 if text.length() <= 3 else 0.11))
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, P.call(Vector2(0.5, 0.31)) - Vector2(tw / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c2 if c3.get_luminance() < 0.5 else c1)
	# stars over the top (titles won)
	var stars: int = b.get("stars", 0)
	for i in stars:
		var sx := 0.5 + (i - (stars - 1) / 2.0) * 0.14
		_star(ci, P.call(Vector2(sx, -0.04)), r.size.x * 0.05, Color(1.0, 0.8, 0.25))
	# the founding year along the bottom
	if shape != "diamond":
		var font2 := ThemeDB.fallback_font
		var fy := str(club.founded)
		var fs2 := int(r.size.y * 0.075)
		var w2 := font2.get_string_size(fy, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var at: Vector2 = P.call(Vector2(0.5, 0.87)) - Vector2(w2 / 2.0, 0)
		ci.draw_string_outline(font2, at, fy, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, maxi(2, fs2 / 4), c3)
		ci.draw_string(font2, at, fy, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, c2 if c2.get_luminance() > c3.get_luminance() + 0.2 else Color.WHITE)


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)


static func _symbol(ci: CanvasItem, sym: String, c: Vector2, r: float, col: Color, back: Color) -> void:
	match sym:
		"ball":
			ci.draw_circle(c, r, col)
			var pent := PackedVector2Array()
			for i in 5:
				var a := -PI / 2.0 + TAU * i / 5.0
				pent.append(c + Vector2(cos(a), sin(a)) * r * 0.38)
			ci.draw_colored_polygon(pent, back)
		"star":
			_star(ci, c, r * 1.2, col)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r * 0.6), c + Vector2(-r, -r * 0.3), c + Vector2(-r * 0.5, r * 0.1), c + Vector2(0, -r * 0.7),
				c + Vector2(r * 0.5, r * 0.1), c + Vector2(r, -r * 0.3), c + Vector2(r, r * 0.6)]), col)
		"lion":
			ci.draw_circle(c + Vector2(0, -r * 0.2), r * 0.7, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.8, r), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.4, 0), c + Vector2(r * 0.8, r)]), col)
			ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.1, back)
			ci.draw_circle(c + Vector2(r * 0.25, -r * 0.3), r * 0.1, back)
		"bird":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.2, -r * 0.3), c + Vector2(0, r * 0.2), c + Vector2(r * 1.2, -r * 0.3), c + Vector2(r * 0.2, r * 0.6), c + Vector2(0, r), c + Vector2(-r * 0.2, r * 0.6)]), col)
		"tower":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.4), Vector2(r * 1.2, r * 1.4)), col)
			for i in 3:
				ci.draw_rect(Rect2(c + Vector2(-r * 0.6 + i * r * 0.45, -r * 0.75), Vector2(r * 0.3, r * 0.4)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.15, r * 0.3), Vector2(r * 0.3, r * 0.7)), back)
		"anchor":
			ci.draw_line(c + Vector2(0, -r), c + Vector2(0, r), col, r * 0.22)
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.55), c + Vector2(r * 0.5, -r * 0.55), col, r * 0.2)
			ci.draw_arc(c + Vector2(0, r * 0.2), r * 0.8, 0.2, PI - 0.2, 12, col, r * 0.2)
		"oak":
			ci.draw_circle(c + Vector2(0, -r * 0.3), r * 0.75, col)
			ci.draw_circle(c + Vector2(-r * 0.5, 0), r * 0.5, col)
			ci.draw_circle(c + Vector2(r * 0.5, 0), r * 0.5, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.12, r * 0.2), Vector2(r * 0.24, r * 0.8)), col)
		"rose":
			for i in 5:
				var a := TAU * i / 5.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.5, r * 0.45, col)
			ci.draw_circle(c, r * 0.3, back)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.3, -r), c + Vector2(-r * 0.5, r * 0.1), c + Vector2(0, r * 0.1), c + Vector2(-r * 0.3, r), c + Vector2(r * 0.5, -r * 0.1), c + Vector2(0, -r * 0.1)]), col)
		"wheel":
			ci.draw_arc(c, r * 0.85, 0, TAU, 24, col, r * 0.2)
			for i in 6:
				var a := TAU * i / 6.0
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.8, col, r * 0.12)


## Renders the badge (or the uploaded logo) into a texture for the 3D world.
static func bake(club: ClubState, tree: SceneTree, px := 256) -> Texture2D:
	var logo := load_logo(String(club.badge.get("logo", "")))
	if logo:
		return logo
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var b := preload("res://view/ui/badge.gd").new(club)
	b.size = Vector2(px, px)
	vp.add_child(b)
	tree.root.add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)
