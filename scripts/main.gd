extends Node3D
## Builds a fresh maze every round, places the keys, batteries, lamps, exit
## door and stalker, bakes the navmesh and runs the round: three keys open
## the door, walking out of it wins, the stalker's touch loses. Only the
## shortest escape time is saved.

const CELL := 4.0
const WALL_H := 3.4
const WALL_T := 0.4
const MAZE_W := 10
const MAZE_H := 10
const KEY_COUNT := 3
const BATTERY_COUNT := 3
const LAMP_COUNT := 7
## The stalker waits this long before it starts moving.
const GRACE := 4.0
const DOOR_GAP := 2.0
const SAVE_PATH := "user://save.cfg"

const TEX_WALL := "res://assets/textures/wall.png"
const TEX_FLOOR := "res://assets/textures/floor.png"
const TEX_CEIL := "res://assets/textures/ceiling.png"
const MODEL_STALKER := "res://assets/models/stalker.glb"
const MODEL_STALKER_RUN := "res://assets/models/stalker_run.glb"
const MODEL_STALKER_IDLE := "res://assets/models/stalker_idle.glb"
const MODEL_KEY := "res://assets/models/key.glb"
const MODEL_BATTERY := "res://assets/models/battery.glb"
const MODEL_DOOR := "res://assets/models/door.glb"
const MODEL_FLASHLIGHT := "res://assets/models/flashlight.glb"
const ESCAPE_VIDEO := "res://assets/video/escape.ogv"

enum Phase { PLAY, CAUGHT, ESCAPED }

var maze: MazeGen
var phase := Phase.PLAY
var keys_taken := 0
var elapsed := 0.0
var best_time := -1.0

var player: Player
var stalker: Stalker
var hud: Hud
var nav: NavigationRegion3D
var door: Node3D
var door_shape: CollisionShape3D
var exit_goal := Vector3.ZERO

var _start_cell := Vector2i.ZERO
var _exit_cell := Vector2i.ZERO
## Unit step from the exit cell out through the door.
var _exit_out := Vector2i.ZERO
var _used := {}
var _lamps: Array[OmniLight3D] = []
var _heart_t := 0.0
var _auto_restart := -1.0
var _rng := RandomNumberGenerator.new()
var _bot_seen := {}


func _ready() -> void:
	_rng.randomize()
	Engine.time_scale = Autopilot.time_scale()
	_load_best()
	maze = MazeGen.new(MAZE_W, MAZE_H, _rng.randi())
	_build_environment()
	nav = NavigationRegion3D.new()
	add_child(nav)
	_build_floor_and_ceiling()
	_place_start_and_exit()
	_build_walls()
	_bake_nav()
	_spawn_player()
	_place_items()
	_spawn_stalker()
	_place_lamps()
	hud = Hud.new()
	add_child(hud)
	Audio.music()
	if not Autopilot.enabled():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().create_timer(GRACE, false).timeout.connect(func() -> void: stalker.active = phase == Phase.PLAY)


## Difficulty: one step per key plus one every 90 seconds.
func level() -> float:
	return keys_taken + elapsed / 90.0


func cell_pos(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func pos_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, MAZE_W - 1), clampi(int(p.z / CELL), 0, MAZE_H - 1))


func random_point_near(p: Vector3, radius_cells: int) -> Vector3:
	var c := pos_cell(p)
	var n := Vector2i(
		clampi(c.x + _rng.randi_range(-radius_cells, radius_cells), 0, MAZE_W - 1),
		clampi(c.y + _rng.randi_range(-radius_cells, radius_cells), 0, MAZE_H - 1))
	return cell_pos(n) + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))


