class_name SaveSlotButton
extends Button

@onready var money_label: Label = %MoneyLabel
@onready var date_label: Label = %DateLabel

func show_save(money: int, saved_at: String) -> void:
	money_label.text = "Money: %d" % money
	date_label.text = _format_date(saved_at)

func show_empty() -> void:
	money_label.text = "Empty"
	date_label.text = ""

func show_overwrite_prompt() -> void:
	money_label.text = "Overwrite? Press again"
	date_label.text = ""

func set_available(available: bool) -> void:
	disabled = not available
	modulate.a = 1.0 if available else 0.5

# 2026-11-27 14:05:33 -> 11/27/26
func _format_date(saved_at: String) -> String:
	var parts := saved_at.left(10).split("-")
	if parts.size() != 3:
		return ""
	return "%s/%s/%s" % [parts[1], parts[2], parts[0].right(2)]
