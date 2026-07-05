#!/usr/bin/env bash
# tests/net/run_spawn_probe.sh
#
# TK-BUG-P1-01 / TK-BUG-P1-02 regression probe (seed for TK-P1-07): launches
# a headless host + client (tests/net/spawn_probe_peer.gd) that connect over
# real ENet on localhost, load the FULL TestArena scene, and assert:
#   - the client own spawned Player position is neither (0,0,0) nor the
#     host slot-0 position (no stacking, no discarded spawn state)
#   - neither log contains an ERROR line (in particular no "unable to
#     process the pending spawn" engine error)
#   - once the host process is killed, the client server_disconnected
#     path fires (both the probe own marker and TestArena.gd log line)
#
# Usage (Git Bash on Windows, or bash on Linux CI):
#   GODOT_BIN=/path/to/godot ./tests/net/run_spawn_probe.sh
#
# Env overrides:
#   GODOT_BIN     path to the Godot executable (default: local Windows console build)
#   SPAWN_PROBE_PORT     ENet port to use (default: 7778, distinct from run_net_smoke.sh default)
#   SPAWN_PROBE_TIMEOUT  per-instance --timeout in seconds (default: 20)

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
PORT="${SPAWN_PROBE_PORT:-7778}"
TIMEOUT="${SPAWN_PROBE_TIMEOUT:-20}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_spawn_probe.XXXXXX" 2>/dev/null || mktemp -d)"
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

echo "SPAWN PROBE: repo root = $REPO_ROOT"
echo "SPAWN PROBE: logs      = $LOG_DIR"
echo "SPAWN PROBE: godot bin = $GODOT_BIN"
echo "SPAWN PROBE: port      = $PORT"

# --- launch host ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/spawn_probe_peer.gd -- \
	--role=host --port="$PORT" --timeout="$TIMEOUT" > "$HOST_LOG" 2>&1 &
HOST_PID=$!

sleep 1

# --- launch client ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/spawn_probe_peer.gd -- \
	--role=client --port="$PORT" --timeout="$TIMEOUT" > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

# --- wait for the client spawn check to land, then kill the host to
#     exercise the TK-BUG-P1-02 disconnect path ---
SPAWN_WAIT_DEADLINE=$((SECONDS + TIMEOUT))
while [ "$SECONDS" -lt "$SPAWN_WAIT_DEADLINE" ]; do
	if grep -q "SPAWN_CHECK_PASS" "$CLIENT_LOG" 2>/dev/null; then
		break
	fi
	if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
		break
	fi
	sleep 0.5
done

echo "SPAWN PROBE: killing host process to exercise disconnect path"
if kill -0 "$HOST_PID" 2>/dev/null; then
	kill "$HOST_PID" 2>/dev/null
fi

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
	echo "SPAWN PROBE: client process exited non-zero ($CLIENT_EXIT)"
	PASS=0
fi

# NOTE: the host process is deliberately force-killed below (simulating a
# real "host quits"/crash) to exercise the TK-BUG-P1-02 disconnect path --
# an abrupt kill (vs. a clean quit()) can print benign engine-shutdown
# noise ("BUG: Unreferenced static string...", "RID allocations... leaked
# at exit", etc.) that has nothing to do with networking/spawning. We
# therefore check for our OWN explicit error markers (GameLog's "[ERROR]"
# tag and this probe/NetworkManager's own "ERROR"-prefixed prints) plus the
# exact TK-BUG-P1-01 symptom string, rather than a blanket "ERROR" grep
# that would also flag that unrelated shutdown noise.
if grep -qE "\[ERROR\]|\[PROBE\]\[[a-z]+\] ERROR" "$HOST_LOG"; then
	echo "SPAWN PROBE: host.log contains a GameLog/probe ERROR line"
	PASS=0
fi
if grep -qE "\[ERROR\]|\[PROBE\]\[[a-z]+\] ERROR" "$CLIENT_LOG"; then
	echo "SPAWN PROBE: client.log contains a GameLog/probe ERROR line"
	PASS=0
fi
if grep -qi "pending spawn" "$HOST_LOG" "$CLIENT_LOG"; then
	echo "SPAWN PROBE: a log contains the pending-spawn engine error"
	PASS=0
fi

if ! grep -q "SPAWN_CHECK_PASS" "$CLIENT_LOG"; then
	echo "SPAWN PROBE: client.log missing SPAWN_CHECK_PASS (spawn desync/stack not ruled out)"
	PASS=0
fi
if ! grep -q "SERVER_DISCONNECTED_SIGNAL_FIRED" "$CLIENT_LOG"; then
	echo "SPAWN PROBE: client.log missing SERVER_DISCONNECTED_SIGNAL_FIRED (disconnect path not exercised)"
	PASS=0
fi

if [ "$PASS" -eq 1 ]; then
	echo "SPAWN PROBE: PASS"
	exit 0
else
	echo "SPAWN PROBE: FAIL"
	exit 1
fi
