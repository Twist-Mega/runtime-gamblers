extends CharacterBody2D


const SPEED = 300.0


func _physics_process(delta: float) -> void:
	process_movement()
	move_and_slide()


func process_movement() -> void:
	var direction := Input.get_vector("left", "right", "up", "down")
	
	velocity = direction * SPEED
