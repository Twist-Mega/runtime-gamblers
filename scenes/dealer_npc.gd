extends Node2D

@export var lines: Array[String] = ["..."]

@onready var talk_zone: Area2D = find_child("TalkZone", true, false)

var player_in_range := false

@onready var prompt: Node2D = find_child("InteractPrompt", true, false)

func _ready() -> void:
	if prompt:
		prompt.hide()
	talk_zone.body_entered.connect(_on_body_entered)
	talk_zone.body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	# Show the icon only while in range and not already talking
	if prompt:
		prompt.visible = player_in_range and not DialogueBox.is_busy()

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
