#!/usr/bin/env bash
# tests/net/run_spawn_probe_together.sh
#
# TK-P2-13 readiness-BARRIER S1 regression probe (companion to
# run_spawn_probe.sh, which covers the OLD staggered-connect path). Launches a
# headless host + client (tests/net/spawn_probe_together_peer.gd) that connect
# over real ENet on localhost while in a "Waiting Room" (no arena yet), THEN
# both enter TestArena in PRODUCTION host-FIRST ordering (host enters, then the
# client), and asserts:
#   - the CLIENT own barrier-spawned Player exists under TestArena/Players,
#     named str(own_id), with the client itself as multiplayer authority
#   - the HOST own Player (named "1") also replicated to the client
#   - the client Player position is neither (0,0,0) nor the host slot-0 position
#     (host-seeded spawn state arrived; host slot 0 / client slot 1 ordering
#     did not stack anyone at the origin)
#   - neither log contains an ERROR marker
#
# The fix under test (networking/PlayerSpawner.gd): the host runs a readiness
# BARRIER -- it spawns NOTHING (not even its own Player) until every connected
# peer has announced its arena spawner exists (_rpc_arena_ready), then spawns
# everyone at once. Without it, the host's early own-Player spawn poisons the
# per-peer node-path cache toward the not-yet-arrived client, so the client's
# own later spawn is dropped PERMANENTLY and its Player never appears -> this
# probe FAILs (SPAWN_TOGETHER_PASS never printed). Verified: FAILs against the
# pre-barrier code, PASSes with the barrier.
#
# Usage (Git Bash on Windows, or bash on Linux CI):
#   GODOT_BIN=/path/to/godot ./tests/net/run_spawn_probe_together.sh
#
# Env overrides:
#   GODOT_BIN              path to Godot (default: local Windows console build)
#   SPAWN_TOGETHER_PORT    ENet port (default: 7779, distinct from the others)
#   SPAWN_TOGETHER_TIMEOUT per-instance --timeout in seconds (default: 25)

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
PORT="${SPAWN_TOGETHER_PORT:-7779}"
TIMEOUT="${SPAWN_TOGETHER_TIMEOUT:-25}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_spawn_together.XXXXXX" 2>/dev/null || mktemp -d)"
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

echo "SPAWN TOGETHER: repo root = $REPO_ROOT"
echo "SPAWN TOGETHER: logs      = $LOG_DIR"
echo "SPAWN TOGETHER: godot bin = $GODOT_BIN"
echo "SPAWN TOGETHER: port      = $PORT"

# --- launch host (stays in Waiting Room until the client connects) ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/spawn_probe_together_peer.gd -- \
	--role=host --port="$PORT" --timeout="$TIMEOUT" > "$HOST_LOG" 2>&1 &
HOST_PID=$!

sleep 1

# --- launch client ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/spawn_probe_together_peer.gd -- \
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
	echo "SPAWN TOGETHER: client process exited non-zero ($CLIENT_EXIT)"
	PASS=0
fi
if [ "$HOST_EXIT" -ne 0 ]; then
	echo "SPAWN TOGETHER: host process exited non-zero ($HOST_EXIT)"
	PASS=0
fi

if grep -qE "\[ERROR\]|\[TOGETHER\](\[[a-z]+\])? ERROR|FAIL" "$HOST_LOG"; then
	echo "SPAWN TOGETHER: host.log contains an ERROR/FAIL marker"
	PASS=0
fi
if grep -qE "\[ERROR\]|\[TOGETHER\](\[[a-z]+\])? ERROR|FAIL" "$CLIENT_LOG"; then
	echo "SPAWN TOGETHER: client.log contains an ERROR/FAIL marker"
	PASS=0
fi
if grep -qi "pending spawn" "$HOST_LOG" "$CLIENT_LOG"; then
	echo "SPAWN TOGETHER: a log contains the pending-spawn engine error"
	PASS=0
fi

if ! grep -q "SPAWN_TOGETHER_PASS" "$CLIENT_LOG"; then
	echo "SPAWN TOGETHER: client.log missing SPAWN_TOGETHER_PASS (client own Player was not swept in)"
	PASS=0
fi

if [ "$PASS" -eq 1 ]; then
	echo "SPAWN TOGETHER: PASS"
	exit 0
else
	echo "SPAWN TOGETHER: FAIL"
	exit 1
fi
