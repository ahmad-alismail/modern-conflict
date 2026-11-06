#!/usr/bin/env bash
# Dev helper for Modern Conflict. Usage:
#   tools/gd.sh import            # (re)import resources + refresh class cache
#   tools/gd.sh check            # parse-check all scripts
#   tools/gd.sh test [filter]     # run headless tests
#   tools/gd.sh shot out.png [delay] [extra args...]   # windowed screenshot
#   tools/gd.sh run [args...]     # run the game windowed
#   tools/gd.sh export            # build/ModernConflict.exe
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$ROOT/.tools/godot/Godot_v4.7.2-stable_win64_console.exe"
cmd="$1"; shift || true
case "$cmd" in
  import) "$GODOT" --headless --path "$ROOT" --import 2>&1 | grep -vE "^\s*$|Godot Engine|^--- Debug" || true ;;
  check)  "$GODOT" --headless --path "$ROOT" -s res://tools/check.gd 2>&1 | grep -E "SCRIPT ERROR|at: GDScript::reload|FAILED|checked" ;;
  test)   "$GODOT" --headless --path "$ROOT" -s res://tests/run_tests.gd -- "--filter=${1:-}" ;;
  shot)   out="$1"; delay="${2:-4}"; shift 2 || shift $#; mkdir -p "$ROOT/shots"; touch "$ROOT/shots/.gdignore"
          "$GODOT" --path "$ROOT" --resolution 1600x900 -- "--shot=$ROOT/shots/$out" "--shot-delay=$delay" "$@" ;;
  run)    "$GODOT" --path "$ROOT" -- "$@" ;;
  export) mkdir -p "$ROOT/build"; "$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" "$ROOT/build/ModernConflict.exe" ;;
  *) echo "unknown command: $cmd"; exit 1 ;;
esac