# --- building ---------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.45)
	env.ambient_light_energy = 0.06
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.55, 0.57, 0.6)
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_ambient_inject = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0, 0, 0)
	env.fog_density = 0.02
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _material(tex_path: String, fallback: Color, tile_m: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	else:
		m.albedo_color = fallback
	# World-space triplanar mapping keeps the tiling scale identical on every
	# wall length, so merged wall runs do not stretch the texture.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.roughness = 0.92
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _build_floor_and_ceiling() -> void:
	var size := Vector3((MAZE_W + 2) * CELL, 0.2, (MAZE_H + 2) * CELL)
	var centre := Vector3(MAZE_W * CELL * 0.5, 0, MAZE_H * CELL * 0.5)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = centre + Vector3(0, -0.1, 0)
	_add_box(floor_body, Vector3.ZERO, size, _material(TEX_FLOOR, Color(0.25, 0.24, 0.23), 3.0))
	nav.add_child(floor_body)
	var ceil_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(TEX_CEIL, Color(0.14, 0.14, 0.15), 3.0)
	ceil_mesh.mesh = box
	ceil_mesh.position = centre + Vector3(0, WALL_H + 0.1, 0)
	add_child(ceil_mesh)


func _add_box(body: StaticBody3D, pos: Vector3, size: Vector3, mat: Material, with_mesh := true) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	if with_mesh:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		mi.position = pos
		body.add_child(mi)
	return cs


func _place_start_and_exit() -> void:
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(MAZE_W - 1, 0), Vector2i(0, MAZE_H - 1), Vector2i(MAZE_W - 1, MAZE_H - 1)]
	_start_cell = corners[_rng.randi() % corners.size()]
	_used[_start_cell] = true
	var dist := maze.distances(_start_cell)
	# Exit: one of the three border cells furthest from the start.
	var border: Array[Vector2i] = []
	for c: Vector2i in dist:
		if c.x == 0 or c.y == 0 or c.x == MAZE_W - 1 or c.y == MAZE_H - 1:
			border.append(c)
	border.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return dist[a] > dist[b])
	var exit_cell := border[_rng.randi() % mini(3, border.size())]
	_used[exit_cell] = true
	var out := Vector2i.ZERO
	if exit_cell.x == 0:
		out = Vector2i(-1, 0)
	elif exit_cell.x == MAZE_W - 1:
		out = Vector2i(1, 0)
	elif exit_cell.y == 0:
		out = Vector2i(0, -1)
	else:
		out = Vector2i(0, 1)
	# Remove that border wall; _build_walls puts stubs and the door back.
	if out.x != 0:
		maze.v[exit_cell.x + maxi(out.x, 0)][exit_cell.y] = false
	else:
		maze.hw[exit_cell.x][exit_cell.y + maxi(out.y, 0)] = false
	_exit_cell = exit_cell
	_exit_out = out


func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	nav.add_child(body)
	var mat := _material(TEX_WALL, Color(0.35, 0.22, 0.18), 3.0)
	# Merge runs of wall segments on each grid line into single boxes.
	for y in MAZE_H + 1:
		var x := 0
		while x < MAZE_W:
			if not maze.hw[x][y]:
				x += 1
				continue
			var x0 := x
			while x < MAZE_W and maze.hw[x][y]:
				x += 1
			var length := (x - x0) * CELL + WALL_T
			_add_box(body, Vector3((x0 + x) * 0.5 * CELL, WALL_H * 0.5, y * CELL), Vector3(length, WALL_H, WALL_T), mat)
	for x in MAZE_W + 1:
		var y := 0
		while y < MAZE_H:
			if not maze.v[x][y]:
				y += 1
				continue
			var y0 := y
			while y < MAZE_H and maze.v[x][y]:
				y += 1
			var length := (y - y0) * CELL + WALL_T
			_add_box(body, Vector3(x * CELL, WALL_H * 0.5, (y0 + y) * 0.5 * CELL), Vector3(WALL_T, WALL_H, length), mat)
	_build_exit(body, mat)


## Door frame stubs on the border, the door itself, and a short dead-end
## corridor outside with a cold light and the win trigger.
func _build_exit(body: StaticBody3D, mat: Material) -> void:
	var out := Vector3(_exit_out.x, 0, _exit_out.y)
	var side := Vector3(-out.z, 0, out.x)
	var edge := cell_pos(_exit_cell) + out * CELL * 0.5
	var stub := (CELL - DOOR_GAP) * 0.5
	for s in [-1.0, 1.0]:
		var p: Vector3 = edge + side * s * (DOOR_GAP * 0.5 + stub * 0.5)
		_add_box(body, p + Vector3(0, WALL_H * 0.5, 0), _oriented(Vector3(stub + WALL_T, WALL_H, WALL_T), side), mat)
	# Outside corridor: two side walls and an end wall, one cell deep.
	var mid := edge + out * CELL * 0.5
	for s in [-1.0, 1.0]:
		var p: Vector3 = mid + side * s * CELL * 0.5
		_add_box(body, p + Vector3(0, WALL_H * 0.5, 0), _oriented(Vector3(WALL_T, WALL_H, CELL), side), mat)
	_add_box(body, edge + out * CELL + Vector3(0, WALL_H * 0.5, 0), _oriented(Vector3(CELL + WALL_T, WALL_H, WALL_T), side), mat)

	door = Node3D.new()
	door.name = "Door"
	door.position = edge
	# The model's front (+Z) faces into the maze.
	door.rotation.y = atan2(-out.x, -out.z)
	var door_body := StaticBody3D.new()
	door.add_child(door_body)
	door_shape = _add_box(door_body, Vector3(0, WALL_H * 0.5, 0), Vector3(DOOR_GAP, WALL_H, 0.3), null, false)
	var model: Node3D = ModelUtil.load_model(MODEL_DOOR)
	if model:
		var meshes: Array[MeshInstance3D] = []
		ModelUtil.collect_meshes(model, meshes)
		ModelUtil.fix_meshy_materials(meshes)
		ModelUtil.fit_height(model, WALL_H - 0.1)
	else:
		model = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(DOOR_GAP, WALL_H, 0.25)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.2, 0.14)
		m.metallic = 0.5
		m.roughness = 0.6
		bm.material = m
		(model as MeshInstance3D).mesh = bm
		model.position.y = WALL_H * 0.5
	door.add_child(model)
	nav.add_child(door)

	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.75, 1.0)
	glow.light_energy = 1.4
	glow.omni_range = 6.0
	glow.position = mid + Vector3(0, WALL_H - 0.5, 0)
	add_child(glow)

	exit_goal = mid
	var win := Area3D.new()
	win.collision_layer = 0
	win.collision_mask = 2
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL * 0.8, 2.5, CELL * 0.8)
	cs.shape = shape
	win.add_child(cs)
	win.position = mid + out * 0.6 + Vector3(0, 1.25, 0)
	win.body_entered.connect(func(b: Node) -> void:
		if b is Player:
			_escape())
	add_child(win)


