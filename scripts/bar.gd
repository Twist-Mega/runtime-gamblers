extends StaticBody2D

#for UI
@export var bar_ui: Control
var player_in_range: bool = false

func _ready() -> void:
	#body_entered and body_exited are properties of Area2D (interact_zone for the table)
	#Area2D sends body_entered when a physics body overlaps with it
	$interact_zone.body_entered.connect(_on_body_entered)
	$interact_zone.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	#filters for player entry only to set state flag so npcs and walls and stuff dont count
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node) -> void:
	#same as above
	if body.is_in_group("player"):
		player_in_range = false

func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		bar_ui.open()
