extends CanvasLayer

#Text and Advance labels accessed as unique names
@onready var dialogue_container = $DialogueContainer
@onready var text = %Text
@onready var advance_symbol = %Advance


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	hide_dialogue()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func show_dialogue():
	dialogue_container.show

func hide_dialogue():
	text.text = ""
	advance_symbol.text = ""
	dialogue_container.hide()