## Box sizes are given along (side, up, out); rotate to world axes.
func _oriented(size_side_up_out: Vector3, side: Vector3) -> Vector3:
	if absf(side.x) > 0.5:
		return size_side_up_out
	return Vector3(size_side_up_out.z, size_side_up_out.y, size_side_up_out.x)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Multiples of the 0.25 m voxel so the baker does not round them. The
	# radius is well above the stalker's 0.28 m body because voxel erosion
	# lets paths hug wall ends by about one cell.
	nm.agent_radius = 0.75
	nm.agent_height = 2.25
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


func _spawn_player() -> void:
	player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	player.position = cell_pos(_start_cell) + Vector3(0, 0.05, 0)
	# Face the first open passage.
	for d in MazeGen.DIRS:
		if maze.is_open(_start_cell, _start_cell + d):
			player.rotation.y = atan2(-float(d.x), -float(d.y))
			break
	add_child(player)
	var model: Node3D = ModelUtil.load_model(MODEL_FLASHLIGHT)
	if model:
		var meshes: Array[MeshInstance3D] = []
		ModelUtil.collect_meshes(model, meshes)
		ModelUtil.fix_meshy_materials(meshes)
		for mi in meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Layer 2 only: the flashlight's own beam skips it (cull mask).
			mi.layers = 2
		var hand := player.get_node("Head/Camera/Hand") as Node3D
		ModelUtil.fit_height(model, 0.07)
		# The mesh lies along X with the lens at -X; turn the lens to -Z.
		var pivot := Node3D.new()
		pivot.rotation.y = -PI / 2.0
		pivot.position.y = -0.035
		pivot.add_child(model)
		hand.add_child(pivot)
		# Spill from the lens, lighting only the hand-held model.
		var spill := OmniLight3D.new()
		spill.light_cull_mask = 2
		spill.light_color = Color(1.0, 0.9, 0.75)
		spill.light_energy = 0.5
		spill.omni_range = 0.5
		spill.position = Vector3(0, 0.05, -0.2)
		hand.add_child(spill)


func _place_items() -> void:
	var dist := maze.distances(_start_cell)
	# Keys: spread out, each far from the start and from the keys before it.
	var chosen: Array[Vector2i] = [_start_cell]
	var dists: Array[Dictionary] = [dist]
	for i in KEY_COUNT:
		var scored: Array = []
		for c: Vector2i in dist:
			if _used.has(c) or dist[c] < 4:
				continue
			var m := 1 << 30
			for d in dists:
				m = mini(m, d[c])
			scored.append([m, c])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var pick: Vector2i = scored[_rng.randi() % mini(4, scored.size())][1]
		chosen.append(pick)
		dists.append(maze.distances(pick))
		_used[pick] = true
		_spawn_pickup("key", pick, MODEL_KEY, Color(1.0, 0.72, 0.3), 0.35)
	var free: Array[Vector2i] = []
	for c: Vector2i in dist:
		if not _used.has(c) and dist[c] >= 3:
			free.append(c)
	for i in BATTERY_COUNT:
		if free.is_empty():
			break
		var c: Vector2i = free.pop_at(_rng.randi() % free.size())
		_used[c] = true
		_spawn_pickup("battery", c, MODEL_BATTERY, Color(0.5, 1.0, 0.55), 0.3)


