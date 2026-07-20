extends SceneTree
## tests/net/bot_outer_peer.gd
##
## TK-P3-07 (tools-devops) -- headless BOT CLIENT that behaves like a simple
## Outer player: approach the current Tiger -> attempt a Kick once in range
## -> flee in a random direction for a short window -> resume approaching.
## Built as a TEST/DEV TOOL to unblock solo (and future N>=3) feel-testing
## while a second human tester is unavailable (see the card's
## `assignment_note`/`note` in _backlog.json and TK-P2-27's re-scoping note).
## This is explicitly NOT a shipped bot-opponent game mode -- Tiger Kick's GDD
## core loop stays Human-vs-Human; this script lives entirely under
## tests/net/ and only ever calls existing PUBLIC client-side entry points
## (NetworkManager.host()/join(), the real ui/WaitingRoom.tscn scene's own
## Start button signal, AbilityController.try_activate(), and simulated
## Input actions that MovementComponent's own _physics_process() already
## polls every tick) -- no product file under characters/ or managers/ was
## touched to build this.
##
## SIBLING of tests/net/spawn_probe_together_peer.gd,
## tests/net/spawn_probe_slowjoin_peer.gd and tests/net/tag_detect_probe_peer.gd
## (read first, per this card's own instructions) -- reuses their exact
## "headless SceneTree peer drives a real ENet connection through
## NetworkManager" shape, their _get_network_manager()/_after()/
## _parse_args() plumbing, and their "resolve a peer id to a live Player
## node off the shared Players root" convention (also the same convention
## managers/GameManager.gd's apply_role_switch()/_apply_tiger_position_
## correction() and the TK-BUG-P2-01-fixed KickAbility.on_confirmed() already
## establish -- resolve the live node, never guess).
##
## WHERE THIS SCRIPT DIVERGES FROM ITS SIBLINGS, AND WHY: those three probes
## are pure automation -- they skip the actual ui/MainMenu.tscn + ui/
## WaitingRoom.tscn scenes and directly approximate the PRODUCTION ORDERING
## those scenes create (host enters the arena first, client later) because
## nothing else needs to observe their UI. This bot is different: a REAL
## human is expected to join the SAME session with their own ordinary Godot
## client (MainMenu -> Join -> the real WaitingRoom screen, exactly as
## always) alongside this bot -- so this script drives the REAL ui/
## WaitingRoom.tscn scene (not a shortcut/approximation of it) so the RPCs
## ui/WaitingRoom.gd already declares (_rpc_receive_roster, _rpc_start_
## match) find a genuine matching node on every peer, bot AND the human's
## real client alike. Concretely:
##   - HOST role: calls NetworkManager.host() (exactly what MainMenu.gd's
##     _on_host_pressed() calls), instantiates the REAL ui/WaitingRoom.tscn
##     scene as current_scene (mirrors MainMenu.gd's _switch_to_waiting_
##     room()), waits for the roster to reach --expected-players, then
##     triggers the match start by EMITTING THE REAL START BUTTON'S OWN
##     pressed SIGNAL (_waiting_room.start_button.pressed.emit()) -- this
##     runs ui/WaitingRoom.gd's own already-reviewed _on_start_pressed() ->
##     rpc("_rpc_start_match") exactly as a human clicking that button
##     would, not a new/parallel code path. A human's real GUI client
##     Joining this host therefore sees a completely ordinary Waiting Room
##     (with this bot already in the roster) and needs to do nothing special
##     at all -- the headless host starts the match once enough players have
##     joined.
##   - BOT role: calls NetworkManager.join() (exactly what MainMenu.gd's
##     _on_join_pressed() calls) and instantiates the REAL ui/
##     WaitingRoom.tscn scene the same way -- WaitingRoom.gd's own _ready()
##     immediately fires its existing client-hello RPC, so this bot appears
##     in the roster the same way a real second client would. It then just
##     waits for the HOST's real _rpc_start_match broadcast (fired above)
##     to carry it into res://world/TestArena.tscn, same as everyone else.
##
## MOVEMENT-DRIVING APPROACH (the card's own open question) -- chosen:
## SIMULATED InputMap actions via Input.action_press()/action_release(),
## NOT a new direct-callable movement seam on MovementComponent. Investigated
## characters/components/MovementComponent.gd in full first: its
## _physics_process() reads Input.get_vector("move_left","move_right",
## "move_forward","move_back") and Input.is_action_pressed("sprint") every
## physics tick, gated only on _body.is_multiplayer_authority() -- which
## this bot's own Player legitimately has, being an ordinary connected
## client peer. Input.action_press()/action_release() write directly into
## the Input singleton's action-state table, which Input.get_vector()
## reads back -- this requires NO display/window (confirmed by this
## codebase's own characters/components/CameraComponent.gd class doc: "mouse
## mode is a headless no-op", i.e. Input singleton state is already known in
## this codebase to work headless) and needs zero new code on
## MovementComponent, which already exposes no "walk toward direction"
## method (unlike the short-lived overrides start_pounce_burst()/
## start_stagger() expose for THEIR OWN one-shot use cases -- neither fits
## "hold WASD for many ticks", the actual need here). Held action state
## persists across ticks exactly like a human physically holding a key,
## so ordinary WASD-driven movement, gravity, Safe-Circle clamping (for a
## Tiger this bot becomes, see below) etc. all run completely UNMODIFIED --
## the single most production-faithful option, and the one the card itself
## flags as the leading candidate. Kick itself is fired via
## AbilityController.try_activate(&"kick") -- the exact same owner-side
## entry point AbilityController._unhandled_input() calls for a real
## player's mouse-button "kick" InputMap action (see that file's own doc);
## calling it directly here only skips the _unhandled_input event-dispatch
## GLUE (which itself gates on Input.mouse_mode == MOUSE_MODE_CAPTURED, a
## real-window-only concept CameraComponent's own doc already says is a
## headless no-op) -- the entire ability pipeline downstream of that call
## (can_activate() prediction, the rpc_request_activate round-trip,
## host_validate(), rpc_confirm/rpc_reject) runs completely for real, with
## host_validate() the sole authority on whether the kick actually lands,
## exactly per this card's "not a shortcut that bypasses host_validate()"
## requirement.
##
## BEHAVIOR (v2, TK-P3-08 -- kept deliberately simple, this is a test tool,
## not game AI): every BOT_TICK_SEC this bot re-derives the CURRENT Tiger
## (scans TestArena/Players for role == RoleRules.TIGER, same "resolve off
## the shared Players root" convention this file's class doc cites above --
## re-derived fresh every tick, so a mid-session Tag Sequence role swap is
## picked up automatically with no extra event wiring). Two mutually
## exclusive branches depending on this bot's OWN Player's OWN role:
##
## OUTER (unchanged from TK-P3-07 v1):
##   - no Tiger exists yet -> idle (movement input cleared).
##   - Tiger exists and is farther than KICK_ATTEMPT_RANGE_M -> steer WASD
##     input toward it (camera-relative, matching MovementComponent's own
##     camera_relative_dir()/CameraRig.rotation.y convention -- this bot never
##     turns its camera, so that yaw stays whatever the scene authored it at,
##     read fresh every tick rather than assumed constant).
##   - Tiger is within KICK_ATTEMPT_RANGE_M -> stop, fire
##     AbilityController.try_activate(&"kick") ONCE, then unconditionally
##     enter FLEE for FLEE_DURATION_SEC in a uniformly random direction
##     (RandomNumberGenerator -- plain GDScript, not a workflow script, no
##     Math.random()-style restriction applies here per this card's own
##     note), regardless of whether the host actually confirms or rejects
##     that kick (the card's own spec: "landed or rejected" both flee) --
##     this bot does not wait for/inspect rpc_confirm/rpc_reject at all;
##     KICK_ATTEMPT_RANGE_M (see its own doc below) is only ever this TEST
##     TOOL's own heuristic for "worth trying"; host_validate() alone decides
##     the real outcome, same as for any real client.
##   - FLEE window elapsed -> clear flee input, resume the Tiger check above
##     on the very next tick (no idle gap).
##
## TIGER (TK-P3-08 -- was a v1 idle "frozen tiger mannequin", the bug this
## card fixes; a Tiger has no Kick ability registered at all, see
## characters/abilities/AbilityCatalog.gd, so this branch is genuinely new
## behavior, not a re-target of the Outer logic above):
##   - WANDER: every WANDER_MIN/MAX_DURATION_SEC (re-rolled per window, same
##     RandomNumberGenerator this file already uses for FLEE direction), pick
##     a new uniformly random world-space direction and hold it via the exact
##     same _steer_toward()/simulated-Input approach the Outer branch already
##     uses for approach/flee movement -- no new movement-driving mechanism.
##     Deliberately NO boundary-awareness logic here: MovementComponent's own
##     host+owner Safe Circle clamp (TK-P2-06) already confines a Tiger body
##     to the arena's Safe Circle regardless of input direction, so undirected
##     wandering is sufficient and correct per the card's own instruction --
##     this bot does not need to know the radius, or that a boundary exists
##     at all.
##   - TAG WHEN NEAR: every tick, before (re-)rolling a wander direction, this
##     bot polls its OWN Player's OWN TagDetector sibling
##     (characters/components/TagDetectorComponent.gd, TK-P2-02, unchanged) via
##     get_candidates_in_range() and feeds that straight into
##     TagRules.nearest_candidate() (characters/components/TagRules.gd,
##     TK-P2-02, unchanged) -- the EXACT same "poll the detector, hand off to
##     the pure static" call shape TagAbility.host_validate() itself uses (see
##     that file's own doc), reused here rather than hand-rolled distance
##     math, per the card's explicit instruction. If the result is NOT
##     empty, this bot fires AbilityController.try_activate(&"tag") ONCE (same
##     real call-path-fidelity principle as Kick above: this goes through the
##     ability's own can_activate() prediction -> rpc_request_activate ->
##     host_validate() -> rpc_confirm/rpc_reject -- no shortcut, host_validate()
##     alone decides whether the tag actually lands). No flee/cooldown state
##     is layered on top of this: a CONFIRMED tag ends this bot's Tiger role
##     entirely (role swap makes this bot an Outer again, and the very next
##     tick's role check routes it back into the OUTER branch above with no
##     extra wiring needed); a REJECTED tag (cooldown/sequence_active/out of
##     range by the time host_validate() actually runs) just lets the wander
##     loop resume on the very next tick, same "no idle gap" shape FLEE's own
##     state-elapsed fallthrough already uses.
##
## Run directly with (see tests/net/run_bot_outer.sh for the full launcher a
## human actually runs):
##   godot --headless --path <repo> -s res://tests/net/bot_outer_peer.gd -- \
##     --role=host --port=7777 --timeout=3600 --expected-players=3
##   godot --headless --path <repo> -s res://tests/net/bot_outer_peer.gd -- \
##     --role=bot --address=127.0.0.1 --port=7777 --timeout=3600
##
## Non-GUT (SceneTree -s script, same pattern as every other tests/net/*_peer.gd
## probe) -- GUT -gdir=res://tests -ginclude_subdirs ignores it.

