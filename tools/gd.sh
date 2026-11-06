#!/usr/bin/env bash
# Dev helper for Modern Conflict (Windows Git Bash, Linux, macOS). Usage:
#   tools/gd.sh run [args...]     # play from source (dev args after, e.g. --screen=skirmish)
#   tools/gd.sh test [filter]     # headless test suite (optionally only tests/test_<filter>*.gd)
#   tools/gd.sh check             # parse-check every script
#   tools/gd.sh import            # (re)import resources + refresh the class_name cache
#   tools/gd.sh shot out.png [delay] [extra args...]   # windowed screenshot to shots/
#   tools/gd.sh editor            # open the project in the Godot editor
#   tools/gd.sh export            # build build/ModernConflict.exe (needs export templates)
# Run tools/setup.sh once first. Set GODOT=/path/to/godot to use your own Godot 4.7.2.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) DEFAULT_GODOT="$ROOT/.tools/godot/Godot_v4.7.2-stable_win64_console.exe" ;;
  Darwin)               DEFAULT_GODOT="$ROOT/.tools/godot/Godot.app/Contents/MacOS/Godot" ;;
  *)                    DEFAULT_GODOT="$ROOT/.tools/godot/Godot_v4.7.2-stable_linux.x86_64" ;;
esac
GODOT="${GODOT:-$DEFAULT_GODOT}"
if [ ! -x "$GODOT" ] && [ ! -f "$GODOT" ]; then
  echo "Godot not found at $GODOT — run tools/setup.sh first (or set GODOT=...)." >&2
  exit 1
fi
cmd="${1:-}"; shift || true
case "$cmd" in
  import) "$GODOT" --headless --path "$ROOT" --import 2>&1 | grep -vE "^\s*$|Godot Engine|^--- Debug" || true ;;
  check)  "$GODOT" --headless --path "$ROOT" -s res://tools/check.gd 2>&1 | grep -E "SCRIPT ERROR|at: GDScript::reload|FAILED|checked" ;;
  test)   "$GODOT" --headless --path "$ROOT" -s res://tests/run_tests.gd -- "--filter=${1:-}" ;;
  shot)   out="$1"; delay="${2:-4}"; shift 2 || shift $#; mkdir -p "$ROOT/shots"; touch "$ROOT/shots/.gdignore"
          "$GODOT" --path "$ROOT" --resolution 1600x900 -- "--shot=$ROOT/shots/$out" "--shot-delay=$delay" "$@" ;;
  run)    "$GODOT" --path "$ROOT" -- "$@" ;;
  editor) "$GODOT" --editor --path "$ROOT" ;;
  export) mkdir -p "$ROOT/build"; "$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" "$ROOT/build/ModernConflict.exe" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
