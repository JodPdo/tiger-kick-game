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
#     signal -- exactly what a human host clicking Start does. TK-P3-11: the
#     host now runs as a TRUE dedicated host (NetworkManager.dedicated_host_
#     no_self_spawn=true, set right after host() succeeds) -- it never spawns
#     a Player of its own at all, so it can never be picked/tagged as Tiger
#     and softlock a match; it does not run the bot AI either way. This does
#     add an extra ~12s "first Tiger" grace delay to EVERY match (see bot_
#     outer_peer.gd's own class doc "KNOWN, ACCOUNTED-FOR SIDE EFFECT" note)
#     -- already covered by this script's generous default BOT_TIMEOUT, but
#     budget it yourself if you pass a tighter one alongside BOT_MATCHES.
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
#   BOT_PORT      ENet port (default: 7777 -- NetworkManager/MainMenu's own
#                 default, so the join box works unchanged. Unlike the automated
#                 probes this one is NOT shifted per worktree; it only moves if
#                 7777 is genuinely busy. See tests/net/_port_alloc.sh)
#   BOT_COUNT     how many headless bot clients to launch (default: 1)
#   HUMAN_COUNT   how many REAL human clients you intend to also join with
#                 (default: 1) -- used only to compute EXPECTED_PLAYERS
#                 (host + BOT_COUNT + HUMAN_COUNT) so the host knows when to
#                 auto-start; it does not launch anything for you.
#   BOT_TIMEOUT   safety-net ceiling in seconds for every process, host and
#                 bots alike (default: 3600 = 1 hour; not a pass/fail
#                 deadline, just so a forgotten session doesn't run forever).
#                 TK-P3-11: since the host now runs as a true dedicated host
#                 (see above), every single match pays an extra ~12s "first
#                 Tiger" grace delay on top of roster-settle + Countdown +
#                 round time (see bot_outer_peer.gd's own class doc) -- if you
#                 override this to something tighter than the 3600s default
#                 while also passing BOT_MATCHES=N, budget that ~12s * N in.
#   BOT_MATCHES   TK-P3-09 -- optional --matches=N passthrough to every
#                 launched process (host + bots alike). Once N matches have
#                 completed, that process ends cleanly (_finish(0)) instead of
#                 re-arming for another one -- default unset/unlimited (keeps
#                 re-arming across returns to a fresh Waiting Room until
#                 BOT_TIMEOUT eventually cuts it off). Useful for a scripted
#                 CASE E session (TK-P2-15 qa_verdict checklist) that wants an
#                 exact number of match cycles, e.g. BOT_MATCHES=2.
#
# Stop the whole session with Ctrl+C (cleans up every process this script
# started, mirrors run_spawn_probe_together.sh's own trap cleanup).

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
BOT_COUNT="${BOT_COUNT:-1}"
HUMAN_COUNT="${HUMAN_COUNT:-1}"
TIMEOUT="${BOT_TIMEOUT:-3600}"
MATCHES="${BOT_MATCHES:-}"
EXPECTED_PLAYERS=$((1 + BOT_COUNT + HUMAN_COUNT)) # host + bots + human(s)

MATCHES_ARGS=()
if [ -n "$MATCHES" ]; then
	MATCHES_ARGS=(--matches="$MATCHES")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Sticky on purpose: a human types this port into the MainMenu join box, so it
# stays 7777 even in a worktree, and only moves if 7777 is actually taken.
# shellcheck source=tests/net/_port_alloc.sh
. "$SCRIPT_DIR/_port_alloc.sh"
PORT="$(tk_alloc_port_sticky "${BOT_PORT:-}" 7777 "$REPO_ROOT" "BOT OUTER")"

BASE_TMP="${TMPDIR:-${TMP:-/tmp}}"
LOG_DIR="$(mktemp -d "$BASE_TMP/tigerkick_bot_outer.XXXXXX" 2>/dev/null || mktemp -d)"
HOST_LOG="$LOG_DIR/host.log"

echo "BOT OUTER: repo root         = $REPO_ROOT"
echo "BOT OUTER: logs              = $LOG_DIR"
echo "BOT OUTER: godot bin         = $GODOT_BIN"
echo "BOT OUTER: port              = $PORT"
echo "BOT OUTER: bot count         = $BOT_COUNT"
echo "BOT OUTER: expected players  = $EXPECTED_PLAYERS (host + $BOT_COUNT bot(s) + $HUMAN_COUNT human(s))"
echo "BOT OUTER: matches           = ${MATCHES:-unlimited (re-arms until timeout)}"
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
	"${MATCHES_ARGS[@]}" \
	> "$HOST_LOG" 2>&1 &
PIDS+=("$!")

sleep 1

# --- launch BOT_COUNT bot clients ---
for i in $(seq 1 "$BOT_COUNT"); do
	BOT_LOG="$LOG_DIR/bot_$i.log"
	echo "BOT OUTER: bot $i log = $BOT_LOG"
	"$GODOT_BIN" --headless --path "$REPO_ROOT" -s res://tests/net/bot_outer_peer.gd -- \
		--role=bot --address=127.0.0.1 --port="$PORT" --timeout="$TIMEOUT" \
		"${MATCHES_ARGS[@]}" \
		> "$BOT_LOG" 2>&1 &
	PIDS+=("$!")
	sleep 0.5
done

echo "BOT OUTER: host log = $HOST_LOG"
echo "BOT OUTER: running -- Ctrl+C to stop the whole session (host + $BOT_COUNT bot(s))."

wait