const DEFAULT_PORT := 7777 # deliberately NetworkManager.DEFAULT_PORT / MainMenu.gd's own default (not one of the other tests/net/*_peer.gd probes' dedicated non-default ports) -- a human's real GUI client's Join field is PRE-FILLED "127.0.0.1:7777" (MainMenu.gd's own DEFAULT_ADDRESS_PORT), so hosting here on the same default port means the human can Join with zero typing.
const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_TIMEOUT_SEC := 3600.0 # safety-net ceiling for an interactive dev-tool session, not a pass/fail assertion deadline like the other probes' --timeout.
const TEST_ARENA_NODE_NAME := "TestArena"
const WAITING_ROOM_SCENE := "res://ui/WaitingRoom.tscn"
const WAITING_ROOM_SCRIPT_PATH := "res://ui/WaitingRoom.gd"

const ARENA_POLL_SEC := 0.3
const SPAWN_POLL_SEC := 0.3

# HOST-ONLY roster wait tuning. Mirrors this codebase's own "bounded grace,
# then a safe fallback" convention (e.g. networking/ArenaBarrierRules.gd,
# TK-P2-30) rather than waiting forever or starting instantly on the first
# connection (which would race a second bot/the human still mid-join).
const ROSTER_SETTLE_SEC := 2.0 # once --expected-players is reached, wait this long before actually starting -- absorbs near-simultaneous joins landing a frame apart.
const ROSTER_POLL_SEC := 0.5
const ROSTER_MAX_WAIT_SEC := 300.0 # 5 min fallback: if --expected-players is never reached (e.g. a bot failed to launch, or the human is slow), auto-start anyway once the roster is at least WaitingRoomScript.MIN_PLAYERS_TO_START, so the session never hangs forever waiting on a peer that may never arrive.
const ROSTER_STATUS_LOG_SEC := 5.0

