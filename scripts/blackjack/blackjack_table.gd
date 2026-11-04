extends Node2D

signal table_selected(table_id: String, stake_amount: int)

@export var table_id: String = ""
@export var stake_amount: int = 5

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
		if GameState.request_state(GameState.State.TABLE):
			table_selected.emit(table_id, stake_amount)
			get_viewport().set_input_as_handled()
