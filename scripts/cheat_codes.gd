class_name CheatCodes
extends Node
## Listens to every key / gamepad button press and remembers the last few.
## When the end of that history matches a code, it emits `code_entered`.
## Main decides what each code actually does.
##
## To add a code: add a line to CODES, then handle its id in
## Main._on_cheat(). Letter codes are typed as words.
##
## Avoid the letters P (pause), M (mute), N (music) and J (fire) in word
## codes: those keys already do something and would get in the way.

signal code_entered(id: String)

const CODES := {
	"god_mode":  "GODTIER",
	"lives":     ["Up", "Up", "Down", "Down", "Left", "Right", "Left", "Right", "B", "A"],
	"max_power": "OVERLOAD",
	"kaboom":    "BLASTOFF",
	"fortress":  "CASTLE",
	"skip":      "SHORTCUT",
	"loot":      "LOOTBOX",
	"disco":     "DISCO",
}

const MAX_HISTORY := 16

var _history: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # codes also work in the pause menu


## _input sees every event first, before the UI or the game uses it.
func _input(event: InputEvent) -> void:
	var token := _token(event)
	if token == "":
		return
	_history.append(token)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	for id: String in CODES:
		if _history_ends_with(_as_tokens(CODES[id])):
			_history.clear()
			code_entered.emit(id)
			return


func _history_ends_with(code: Array[String]) -> bool:
	if _history.size() < code.size():
		return false
	var offset := _history.size() - code.size()
	for i in code.size():
		if _history[offset + i] != code[i]:
			return false
	return true


## Turn an input event into a short text token, like "A" or "Up".
func _token(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed and not event.echo:
		# physical_keycode: the key's POSITION, so codes work with any
		# keyboard layout (QWERTY positions).
		var key := (event as InputEventKey).physical_keycode
		return OS.get_keycode_string(key)
	if event is InputEventJoypadButton and event.pressed:
		# Gamepad: D-pad for directions, and the bottom/right face buttons
		# stand in for A and B, so the classic code works on a controller too.
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_UP: return "Up"
			JOY_BUTTON_DPAD_DOWN: return "Down"
			JOY_BUTTON_DPAD_LEFT: return "Left"
			JOY_BUTTON_DPAD_RIGHT: return "Right"
			JOY_BUTTON_A: return "A"
			JOY_BUTTON_B: return "B"
	return ""


func _as_tokens(code: Variant) -> Array[String]:
	var tokens: Array[String] = []
	if code is String:
		for ch in (code as String):
			tokens.append(ch)
	else:
		for t: String in code:
			tokens.append(t)
	return tokens