# Test-tool heuristic ONLY for "close enough to try a kick" -- NOT the
# authoritative range (that is characters/abilities/KickAbility.kick_range_m,
# 1.5 m, Game_Balance.md). Slightly inside that value so this bot reliably
# lands within the true range by the time host_validate() (which reads the
# HOST's own, possibly one-tick-stale, view of both positions) actually
# checks -- host_validate() is the sole authority either way; a rejected
# "no_target_in_range" kick just gets treated as an ordinary attempt per
# this file's class doc (flee regardless).
const KICK_ATTEMPT_RANGE_M := 1.3

const FLEE_DURATION_SEC := 1.6 # short fixed window, per the card -- arbitrary placeholder, not a Game_Balance.md value; TestArena's Floor is 40x40 (world/TestArena.tscn), comfortably larger than any flee distance this window can cover even at Outer sprint speed (6.0 m/s * 1.6s = 9.6m).
const MOVE_DEADZONE := 0.35 # WASD is digital (action_press/release), not analog -- a small deadzone avoids flapping between two actions when a direction is nearly axis-aligned.
const BOT_TICK_SEC := 0.1 # AI decision cadence; actual movement/physics still runs every physics tick off whichever WASD actions are currently held, exactly like a human holding a key between decisions.

# TK-P3-08 -- TIGER-branch wander window, re-rolled (new random direction)
# every WANDER_MIN..MAX_DURATION_SEC. Arbitrary placeholder, same class of
# value as FLEE_DURATION_SEC (not a Game_Balance.md tunable) -- "a few
# seconds" per the card, randomized rather than fixed purely so a wandering
# Tiger doesn't look mechanically identical every cycle in a live-watched
# test session. Deliberately NO boundary-awareness constant here (no radius,
# no arena-size math) -- see this file's class doc TIGER/WANDER note for why
# that is correct, not an oversight.
const WANDER_MIN_DURATION_SEC := 1.5
const WANDER_MAX_DURATION_SEC := 3.5

