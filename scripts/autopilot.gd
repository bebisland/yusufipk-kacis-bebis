class_name Autopilot
extends RefCounted
## Debug-only bot used to measure round length while tuning difficulty.
## Enabled by creating user://autopilot; never active in a normal install.
## A number in the file sets Engine.time_scale for faster runs.

const FLAG_PATH := "user://autopilot"

static var _cached := -1


static func enabled() -> bool:
	if _cached < 0:
		_cached = 1 if FileAccess.file_exists(FLAG_PATH) else 0
	return _cached == 1


static func time_scale() -> float:
	if not enabled():
		return 1.0
	var t := FileAccess.get_file_as_string(FLAG_PATH).strip_edges()
	return clampf(t.to_float(), 1.0, 4.0) if t.is_valid_float() else 1.0


## Walks the navmesh to `goal`, sprinting when the stalker is on its heels.
## Keeps the flashlight on only while the battery is healthy.
static func drive(player: Player, goal: Vector3, stalker: Stalker, delta: float) -> void:
	var map := player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, player.global_position, goal, true)
	var next := goal
	for p in path:
		if Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() > 0.6:
			next = p
			break
	var to := next - player.global_position
	to.y = 0.0
	if to.length() > 0.05:
		var yaw := atan2(-to.x, -to.z)
		player.rotation.y = lerp_angle(player.rotation.y, yaw, 10.0 * delta)
	player.bot_input = Vector2(0, -1)
	var d := player.global_position.distance_to(stalker.global_position)
	player.bot_sprint = stalker.is_chasing() and d < 14.0
	if player.is_lit() != (player.battery > 0.12) and player.battery > 0.0:
		player.toggle_light()
