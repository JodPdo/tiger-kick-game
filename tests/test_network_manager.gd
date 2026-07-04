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


func after_each() -> void:
	if is_instance_valid(_net):
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
