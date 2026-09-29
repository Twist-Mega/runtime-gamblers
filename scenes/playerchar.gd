extends CharacterBody2D


const SPEED = 300.0

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(delta: float) -> void:
	process_movement()
	move_and_slide()


func process_movement() -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	
	# No diagonal movement
	if direction.x != 0:
		direction.y = 0
	else:
		direction.x = 0
	
	velocity = direction * SPEED
	
	process_animation(direction)
	
func process_animation(direction) -> void:
	if velocity != Vector2.ZERO:
		play_animation("move_", direction)
	else:
		play_animation("default", direction)

func play_animation(prefix: String, dir: Vector2) -> void:
	if dir.x > 0:
		animated_sprite_2d.flip_h = dir.x < 0
		animated_sprite_2d.play(prefix + "right")
	elif dir.y < 0:
		animated_sprite_2d.play(prefix + "up")
	elif dir.y > 0:
		animated_sprite_2d.play(prefix + "down")
