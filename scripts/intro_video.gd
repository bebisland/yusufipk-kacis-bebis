extends Control
## First thing on launch: the Seedance opening film, then the maze.
## Space, Enter or Esc skip it.

# Loaded by path only, so an export preset limited to selected scenes would
# leave it out and the game would silently skip the film. Keep "Export all
# resources" or add *.ogv to the preset's include filter.
const VIDEO_PATH := "res://assets/video/intro.ogv"
const GAME := "res://scenes/main.tscn"

@onready var player: VideoStreamPlayer = $Video

var _t := 0.0
var _leaving := false


func _ready() -> void:
	if Autopilot.enabled() or not ResourceLoader.exists(VIDEO_PATH):
		_go.call_deferred()
		return


func _process(delta: float) -> void:
	_t += delta


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _t < 0.5 or not event is InputEventKey:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).physical_keycode
	if k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(GAME)
