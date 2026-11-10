extends CharacterBody2D

# ---------- CONSTANTES ----------
const SPEED = 120.0
const JUMP_VELOCITY = -290.0   # altura MÁXIMA (manteniendo presionado). Antes: -250
const JUMP_CUT = 0.4           # al soltar antes, la subida se multiplica por esto
const JUMP_DELAY = 0.08        # segundos de espera antes de despegar del suelo
const MID_THRESHOLD = -80.0
const AIR_GRACE = 0.15         # segundos sin tocar suelo antes de contar como "en el aire"
const FALL_GRAVITY_SCALE = 0.75  # 1.0 = caída normal, menos = cae más lento

# Wall jump
const WALL_SLIDE_SPEED = 50.0  # velocidad máxima de caída pegado a la pared
const WALL_JUMP_X = 130.0      # empuje horizontal al separarse de la pared
const WALL_JUMP_LOCK = 0.15    # segundos sin control horizontal tras el wall jump
const WALL_ANIM = "jump_end"   # PLACEHOLDER: cámbialo a "wall_slide" cuando tengas el sprite

# ---------- REFERENCIAS Y VARIABLES ----------
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var col_ground: CollisionShape2D = $CollisionGround
@onready var col_air: CollisionShape2D = $CollisionAir

var air_phase := ""
var winding_up := false
var windup_time := 0.0
var off_floor_time := 0.0
var airborne := false
var wall_sliding := false
var wall_lock := 0.0

func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("left", "right")

	# 1. Detectar pared (solo paredes realmente verticales y en el aire)
	var wall_dir := 0
	if is_on_wall_only() and airborne:
		var n := get_wall_normal()
		if abs(n.y) < 0.1:
			wall_dir = -int(sign(n.x))   # hacia dónde está la pared
	var touching_wall := wall_dir != 0 and int(sign(direction)) == wall_dir
	wall_sliding = touching_wall and velocity.y > 0.0

	# 2. Gravedad (más suave al caer, con límite si te deslizas por la pared)
	if not is_on_floor():
		var g := get_gravity() * delta
		if velocity.y > 0.0:
			g *= FALL_GRAVITY_SCALE
		velocity += g
		if wall_sliding:
			velocity.y = min(velocity.y, WALL_SLIDE_SPEED)

	# 3. Salto
	if Input.is_action_just_pressed("jump") and touching_wall:
		# Wall jump: sin retraso, te empuja lejos de la pared
		var away := get_wall_normal().x
		velocity.y = JUMP_VELOCITY
		velocity.x = away * WALL_JUMP_X
		wall_lock = WALL_JUMP_LOCK
		wall_sliding = false
		air_phase = "up"
		anim.flip_h = away < 0     # mira hacia el lado contrario a la pared
		anim.play("jump_up")
	elif Input.is_action_just_pressed("jump") and is_on_floor() and not winding_up:
		# Salto normal: arranca la animación y despega después del retraso
		winding_up = true
		windup_time = JUMP_DELAY
		air_phase = "up"
		anim.play("jump_up")

	# 4. Soltar el botón mientras sube = salto más corto
	#    (va ANTES del bloque de despegue para no cortar dos veces)
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	# 5. Cuenta regresiva y despegue del salto normal
	if winding_up:
		windup_time -= delta
		if windup_time <= 0.0:
			winding_up = false
			velocity.y = JUMP_VELOCITY
			off_floor_time = AIR_GRACE + 0.01   # cuenta como aire de inmediato
			if not Input.is_action_pressed("jump"):
				velocity.y *= JUMP_CUT

	# 6. Movimiento horizontal (bloqueado un instante tras el wall jump)
	if wall_lock > 0.0:
		wall_lock -= delta
	else:
		velocity.x = direction * SPEED
		if direction != 0:
			anim.flip_h = direction < 0

	move_and_slide()

	# 7. Estado de "en el aire" filtrado (evita el temblor en rampas)
	if is_on_floor():
		off_floor_time = 0.0
	else:
		off_floor_time += delta
	airborne = off_floor_time > AIR_GRACE

	_update_collider()
	_update_animation()

# ---------- COLLIDER ----------
func _update_collider() -> void:
	col_ground.set_deferred("disabled", airborne)
	col_air.set_deferred("disabled", not airborne)

# ---------- ANIMACIONES ----------
func _update_animation() -> void:
	if winding_up:
		return   # la animación de salto ya está corriendo

	# Deslizándose por la pared
	if wall_sliding:
		air_phase = "end"
		if anim.animation != WALL_ANIM:
			anim.play(WALL_ANIM)
		return

	# En el suelo
	if not airborne:
		air_phase = ""
		if velocity.x != 0:
			anim.play("walk")
		else:
			anim.play("idle")
		return

	# En el aire sin haber saltado (cayó de un borde o rampa)
	if air_phase == "":
		air_phase = "end"
		anim.play("jump_end")

	# Subiendo y ya casi en la cima: transición
	if air_phase == "up" and velocity.y > MID_THRESHOLD:
		air_phase = "mid"
		anim.play("jump_mid")

	# Al soltar la pared, vuelve a la animación de caída normal
	if air_phase == "end" and anim.animation == "wall_slide":
		anim.play("jump_end")

func _on_animation_finished() -> void:
	if anim.animation == "jump_mid":
		air_phase = "end"
		anim.play("jump_end")
