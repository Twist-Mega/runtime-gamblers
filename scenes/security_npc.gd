extends Node2D
# Attach to the root of security_npc.tscn.
# Needs an Area2D child named "TalkZone" with a CollisionShape2D under it.
# Fill in `lines` on each guard in the Inspector for unique dialogue.

@export var lines: Array[String] = ["..."]

@onready var talk_zone: Area2D = $TalkZone

var player_in_range := false

func _ready() -> void:
	talk_zone.body_entered.connect(_on_body_entered)
	talk_zone.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false

func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range:
		return
	if lines.is_empty():
		return
	if event.is_action_pressed("interact") and not DialogueBox.is_busy():
		DialogueBox.start_dialogue(lines)
