#!/usr/bin/env bash
# tests/net/_port_alloc.sh
#
# Shared ENet port allocation for the tests/net/run_*.sh drivers.
# Sourced, never executed:  . "$SCRIPT_DIR/_port_alloc.sh"
#
# WHY THIS EXISTS
# ---------------
# Each driver has its own documented default port (net_smoke 7777, spawn_probe
# 7778, together 7779, tag_detect 7780, slowjoin 7781) so the drivers do not
# collide with each OTHER. That is enough for one working tree.
#
# It stops being enough the moment two agents work in parallel: with one git
# worktree per agent, agent A and agent B both run run_spawn_probe.sh, both
# bind 7778, and the second one fails on a port already in use -- a failure that
# looks exactly like a real networking regression. run_bot_outer.sh (7777) also
# overlaps run_net_smoke.sh (7777) even inside a single tree.
#
# POLICY (least surprise first)
#   1. An explicit env override always wins, untouched. Existing invocations
#      like `NET_SMOKE_PORT=7788 bash tests/net/run_net_smoke.sh` behave exactly
#      as before, and so do the permission rules that allowlist them.
#   2. In the PRIMARY working tree (and therefore in CI, which checks out a
#      normal clone) the documented default is used verbatim -- ports stay
#      7777..7781 exactly as the driver headers advertise.
#   3. In a LINKED git worktree (created by tools/new_worktree.sh) the port is
#      shifted into that worktree's own deterministic band, so parallel agents
#      never share a port. Deterministic rather than random so a given worktree
#      always reuses the same port: logs stay comparable and Windows Firewall
#      only prompts once per worktree.
#   4. Whatever step 2/3 chose, if the port is actually busy right now, walk to
#      the next band until a free one is found. This also covers a stale peer
#      from a previous run that has not exited yet.
#
# The band step (20) is wider than the number of drivers (5), so a worktree's
# five ports can never overlap another worktree's five.

# Guard against being sourced twice (drivers may be nested in future).
if [ -n "${TK_PORT_ALLOC_LOADED:-}" ]; then
	return 0 2>/dev/null || true
fi
TK_PORT_ALLOC_LOADED=1

TK_PORT_BAND_STEP="${TK_PORT_BAND_STEP:-20}"
TK_PORT_MAX_BANDS="${TK_PORT_MAX_BANDS:-40}"

