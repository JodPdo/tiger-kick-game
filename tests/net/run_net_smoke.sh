#!/usr/bin/env bash
# tests/net/run_net_smoke.sh
#
# TK-P0-06 Phase 0 Exit Gate automated proof: launches two headless Godot
# instances (one host, one client) that use tests/net/net_smoke_peer.gd to
# connect over ENet on localhost, then greps their logs for connection
# confirmation and prints a clear PASS/FAIL.
#
# Usage (Git Bash on Windows, or bash on Linux CI):
#   GODOT_BIN=/path/to/godot ./tests/net/run_net_smoke.sh
# Defaults to the local Windows console build if GODOT_BIN is unset.
#
# Env overrides:
#   GODOT_BIN         path to the Godot executable (default: local Windows console build)
#   NET_SMOKE_PORT    ENet port to use (default: 7777)
#   NET_SMOKE_TIMEOUT per-instance timeout in seconds (default: 10)

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
PORT="${NET_SMOKE_PORT:-7777}"
ADDRESS="127.0.0.1"
TIMEOUT="${NET_SMOKE_TIMEOUT:-10}"

# Repo root = two levels up from this script (tests/net/..).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Transient logs go to the OS temp dir -- never into the repo working tree.
BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_net_smoke.XXXXXX" 2>/dev/null || mktemp -d)"
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

echo "NET SMOKE: repo root = $REPO_ROOT"
echo "NET SMOKE: logs      = $LOG_DIR"
echo "NET SMOKE: godot bin = $GODOT_BIN"
echo "NET SMOKE: port      = $PORT"

# --- launch host ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/net_smoke_peer.gd -- \
	--role=host --port="$PORT" --timeout="$TIMEOUT" > "$HOST_LOG" 2>&1 &
HOST_PID=$!

# Give the host a moment to bind its listen socket before starting the
# client (the client script also has its own internal head-start delay).
sleep 1

# --- launch client ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/net_smoke_peer.gd -- \
	--role=client --address="$ADDRESS" --port="$PORT" --timeout="$TIMEOUT" > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

# --- wait for both to finish (each is bounded by its own --timeout) ---
wait "$CLIENT_PID"
CLIENT_EXIT=$?
wait "$HOST_PID"
HOST_EXIT=$?

echo "--- host.log ($HOST_LOG) ---"
cat "$HOST_LOG"
echo "--- client.log ($CLIENT_LOG) ---"
cat "$CLIENT_LOG"
echo "---"

PASS=1

if [ "$HOST_EXIT" -ne 0 ]; then
	echo "NET SMOKE: host process exited non-zero ($HOST_EXIT)"
	PASS=0
fi
if [ "$CLIENT_EXIT" -ne 0 ]; then
	echo "NET SMOKE: client process exited non-zero ($CLIENT_EXIT)"
	PASS=0
fi

if ! grep -q "\[NET\] peer joined" "$HOST_LOG"; then
	echo "NET SMOKE: host.log missing '[NET] peer joined'"
	PASS=0
fi
if ! grep -q "\[SMOKE\]\[host\] PEER_JOINED" "$HOST_LOG"; then
	echo "NET SMOKE: host.log missing '[SMOKE][host] PEER_JOINED'"
	PASS=0
fi
if ! grep -q "\[NET\] connection succeeded" "$CLIENT_LOG"; then
	echo "NET SMOKE: client.log missing '[NET] connection succeeded'"
	PASS=0
fi
if ! grep -q "\[SMOKE\]\[client\] CONNECTED" "$CLIENT_LOG"; then
	echo "NET SMOKE: client.log missing '[SMOKE][client] CONNECTED'"
	PASS=0
fi

if [ "$PASS" -eq 1 ]; then
	echo "NET SMOKE: PASS"
	exit 0
else
	echo "NET SMOKE: FAIL"
	exit 1
fi
