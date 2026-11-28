extends Node2D

@export var lines: Array[String] = ["..."]
@export var dialogue: DialogueResource
@export var start_title := "start"

@onready var talk_zone: Area2D = $TalkZone
@onready var prompt: Sprite2D = $InteractPrompt

var player_in_range: bool = false

func _ready() -> void:
	prompt.hide()
	talk_zone.body_entered.connect(_on_body_entered)
	talk_zone.body_exited.connect(_on_body_exited)

# shows the interact icon only while in range and not already talking
func _process(_delta: float) -> void:
	prompt.visible = player_in_range and not DialogueBox.is_busy()

func _on_body_entered(body: Node) -> void:
	# filters for player entry only so other guards and walls don't count
	if body.is_in_group("player"):
		player_in_range = true

func _on_body_exited(body: Node) -> void:
	# same as above
	if body.is_in_group("player"):
		player_in_range = false

# x is used up while in range so a table or the bar next to this npc doesn't open too
func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range:
		return
	if event.is_action_pressed("interact") and not DialogueBox.is_busy():
		if dialogue:
			DialogueBox.start_dialogue_from_file(dialogue, start_title)
		elif not lines.is_empty():
			DialogueBox.start_dialogue(lines)
