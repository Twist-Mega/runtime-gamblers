extends Node

#EXPLORING: 0
#MENU: 1
#TABLE: 2
#BAR: 3
enum State { EXPLORING, MENU, TABLE, BAR}

signal state_changed(new_state: int)

#starts as exploring
var state: State = State.EXPLORING

#Allowed state changes -- can't go to menu from inside a minigame to prevent save-scumming, like we talked about
const ALLOWED = {
	State.EXPLORING: [State.MENU, State.TABLE, State.BAR],
	State.MENU: [State.EXPLORING],
	State.TABLE: [State.EXPLORING],
	State.BAR: [State.EXPLORING, State.MENU]
}

func request_state(new_state: State) -> bool:
	#won't change state if it's the same as current or the requested state isn't an allowed transition from the current state
	if new_state == state or not ALLOWED[state].has(new_state):
		return false
	state = new_state
	#paused when state is anything but exploring 
	get_tree().paused = (state != State.EXPLORING)
	state_changed.emit(state)
	return true
