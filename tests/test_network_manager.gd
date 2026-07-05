extends GutTest
## Unit tests for networking/NetworkManager.gd input validation.
##
## NOTE: These tests require the GUT addon (Godot Unit Test), which is
## installed by TK-PX-07. Until that card lands, this file is not executed
## by CI but is ready to run once GUT is available (addons/gut/...).
## Only node-independent logic (input validation, no live peers/sockets)
## is covered here — live 2-instance connectivity is verified in TK-P0-06.

const NetworkManagerScript := preload("res://networking/NetworkManager.gd")

var _net: Node


func before_each() -> void:
	_net = NetworkManagerScript.new()
	# Real host()/join() calls need `multiplayer` (Node.get_multiplayer()) to
	# resolve to a live SceneMultiplayer, which requires this node to be
	# inside the SceneTree -- a bare NetworkManagerScript.new() (as used by
	# the input-validation-only tests above) is not. Only the two
	# already-active-peer guard tests below need a real bind.
	add_child(_net)


func after_each() -> void:
	if is_instance_valid(_net):
		_net.disconnect_from_game()
		remove_child(_net)
		_net.free()


func test_default_constants() -> void:
	assert_eq(_net.DEFAULT_PORT, 7777, "DEFAULT_PORT should match shared interface contract")
	assert_eq(_net.DEFAULT_ADDRESS, "127.0.0.1", "DEFAULT_ADDRESS should match shared interface contract")
	assert_eq(_net.MAX_CLIENTS, 8, "MAX_CLIENTS should support up to 8 players")


func test_host_rejects_invalid_port_negative() -> void:
	var err: int = _net.host(-1)
	assert_eq(err, ERR_INVALID_PARAMETER, "host() should reject a negative port")


func test_host_rejects_invalid_port_out_of_range() -> void:
	var err: int = _net.host(70000)
	assert_eq(err, ERR_INVALID_PARAMETER, "host() should reject a port above 65535")


func test_join_rejects_empty_address() -> void:
	var err: int = _net.join("", NetworkManagerScript.DEFAULT_PORT)
	assert_eq(err, ERR_INVALID_PARAMETER, "join() should reject an empty address")


func test_join_rejects_invalid_port() -> void:
	var err: int = _net.join(NetworkManagerScript.DEFAULT_ADDRESS, 0)
	assert_eq(err, ERR_INVALID_PARAMETER, "join() should reject port 0")


func test_disconnect_from_game_is_safe_when_idle() -> void:
	# Should not error/crash even if no peer is active yet.
	_net.disconnect_from_game()
	assert_true(true, "disconnect_from_game() did not crash with no active peer")


## TK-BUG-P1-02 (audit item #10): host()/join() must refuse to stomp an
## already-active peer instead of silently replacing it (which would leak
## the old ENetMultiplayerPeer/socket and desync local state from the new
## one). Uses a real bind on a dedicated test port (not DEFAULT_PORT, to
## avoid colliding with a concurrently-running net_smoke instance) and tears
## it down via disconnect_from_game() so no socket/peer leaks past the test.
func test_host_rejects_when_peer_already_active() -> void:
	var first_err: int = _net.host(17777)
	assert_eq(first_err, OK, "first host() call should succeed and create the peer")
	var second_err: int = _net.host(17777)
	assert_eq(second_err, ERR_ALREADY_IN_USE, "host() should reject a second call while a peer is already active")
	_net.disconnect_from_game()


func test_join_rejects_when_peer_already_active() -> void:
	var first_err: int = _net.host(17778)
	assert_eq(first_err, OK, "host() should succeed to set up an active peer")
	var second_err: int = _net.join(NetworkManagerScript.DEFAULT_ADDRESS, 17778)
	assert_eq(second_err, ERR_ALREADY_IN_USE, "join() should reject while a peer is already active")
	_net.disconnect_from_game()


## TK-BUG-P1-02: _on_server_disconnected() (wired to
## multiplayer.server_disconnected, which only fires with a live network
## connection loss) must emit the new `server_disconnected` signal so
## arena-level UI (world/TestArena.gd) can return to MainMenu. Calling the
## handler directly keeps this a fast, node-independent unit test rather
## than requiring a live 2-instance connection (that end-to-end path is
## covered by the manual 2-window test / smoke probe instead).
func test_on_server_disconnected_emits_signal() -> void:
	watch_signals(_net)
	_net._on_server_disconnected()
	assert_signal_emitted(_net, "server_disconnected",
		"server_disconnected should be emitted when the host connection is lost")
