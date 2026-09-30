class_name Hud
extends CanvasLayer
## Built in code: key count, timer and best time, battery and stamina bars,
## a vignette that pulses red with the heartbeat, centre messages and the
## end-of-round panel. Also hosts the full-screen escape video.

const VIGNETTE := """
shader_type canvas_item;
uniform float danger = 0.0;
uniform float pulse = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.6;
	float d = length(uv);
	float edge = smoothstep(0.35, 0.95, d);
	float red = clamp(danger * 0.7 + pulse * 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.0), vec3(0.35, 0.0, 0.02), red);
	COLOR = vec4(col, edge * (0.55 + red * 0.4));
}
"""

var _keys: Label
var _time: Label
var _best: Label
var _battery: ColorRect
var _battery_bg: ColorRect
var _stamina: ColorRect
var _msg: Label
var _hint: Label
var _mouse_hint: Label
var _vignette_mat: ShaderMaterial
var _end: Control
var _end_title: Label
var _end_body: Label
var _video: VideoStreamPlayer
var _msg_t := 0.0
var _pulse := 0.0
var _danger := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE
	_vignette_mat.shader = sh
	vig.material = _vignette_mat
	root.add_child(vig)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.35)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	_anchor(dot, 0.5, 0.5, -2, -2, 4, 4)

	_keys = _label(root, 30, Vector2(32, 24))
	_time = _label(root, 30, Vector2.ZERO, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(_time, 1, 0, -332, 24, 300, 40)
	_best = _label(root, 18, Vector2.ZERO, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor(_best, 1, 0, -332, 64, 300, 30)
	_best.modulate.a = 0.7

	var bars := Control.new()
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)
	_anchor(bars, 0, 1, 32, -86, 300, 60)
	_bar_label(bars, "Pil", 0)
	_battery_bg = _bar(bars, Color(1, 1, 1, 0.12), 0)
	_battery = _bar(bars, Color(1.0, 0.86, 0.45, 0.85), 0)
	_bar_label(bars, "Nefes", 32)
	_bar(bars, Color(1, 1, 1, 0.12), 32)
	_stamina = _bar(bars, Color(0.7, 0.85, 1.0, 0.75), 32)

	_msg = _label(root, 34, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_msg, 0.5, 0, -400, 150, 800, 50)
	_msg.modulate.a = 0.0

	_hint = _label(root, 20, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_hint, 0.5, 1, -500, -70, 1000, 30)
	_hint.text = "WASD yürü   Shift koş   F fener   Üç anahtarı bul, kapıdan çık"
	_hint.modulate.a = 0.8

	_mouse_hint = _label(root, 22, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_mouse_hint, 0.5, 0.5, -300, 40, 600, 30)
	_mouse_hint.text = "Fareyi yakalamak için tıkla"
	_mouse_hint.visible = false

	_video = VideoStreamPlayer.new()
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.visible = false
	root.add_child(_video)

	_end = ColorRect.new()
	(_end as ColorRect).color = Color(0, 0, 0, 0.78)
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.visible = false
	root.add_child(_end)
	_end_title = _label(_end, 72, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_end_title, 0.5, 0.5, -500, -150, 1000, 90)
	_end_body = _label(_end, 28, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	_anchor(_end_body, 0.5, 0.5, -500, -30, 1000, 200)


## Pins c to one anchor point of its parent with an offset and a size.
func _anchor(c: Control, ax: float, ay: float, ox: float, oy: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_top = oy
	c.offset_right = ox + w
	c.offset_bottom = oy + h


func _label(parent: Control, font_size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(200, 40)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.9, 0.88, 0.84))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar_label(parent: Control, text: String, y: float) -> void:
	var l := _label(parent, 16, Vector2(0, y - 2))
	l.text = text


func _bar(parent: Control, color: Color, y: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = Vector2(64, y + 6)
	r.size = Vector2(220, 10)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


static func fmt_time(t: float) -> String:
	if t < 0.0:
		return "--:--"
	# Round to tenths first so 59.97 carries into the minutes.
	var d := roundi(t * 10.0)
	return "%02d:%02d.%d" % [d / 600, (d / 10) % 60, d % 10]


func set_stats(keys: int, total: int, elapsed: float, best: float, battery: float, stamina: float) -> void:
	_keys.text = "Anahtar %d/%d" % [keys, total]
	_time.text = fmt_time(elapsed)
	_best.text = "En kısa kaçış " + fmt_time(best)
	_battery.size.x = 220.0 * battery
	_battery.color = Color(1.0, 0.86, 0.45, 0.85) if battery > 0.2 else Color(1.0, 0.35, 0.25, 0.9)
	_stamina.size.x = 220.0 * stamina


func set_danger(d: float) -> void:
	_danger = d


func pulse() -> void:
	_pulse = 1.0


func message(text: String, duration := 2.5) -> void:
	_msg.text = text
	_msg_t = duration


func set_mouse_hint(on: bool) -> void:
	_mouse_hint.visible = on and not _end.visible


func show_end(title: String, body: String, color: Color) -> void:
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", color)
	_end_body.text = body + "\n\nYeniden başlamak için R"
	_end.visible = true
	_mouse_hint.visible = false
	_hint.visible = false


## Full-screen video over the game; calls `done` when it ends or is skipped.
func play_video(stream: VideoStream, done: Callable) -> void:
	_video.stream = stream
	_video.visible = true
	_video.finished.connect(func() -> void: _stop_video(done), CONNECT_ONE_SHOT)
	_video.play()


func video_playing() -> bool:
	return _video.visible


func skip_video() -> void:
	if _video.visible:
		_video.stop()
		_video.finished.emit()


func _stop_video(done: Callable) -> void:
	_video.visible = false
	done.call()


func _process(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	_vignette_mat.set_shader_parameter("danger", _danger)
	_vignette_mat.set_shader_parameter("pulse", _pulse)
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if _hint.visible:
		_hint.modulate.a = maxf(0.0, _hint.modulate.a - delta * 0.06)
