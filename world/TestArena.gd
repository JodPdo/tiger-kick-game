extends Node3D
## TestArena.gd (TK-BUG-P1-02, network-engineer)
##
## Arena-level network-lifecycle glue -- deliberately NOT on Player.gd
## (per-peer gameplay/input script) since both cases below are about the
## WHOLE session, not any one player's local state:
##
## 1. Host quits (S2 bug fix): NetworkManager.server_disconnected (emitted by
##    NetworkManager._on_server_disconnected(), see that file) fires on every
##    remaining CLIENT once the host's ENet connection is lost/torn down.
##    Before this fix nothing listened for it -- the client sat in an empty
##    arena forever (its own Player still locally simulated, but no host to
##    talk to, no other players, no way out). We return to MainMenu and
##    restore the mouse cursor (Player.gd only knows how to release ITS OWN
##    peer's mouse capture on Esc, not "the whole match just ended").
##
## 2. Deliberate Leave (new, minimal viable UX per the card): Player.gd's
##    Esc handler releases mouse capture (MOUSE_MODE_CAPTURED ->
##    MOUSE_MODE_VISIBLE) but does nothing else -- there was previously no
##    way to actually leave a session short of alt-F4. Chosen UX (no pause
##    menu exists yet -- flagged as future work in Player.gd's own doc): a
##    SECOND Esc press, while the mouse is ALREADY visible (i.e. the first
##    Esc already released capture), calls
##    NetworkManager.disconnect_from_game() and returns to MainMenu. This
##    reuses the existing Esc key with no new input action / UI needed.
##
##    CRITICAL ORDERING (TK-BUG-P1-02 review fix -- an earlier version of
##    this comment got this exactly backwards and shipped a one-ESC-ends-the-
##    session bug): _unhandled_input propagates from the DEEPEST node UP, so
##    the local Player runs on any given ESC event BEFORE this scene-root
##    TestArena, and Input.mouse_mode readback is immediate. If Player did NOT
##    consume its ESC, a single tap would release the mouse in Player and then
##    this node would observe mouse == VISIBLE on that SAME press and _leave()
##    instantly (fatal on the host). The fix lives in Player.gd: its ESC
##    branch is gated on mouse == CAPTURED and calls
##    get_viewport().set_input_as_handled(), so this handler ONLY ever
##    receives an ESC event when the mouse was ALREADY visible before that
##    event -- guaranteeing two distinct presses. Do NOT remove that
##    gate/consume without revisiting this. On the HOST, this Leave naturally
##    tears down its ENetMultiplayerPeer, which triggers path 1 above on every
##    remaining client.
##
## Reference: CLAUDE.md server authority; TDD §9 Network Flow.

const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

## Guards against acting twice on the same session end (e.g. a client's own
## disconnect_from_game() call plus a possible server_disconnected fired as
## a side effect of tearing down its own peer) -- change_scene_to_file() is
## deferred, so without this guard a second call could double-queue the
## scene switch on the same frame.
var _session_ended: bool = false


func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_leave()


func _on_server_disconnected() -> void:
	if _session_ended:
		return
	_session_ended = true
	GameLog.info("[NET] host disconnected -- returning to MainMenu")
	_return_to_main_menu()


func _leave() -> void:
	if _session_ended:
		return
	_session_ended = true
	GameLog.info("[NET] player chose Leave -- disconnecting")
	NetworkManager.disconnect_from_game()
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var err: Error = get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if err != OK:
		push_warning("[ARENA] failed to switch to %s (error %d)" % [MAIN_MENU_SCENE, err])
