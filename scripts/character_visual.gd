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
		var key := StringName("x_" + clip)
		# The library is shared by every instance of the GLB, so after the
		# first round the clip is already there.
		if lib.has_animation(key):
			_clips[clip] = key
			continue
		var tmp: Node = (load(path) as PackedScene).instantiate()
		var ap := _find_anim_player(tmp)
		if ap and ap.get_animation_list().size() > 0:
			var src := ap.get_animation(ap.get_animation_list()[0])
			var src_skel := _find_skeleton(tmp)
			var dst_skel := _find_skeleton(anim_player.get_parent())
			if src_skel and dst_skel:
				src = _retarget(src, src_skel, dst_skel)
			lib.add_animation(key, src)
			_clips[clip] = key
		tmp.free()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


## Each clip comes from a separate auto-rig of the same mesh, and those rigs
## can disagree on bone rest orientation (one came back with the hips turned
## ~117 degrees). Rewrites rotation keys so every bone keeps the same world
## orientation relative to its rest: q_dst = C_parent^-1 * q_src * C_bone,
## with C = global_rest_src^-1 * global_rest_dst. Position keys live in the
## parent's frame, so their offset from rest is turned by C_parent^-1 and
## added to this rig's rest, keeping this rig's bone lengths.
func _retarget(anim: Animation, src: Skeleton3D, dst: Skeleton3D) -> Animation:
	var out := anim.duplicate(true) as Animation
	var corr := {}
	for b in dst.get_bone_count():
		var sb := src.find_bone(dst.get_bone_name(b))
		if sb < 0:
			continue
		var gs := src.get_bone_global_rest(sb).basis.orthonormalized().get_rotation_quaternion()
		var gd := dst.get_bone_global_rest(b).basis.orthonormalized().get_rotation_quaternion()
		corr[b] = gs.inverse() * gd
	for t in out.get_track_count():
		var kind := out.track_get_type(t)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var b := dst.find_bone(String(out.track_get_path(t).get_concatenated_subnames()))
		if b < 0 or not corr.has(b):
			continue
		var p := dst.get_bone_parent(b)
		var pre: Quaternion = (corr[p] as Quaternion).inverse() if corr.has(p) else Quaternion.IDENTITY
		if kind == Animation.TYPE_POSITION_3D:
			var src_rest := src.get_bone_rest(src.find_bone(dst.get_bone_name(b))).origin
			var dst_rest := dst.get_bone_rest(b).origin
			for k in out.track_get_key_count(t):
				var v: Vector3 = out.track_get_key_value(t, k)
				out.track_set_key_value(t, k, dst_rest + pre * (v - src_rest))
			continue
		var post: Quaternion = corr[b]
		for k in out.track_get_key_count(t):
			var q: Quaternion = out.track_get_key_value(t, k)
			out.track_set_key_value(t, k, (pre * q * post).normalized())
	return out


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
