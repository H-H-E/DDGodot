class_name DashCourse
extends RefCounted
## Fixed-step simulation. The renderer never writes these values.
const PLAYER_X := 240.0
const FLOOR_Y := 280.0
const GRAVITY := 1650.0
const JUMP_SPEED := -650.0
const BUFFER_SECONDS := 0.12
var y := FLOOR_Y
var velocity := 0.0
var jump_buffer := 0.0
var gate_x := 1180.0
var obstacle_x := 750.0
var obstacle_kind := 0
var obstacle_active := true
var cleared := false
var waiting := false
var scroll := 0.0
var recovery := 0.0
var collisions := 0
var jumps := 0
var ground_time := 0.0
var rng := RandomNumberGenerator.new()

func reset(seed_value: int) -> void:
	rng.seed = seed_value
	y = FLOOR_Y
	velocity = 0
	jump_buffer = 0
	scroll = 0
	collisions = 0
	jumps = 0
	recovery = 0
	new_gate()

func new_gate() -> void:
	gate_x = 1180
	obstacle_x = 730 + rng.randf_range(-70, 70)
	obstacle_kind = rng.randi_range(0, 2)
	obstacle_active = true
	cleared = false
	waiting = false

func jump() -> void:
	jump_buffer = BUFFER_SECONDS

func clear_gate(auto_jump: bool) -> void:
	cleared = true
	waiting = false
	# Solving the gate dissolves its hazard: maths creates a safe path.
	obstacle_active = false
	if auto_jump:
		jump()

func step(dt: float, duration: float, practice: bool, auto_jump: bool) -> bool:
	var collided := false
	recovery = maxf(0, recovery - dt)
	jump_buffer = maxf(0, jump_buffer - dt)
	var speed := 940.0 / maxf(duration, 2.0)
	if cleared:
		speed = 1200.0
	elif waiting:
		speed = 0
	elif practice:
		speed *= clampf((gate_x - 330.0) / 500.0, 0.0, 1.0)
	gate_x = maxf(-100, gate_x - speed * dt)
	obstacle_x -= speed * dt
	scroll += speed * dt
	if auto_jump and obstacle_active and obstacle_x - PLAYER_X < maxf(10, speed * 0.38) and obstacle_x > PLAYER_X:
		jump()
	if jump_buffer > 0 and y >= FLOOR_Y - 0.1:
		velocity = JUMP_SPEED
		jump_buffer = 0
		jumps += 1
	velocity += GRAVITY * dt
	y = minf(FLOOR_Y, y + velocity * dt)
	if y >= FLOOR_Y:
		velocity = 0
		ground_time += dt
	else:
		ground_time = 0
	# Collision box is smaller than the visible cube; spikes use a narrow core.
	if obstacle_active and recovery <= 0 and absf(obstacle_x - PLAYER_X) < 12 and y > FLOOR_Y - 36:
		collisions += 1
		recovery = 1.2
		obstacle_active = false
		velocity = JUMP_SPEED * 0.7
		collided = true
	return collided

func snapshot() -> Dictionary:
	return {"y": y, "velocity": velocity, "jump_buffer": jump_buffer, "gate_x": gate_x, "obstacle_x": obstacle_x, "obstacle_kind": obstacle_kind, "obstacle_active": obstacle_active, "cleared": cleared, "waiting": waiting, "scroll": scroll, "recovery": recovery, "collisions": collisions, "jumps": jumps, "rng_state": str(rng.state)}

func restore(s: Dictionary) -> void:
	for key in ["y", "velocity", "jump_buffer", "gate_x", "obstacle_x", "obstacle_kind", "obstacle_active", "cleared", "waiting", "scroll", "recovery", "collisions", "jumps"]:
		if s.has(key):
			set(key, s[key])
	y = clampf(y, FLOOR_Y - 300, FLOOR_Y)
	if s.has("rng_state"):
		rng.state = int(s.rng_state)
