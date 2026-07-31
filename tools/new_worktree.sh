#!/usr/bin/env bash
# tools/new_worktree.sh
#
# Create an isolated git worktree so a code-writing agent can work in parallel
# without colliding with the others.
#
# WHY THIS EXISTS
# ---------------
# Two agents editing the same working tree have bitten this project twice
# already, in ways that were expensive to untangle:
#
#   * `_backlog.json` was corrupted by concurrent writes -- see the docstring of
#     tools/validate_backlog.py, which exists because of it.
#   * TK-P2-05's qa_verdict had to be qualified because the GUT run "included
#     another agent's concurrent UNCOMMITTED changes to managers/GameManager.gd
#     (TK-P2-09, not yet reviewed) since GUT runs the whole tests/ dir". The QA
#     verdict was measuring two cards at once.
#
# A worktree gives each agent its own checkout, its own branch, and -- crucially
# for this project -- its own `.godot/` import cache, so concurrent
# `--headless --import` runs cannot race. tests/net/_port_alloc.sh then shifts
# every ENet test port into a per-worktree band, so parallel net probes do not
# fight over 7777..7781 either.
#
# USAGE
#   bash tools/new_worktree.sh <agent-name> [card-id]
#   bash tools/new_worktree.sh gameplay-engineer TK-P2-31
#   bash tools/new_worktree.sh --list
#   bash tools/new_worktree.sh --remove gameplay-engineer
#
# Worktrees are created as siblings of the repo (../Tiger-Kick-wt-<agent>) so
# they never land inside the Godot project directory, where the engine would
# try to import them as project content.
#
# Env overrides:
#   GODOT_BIN       path to Godot; used for the initial import (default: the
#                   same local Windows console build the test drivers assume)
#   WORKTREE_BASE   directory to create worktrees in (default: repo's parent)
#   BASE_BRANCH     branch to fork from (default: current branch)
#   SKIP_IMPORT=1   skip the Godot import step (faster; the agent's first
#                   Godot run will just do the import itself)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64_console.exe}"
WORKTREE_BASE="${WORKTREE_BASE:-$(cd "$REPO_ROOT/.." && pwd)}"
SKIP_IMPORT="${SKIP_IMPORT:-}"

PREFIX="Tiger-Kick-wt-"

die() {
	echo "::error::$*" >&2
	exit 1
}

usage() {
	sed -n '5,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

require_clean_git() {
	git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
		|| die "$REPO_ROOT is not a git repository"
}

cmd_list() {
	echo "worktrees for $(basename "$REPO_ROOT"):"
	git -C "$REPO_ROOT" worktree list
}

cmd_remove() {
	agent="$1"
	[ -n "$agent" ] || die "--remove needs an agent name"
	path="$WORKTREE_BASE/$PREFIX$agent"

	[ -d "$path" ] || die "no worktree at $path"

	# Refuse to throw away work. `git worktree remove` also refuses, but its
	# message does not say what to do about it.
	if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
		echo "worktree $path has uncommitted changes:" >&2
		git -C "$path" status --short >&2
		die "commit or discard them first, then re-run --remove"
	fi

	git -C "$REPO_ROOT" worktree remove "$path" \
		|| die "git worktree remove failed for $path"
	echo "removed worktree: $path"
	echo "note: branch agent/$agent still exists. Delete with: git branch -d agent/$agent"
}

cmd_create() {
	agent="$1"
	card="${2:-}"

	case "$agent" in
		-*) die "agent name cannot start with '-' (got: $agent)" ;;
		*/*) die "agent name cannot contain '/' (got: $agent)" ;;
	esac

	# Only agents that actually write files need a worktree. The read-only ones
	# can safely share the primary tree, and giving them one just wastes disk.
	case "$agent" in
		architect|code-reviewer|producer)
			echo "note: '$agent' is a read-only agent (no Edit tool / docs-only)."
			echo "      It can run in the primary tree alongside others; a worktree is optional."
			;;
	esac

	path="$WORKTREE_BASE/$PREFIX$agent"
	branch="agent/$agent"
	if [ -n "$card" ]; then
		branch="agent/$agent/$card"
	fi

	if [ -d "$path" ]; then
		echo "worktree already exists: $path"
		echo "  branch: $(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
		echo "  reuse it, or remove it with: bash tools/new_worktree.sh --remove $agent"
		exit 0
	fi

	base="${BASE_BRANCH:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)}"
	[ -n "$base" ] || die "could not determine the base branch"

	echo "creating worktree"
	echo "  agent  : $agent"
	echo "  path   : $path"
	echo "  branch : $branch (from $base)"

	if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$REPO_ROOT" worktree add "$path" "$branch" \
			|| die "git worktree add failed"
	else
		git -C "$REPO_ROOT" worktree add -b "$branch" "$path" "$base" \
			|| die "git worktree add failed"
	fi

	# .godot/ is gitignored, so the new worktree starts without an import cache.
	# Importing now means the agent's first test run is not a cold import (and,
	# more importantly, that two agents never run their first import against the
	# same cache directory).
	if [ -n "$SKIP_IMPORT" ]; then
		echo "skipping Godot import (SKIP_IMPORT set)"
	elif [ -x "$GODOT_BIN" ] || command -v "$GODOT_BIN" >/dev/null 2>&1; then
		echo "importing project (headless) so the first test run is warm..."
		if "$GODOT_BIN" --headless --path "$path" --import --quit >/dev/null 2>&1; then
			echo "import OK"
		else
			echo "warning: import returned non-zero; the agent's first Godot run will retry it" >&2
		fi
	else
		echo "warning: GODOT_BIN not found ($GODOT_BIN) -- skipping import." >&2
		echo "         Set GODOT_BIN, or let the agent's first Godot run import." >&2
	fi

	# Show the ports this worktree will use, so the agent (and the human reading
	# the log) can tell at a glance that it is not sharing with anyone.
	if [ -f "$REPO_ROOT/tests/net/_port_alloc.sh" ]; then
		# shellcheck source=tests/net/_port_alloc.sh
		. "$REPO_ROOT/tests/net/_port_alloc.sh"
		echo
		echo "ENet ports for this worktree (auto-shifted, no collision with others):"
		printf '  net_smoke      %s\n' "$(tk_alloc_port "" 7777 "$path" X 2>/dev/null)"
		printf '  spawn_probe    %s\n' "$(tk_alloc_port "" 7778 "$path" X 2>/dev/null)"
		printf '  spawn_together %s\n' "$(tk_alloc_port "" 7779 "$path" X 2>/dev/null)"
		printf '  tag_detect     %s\n' "$(tk_alloc_port "" 7780 "$path" X 2>/dev/null)"
		printf '  spawn_slowjoin %s\n' "$(tk_alloc_port "" 7781 "$path" X 2>/dev/null)"
	fi

	cat <<EOF

next steps
  cd "$path"
  python3 tools/split_backlog.py --agent $agent    # pick a ready card

when the card is done
  git -C "$path" push -u origin $branch            # then open a PR
  bash tools/new_worktree.sh --remove $agent       # after it is merged

reminders (see "Parallel work rules" in CLAUDE.md)
  * Do NOT edit _backlog.json here -- report status to producer, who is the
    single writer. Concurrent writes have corrupted it before.
  * Run GUT from THIS worktree only, so the result reflects your card alone.
EOF
}

require_clean_git

case "${1:-}" in
	""|-h|--help)  usage 0 ;;
	--list)        cmd_list ;;
	--remove)      cmd_remove "${2:-}" ;;
	*)             cmd_create "$1" "${2:-}" ;;
esac
