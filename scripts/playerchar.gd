extends CharacterBody2D


const SPEED = 64.0

@onready var mainChar_animation: AnimatedSprite2D = $sprite

func _physics_process(delta: float) -> void:
	#player can't move while talking to npc
	if DialogueBox.is_busy():
		velocity = Vector2.ZERO
		mainChar_animation.play("default")
		move_and_slide()
		return

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
		play_animation("walk_", direction)
	else:
		mainChar_animation.play("default")

func play_animation(prefix: String, dir: Vector2) -> void:
	if dir.x > 0:
		mainChar_animation.flip_h = false
		mainChar_animation.play(prefix + "side_right")
	elif dir.x < 0:
		mainChar_animation.flip_h = false
		mainChar_animation.play(prefix + "side_left")
	elif dir.y < 0:
		mainChar_animation.flip_h = false
		mainChar_animation.play(prefix + "up")
	elif dir.y > 0:
		mainChar_animation.flip_h = false
		mainChar_animation.play(prefix + "down")