func _spawn_pickup(kind: String, c: Vector2i, model: String, color: Color, size: float) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.model_path = model
	p.glow_color = color
	p.size = size
	p.position = cell_pos(c)
	p.add_to_group(kind + "s")
	p.taken.connect(_on_pickup)
	add_child(p)


func _spawn_stalker() -> void:
	var dist := maze.distances(_start_cell)
	var far := 0
	for c: Vector2i in dist:
		far = maxi(far, dist[c])
	var options: Array[Vector2i] = []
	for c: Vector2i in dist:
		if dist[c] >= int(far * 0.6) and c != _exit_cell:
			options.append(c)
	stalker = (load("res://scenes/stalker.tscn") as PackedScene).instantiate()
	var vis := stalker.get_node("Visual") as CharacterVisual
	vis.model_path = MODEL_STALKER
	# Rest-pose height; the hunched walk clip carries it at about 2 m.
	vis.target_height = 2.4
	vis.extra_anims = {"run": MODEL_STALKER_RUN, "idle": MODEL_STALKER_IDLE}
	stalker.main = self
	stalker.player = player
	stalker.position = cell_pos(options[_rng.randi() % options.size()])
	add_child(stalker)
	if FileAccess.file_exists("user://stalkercam"):
		# Dev only: watch the stalker from over its shoulder.
		var cam := Camera3D.new()
		cam.position = Vector3(0.6, 2.6, -2.6)
		cam.rotation_degrees = Vector3(-15, 180, 0)
		stalker.add_child(cam)
		cam.make_current.call_deferred()
		var l := OmniLight3D.new()
		l.position = Vector3(0, 2.5, 1.2)
		l.omni_range = 5.0
		stalker.add_child(l)
	player.noise.connect(stalker.hear)
	stalker.caught.connect(_on_caught)
	stalker.state_changed.connect(func(chasing: bool) -> void:
		if chasing:
			Audio.music(-20.0, 0.5)
		else:
			Audio.music())


func _place_lamps() -> void:
	var cells: Array[Vector2i] = []
	for x in MAZE_W:
		for y in MAZE_H:
			cells.append(Vector2i(x, y))
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.7, 0.4)
	bulb_mat.emission_energy_multiplier = 3.0
	bulb_mat.albedo_color = Color(1.0, 0.8, 0.6)
	for i in LAMP_COUNT:
		var c: Vector2i = cells.pop_at(_rng.randi() % cells.size())
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.38)
		l.light_energy = 0.9
		l.omni_range = 5.5
		l.shadow_enabled = true
		l.position = cell_pos(c) + Vector3(0, WALL_H - 0.45, 0)
		l.set_meta("base", l.light_energy)
		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		s.material = bulb_mat
		bulb.mesh = s
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.add_child(bulb)
		add_child(l)
		_lamps.append(l)


# --- round ------------------------------------------------------------------

func _on_pickup(p: Pickup) -> void:
	if phase != Phase.PLAY:
		return
	if p.kind == "battery":
		player.add_battery(0.45)
		Audio.play("battery", -4.0)
		hud.message("Pil")
		return
	keys_taken += 1
	Audio.play("key", -2.0)
	if keys_taken < KEY_COUNT:
		hud.message("Anahtar %d/%d" % [keys_taken, KEY_COUNT])
	else:
		hud.message("Çıkış kapısı açıldı", 4.0)
		_open_door()


func _open_door() -> void:
	Audio.play("door", 0.0, 0.0)
	door_shape.set_deferred("disabled", true)
	var t := create_tween()
	t.tween_property(door, "position:y", WALL_H - 0.2, 2.5).set_trans(Tween.TRANS_SINE)


func _on_caught() -> void:
	if phase != Phase.PLAY:
		return
	phase = Phase.CAUGHT
	player.can_move = false
	Audio.play("caught", 0.0, 0.0)
	Audio.music(-40.0, 1.0)
	# Snap the view onto the stalker's face.
	var face := stalker.global_position + Vector3.UP * 2.0
	var t := create_tween().set_parallel()
	var look := player.global_transform.looking_at(Vector3(face.x, player.global_position.y, face.z))
	t.tween_property(player, "rotation:y", look.basis.get_euler().y, 0.25)
	t.tween_property(player.head, "rotation:x", 0.25, 0.25)
	hud.set_danger(1.0)
	hud.show_end("YAKALANDIN", "Hayatta kaldığın süre %s   Anahtar %d/%d" % [Hud.fmt_time(elapsed), keys_taken, KEY_COUNT], Color(0.9, 0.2, 0.18))
	_round_over("caught")


