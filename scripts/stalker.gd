class_name Stalker
extends CharacterBody3D
## The thing in the maze. Wanders on the navmesh, walks to where it saw the
## flashlight or heard running, chases on sight and ends the round on touch.
## Every sense and speed scales with Main.level(), which rises with time and
## with each key the player takes.

signal caught
signal state_changed(chasing: bool)

enum State { WANDER, INVESTIGATE, CHASE, SEARCH }

const CATCH_DIST := 1.25
const EYE_HEIGHT := 2.0
const FOV_COS := 0.42  # about 130 degrees wide
const STRIDE := 1.5
const SEARCH_TIME := 9.0
const TURN_RATE := 7.0

var main: Node  # Main; untyped to avoid a class cycle
var player: Player
var state := State.WANDER
var active := false

var _last_seen := Vector3.ZERO
var _lost_t := 0.0
var _search_t := 0.0
var _think_t := 0.0
var _stuck_t := 0.0
var _stride := 0.0
var _speed := 0.0

@onready var agent: NavigationAgent3D = $Agent
@onready var visual: CharacterVisual = $Visual
@onready var steps: AudioStreamPlayer3D = $Steps


func _physics_process(delta: float) -> void:
	if not active:
		visual.set_motion(0.0)
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.1
		_perceive()
	_tick_state(delta)
	_move(delta)
	if global_position.distance_to(player.global_position) < CATCH_DIST and _can_see_point(player.eye_position()):
		active = false
		caught.emit()


func level() -> float:
	return main.level()


func wander_speed() -> float:
	return 1.5 + 0.15 * level()


func chase_speed() -> float:
	return minf(3.9 + 0.4 * level(), 6.2)


func _target_speed() -> float:
	match state:
		State.CHASE:
			return chase_speed()
		State.INVESTIGATE:
			return 2.6 + 0.25 * level()
		State.SEARCH:
			return 2.0 + 0.2 * level()
	return wander_speed()


func is_chasing() -> bool:
	return state == State.CHASE


## Called for each of the player's footsteps; strength is 1 for a sprint
## stride and 0.25 for a walking one.
func hear(pos: Vector3, strength: float) -> void:
	if not active or state == State.CHASE:
		return
	var radius := (13.0 + 2.0 * level()) * strength
	var d := global_position.distance_to(pos)
	# Walls between muffle the sound.
	if not _can_see_point(pos + Vector3.UP * 1.0):
		radius *= 0.7
	if d < radius:
		_investigate(pos)


func _perceive() -> void:
	var L := level()
	var p_eye := player.eye_position()
	var d := global_position.distance_to(player.global_position)
	var sight := 18.0 + 2.0 * L if player.is_lit() else 7.0 + 0.8 * L
	var sees := d < sight and (d < 2.5 or _in_fov(p_eye)) and _can_see_point(p_eye)
	if sees:
		_last_seen = player.global_position
		_lost_t = 0.0
		if state != State.CHASE:
			_set_state(State.CHASE)
		return
	if state == State.CHASE:
		return
	if player.is_lit():
		var lp := player.light_point()
		# Pull the spot a little toward the player so the ray does not end
		# inside the wall it is painted on.
		var probe := lp + (player.eye_position() - lp).normalized() * 0.3
		if global_position.distance_to(lp) < 16.0 + 2.0 * L and _in_fov(probe) and _can_see_point(probe):
			_investigate(player.global_position)


func _tick_state(delta: float) -> void:
	match state:
		State.CHASE:
			var sees_now := _can_see_point(player.eye_position())
			if sees_now:
				_lost_t = 0.0
				_last_seen = player.global_position
			else:
				_lost_t += delta
			# For a moment after losing sight it still knows where the player
			# went, so one corner is not enough to shake it.
			if _lost_t < 1.2 + 0.25 * level():
				agent.target_position = player.global_position
			else:
				_investigate(_last_seen)
		State.SEARCH:
			_search_t -= delta
			if _search_t <= 0.0:
				_set_state(State.WANDER)
			elif agent.is_navigation_finished():
				agent.target_position = main.random_point_near(global_position, 2)
		State.INVESTIGATE:
			if agent.is_navigation_finished():
				_search_t = SEARCH_TIME
				_set_state(State.SEARCH)
		State.WANDER:
			if agent.is_navigation_finished():
				agent.target_position = _pick_wander_target()


func _pick_wander_target() -> Vector3:
	# Drifts toward the player more and more as the round goes on.
	var hunt := clampf(0.2 + 0.12 * level(), 0.0, 0.85)
	if randf() < hunt:
		return main.random_point_near(player.global_position, 3)
	return main.random_point_near(global_position, 6)


func _investigate(pos: Vector3) -> void:
	agent.target_position = pos
	if state != State.INVESTIGATE:
		_set_state(State.INVESTIGATE)


func _set_state(s: State) -> void:
	var was_chasing := state == State.CHASE
	state = s
	if s == State.CHASE and not was_chasing:
		Audio.play("alert", -2.0)
	if (s == State.CHASE) != was_chasing:
		state_changed.emit(s == State.CHASE)


func _move(delta: float) -> void:
	var target_speed := 0.0 if agent.is_navigation_finished() else _target_speed()
	var dir := Vector3.ZERO
	if target_speed > 0.0:
		dir = agent.get_next_path_position() - global_position
		dir.y = 0.0
		dir = dir.normalized()
	_speed = move_toward(_speed, target_speed, 8.0 * delta)
	velocity.x = dir.x * _speed
	velocity.z = dir.z * _speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()

	var hv := Vector3(velocity.x, 0, velocity.z)
	var moved := hv.length()
	if moved > 0.2:
		# The model faces +Z, so yaw = atan2(x, z) points it along the motion.
		rotation.y = lerp_angle(rotation.y, atan2(hv.x, hv.z), TURN_RATE * delta)
	visual.set_motion(moved, 1.6, 4.5)

	# Wedged on a corner or another collider: ask for a fresh path.
	if target_speed > 0.5 and moved < 0.3:
		_stuck_t += delta
		if _stuck_t > 1.0:
			_stuck_t = 0.0
			if state == State.WANDER or state == State.SEARCH:
				agent.target_position = main.random_point_near(global_position, 3)
			else:
				agent.target_position = agent.target_position
	else:
		_stuck_t = 0.0

	_stride += moved * delta
	if _stride > STRIDE:
		_stride = 0.0
		_step_sound()


func _step_sound() -> void:
	var loud := state == State.CHASE
	var s := Audio.stream("stalker_step")
	if not s:
		return
	steps.stream = s
	steps.pitch_scale = randf_range(0.9, 1.05)
	# No real occlusion in the engine; walls in the way just dull the step.
	var blocked := not _can_see_point(player.eye_position())
	steps.volume_db = (2.0 if loud else -4.0) - (7.0 if blocked else 0.0)
	steps.play()


func _in_fov(p: Vector3) -> bool:
	var to := p - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return true
	return global_transform.basis.z.normalized().dot(to.normalized()) > FOV_COS


## Line of sight from the eyes to p against world geometry (layer 1).
func _can_see_point(p: Vector3) -> bool:
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var q := PhysicsRayQueryParameters3D.create(from, p, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