enum State { APPROACH, FLEE }

var _net: Node
var _role := ""
var _own_id := 0
var _done := false

var _waiting_room: Control
# Loaded LAZILY (a runtime load(), never a top-level preload) -- see
# _start_host()'s own comment for why: ui/WaitingRoom.gd references the
# `NetworkManager` autoload by its bare global identifier (as production code
# legitimately may), which only resolves once this process's autoloads have
# actually been bootstrapped (they are NOT yet at the moment THIS SceneTree
# script itself is first loaded/compiled under `-s`) -- a top-level preload()
# of ui/WaitingRoom.gd forces an eager compile at that too-early moment and
# poisons Godot's script cache for the rest of the process, breaking every
# LATER load() of the same script too. Empirically confirmed while building
# this tool (a standalone probe reproduced + isolated this exact ordering).
var _waiting_room_script: GDScript
var _arena: Node
var _players_root: Node
var _own_player: CharacterBody3D
var _ability_controller: Node
var _camera_rig: Node3D
# TK-P3-08 -- own Player's own TagDetector sibling (see
# characters/components/TagDetectorComponent.gd, TK-P2-02), cached the same
# way/place as _ability_controller/_camera_rig above. Only ever queried while
# this bot's OWN role is Tiger (see _tiger_tick() below) -- an Outer's own
# TagDetector still exists/tracks overlap (that component is role-agnostic,
# see its own class doc), this bot just never has a reason to read it in the
# OUTER branch.
var _tag_detector: Area3D

var _state: int = State.APPROACH
var _flee_end_ms: int = 0
var _rng := RandomNumberGenerator.new()
var _tiger_ai_started_logged := false # TK-P3-08 -- renamed from _idle_tiger_role_logged (the bot no longer idles as Tiger); same one-shot "log the role transition once" purpose, reset back to false the moment role != TIGER so a LATER Tiger stint (e.g. a future round) logs its own transition again.
# TK-P3-08 -- next wander re-roll deadline (Time.get_ticks_msec()-space, same
# convention as _flee_end_ms above). 0 is a safe "never wandered yet"
# sentinel: Time.get_ticks_msec() is already > 0 by the time this script's
# AI loop can possibly run (engine + connection/spawn handshake time has
# already elapsed), so the very first Tiger tick always re-rolls immediately.
var _wander_end_ms: int = 0

# -- host-only roster-wait state ---------------------------------------------
var _expected_players := 2
var _match_start_triggered := false
var _roster_wait_elapsed_sec := 0.0
var _roster_settle_elapsed_sec := 0.0
var _roster_last_status_log_sec := 0.0

