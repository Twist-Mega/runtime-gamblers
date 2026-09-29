extends CharacterBody2D


const SPEED = 300.0


func _physics_process(delta: float) -> void:
	process_movement()
	move_and_slide()


func process_movement() -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if direction.x != 0:
		direction.y = 0
	else:
		direction.x = 0
	
	velocity = direction * SPEED
