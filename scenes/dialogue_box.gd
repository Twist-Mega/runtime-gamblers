extends CanvasLayer

const CHAR_READ_RATE = 0.0275

#Text and Advance labels accessed as unique names
@onready var dialogue_container = $DialogueContainer
@onready var text = %Text
@onready var advance_symbol = %Advance

var dialogue_resource: DialogueResource
var current_line
var in_dialogue := false

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
func _process(_delta: float) -> void:
	match current_state:
		State.READY:
			if !dialogue_queue.is_empty():
				display_dialogue()
		State.READING:
			if advance_pressed():
				text.visible_ratio = 1.0
				tween.kill()
				advance_symbol.modulate.a = 1.0
				change_state(State.FINISHED)
		State.FINISHED:
			if advance_pressed():
				if in_dialogue:
					_advance_dialogue()
				else:
					change_state(State.READY)
					hide_dialogue()

# True when the player presses a button that skips/advances dialogue
func advance_pressed() -> bool:
	return Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact")

# ----Public API

# Queue a single line
func queue_dialogue(next_dialogue):
	dialogue_queue.push_back(next_dialogue)

# Queue a whole conversation (e.g. an NPC's exported lines)
func start_dialogue(lines: Array[String]) -> void:
	for line in lines:
		queue_dialogue(line)

# Start a conversation from a dialogue file using plugin
func start_dialogue_from_file(resource: DialogueResource, title: String = "start") -> void:
	dialogue_resource = resource
	in_dialogue = true
	await _fetch_line(title)

# True while a conversation is in progress, so NPCs don't retrigger it
func is_busy() -> bool:
	return current_state != State.READY or !dialogue_queue.is_empty() or in_dialogue == true

# ----Internal functions

func show_dialogue():
	dialogue_container.show()

func hide_dialogue():
	text.text = ""
	advance_symbol.modulate.a = 0.0
	dialogue_container.hide()

func display_dialogue():
	var next_dialogue = dialogue_queue.pop_front()
	text.text = next_dialogue
	text.visible_ratio = 0.0
	advance_symbol.modulate.a = 0.0
	change_state(State.READING)
	show_dialogue()
	tween = create_tween()
	tween.tween_property(text, "visible_ratio", 1.0, len(next_dialogue) * CHAR_READ_RATE).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_Tween_tween_all_completed)

func _on_Tween_tween_all_completed():
	advance_symbol.modulate.a = 1.0
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

func _fetch_line(id: String) -> void:
	current_line = await dialogue_resource.get_next_dialogue_line(id)
	if not current_line:
		_end_dialogue()
		return
	queue_dialogue(current_line.text)

func _advance_dialogue() -> void:
	change_state(State.READY)
	var next_id: String = current_line.next_id
	if next_id.is_empty() or next_id.begins_with("END"):
		_end_dialogue()
	else:
		await _fetch_line(next_id)

func _end_dialogue() -> void:
	in_dialogue = false
	dialogue_resource = null
	current_line = null
	change_state(State.READY)
	hide_dialogue()
