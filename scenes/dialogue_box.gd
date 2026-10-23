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
var dialogue_queue = []
var tween

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("Starting state: State.READY")
	hide_dialogue()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	match current_state:
		State.READY:
			if !dialogue_queue.is_empty():
				display_dialogue()
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

# --- Public API (call these from NPCs/objects) ---

# Queue a single line
func queue_dialogue(next_dialogue):
	dialogue_queue.push_back(next_dialogue)

# Queue a whole conversation (e.g. an NPC's exported lines)
func start_dialogue(lines: Array[String]) -> void:
	for line in lines:
		queue_dialogue(line)

# True while a conversation is in progress, so NPCs don't retrigger it
func is_busy() -> bool:
	return current_state != State.READY or !dialogue_queue.is_empty()

# --- Internals ---

func show_dialogue():
	dialogue_container.show()

func hide_dialogue():
	text.text = ""
	advance_symbol.text = ""
	dialogue_container.hide()

func display_dialogue():
	var next_dialogue = dialogue_queue.pop_front()
	text.text = next_dialogue
	text.visible_ratio = 0.0
	change_state(State.READING)
	show_dialogue()
	tween = create_tween()
	tween.tween_property(text, "visible_ratio", 1.0, len(next_dialogue) * CHAR_READ_RATE).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
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
