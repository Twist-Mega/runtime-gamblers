
extends CanvasLayer

const CHAR_READ_RATE = 0.0275

#Text and Advance labels accessed as unique names
@onready var dialogue_container = $DialogueContainer
@onready var text = %Text
@onready var advance_symbol = %Advance

enum State {
	READY,
	READING,
	FINISHED
}

var current_state = State.READY
var tween

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Starting state: State.READY")
	hide_dialogue()
	add_dialogue("Lorem ipsum and much adieu")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	match current_state:
		State.READY:
			pass
		State.READING:
			if Input.is_action_just_pressed("ui_accept"):
				text.visible_ratio = 1.0
				tween.kill()
				advance_symbol.text = "$"
				change_state(State.FINISHED)
		State.FINISHED:
			if Input.is_action_just_pressed("ui_accept"):
				change_state(State.READY)
				hide_dialogue()

func show_dialogue():
	dialogue_container.show()

func hide_dialogue():
	text.text = ""
	advance_symbol.text = ""
	dialogue_container.hide()

func add_dialogue(next):
	text.text = next
	text.visible_ratio = 0.0
	change_state(State.READING)
	show_dialogue()
	tween = create_tween()
	tween.tween_property(text, "visible_ratio", 1.0, len(next) * CHAR_READ_RATE).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_Tween_tween_all_completed)

func _on_Tween_tween_all_completed():
	advance_symbol.text = "$"
	change_state(State.FINISHED)

func change_state(next_state):
	current_state = next_state
	match current_state:
		State.READY:
			print("Changing state to: State.READY")
		State.READING:
			print("Changing state to: State.READING")
		State.FINISHED:
			print("Changing state to: State.FINISHED")
