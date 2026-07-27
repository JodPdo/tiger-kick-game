#!/usr/bin/env bash
# tools/show_host_log.sh
#
# Prints the Windows-style path of a directory (works whether running under
# git-bash/MSYS or plain bash) and then dumps a log file inside it.
#
# This replaces ad-hoc compound one-liners like:
#   cd /tmp/foo && pwd -W 2>/dev/null || cygpath -w "$(pwd)" 2>/dev/null || echo "no conv"; cat host.log
# which Claude Code can never statically approve (they contain &&, ||, $()).
# Because this script takes plain space-separated arguments, a single
# permission rule can cover every future invocation:
#   Bash(bash tools/show_host_log.sh *)
#
# Usage:
#   bash tools/show_host_log.sh [directory] [logfile]
#
#   directory  Folder to inspect (default: current directory)
#   logfile    Log file name inside that folder (default: host.log)

set -u

dir="${1:-.}"
logfile="${2:-host.log}"

if ! cd "$dir" 2>/dev/null; then
  echo "Could not cd into: $dir"
  exit 1
fi

winpath="$(pwd -W 2>/dev/null)"
if [ -z "$winpath" ]; then
  winpath="$(cygpath -w "$(pwd)" 2>/dev/null)"
fi
if [ -z "$winpath" ]; then
  winpath="(no windows path conversion available: $(pwd))"
fi

echo "Directory (Windows path): $winpath"
echo "--- $logfile ---"
if [ -f "$logfile" ]; then
  cat "$logfile"
else
  echo "(no such file: $logfile)"
fi