func _initialize() -> void:
	var args := _parse_args()
	_role = String(args.get("role", ""))

	if _role != "host" and _role != "bot":
		print("[BOT] ERROR invalid or missing --role= (expected host|bot)")
		quit(1)
		return

	var port: int = int(args.get("port", DEFAULT_PORT))
	var address: String = String(args.get("address", DEFAULT_ADDRESS))
	var timeout_sec: float = float(args.get("timeout", DEFAULT_TIMEOUT_SEC))
	_expected_players = int(args.get("expected-players", 2))

	_rng.randomize() # flee direction only -- plain GDScript RNG, no game-deciding state (see class doc).

	await process_frame

	_net = _get_network_manager()
	_start_timeout(timeout_sec)

	if _role == "host":
		_start_host(port)
	else:
		_net.connection_succeeded.connect(_on_bot_connected)
		_net.connection_failed.connect(_on_bot_connection_failed)
		_net.server_disconnected.connect(_on_bot_server_disconnected)
		_start_bot(address, port)


func _get_network_manager() -> Node:
	var existing := root.get_node_or_null("NetworkManager")
	if existing:
		return existing
	var script: GDScript = load("res://networking/NetworkManager.gd")
	var node: Node = script.new()
	node.name = "NetworkManager"
	root.add_child(node)
	return node

# =============================================================================
# HOST: real NetworkManager.host() + the REAL ui/WaitingRoom.tscn scene, then
# trigger its own real Start button once the roster is ready (see class doc).
# =============================================================================

func _start_host(port: int) -> void:
	# Lazy load, on purpose -- see _waiting_room_script's own doc above. By
	# this point _get_network_manager() (called from _initialize() before
	# this function) has already run past `await process_frame`, so this
	# process's autoloads exist and ui/WaitingRoom.gd's own `NetworkManager`
	# identifier reference resolves cleanly.
	_waiting_room_script = load(WAITING_ROOM_SCRIPT_PATH)

	var err: int = _net.host(port)
	if err != OK:
		print("[BOT][host] ERROR host() failed with code %d" % err)
		_finish(1)
		return
	_own_id = _net.multiplayer.get_unique_id()
	print("[BOT][host] listening on port %d -- waiting for %d total player(s) (host+bot(s)+human) before starting the match" % [port, _expected_players])
	_enter_waiting_room()
	_start_roster_watch()


func _enter_waiting_room() -> void:
	var scene: PackedScene = load(WAITING_ROOM_SCENE)
	_waiting_room = scene.instantiate() as Control
	root.add_child(_waiting_room)
	current_scene = _waiting_room


func _start_roster_watch() -> void:
	var t := Timer.new()
	t.wait_time = ROSTER_POLL_SEC
	t.one_shot = false
	root.add_child(t)
	t.timeout.connect(func() -> void:
		if _done or _match_start_triggered:
			t.stop()
			return
		_check_roster(t.wait_time)
	)
	t.start()


func _current_roster_size() -> int:
	return 1 + _net.get_connected_peer_ids().size() # host + every connected peer, same convention managers/GameManager.gd's own _expected_first_tiger_roster_size uses.


func _check_roster(dt: float) -> void:
	var size: int = _current_roster_size()
	_roster_wait_elapsed_sec += dt

	if size >= _expected_players:
		_roster_settle_elapsed_sec += dt
		if _roster_settle_elapsed_sec >= ROSTER_SETTLE_SEC:
			print("[BOT][host] roster reached %d/%d players and settled -- starting match" % [size, _expected_players])
			_trigger_match_start()
		return

	_roster_settle_elapsed_sec = 0.0

	if size >= _waiting_room_script.MIN_PLAYERS_TO_START and _roster_wait_elapsed_sec >= ROSTER_MAX_WAIT_SEC:
		print("[BOT][host] gave up waiting for %d players after %.0fs -- starting anyway with %d (>= WaitingRoom's own MIN_PLAYERS_TO_START=%d)" % [_expected_players, ROSTER_MAX_WAIT_SEC, size, _waiting_room_script.MIN_PLAYERS_TO_START])
		_trigger_match_start()
		return

	_roster_last_status_log_sec += dt
	if _roster_last_status_log_sec >= ROSTER_STATUS_LOG_SEC:
		_roster_last_status_log_sec = 0.0
		print("[BOT][host] waiting for players: %d/%d connected (elapsed %.0fs)" % [size, _expected_players, _roster_wait_elapsed_sec])


