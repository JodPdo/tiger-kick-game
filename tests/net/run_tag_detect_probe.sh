#!/usr/bin/env bash
# tests/net/run_tag_detect_probe.sh
#
# TK-P2-24 regression probe for the Tag detection GLUE (TK-P2-02) that GUT
# cannot cover -- launches a headless host + client
# (tests/net/tag_detect_probe_peer.gd) that connect over real ENet on
# localhost, enter res://world/TestArena.tscn together (host-first, same
# barrier flow as run_spawn_probe_together.sh), then:
#   1. the HOST teleports its own authoritative Player within tag range of
#      the client's replicated Player (no input available headless -- see
#      the peer script's own "IN-RANGE MECHANISM" doc) and asserts a real
#      Area3D overlap fires tag_target_in_range on the HOST process with the
#      correct (host_id, client_id) pair;
#   2. the CLIENT independently confirms (via the gate-free
#      get_candidates_in_range()) that its OWN local physics detected the
#      SAME overlap, while its own tag_target_in_range/tag_target_left_range
#      listener never fires -- proving TagDetectorComponent's
#      `multiplayer.is_server()` emission gate actually holds cross-process,
#      not just "nothing happened";
#   3. once both of the above are confirmed, this driver kills the CLIENT
#      process (simulating a disconnect while in range) and the HOST asserts
#      get_candidates_in_range() afterward contains NO stale entry for the
#      departed peer and raised no error/crash reading a freed body.
#
# See tests/net/tag_detect_probe_peer.gd's own class doc for the full
# rationale, the exact log markers asserted below, and the falsifiability
# argument/demonstration for each of the three checks.
#
# Usage (Git Bash on Windows, or bash on Linux CI):
#   GODOT_BIN=/path/to/godot ./tests/net/run_tag_detect_probe.sh
#
# Env overrides:
#   GODOT_BIN            path to Godot (default: local Windows console build)
#   TAG_PROBE_PORT        ENet port (default: 7780, distinct from the others)
#   TAG_PROBE_TIMEOUT     per-instance --timeout in seconds (default: 35)
#   TAG_PROBE_WAIT_SEC    max seconds this driver waits for the in-range
#                          markers before giving up and killing both
#                          processes (default: 25)

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
TIMEOUT="${TAG_PROBE_TIMEOUT:-35}"
WAIT_SEC="${TAG_PROBE_WAIT_SEC:-25}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# TAG_PROBE_PORT wins if set; otherwise 7780 in the primary tree, or this
# worktree's own band when running in parallel. See tests/net/_port_alloc.sh.
# shellcheck source=tests/net/_port_alloc.sh
. "$SCRIPT_DIR/_port_alloc.sh"
PORT="$(tk_alloc_port "${TAG_PROBE_PORT:-}" 7780 "$REPO_ROOT" "TAG DETECT PROBE")"

BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_tag_detect_probe.XXXXXX" 2>/dev/null || mktemp -d)"
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

echo "TAG DETECT PROBE: repo root = $REPO_ROOT"
echo "TAG DETECT PROBE: logs      = $LOG_DIR"
echo "TAG DETECT PROBE: godot bin = $GODOT_BIN"
echo "TAG DETECT PROBE: port      = $PORT"

# --- launch host (stays in Waiting Room until the client connects) ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/tag_detect_probe_peer.gd -- \
	--role=host --port="$PORT" --timeout="$TIMEOUT" > "$HOST_LOG" 2>&1 &
HOST_PID=$!

sleep 1

# --- launch client ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/tag_detect_probe_peer.gd -- \
	--role=client --port="$PORT" --timeout="$TIMEOUT" > "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

# --- wait for the in-range assertions to land on BOTH processes (or an
#     early FAIL marker, or one of the processes exiting on its own), then
#     kill the client to exercise the despawn edge (c) ---
DEADLINE=$((SECONDS + WAIT_SEC))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
	if grep -q "TAGPROBE_CLIENT_EMIT_FAIL" "$CLIENT_LOG" 2>/dev/null; then
		break
	fi
	if grep -q "TAG_IN_RANGE_HOST_PASS" "$HOST_LOG" 2>/dev/null && \
	   grep -q "TAG_IN_RANGE_CLIENT_DID_NOT_EMIT_PASS" "$CLIENT_LOG" 2>/dev/null; then
		break
	fi
	if ! kill -0 "$HOST_PID" 2>/dev/null || ! kill -0 "$CLIENT_PID" 2>/dev/null; then
		break
	fi
	sleep 0.5
