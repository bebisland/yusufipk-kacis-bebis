class_name Player
extends CharacterBody3D
## First-person player: WASD + mouse, Shift to sprint on a stamina budget,
## F toggles a flashlight whose battery drains while it is on. Every stride
## emits a noise the stalker can hear; sprinting is far louder.

signal noise(pos: Vector3, radius: float)

const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.6
const ACCEL := 11.0
const MOUSE_SENS := 0.0022
const STRIDE_WALK := 2.1
const STRIDE_RUN := 2.7
## Full sprint lasts this long; stamina comes back after a short pause.
const SPRINT_TIME := 6.0
const RECOVER_TIME := 6.0
const RECOVER_DELAY := 0.8
## Seconds of light in a full battery.
const BATTERY_LIFE := 170.0
const LOW_BATTERY := 0.2
const BEAM_RANGE := 16.0

var can_move := true
var stamina := 1.0
var battery := 1.0
var light_on := true
var sprinting := false
## Sprint is locked out after emptying stamina until it refills past this.
var _exhausted := false
var _recover_wait := 0.0
var _stride := 0.0
var _bob_t := 0.0
var _flicker_t := 0.0
## Set by the autopilot instead of keyboard/mouse.
var bot_input := Vector2.ZERO
var bot_sprint := false

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera
@onready var flashlight: SpotLight3D = $Head/Camera/Flashlight
@onready var beam: RayCast3D = $Head/Camera/Beam


func _ready() -> void:
	beam.target_position = Vector3(0, 0, -BEAM_RANGE)
	beam.add_exception(self)
	_apply_light()


func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		rotate_y(-m.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - m.relative.y * MOUSE_SENS, -1.45, 1.45)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_F:
			toggle_light()


func toggle_light() -> void:
	if battery <= 0.0:
		light_on = false
	else:
		light_on = not light_on
	Audio.play("click", -6.0)
	_apply_light()


func add_battery(amount: float) -> void:
	battery = minf(1.0, battery + amount)
	_apply_light()


## Where the beam lands (wall, floor or its far end); what the stalker can
## spot from around a corner.
func light_point() -> Vector3:
	if beam.is_colliding():
		return beam.get_collision_point()
	return beam.to_global(beam.target_position)


func eye_position() -> Vector3:
	return cam.global_position


func is_lit() -> bool:
	return light_on and battery > 0.0


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	var want_sprint := false
	if can_move:
		if Autopilot.enabled():
			input = bot_input
			want_sprint = bot_sprint
		else:
			input = Vector2(
				float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
				float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
			want_sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	input = input.limit_length(1.0)

	sprinting = want_sprint and input.y < -0.1 and not _exhausted and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - delta / SPRINT_TIME)
		_recover_wait = RECOVER_DELAY
		if stamina <= 0.0:
			_exhausted = true
	else:
		_recover_wait -= delta
		if _recover_wait <= 0.0:
			stamina = minf(1.0, stamina + delta / RECOVER_TIME)
		if _exhausted and stamina > 0.3:
			_exhausted = false

	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var dir := (transform.basis * Vector3(input.x, 0, input.y)) * speed
	velocity.x = move_toward(velocity.x, dir.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z, ACCEL * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	_footsteps(hspeed * delta)
	_head_bob(hspeed, delta)
	_update_battery(delta)


func _footsteps(moved: float) -> void:
	if moved <= 0.0:
		return
	_stride += moved
	var stride := STRIDE_RUN if sprinting else STRIDE_WALK
	if _stride < stride:
		return
	_stride = 0.0
	if sprinting:
		Audio.play("step_run", -4.0, 0.1)
		noise.emit(global_position, 1.0)
	else:
		Audio.play("step_walk", -12.0, 0.1)
		noise.emit(global_position, 0.25)


func _head_bob(hspeed: float, delta: float) -> void:
	var amount := clampf(hspeed / SPRINT_SPEED, 0.0, 1.0)
	_bob_t += delta * hspeed * 2.2
	var target := Vector3(cos(_bob_t * 0.5) * 0.03 * amount, 1.6 + sin(_bob_t) * 0.045 * amount, 0)
	head.position = head.position.lerp(target, 10.0 * delta)


func _update_battery(delta: float) -> void:
	if light_on and battery > 0.0:
		battery = maxf(0.0, battery - delta / BATTERY_LIFE)
		if battery <= 0.0:
			light_on = false
			Audio.play("click", -6.0)
	_flicker_t -= delta
	if _flicker_t <= 0.0:
		_flicker_t = randf_range(0.04, 0.12)
		_apply_light()


func _apply_light() -> void:
	flashlight.visible = is_lit()
	if not flashlight.visible:
		return
	var e := 4.0
	if battery < LOW_BATTERY:
		# Weaker and stuttering as it runs out.
		e *= lerpf(0.35, 1.0, battery / LOW_BATTERY)
		if randf() < lerpf(0.35, 0.05, battery / LOW_BATTERY):
			e *= randf_range(0.0, 0.3)
	flashlight.light_energy = e