# Fires the REAL Start button's own pressed signal -- runs ui/WaitingRoom.gd's
# already-reviewed _on_start_pressed() exactly as a human click would (see
# this file's class doc "HOST role" note). Not a new/parallel code path, not
# a debug hook.
#
# DELIBERATELY does NOT call _start_arena_watch()/start its own AI loop here:
# the headless host is a DEDICATED SERVER + a passive/idle Player body (see
# class doc), not a second bot -- ui/WaitingRoom.gd's own _rpc_start_match()
# already carries the host into res://world/TestArena.tscn for free (its
# call_local also runs on this process), which is all the host needs to keep
# simulating the match host-authoritatively (GameManager/RoundManager/
# PlayerSpawner/Safe-Circle correction etc. all already run host-side
# regardless of anything this script does). A future card could opt the host
# BODY into the same AI loop too (nothing here would need to change beyond
# calling _start_arena_watch() from here as well) -- not done in this v1 pass
# to keep host-vs-bot roles unambiguous in the logs.
func _trigger_match_start() -> void:
	if _match_start_triggered:
		return
	_match_start_triggered = true
	_waiting_room.start_button.pressed.emit()
	print("[BOT][host] match started -- running as dedicated host (own Player stays idle at spawn; see doc above)")

# =============================================================================
# BOT: real NetworkManager.join() + the REAL ui/WaitingRoom.tscn scene, then
# wait for the HOST's real _rpc_start_match broadcast to carry us into the
# arena (see class doc "BOT role" note).
# =============================================================================

func _start_bot(address: String, port: int) -> void:
	var err: int = _net.join(address, port)
	if err != OK:
		print("[BOT][bot] ERROR join() failed with code %d" % err)
		_finish(1)
		return
	print("[BOT][bot] connecting to %s:%d ..." % [address, port])


func _on_bot_connected() -> void:
	_own_id = _net.multiplayer.get_unique_id()
	print("[BOT][bot] CONNECTED (own_id=%d) -- entering Waiting Room" % _own_id)
	_enter_waiting_room()
	_start_arena_watch()


func _on_bot_connection_failed() -> void:
	print("[BOT][bot] CONNECTION_FAILED")
	_finish(1)


func _on_bot_server_disconnected() -> void:
	if _done:
		return
	print("[BOT][bot] host disconnected -- ending session")
	_finish(0)


# =============================================================================
# SHARED: wait for the arena to actually appear (host's real Start-button
# broadcast, or this bot's own reaction to it), then wait for OWN Player to
# spawn (barrier-spawned by networking/PlayerSpawner.gd, same "own Player
# under TestArena/Players named str(own_id)" contract spawn_probe_together_
# peer.gd's own doc already establishes), then start the AI loop.
# =============================================================================

func _start_arena_watch() -> void:
	var t := Timer.new()
	t.wait_time = ARENA_POLL_SEC
	t.one_shot = false
	root.add_child(t)
	t.timeout.connect(func() -> void:
		if _done:
			t.stop()
			return
		var found: Node = root.get_node_or_null(TEST_ARENA_NODE_NAME)
		if found == null:
			return
		t.stop()
		_arena = found
		_players_root = _arena.get_node("Players")
		print("[BOT][%s] entered arena -- waiting for own Player to spawn" % _role)
		_start_own_spawn_watch()
	)
	t.start()


func _start_own_spawn_watch() -> void:
	var t := Timer.new()
	t.wait_time = SPAWN_POLL_SEC
	t.one_shot = false
	root.add_child(t)
	t.timeout.connect(func() -> void:
		if _done:
			t.stop()
			return
		var candidate: Node3D = _players_root.get_node_or_null(str(_own_id)) as Node3D
		if candidate == null:
			return
		if not candidate.is_multiplayer_authority():
			return # not yet replicated as ours (barrier group still landing) -- keep polling, do not fail (unlike the assertion probes, this is a long-lived tool, not a bounded pass/fail check).
		t.stop()
		_own_player = candidate as CharacterBody3D
		_ability_controller = _own_player.get_node("AbilityController")
		_camera_rig = _own_player.get_node("CameraRig") as Node3D
		_tag_detector = _own_player.get_node("TagDetector") as Area3D
		print("[BOT][%s] own Player ready (id=%d) -- starting approach/kick/flee/wander/tag loop" % [_role, _own_id])
		_start_ai_loop()
	)
	t.start()