done

echo "TAG DETECT PROBE: killing client process to exercise the despawn edge (c)"
if kill -0 "$CLIENT_PID" 2>/dev/null; then
	kill "$CLIENT_PID" 2>/dev/null
fi

# --- wait for both to finish (each bounded by its own --timeout) ---
# The client was force-killed just above, so its exit status reports the signal
# rather than anything about the run; it is deliberately not captured (see the
# NOTE below). The host's exit code IS meaningful and is gated on.
wait "$CLIENT_PID" 2>/dev/null || true
wait "$HOST_PID"
HOST_EXIT=$?

echo "--- host.log ($HOST_LOG) ---"
cat "$HOST_LOG"
echo "--- client.log ($CLIENT_LOG) ---"
cat "$CLIENT_LOG"
echo "---"

PASS=1

# NOTE: the client process is deliberately force-killed above (simulating a
# disconnect while in range) -- do not gate on its exit code (an abrupt kill
# is not a clean quit()). The host's own exit code IS meaningful (it only
# quits after the full sequence, or a bounded timeout).
if [ "$HOST_EXIT" -ne 0 ]; then
	echo "TAG DETECT PROBE: host process exited non-zero ($HOST_EXIT)"
	PASS=0
fi

if grep -qE "\[ERROR\]|\[TAGPROBE\]\[[a-z]+\] ERROR|previously freed|Nonexistent function" "$HOST_LOG"; then
	echo "TAG DETECT PROBE: host.log contains an ERROR/freed-instance marker"
	PASS=0
fi
if grep -qE "\[ERROR\]|\[TAGPROBE\]\[[a-z]+\] ERROR" "$CLIENT_LOG"; then
	echo "TAG DETECT PROBE: client.log contains an ERROR marker"
	PASS=0
fi

if grep -q "TAGPROBE_CLIENT_EMIT_FAIL" "$CLIENT_LOG"; then
	echo "TAG DETECT PROBE: client.log shows the CLIENT process emitted a tag signal -- host-only-emit gate did NOT hold"
	PASS=0
fi
if grep -q "TAGPROBE_DESPAWN_STALE_FAIL" "$HOST_LOG"; then
	echo "TAG DETECT PROBE: host.log shows a stale candidate/crash on the despawn edge"
	PASS=0
fi

if ! grep -q "TAG_IN_RANGE_HOST_PASS" "$HOST_LOG"; then
	echo "TAG DETECT PROBE: host.log missing TAG_IN_RANGE_HOST_PASS (real cross-peer Area3D overlap not proven)"
	PASS=0
fi
if ! grep -q "LOCAL_OVERLAP_DETECTED" "$CLIENT_LOG"; then
	echo "TAG DETECT PROBE: client.log missing LOCAL_OVERLAP_DETECTED (client-side overlap never independently confirmed -- the no-emit assertion below would be meaningless without this)"
	PASS=0
fi
if ! grep -q "TAG_IN_RANGE_CLIENT_DID_NOT_EMIT_PASS" "$CLIENT_LOG"; then
	echo "TAG DETECT PROBE: client.log missing TAG_IN_RANGE_CLIENT_DID_NOT_EMIT_PASS (host-only-emit gate not confirmed)"
	PASS=0
fi
if ! grep -q "TAGPROBE_DESPAWN_PASS" "$HOST_LOG"; then
	echo "TAG DETECT PROBE: host.log missing TAGPROBE_DESPAWN_PASS (despawn/ghost edge not confirmed)"
	PASS=0
fi

if [ "$PASS" -eq 1 ]; then
	echo "TAG DETECT PROBE: PASS"
	exit 0
else
	echo "TAG DETECT PROBE: FAIL"
	exit 1
fi
