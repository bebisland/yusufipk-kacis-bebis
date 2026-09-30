class_name Pickup
extends Area3D
## A key or a spare battery. Bobs and turns in place with a small glow so it
## can be found in the dark; emits `taken` when the player walks into it.

signal taken(pickup: Pickup)

var kind := "key"
var model_path := ""
var glow_color := Color(1.0, 0.75, 0.35)
var size := 0.35

var _t := 0.0
var _pivot := Node3D.new()


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9
	shape.shape = sph
	shape.position.y = 1.0
	add_child(shape)
	_pivot.position.y = 0.9
	add_child(_pivot)
	var model: Node3D = ModelUtil.load_model(model_path)
	if model:
		var meshes: Array[MeshInstance3D] = []
		ModelUtil.collect_meshes(model, meshes)
		ModelUtil.fix_meshy_materials(meshes)
		ModelUtil.fit_height(model, size)
		model.position.y -= size * 0.5
	else:
		model = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size * 0.4, size, size * 0.15)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = glow_color
		mat.metallic = 0.6
		mat.roughness = 0.4
		box.material = mat
		(model as MeshInstance3D).mesh = box
	_pivot.add_child(model)
	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = 0.6
	light.omni_range = 2.2
	light.position.y = 1.0
	add_child(light)
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y += delta * 1.2
	_pivot.position.y = 0.9 + sin(_t * 2.0) * 0.08


func _on_body_entered(body: Node) -> void:
	if body is Player:
		taken.emit(self)
		queue_free()
