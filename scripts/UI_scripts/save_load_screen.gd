class_name SaveLoadScreen
extends Control

enum Mode { NEW, SAVE, LOAD }

signal slot_chosen(slot: int, chosen_mode: Mode)
signal closed(closed_mode: Mode)

var mode := Mode.NEW
var pending_overwrite := -1

@onready var title_label: Label = %Title
@onready var slot_buttons: Array = %SlotList.get_children()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	for i in slot_buttons.size():
		slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i + 1))
		# eg: (_on_slot_pressed.1)
		
func open(new_mode: Mode) -> void:
	mode = new_mode
	pending_overwrite = -1
	title_label.text = _title_for(mode)
	
	
	var first_enabled: Button = null
	for i in slot_buttons.size():
		var slot := i + 1
		var button: SaveSlotButton = slot_buttons[i]
		if SaveManager.has_save(slot):
			var saved_at: String = SaveManager.get_slot_info(slot).get("saved_at", "")
			var wallet_data: Dictionary = SaveManager.get_slot_data(slot, "wallet")
			button.show_save(int(wallet_data.get("money", 0)), saved_at)
			button.set_available(true)
		else:
			button.show_empty()
			button.set_available(mode != Mode.LOAD)
		if first_enabled == null and not button.disabled:
			first_enabled = button

	visible = true
	if first_enabled != null:
		first_enabled.grab_focus()
		
#hides screen, doesn't announce anything
func close() -> void:
	visible = false
	pending_overwrite = -1
		
func _on_slot_pressed(slot: int) -> void:
	var needs_confirm: bool = (mode != Mode.LOAD and SaveManager.has_save(slot) 
						and pending_overwrite != slot)
	if needs_confirm:
		pending_overwrite = slot
		slot_buttons[slot - 1].show_overwrite_prompt()
		return
	close()
	slot_chosen.emit(slot, mode)
	
func _cancel() -> void:
	close()
	closed.emit(mode)
	
func _title_for(m: Mode) -> String:
	match m:
		Mode.NEW:
			return "New Game"
		Mode.SAVE:
			return "Save Game"
		_:
			return "Load Game"

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
	
	
