extends CanvasLayer

const CHAR_READ_RATE = 0.0275

#Text and Advance labels accessed as unique names
@onready var dialogue_container = $DialogueContainer
@onready var text = %Text
@onready var advance_symbol = %Advance
@onready var choices: Control = %Choices
@onready var choice_list: VBoxContainer = %ChoiceList

var dialogue_resource: DialogueResource
# untyped on purpose: the plugin can return null or {} when there are no lines left
var current_line
var in_dialogue := false

enum State {
	READY,
	READING,
	FINISHED,
	CHOOSING
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
				tween.kill()
				finish_reading()
		State.FINISHED:
			if advance_pressed():
				if in_dialogue:
					_advance_dialogue()
				else:
					change_state(State.READY)
					hide_dialogue()
		State.CHOOSING:
			pass # the choice buttons handle input

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
	choices.hide()

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
	finish_reading()

# runs once a line is fully shown (typed out or skipped to the end)
# lines with choices show the menu, everything else waits for a press
func finish_reading() -> void:
	text.visible_ratio = 1.0
	if has_choices():
		advance_symbol.modulate.a = 0.0
		show_choices()
	else:
		advance_symbol.modulate.a = 1.0
		change_state(State.FINISHED)

func has_choices() -> bool:
	return in_dialogue and current_line != null and not current_line.responses.is_empty()

func change_state(next_state):
	current_state = next_state
	match current_state:
		State.READY:
			print("Changing state to: State.READY")
		State.READING:
			print("Changing state to: State.READING")
		State.FINISHED:
			print("Changing state to: State.FINISHED")
		State.CHOOSING:
			print("Changing state to: State.CHOOSING")

func _fetch_line(id: String) -> void:
	current_line = await dialogue_resource.get_next_dialogue_line(id)
	if not current_line:
		_end_dialogue()
		return
	print("Got line: ", current_line.text, " | responses: ", current_line.responses.size())
	queue_dialogue(current_line.text)

# jump to a line id, or end the conversation if there is nowhere to go
func _go_to(next_id: String) -> void:
	if next_id.is_empty() or next_id.begins_with("END"):
		_end_dialogue()
	else:
		await _fetch_line(next_id)

func _advance_dialogue() -> void:
	change_state(State.READY)
	await _go_to(current_line.next_id)

func _end_dialogue() -> void:
	in_dialogue = false
	dialogue_resource = null
	current_line = null
	change_state(State.READY)
	hide_dialogue()

# ----Choices

# builds one button per allowed response and focuses the first
func show_choices() -> void:
	change_state(State.CHOOSING)
	clear_choices()

	var first_button: Button = null
	for response: DialogueResponse in current_line.responses:
		if not response.is_allowed:
			continue
		var button := Button.new()
		button.text = response.text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_choice_pressed.bind(response))
		choice_list.add_child(button)
		if first_button == null:
			first_button = button

	# every choice was filtered out by conditions, so don't get stuck
	if first_button == null:
		push_warning("DialogueBox: no allowed responses, skipping choices")
		_advance_dialogue()
		return

	choices.show()
	first_button.grab_focus()

# removes old buttons right away so they can't take focus
func clear_choices() -> void:
	for child in choice_list.get_children():
		choice_list.remove_child(child)
		child.queue_free()

func _on_choice_pressed(response: DialogueResponse) -> void:
	choices.hide()
	clear_choices()
	change_state(State.READY)
	await _go_to(response.next_id)
