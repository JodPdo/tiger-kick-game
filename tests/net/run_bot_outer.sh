#!/usr/bin/env bash
# tests/net/run_bot_outer.sh
#
# TK-P3-07 (tools-devops) -- launches a headless HOST + one or more headless
# BOT clients (tests/net/bot_outer_peer.gd) so a human can solo-test against
# a moving target instead of an idle Outer. This is a DEV TOOL, not the
# fixed-duration pass/fail probes elsewhere in tests/net/ (run_spawn_probe*.sh,
# run_tag_detect_probe.sh, run_net_smoke.sh) -- it stays up for an interactive
# session and you stop it yourself (Ctrl+C), same idea as leaving a real
# Godot server window open.
#
# WHAT THIS STARTS:
#   - one headless HOST (real NetworkManager.host() + the REAL ui/
#     WaitingRoom.tscn scene -- see bot_outer_peer.gd's own class doc). It
#     waits for the roster (host + bot(s) + your real GUI client) to reach
#     EXPECTED_PLAYERS, then fires the REAL Start button's own `pressed`
#     signal -- exactly what a human host clicking Start does. The host
#     itself stays a passive/idle body once the match starts (dedicated
#     server), it does not run the bot AI.
#   - BOT_COUNT headless BOT clients (default 1), each its own OS process,
#     each an ordinary connected client peer that approaches the current
#     Tiger, attempts a Kick once in range, then flees, repeating.
#
# WHAT YOU DO: start this script, then open your OWN real Godot client
# normally (the actual game, not headless) and choose "Join" with the
# default address:port already pre-filled ("127.0.0.1:7777", matching
# ui/MainMenu.gd's own default -- this tool intentionally hosts on the same
# default port so you don't have to type anything). You will see yourself +
# the bot(s) in the Waiting Room roster; once EXPECTED_PLAYERS is reached
# (host + bots + you), the match starts automatically.
#
# Usage (Git Bash on Windows):
#   GODOT_BIN=/path/to/godot ./tests/net/run_bot_outer.sh
#
# Env overrides:
#   GODOT_BIN     path to Godot (default: local Windows console build)
#   BOT_PORT      ENet port (default: 7777 -- NetworkManager/MainMenu's own default)
#   BOT_COUNT     how many headless bot clients to launch (default: 1)
#   HUMAN_COUNT   how many REAL human clients you intend to also join with
#                 (default: 1) -- used only to compute EXPECTED_PLAYERS
#                 (host + BOT_COUNT + HUMAN_COUNT) so the host knows when to
#                 auto-start; it does not launch anything for you.
#   BOT_TIMEOUT   safety-net ceiling in seconds for every process, host and
#                 bots alike (default: 3600 = 1 hour; not a pass/fail
#                 deadline, just so a forgotten session doesn't run forever)
#
# Stop the whole session with Ctrl+C (cleans up every process this script
# started, mirrors run_spawn_probe_together.sh's own trap cleanup).

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
PORT="${BOT_PORT:-7777}"
BOT_COUNT="${BOT_COUNT:-1}"
HUMAN_COUNT="${HUMAN_COUNT:-1}"
TIMEOUT="${BOT_TIMEOUT:-3600}"
EXPECTED_PLAYERS=$((1 + BOT_COUNT + HUMAN_COUNT)) # host + bots + human(s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_bot_outer.XXXXXX" 2>/dev/null || mktemp -d)"
HOST_LOG="$LOG_DIR/host.log"

echo "BOT OUTER: repo root         = $REPO_ROOT"
echo "BOT OUTER: logs              = $LOG_DIR"
echo "BOT OUTER: godot bin         = $GODOT_BIN"
echo "BOT OUTER: port              = $PORT"
echo "BOT OUTER: bot count         = $BOT_COUNT"
echo "BOT OUTER: expected players  = $EXPECTED_PLAYERS (host + $BOT_COUNT bot(s) + $HUMAN_COUNT human(s))"
echo "BOT OUTER: --------------------------------------------------------------"
echo "BOT OUTER: now open your OWN real Godot client -> Join -> 127.0.0.1:$PORT"
echo "BOT OUTER: --------------------------------------------------------------"

PIDS=()

cleanup() {
	echo "BOT OUTER: stopping ($((${#PIDS[@]})) process(es))..."
	for pid in "${PIDS[@]}"; do
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null
		fi
	done
}
trap cleanup EXIT INT TERM

# --- launch host (real NetworkManager.host() + real WaitingRoom, auto-starts
#     once EXPECTED_PLAYERS have joined) ---
"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/bot_outer_peer.gd -- \
	--role=host --port="$PORT" --timeout="$TIMEOUT" --expected-players="$EXPECTED_PLAYERS" \
	> "$HOST_LOG" 2>&1 &
PIDS+=("$!")

sleep 1

# --- launch BOT_COUNT bot clients ---
for i in $(seq 1 "$BOT_COUNT"); do
	BOT_LOG="$LOG_DIR/bot_$i.log"
	echo "BOT OUTER: bot $i log = $BOT_LOG"
	"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/bot_outer_peer.gd -- \
		--role=bot --address=127.0.0.1 --port="$PORT" --timeout="$TIMEOUT" \
		> "$BOT_LOG" 2>&1 &
	PIDS+=("$!")
	sleep 0.5
done

echo "BOT OUTER: host log = $HOST_LOG"
echo "BOT OUTER: running -- Ctrl+C to stop the whole session (host + $BOT_COUNT bot(s))."

wait
