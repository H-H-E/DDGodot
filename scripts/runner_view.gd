class_name DashRunnerView
extends Control
const CourseModel = preload("res://scripts/course.gd")
## Procedural illustration only. Coordinates are projected from DashCourse.
var course: CourseModel
var view_rect := Rect2(0, 0, 1280, 350)
var active := false
var reduced_motion := false
var high_contrast := false
var runner_color := Color("d5ed81")
var effect := 0.0
var pulse := 0.0
var time := 0.0
var label_text := "THE NEXT GATE IS YOURS"
const INK := Color("0a1226")
const MINT := Color("72e4cc")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	clip_contents = true

func _process(delta: float) -> void:
	position = view_rect.position
	size = view_rect.size
	if not reduced_motion:
		time += minf(delta, 0.05)
	effect = maxf(0, effect - delta * 1.8)
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, view_rect.size)
	var w := r.size.x
	var h := r.size.y
	if w <= 0 or h <= 0:
		return
	draw_set_transform(r.position)
	draw_style_box(_panel(Color("101e37"), 18), Rect2(Vector2.ZERO, r.size))
	# Quiet grid and mountain silhouettes give speed a readable reference.
	var offset := fmod(course.scroll * 0.14 if active and course else time * 5, 80)
	for x in range(-1, int(w / 80) + 2):
		draw_line(Vector2(x * 80 - offset, 0), Vector2(x * 80 - offset, h), Color(0.4, 0.65, 0.85, 0.035), 1)
	for j in range(1, 5):
		draw_line(Vector2(0, j * h / 5), Vector2(w, j * h / 5), Color(0.4, 0.65, 0.85, 0.04), 1)
	var floor_y := h * 0.77
	for layer in range(2):
		var pts := PackedVector2Array([Vector2(0, floor_y)])
		for i in range(9):
			var px := float(i) * w / 8
			var peak := floor_y - h * (0.12 + 0.18 * absf(sin(i * 5.72 + layer * 2.4)))
			pts.append(Vector2(px, minf(floor_y - 4, peak + layer * 26)))
		pts.append(Vector2(w, floor_y))
		draw_colored_polygon(pts, Color("162d48") if layer == 0 else Color("1b3850"))
	# Satellite and small stars remain still in reduced-motion mode.
	var moon := Vector2(w * 0.77, h * 0.24)
	draw_circle(moon, h * 0.095, Color("24445a"))
	draw_arc(moon, h * 0.12, -0.4, 2.7, 40, Color("73b9b2"), 1.5, true)
	for i in range(22):
		var star := Vector2(fmod(i * 139.73 + 42, w - 20) + 10, 18 + fmod(i * 47.17, h * 0.48))
		draw_circle(star, 1.3 if i % 5 == 0 else 0.75, Color(0.67, 0.83, 0.9, 0.45))
	# Horizontal runway.
	draw_rect(Rect2(0, floor_y + 2, w, h - floor_y - 2), Color("0b172b"))
	draw_line(Vector2(0, floor_y), Vector2(w, floor_y), MINT if high_contrast else Color("42666e"), 2)
	var tile_offset := fmod(course.scroll if active and course else time * 26, 68)
	for i in range(-1, int(w / 68) + 2):
		var px := float(i) * 68 - tile_offset
		draw_line(Vector2(px, floor_y + 4), Vector2(px - 18, h), Color("172d43"), 1)
	var scale_x := w / 1280.0
	var scale_y := h / 365.0
	var player_x := maxf(72, 240.0 * scale_x)
	var player_y := floor_y
	var s := clampf(h * 0.135, 30, 53)
	if active and course:
		player_y -= (CourseModel.FLOOR_Y - course.y) * scale_y
		var gx := player_x + (course.gate_x - CourseModel.PLAYER_X) * scale_x
		var gate_color := MINT if course.cleared else Color("8da6ef")
		if gx > -50 and gx < w + 50:
			draw_rect(Rect2(gx - 7, floor_y - h * 0.56, 14, h * 0.56), Color(gate_color, 0.12))
			draw_line(Vector2(gx, floor_y - h * 0.56), Vector2(gx, floor_y), gate_color, 3)
			draw_circle(Vector2(gx, floor_y - h * 0.56), 5, gate_color)
			if not course.cleared:
				draw_string(ThemeDB.fallback_font, Vector2(gx - 14, floor_y - h * 0.56 - 16), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, gate_color)
		if course.obstacle_active:
			var ox := player_x + (course.obstacle_x - CourseModel.PLAYER_X) * scale_x
			var os := clampf(37 * scale_y, 20, 42)
			if ox > -40 and ox < w + 40:
				if course.obstacle_kind == 1:
					draw_rect(Rect2(ox - os * 0.55, floor_y - os, os * 1.1, os), Color("ef967b"))
					draw_line(Vector2(ox - os * 0.35, floor_y - os + 6), Vector2(ox + os * 0.35, floor_y - os + 6), INK, 2)
				else:
					draw_colored_polygon(PackedVector2Array([Vector2(ox - os, floor_y), Vector2(ox, floor_y - os), Vector2(ox + os, floor_y)]), Color("ef967b"))
					draw_line(Vector2(ox, floor_y - os + 12), Vector2(ox, floor_y - 8), INK, 2)
	else:
		for j in range(3):
			var bx := w * 0.58 + j * w * 0.14
			draw_rect(Rect2(bx, floor_y - 24 - j * 14, 42, 24 + j * 14), Color("31566b"))
		if not reduced_motion:
			player_y -= absf(sin(time * 1.25)) * h * 0.12
	# Ground shadow; rotation is entirely decorative.
	draw_runner_oval(Vector2(player_x, floor_y + 7), Vector2(s * 0.62, 5), Color(0, 0, 0, 0.2))
	var rot := 0.0
	if active and course and course.y < CourseModel.FLOOR_Y - 2 and not reduced_motion:
		rot = (CourseModel.FLOOR_Y - course.y) / 150 * PI * 0.5
	draw_set_transform(r.position + Vector2(player_x, player_y - s * 0.5), rot)
	var tint := runner_color
	if active and course and course.recovery > 0:
		tint = Color("ffb394")
	draw_style_box(_panel(tint, 5), Rect2(-s * 0.5, -s * 0.5, s, s))
	draw_rect(Rect2(-s * 0.31, -s * 0.31, s * 0.62, s * 0.62), INK, false, 3)
	draw_rect(Rect2(-s * 0.12, -s * 0.12, s * 0.24, s * 0.24), INK)
	draw_set_transform(r.position)
	if effect > 0 and not reduced_motion:
		for i in range(10):
			var a := float(i) * TAU / 10
			var p := Vector2(player_x, player_y - s * 0.5) + Vector2(cos(a), sin(a)) * (1 - effect) * 110
			draw_circle(p, 3 * effect, Color(MINT, effect))
	var font := ThemeDB.fallback_font
	if w > 550:
		draw_string(font, Vector2(22, 28), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9bb5c9"))
	if pulse > 0 and not reduced_motion:
		draw_line(Vector2(1, floor_y), Vector2(w - 1, floor_y), Color(MINT, pulse * 0.4), 3)
	draw_set_transform(Vector2.ZERO)

func draw_runner_oval(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32):
		var a := TAU * i / 32
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)

func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
