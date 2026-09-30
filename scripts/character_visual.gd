class_name CharacterVisual
extends Node3D
## Loads a rigged GLB (or a placeholder figure when the file is missing),
## scales it to a target height and drives idle / walk / run clips.

var model_path := ""
var target_height := 2.2
var placeholder_color := Color(0.12, 0.12, 0.13)
## Clip name -> GLB whose single animation shares this model's skeleton.
## The base GLB's own clip is used as "walk".
var extra_anims := {}

var anim_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var _clips := {}
var _current := ""


func _ready() -> void:
	var model: Node3D = ModelUtil.load_model(model_path)
	if not model:
		model = _make_placeholder()
	add_child(model)
	ModelUtil.collect_meshes(model, meshes)
	ModelUtil.fix_meshy_materials(meshes)
	ModelUtil.fit_height(model, target_height)
	anim_player = _find_anim_player(model)
	if anim_player:
		var names := anim_player.get_animation_list()
		if names.size() > 0:
			_clips["walk"] = names[0]
		_merge_extra_anims()
		for clip: StringName in _clips.values():
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _make_placeholder() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = placeholder_color
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = target_height - 0.3
	body.mesh = cap
	body.position.y = cap.height * 0.5
	body.material_override = mat
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.14
	sph.height = 0.34
	head.mesh = sph
	head.position = Vector3(0, target_height - 0.17, 0.02)
	head.material_override = mat
	root.add_child(head)
	return root


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null


func _merge_extra_anims() -> void:
	var lib := anim_player.get_animation_library(&"")
	for clip: String in extra_anims:
		var path: String = extra_anims[clip]
		if not ResourceLoader.exists(path):
			continue
		var tmp: Node = (load(path) as PackedScene).instantiate()
		var ap := _find_anim_player(tmp)
		if ap and ap.get_animation_list().size() > 0:
			var key := StringName("x_" + clip)
			if not lib.has_animation(key):
				lib.add_animation(key, ap.get_animation(ap.get_animation_list()[0]))
			_clips[clip] = key
		tmp.free()


## speed in m/s; idle below a crawl, run once past the walk/run midpoint.
func set_motion(speed: float, walk_speed := 1.6, run_speed := 4.5) -> void:
	if not anim_player or not _clips.has("walk"):
		return
	if speed < 0.15:
		if _clips.has("idle"):
			_play(_clips["idle"], 1.0)
		else:
			_play(_clips["walk"], 0.0)
	elif speed > (walk_speed + run_speed) * 0.5 and _clips.has("run"):
		_play(_clips["run"], clampf(speed / run_speed, 0.6, 1.6))
	else:
		_play(_clips["walk"], clampf(speed / walk_speed, 0.5, 2.2))


func _play(anim: StringName, speed: float) -> void:
	if _current != anim:
		anim_player.play(anim, 0.2)
		_current = anim
	anim_player.speed_scale = speed