func _escape() -> void:
	if phase != Phase.PLAY or keys_taken < KEY_COUNT:
		return
	phase = Phase.ESCAPED
	player.can_move = false
	stalker.active = false
	var record := best_time < 0.0 or elapsed < best_time
	if record:
		best_time = elapsed
		_save_best()
	var body := "Kaçış süren %s\nEn kısa kaçış %s" % [Hud.fmt_time(elapsed), Hud.fmt_time(best_time)]
	if record:
		body += "\nYeni rekor!"
	var show := func() -> void:
		Audio.play("escape", -2.0, 0.0)
		Audio.music()
		hud.show_end("KAÇTIN", body, Color(0.75, 0.9, 1.0))
	if ResourceLoader.exists(ESCAPE_VIDEO) and not Autopilot.enabled():
		Audio.music(-30.0, 1.0)
		hud.play_video(load(ESCAPE_VIDEO), show)
	else:
		show.call()
	_round_over("escaped")


func _round_over(result: String) -> void:
	print("ROUND %s time=%.1f keys=%d level=%.2f" % [result, elapsed, keys_taken, level()])
	if Autopilot.enabled():
		_auto_restart = 2.0


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_time = float(cf.get_value("best", "escape_time", -1.0))


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("best", "escape_time", best_time)
	cf.save(SAVE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() and phase == Phase.PLAY:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud.video_playing():
		if k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			hud.skip_video()
		return
	if k == KEY_R and phase != Phase.PLAY:
		_restart()


func _restart() -> void:
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if phase == Phase.PLAY:
		elapsed += delta
	hud.set_stats(keys_taken, KEY_COUNT, elapsed, best_time, player.battery, player.stamina)
	hud.set_mouse_hint(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and phase == Phase.PLAY and not Autopilot.enabled())
	_flicker_lamps()
	if phase == Phase.PLAY:
		_heartbeat(delta)
	if _auto_restart > 0.0:
		_auto_restart -= delta
		if _auto_restart <= 0.0:
			_restart()


func _physics_process(delta: float) -> void:
	if phase != Phase.PLAY or not Autopilot.enabled():
		return
	Autopilot.drive(player, _bot_goal(), stalker, delta)


## Plays like someone who does not know the map: heads for a pickup only
## once it is close, otherwise explores the nearest unvisited cell.
func _bot_goal() -> Vector3:
	_bot_seen[pos_cell(player.global_position)] = true
	if stalker.is_chasing():
		# Run for whichever nearby cell is furthest from the stalker.
		var pc := pos_cell(player.global_position)
		var far := -1.0
		var flee := player.global_position
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var c := pc + Vector2i(dx, dy)
				if maze.in_bounds(c):
					var d := cell_pos(c).distance_to(stalker.global_position)
					if d > far:
						far = d
						flee = cell_pos(c)
		return flee
	if keys_taken >= KEY_COUNT:
		return exit_goal
	var groups: Array[StringName] = [&"keys"]
	if player.battery < 0.3:
		groups.push_front(&"batterys")
	for g in groups:
		for n: Node3D in get_tree().get_nodes_in_group(g):
			if n.global_position.distance_to(player.global_position) < 7.0:
				return n.global_position
	var best := INF
	var goal := exit_goal
	for x in MAZE_W:
		for y in MAZE_H:
			var c := Vector2i(x, y)
			if _bot_seen.has(c):
				continue
			var d := cell_pos(c).distance_to(player.global_position)
			if d < best:
				best = d
				goal = cell_pos(c)
	return goal


## Heartbeat speeds up and the vignette reddens as the stalker gets close,
## and jumps when it is chasing.
func _heartbeat(delta: float) -> void:
	var d := player.global_position.distance_to(stalker.global_position)
	var danger := clampf(1.0 - (d - 3.0) / 22.0, 0.0, 1.0)
	if stalker.is_chasing():
		danger = maxf(danger, 0.75)
	hud.set_danger(danger * 0.8)
	if danger < 0.08:
		_heart_t = 0.0
		return
	_heart_t -= delta
	if _heart_t <= 0.0:
		_heart_t = lerpf(1.25, 0.36, danger)
		Audio.play("heartbeat", lerpf(-20.0, 0.0, danger), 0.0)
		hud.pulse()


func _flicker_lamps() -> void:
	for l in _lamps:
		var base: float = l.get_meta("base")
		if randf() < 0.02:
			l.light_energy = base * randf_range(0.1, 0.6)
		else:
			l.light_energy = lerpf(l.light_energy, base, 0.2)
