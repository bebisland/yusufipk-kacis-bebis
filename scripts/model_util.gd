class_name ModelUtil
extends RefCounted


## Instantiates a GLB, or returns null when the file is missing.
static func load_model(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()


## Meshy binds the albedo map as the emissive map too, which makes models glow,
## and leaves the metallic factor at the glTF default of 1, which makes cloth
## look like chrome. Materials are shared by every instance of the GLB.
static func fix_meshy_materials(meshes: Array[MeshInstance3D]) -> void:
	for mi in meshes:
		if not mi.mesh:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat:
				mat.emission_enabled = false
				mat.metallic = 0.0
				mat.roughness = 0.85


static func collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		collect_meshes(c, out)


## Scales `model` so its mesh bounds are `height` tall, centred on x/z and
## standing on y = 0. Returns the resulting footprint radius.
static func fit_height(model: Node3D, height: float) -> float:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(model, meshes)
	var aabb := AABB()
	var first := true
	for mi in meshes:
		# Skinned meshes are drawn through their bones, which already place the
		# vertices at the size stored in the mesh; node scales above them
		# (Meshy's 0.01 Armature) do not apply.
		var box := mi.get_aabb() if mi.skin else _relative_xform(mi, model) * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	if first or aabb.size.y <= 0.001:
		return 0.5
	var s := height / aabb.size.y
	model.scale = Vector3.ONE * s
	var c := aabb.get_center()
	model.position = Vector3(-c.x * s, -aabb.position.y * s, -c.z * s)
	return maxf(aabb.size.x, aabb.size.z) * s * 0.5


static func _relative_xform(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