# _tk_port_is_free <port>
# Returns 0 (true) when nothing is listening on the UDP port.
#
# ENet is UDP, so a TCP-only check would report a busy port as free. Probing
# methods are tried best-first; if none is available we assume free rather than
# blocking a test run on a missing tool.
_tk_port_is_free() {
	_tkp_port="$1"

	# 1. Python: the only check here that actually binds the UDP port, i.e. the
	#    only one that tells the truth on every platform. python3 on CI/Linux,
	#    py on the Windows dev box.
	for _tkp_py in python3 py python; do
		if command -v "$_tkp_py" >/dev/null 2>&1; then
			if "$_tkp_py" -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.bind(('127.0.0.1', int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
" "$_tkp_port" >/dev/null 2>&1; then
				return 0
			else
				return 1
			fi
		fi
	done

	# 2. ss / netstat: text scan, good enough as a fallback.
	if command -v ss >/dev/null 2>&1; then
		if ss -uan 2>/dev/null | grep -q "[:.]${_tkp_port}[[:space:]]"; then
			return 1
		fi
		return 0
	fi
	if command -v netstat >/dev/null 2>&1; then
		if netstat -an 2>/dev/null | grep -qi "udp.*[:.]${_tkp_port}[[:space:]]"; then
			return 1
		fi
		return 0
	fi

	# 3. No probe available -- assume free.
	return 0
}

# _tk_worktree_band <repo_root>
# 0 for the primary working tree, a stable 1..(TK_PORT_MAX_BANDS-1) for a
# linked worktree.
#
# The band comes from the worktree's POSITION in git's own registry
# ($GIT_COMMON_DIR/worktrees/<name>), sorted by name. That is unique by
# construction, which a hash of the path is not: an earlier version of this
# file hashed the path modulo the band count and two of six worktrees
# ("gameplay-engineer" and "polish-agent") landed on the same band -- a
# birthday collision at ~35% odds for six trees, which would have put two
# agents back on the same port and reintroduced exactly the bug this file
# exists to prevent.
#
# Only filesystem names are compared, never paths, because `git worktree list`
# prints Windows-style paths (C:/Users/...) while $PWD in Git Bash is
# /c/Users/... and the two would never match.
#
# Removing a worktree renumbers the ones after it. That is fine: the numbering
# only has to be unique among the worktrees that exist right now.
_tk_worktree_band() {
	_tkb_root="$1"

	if [ ! -f "$_tkb_root/.git" ]; then
		echo 0
		return 0
	fi

	if command -v git >/dev/null 2>&1; then
		_tkb_gitdir="$(git -C "$_tkb_root" rev-parse --git-dir 2>/dev/null)"
		_tkb_common="$(git -C "$_tkb_root" rev-parse --git-common-dir 2>/dev/null)"
		_tkb_name="$(basename "${_tkb_gitdir:-}" 2>/dev/null)"

		if [ -n "$_tkb_name" ] && [ -d "$_tkb_common/worktrees/$_tkb_name" ]; then
			_tkb_idx="$(ls "$_tkb_common/worktrees" 2>/dev/null | LC_ALL=C sort \
				| awk -v want="$_tkb_name" '{ if ($0 == want) { print NR; exit } }')"
			if [ -n "$_tkb_idx" ]; then
				echo $(( (_tkb_idx - 1) % (TK_PORT_MAX_BANDS - 1) + 1 ))
				return 0
			fi
		fi
	fi

	# Fallback when git is unavailable or the registry cannot be read: hash the
	# path. Collisions are possible here, but the busy-port walk in _tk_alloc
	# still resolves them at run time.
	if command -v cksum >/dev/null 2>&1; then
		_tkb_hash="$(printf '%s' "$_tkb_root" | cksum | awk '{print $1}')"
	else
		_tkb_hash="$(printf '%s' "$_tkb_root" | od -An -tu1 2>/dev/null \
			| awk '{for (i = 1; i <= NF; i++) s += $i} END {print s + 0}')"
	fi
	[ -n "$_tkb_hash" ] || _tkb_hash=1

	# 1..MAX-1: never 0, which is reserved for the primary tree.
	echo $(( _tkb_hash % (TK_PORT_MAX_BANDS - 1) + 1 ))
}

# tk_alloc_port <explicit_override> <documented_default> <repo_root> <label>
# Echoes the port to use. <explicit_override> is the caller's env var, possibly
# empty; when set it is returned as-is with no probing at all.
tk_alloc_port() {
	_tk_alloc "$1" "$2" "$3" "${4:-NET}" worktree
}

# tk_alloc_port_sticky <explicit_override> <preferred> <repo_root> <label>
# Same, but never applies the worktree shift -- it stays on the preferred port
# unless that port is genuinely busy right now.
#
# For run_bot_outer.sh, where a HUMAN types the address into the MainMenu join
# box: 7777 is NetworkManager/MainMenu's own default, so silently moving it in
# a worktree would make every manual session start with a typo-prone custom
# port for no benefit (nobody runs two human playtest sessions at once).
tk_alloc_port_sticky() {
	_tk_alloc "$1" "$2" "$3" "${4:-NET}" sticky
}

# _tk_alloc <explicit> <default> <repo_root> <label> <worktree|sticky>
_tk_alloc() {
	_tka_explicit="$1"
	_tka_default="$2"
	_tka_root="$3"
	_tka_label="$4"
	_tka_mode="$5"

	if [ -n "$_tka_explicit" ]; then
		echo "$_tka_explicit"
		return 0
	fi

	if [ "$_tka_mode" = "sticky" ]; then
		_tka_band=0
	else
		_tka_band="$(_tk_worktree_band "$_tka_root")"
	fi
	_tka_try=0
	while [ "$_tka_try" -lt "$TK_PORT_MAX_BANDS" ]; do
		_tka_port=$(( _tka_default + (_tka_band + _tka_try) % TK_PORT_MAX_BANDS * TK_PORT_BAND_STEP ))
		if _tk_port_is_free "$_tka_port"; then
			if [ "$_tka_port" -ne "$_tka_default" ]; then
				echo "$_tka_label: port $_tka_default unavailable or worktree-shifted -> using $_tka_port" >&2
			fi
			echo "$_tka_port"
			return 0
		fi
		_tka_try=$(( _tka_try + 1 ))
	done

	# Everything in the range looked busy. Fall back to the documented default
	# and let the peer report the real bind error rather than failing silently
	# here with a port the caller never asked for.
	echo "$_tka_label: no free port found in ${_tka_default}..$(( _tka_default + TK_PORT_MAX_BANDS * TK_PORT_BAND_STEP )); falling back to $_tka_default" >&2
	echo "$_tka_default"
}