# =============================================================================
# BOT AI: OUTER branch approach -> kick -> flee -> approach; TIGER branch
# wander -> tag -> wander (see class doc BEHAVIOR, TK-P3-07 + TK-P3-08).
# =============================================================================

func _start_ai_loop() -> void:
	var t := Timer.new()
	t.wait_time = BOT_TICK_SEC
	t.one_shot = false
	root.add_child(t)
	t.timeout.connect(_bot_tick)
	t.start()


func _bot_tick() -> void:
	if _done or _own_player == null or not is_instance_valid(_own_player):
		return

	var now_ms: int = Time.get_ticks_msec()

	# TK-P3-08: TIGER and OUTER are mutually exclusive branches with entirely
	# separate state (TIGER uses _wander_end_ms, OUTER uses _state/_flee_end_ms)
	# -- route to _tiger_tick() and return before touching any OUTER state at
	# all, so a role swap mid-session (either direction) never leaves stale
	# FLEE/wander state to trip over on the next tick as the wrong role.
	if _own_player.role == RoleRules.TIGER:
		_tiger_tick(now_ms)
		return
	_tiger_ai_started_logged = false # reset so a LATER Tiger stint logs its own transition again (see this var's own doc).

	if _state == State.FLEE:
		if now_ms < _flee_end_ms:
			return # still fleeing -- input was already set once when the flee began, hold it.
		_state = State.APPROACH
		_clear_movement_input()
		# fall through to re-evaluate APPROACH the same tick, no idle gap.

	var tiger: Node3D = _find_tiger()
	if tiger == null:
		_clear_movement_input()
		return

	var to_tiger: Vector3 = tiger.global_position - _own_player.global_position
	to_tiger.y = 0.0
	var dist: float = to_tiger.length()

	if dist <= KICK_ATTEMPT_RANGE_M:
		_clear_movement_input()
		_attempt_kick()
		_enter_flee(now_ms)
		return

	_steer_toward(to_tiger)


# TK-P3-08: TIGER-branch AI tick -- wander undirected within the (already
# host+owner clamped, see class doc TIGER/WANDER note) Safe Circle, tagging
# any Outer that wanders into this bot's own TagDetector's range. Called ONLY
# from _bot_tick() above while _own_player.role == RoleRules.TIGER.
func _tiger_tick(now_ms: int) -> void:
	if not _tiger_ai_started_logged:
		_tiger_ai_started_logged = true
		print("[BOT][%s] own Player is now the Tiger -- wandering the Safe Circle and tagging nearby Outers" % _role)

	# TAG WHEN NEAR (checked every tick, ahead of the wander re-roll below, so
	# a candidate that wanders into range gets tagged on the very tick it
	# enters range rather than waiting on an unrelated wander-timer boundary).
	var candidates: Array = _tag_detector.get_candidates_in_range()
	var target: Dictionary = TagRules.nearest_candidate(_own_player.global_position, candidates, _tag_detector.tag_range_m)
	if not target.is_empty():
		_clear_movement_input()
		_attempt_tag(target)
		return # resume wandering next tick regardless of confirm/reject (see class doc TIGER/TAG WHEN NEAR note) -- no idle gap.

	if now_ms >= _wander_end_ms:
		_pick_new_wander_direction(now_ms)


func _attempt_tag(target: Dictionary) -> void:
	print("[BOT][%s] Outer %s in tag range -- attempting Tag (host_validate() decides the real outcome)" % [_role, target.get("id")])
	_ability_controller.try_activate(&"tag")


# Picks a new uniformly random WORLD-space direction and holds it for a
# random WANDER_MIN..MAX_DURATION_SEC window -- mirrors _enter_flee()'s own
# RandomNumberGenerator direction pick below, deliberately NOT reusing that
# function directly (different duration source: a fixed constant there vs a
# re-rolled range here) even though the body is similar, so FLEE's and
# WANDER's tuning stay independently editable per this file's own "Kick/Tag
# stay free to diverge later" convention (see TagRules.gd's own doc for the
# precedent on that principle).
func _pick_new_wander_direction(now_ms: int) -> void:
	var duration_sec: float = _rng.randf_range(WANDER_MIN_DURATION_SEC, WANDER_MAX_DURATION_SEC)
	_wander_end_ms = now_ms + int(duration_sec * 1000.0)
	var angle: float = _rng.randf_range(0.0, TAU)
	var wander_world_dir := Vector3(cos(angle), 0.0, sin(angle))
	print("[BOT][%s] Tiger wandering for %.1fs (world dir=%s)" % [_role, duration_sec, wander_world_dir])
	_steer_toward(wander_world_dir)


