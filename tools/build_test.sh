#!/usr/bin/env bash
# tools/build_test.sh
#
# TK-P3-02: one-command "produce a fresh Windows test build" wrapper, so
# whoever runs TK-P3-03 (first real-people playtest) doesn't have to remember
# the exact `godot --headless --export-release` invocation or preset name.
#
# WHAT IT DOES
#   1. Runs a clean `--headless --import` first (export can silently pick up a
#      stale/partial .godot/ import cache otherwise -- see CLAUDE.md's
#      "Parallel work rules" for why this project is careful about that).
#   2. Runs `godot --headless --export-release "Windows Desktop" <out>` using
#      the "Windows Desktop" preset defined in export_presets.cfg (repo root).
#   3. Sanity-checks the result: the .exe exists and is a plausible size (a
#      near-zero-byte file usually means the export silently produced a stub).
#
# WHAT IT DELIBERATELY DOES NOT DO
#   - Install export templates. If Godot reports
#       "No export template found at the expected path: ...windows_release_x86_64.exe"
#     that is a one-time *host machine* setup step (Editor -> Manage Export
#     Templates, or download the matching
#     Godot_v4.7-stable_export_templates.tpz for this Godot build and let the
#     editor install it), not something this script or its diff can fix. This
#     script detects that case and prints a clear, actionable message instead
#     of a confusing engine stack trace.
#   - Launch/smoke-test the built .exe against a live match. Run it manually,
#     or drive it the same way tests/net/*.sh drive two Godot instances, if
#     you need a host-vs-client proof beyond "it launches and reaches
#     MainMenu".
#
# USAGE
#   bash tools/build_test.sh [output_exe_path]
#   bash tools/build_test.sh                         # -> build/windows/TigerKick.exe
#   bash tools/build_test.sh build/windows/Foo.exe    # custom output path
#
# Env overrides:
#   GODOT_BIN     path to the Godot editor binary used for import+export
#                 (default: local Windows editor build; use the *editor*
#                 binary, not *_console, since --export-release needs the
#                 full editor, unlike the net probes which only need the
#                 headless runtime)
#   PRESET_NAME   export preset name (default: "Windows Desktop")
#   SKIP_IMPORT=1 skip the `--import` step (faster if you just imported)

set -u

GODOT_BIN="${GODOT_BIN:-C:/Tools/Godot/Godot_v4.7-stable_win64.exe}"
PRESET_NAME="${PRESET_NAME:-Windows Desktop}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT_PATH="${1:-build/windows/TigerKick.exe}"

if [ ! -f "$REPO_ROOT/export_presets.cfg" ]; then
	echo "BUILD: export_presets.cfg not found at repo root ($REPO_ROOT)." >&2
	echo "BUILD: nothing to export -- see TK-P3-02." >&2
	exit 1
fi

echo "BUILD: repo root = $REPO_ROOT"
echo "BUILD: godot bin  = $GODOT_BIN"
echo "BUILD: preset     = $PRESET_NAME"
echo "BUILD: out path   = $OUT_PATH"

if [ "${SKIP_IMPORT:-0}" != "1" ]; then
	echo "BUILD: importing assets (--headless --import)..."
	if ! "$GODOT_BIN" --headless --path "$REPO_ROOT" --import; then
		echo "BUILD: import failed -- see engine output above." >&2
		exit 1
	fi
fi

echo "BUILD: exporting..."
EXPORT_LOG="$(mktemp "${TMPDIR:-${TMP:-/tmp}}/tigerkick_export.XXXXXX" 2>/dev/null || mktemp)"
"$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "$PRESET_NAME" "$OUT_PATH" > "$EXPORT_LOG" 2>&1
EXPORT_EXIT=$?
cat "$EXPORT_LOG"

if grep -q "No export template found" "$EXPORT_LOG"; then
	echo "---"
	echo "BUILD: FAIL -- export templates for this Godot build are not installed on this machine."
	echo "BUILD: this is a one-time host-machine setup step, not something a code change fixes:"
	echo "BUILD:   Editor -> Manage Export Templates -> Download and Install (must match the"
	echo "BUILD:   engine version reported by '\"$GODOT_BIN\" --version'), or download"
	echo "BUILD:   Godot_v4.7-stable_export_templates.tpz manually and let the editor install it."
	rm -f "$EXPORT_LOG"
	exit 1
fi

rm -f "$EXPORT_LOG"

if [ "$EXPORT_EXIT" -ne 0 ]; then
	echo "BUILD: FAIL -- godot --export-release exited $EXPORT_EXIT."
	exit 1
fi

OUT_ABS="$REPO_ROOT/$OUT_PATH"
if [ ! -f "$OUT_ABS" ]; then
	echo "BUILD: FAIL -- export reported success but $OUT_ABS does not exist."
	exit 1
fi

OUT_SIZE=$(wc -c < "$OUT_ABS" 2>/dev/null || echo 0)
echo "BUILD: exported $OUT_ABS ($OUT_SIZE bytes)"

# A real Godot+PCK export is tens of MB at minimum (engine binary alone is
# well over 30MB); anything under ~1MB almost certainly means embed_pck
# produced a stub, not a full-fat build.
MIN_BYTES=1000000
if [ "$OUT_SIZE" -lt "$MIN_BYTES" ]; then
	echo "BUILD: FAIL -- output is suspiciously small ($OUT_SIZE bytes < $MIN_BYTES)."
	exit 1
fi

echo "BUILD: PASS -- $OUT_ABS looks like a real build. Launch it manually to confirm it reaches MainMenu."
exit 0
