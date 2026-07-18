#!/usr/bin/env bash
# tests/net/run_spawn_probe_slowjoin.sh
#
# TK-P2-30 grace-EXTENSION regression probe (companion to
# run_spawn_probe_together.sh, the TK-P2-13 barrier happy-path). Launches a
# headless host + client (tests/net/spawn_probe_slowjoin_peer.gd) that connect
# over real ENet on localhost while in a "Waiting Room" (no arena yet); the host
# enters TestArena first (arming the readiness barrier + its 8s grace timer),
# and the client stays connected but enters the arena / announces readiness
# DELIBERATELY LATE -- past the real 8s ARENA_READY_GRACE_SEC -- so the host's
# first grace timeout fires while the (still-connected, healthy) client is
# legitimately absent. Asserts:
#   - the client is NOT force-disconnected during the wait (the fix EXTENDS the
#     grace because the client is still connected, instead of killing it)
#   - after the client finally enters, its OWN barrier-spawned Player exists
#     under TestArena/Players, named str(own_id), with the client itself as
#     multiplayer authority
#   - the HOST own Player (named "1") also replicated to the client
#   - the client Player position is neither (0,0,0) nor the host slot-0 position
#   - the host log shows the grace was EXTENDED and did NOT force-disconnect the
#     client; neither log contains an ERROR marker
#
# The fix under test (networking/PlayerSpawner.gd + networking/ArenaBarrierRules.gd):
# when the readiness-barrier grace window elapses with a peer still unready but
# still connected at the ENet layer (alive, just slow/backgrounded/throttled),
# the host EXTENDS the grace (up to ARENA_READY_MAX_GRACE_EXTENSIONS) instead of
# force-disconnecting it. Without the fix, the host kills the client at the 8s
# grace -> the client never spawns / gets server_disconnected -> this probe FAILs
# (SLOWJOIN_PASS never printed). Verified: FAILs against the pre-TK-P2-30 code,
# PASSes with the fix.
#
# NOTE: this probe intentionally spans the real ~8s grace + one extension, so it
# runs longer than the other net probes (default timeout 45s). It is a targeted
# regression, run on demand / in the extended net-probe set, not the fast inner CI loop.
#
# Usage (Git Bash on Windows, or bash on Linux CI):
#   GODOT_BIN=/path/to/godot ./tests/net/run_spawn_probe_slowjoin.sh
#
# Env overrides:
#   GODOT_BIN              path to Godot (default: local Windows console build)
#   SPAWN_SLOWJOIN_PORT    ENet port (default: 7781, distinct from the others)
#   SPAWN_SLOWJOIN_TIMEOUT per-instance --timeout in seconds (default: 45)

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
PORT="${SPAWN_SLOWJOIN_PORT:-7781}"
TIMEOUT="${SPAWN_SLOWJOIN_TIMEOUT:-45}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_spawn_slowjoin.XXXXXX" 2>/dev/null || mktemp -d)"
HOST_LOG="$LOG_DIR/host.log"
CLIENT_LOG="$LOG_DIR/client.log"

HOST_PID=""
CLIENT_PID=""

cleanup() {
	for pid in "$HOST_PID" "$CLIENT_PID"; do
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null
		fi
	done
}
trap cleanup EXIT

echo "SPAWN SLOWJOIN: repo root = $REPO_ROOT"
echo "SPAWN SLOWJOIN: logs      = $LOG_DIR"
echo "SPAWN SLOWJOIN: godot bin = $GODOT_BIN"
echo "SPAWN SLOWJOIN: port      = $PORT"

# --- launch host (stays in Waiting Room until the client connects) ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/spawn_probe_slowjoin_peer.gd -- \
	--role=host --port="$PORT" --timeout="$TIMEOUT" > "$HOST_LOG" 2>&1 &
HOST_PID=$!

sleep 1

# --- launch client ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/spawn_probe_slowjoin_peer.gd -- \
	--role=client --port="$PORT" --timeout="$TIMEOUT" > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

# --- wait for both to finish (each bounded by its own --timeout) ---
wait "$CLIENT_PID"
CLIENT_EXIT=$?
wait "$HOST_PID" 2>/dev/null
HOST_EXIT=$?

echo "--- host.log ($HOST_LOG) ---"
cat "$HOST_LOG"
echo "--- client.log ($CLIENT_LOG) ---"
cat "$CLIENT_LOG"
echo "---"

PASS=1

if [ "$CLIENT_EXIT" -ne 0 ]; then
	echo "SPAWN SLOWJOIN: client process exited non-zero ($CLIENT_EXIT)"
	PASS=0
fi
if [ "$HOST_EXIT" -ne 0 ]; then
	echo "SPAWN SLOWJOIN: host process exited non-zero ($HOST_EXIT)"
	PASS=0
fi

if grep -qE "\[ERROR\]|\[SLOWJOIN\](\[[a-z]+\])? ERROR|FAIL" "$HOST_LOG"; then
	echo "SPAWN SLOWJOIN: host.log contains an ERROR/FAIL marker"
	PASS=0
fi
if grep -qE "\[ERROR\]|\[SLOWJOIN\](\[[a-z]+\])? ERROR|FAIL" "$CLIENT_LOG"; then
	echo "SPAWN SLOWJOIN: client.log contains an ERROR/FAIL marker"
	PASS=0
fi
if grep -qi "pending spawn" "$HOST_LOG" "$CLIENT_LOG"; then
	echo "SPAWN SLOWJOIN: a log contains the pending-spawn engine error"
	PASS=0
fi

# The core TK-P2-30 assertion: the host must have EXTENDED the grace for the
# still-connected slow client, and must NOT have force-disconnected it.
if ! grep -q "extending grace" "$HOST_LOG"; then
	echo "SPAWN SLOWJOIN: host.log missing 'extending grace' (the grace-extension path did not run -- the client arrived too fast, or the fix is absent)"
	PASS=0
fi
if grep -q "force-disconnecting still-unready peer" "$HOST_LOG"; then
	echo "SPAWN SLOWJOIN: host.log shows a force-disconnect of a still-unready peer (the healthy slow client was killed -- the TK-P2-30 bug)"
	PASS=0
fi

if ! grep -q "SLOWJOIN_PASS" "$CLIENT_LOG"; then
	echo "SPAWN SLOWJOIN: client.log missing SLOWJOIN_PASS (the late client was not spawned after the grace extension)"
	PASS=0
fi

if [ "$PASS" -eq 1 ]; then
	echo "SPAWN SLOWJOIN: PASS"
	exit 0
else
	echo "SPAWN SLOWJOIN: FAIL"
	exit 1
fi