# Scans the shared Players root for the current Tiger, excluding this bot's
# OWN Player (see class doc BEHAVIOR -- a Tiger never chases itself; if this
# bot's own role is Tiger, _bot_tick() above already returns before reaching
# here, but the exclusion is kept anyway as defense-in-depth, same "a
# defensive check costing nothing is still worth having" reasoning
# characters/abilities/KickAbility.gd's own on_confirmed() doc uses).
func _find_tiger() -> Node3D:
	for child in _players_root.get_children():
		if child == _own_player:
			continue
		if child is CharacterBody3D and child.role == RoleRules.TIGER:
			return child as Node3D
	return null


func _attempt_kick() -> void:
	print("[BOT][%s] in kick range -- attempting Kick (host_validate() decides the real outcome)" % _role)
	_ability_controller.try_activate(&"kick")


func _enter_flee(now_ms: int) -> void:
	_state = State.FLEE
	_flee_end_ms = now_ms + int(FLEE_DURATION_SEC * 1000.0)
	var angle: float = _rng.randf_range(0.0, TAU)
	var flee_world_dir := Vector3(cos(angle), 0.0, sin(angle))
	print("[BOT][%s] fleeing for %.1fs (world dir=%s)" % [_role, FLEE_DURATION_SEC, flee_world_dir])
	_steer_toward(flee_world_dir)

# Converts a WORLD-space (flattened, need not be normalized) direction into
# the digital WASD input MovementComponent's own camera_relative_dir()
# expects, by undoing CameraRig's current yaw (the exact inverse of that
# function's own local_dir.rotated(Vector3.UP, yaw)) -- see this file's
# class doc for why yaw is re-read fresh every call rather than assumed
# constant.
func _steer_toward(world_dir: Vector3) -> void:
	var flat := Vector3(world_dir.x, 0.0, world_dir.z)
	if flat.length() < 0.0001:
		_clear_movement_input()
		return
	flat = flat.normalized()

	var yaw: float = 0.0
	if _camera_rig:
		yaw = _camera_rig.rotation.y
	var local_dir: Vector3 = flat.rotated(Vector3.UP, -yaw)

	_set_axis_input("move_left", "move_right", local_dir.x)
	_set_axis_input("move_forward", "move_back", local_dir.z) # z mirrors input.y in MovementComponent.camera_relative_dir()'s own Vector3(input.x, 0.0, input.y) convention -- negative z == forward, matching Input.get_vector's own move_forward==negative-y wiring in project.godot.


func _set_axis_input(negative_action: StringName, positive_action: StringName, value: float) -> void:
	if value < -MOVE_DEADZONE:
		_press(negative_action)
		_release(positive_action)
	elif value > MOVE_DEADZONE:
		_press(positive_action)
		_release(negative_action)
	else:
		_release(negative_action)
		_release(positive_action)


func _press(action: StringName) -> void:
	if not Input.is_action_pressed(action):
		Input.action_press(action)


func _release(action: StringName) -> void:
	if Input.is_action_pressed(action):
		Input.action_release(action)


func _clear_movement_input() -> void:
	_release(&"move_forward")
	_release(&"move_back")
	_release(&"move_left")
	_release(&"move_right")

# =============================================================================
# shared plumbing (mirrors spawn_probe_together_peer.gd / spawn_probe_slowjoin_peer.gd)
# =============================================================================

func _start_timeout(timeout_sec: float) -> void:
	var timeout_timer := Timer.new()
	timeout_timer.wait_time = timeout_sec
	timeout_timer.one_shot = true
	root.add_child(timeout_timer)
	timeout_timer.timeout.connect(_on_timeout)
	timeout_timer.start()


func _on_timeout() -> void:
	if _done:
		return
	print("[BOT][%s] --timeout reached -- ending session (this is the dev-tool's own safety-net ceiling, not a pass/fail assertion)" % _role)
	_finish(0)


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	quit(code)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var stripped: String = arg.substr(2)
		var eq_idx: int = stripped.find("=")
		if eq_idx == -1:
			result[stripped] = true
			continue
		var key: String = stripped.substr(0, eq_idx)
		var value: String = stripped.substr(eq_idx + 1)
		result[key] = value
	return result
