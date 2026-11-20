extends Node

const SLOT_COUNT := 4
const SAVE_VERSION := 1

var current_slot := 1

func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func any_save_exists() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_save(slot):
			return true
	return false

func new_game(slot: int) -> void:
	current_slot = slot
	for node in get_tree().get_nodes_in_group("saveable"):
		node.reset_to_defaults()

func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"meta": {"saved_at": Time.get_datetime_string_from_system(false, true)},
		"systems": {},
	}
	for node in get_tree().get_nodes_in_group("saveable"):
		data["systems"][node.save_key()] = node.get_save_data()

	var file := FileAccess.open(slot_path(current_slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open save file for writing")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func load_game(slot: int) -> bool:
	var data := _read_slot(slot)
	if data.is_empty():
		return false
	current_slot = slot
	var systems: Dictionary = data.get("systems", {})
	for node in get_tree().get_nodes_in_group("saveable"):
		var key: String = node.save_key()
		if systems.has(key):
			node.load_save_data(systems[key])
	return true

func get_slot_info(slot: int) -> Dictionary:
	return _read_slot(slot).get("meta", {})

func delete_slot(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))

func _read_slot(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: save file is corrupt")
		return {}
	return parsed
