#!/usr/bin/env bash
# One-time developer setup: downloads the pinned Godot engine into .tools/godot
# (git-ignored) and imports the project. Works on Windows (Git Bash), Linux and macOS.
#
#   tools/setup.sh               # engine only (enough to run, test and edit)
#   tools/setup.sh --templates   # also install export templates (~1.2 GB) to build the .exe
set -euo pipefail

VERSION="4.7.2"
TAG="${VERSION}-stable"
BASE="https://github.com/godotengine/godot/releases/download/${TAG}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.tools/godot"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ZIP="Godot_v${TAG}_win64.exe.zip"; OS=windows ;;
  Darwin)               ZIP="Godot_v${TAG}_macos.universal.zip"; OS=macos ;;
  *)                    ZIP="Godot_v${TAG}_linux.x86_64.zip"; OS=linux ;;
esac

mkdir -p "$DEST"
touch "$ROOT/.tools/.gdignore"
if [ -z "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "Downloading Godot ${TAG} for ${OS}..."
  curl -fL --progress-bar -o "$DEST/godot.zip" "$BASE/$ZIP"
  (cd "$DEST" && unzip -q -o godot.zip && rm godot.zip)
  [ "$OS" = linux ] && chmod +x "$DEST"/Godot_v*_linux.x86_64
else
  echo "Godot already present in .tools/godot"
fi

if [ "${1:-}" = "--templates" ]; then
  case "$OS" in
    windows) TDIR="$APPDATA/Godot/export_templates/${VERSION}.stable" ;;
    macos)   TDIR="$HOME/Library/Application Support/Godot/export_templates/${VERSION}.stable" ;;
    *)       TDIR="$HOME/.local/share/godot/export_templates/${VERSION}.stable" ;;
  esac
  echo "Downloading export templates (~1.2 GB)..."
  TMP="$(mktemp -d)"
  curl -fL --progress-bar -o "$TMP/templates.tpz" "$BASE/Godot_v${TAG}_export_templates.tpz"
  mkdir -p "$TDIR"
  unzip -q -o -j "$TMP/templates.tpz" -d "$TDIR"
  rm -rf "$TMP"
  echo "Templates installed to $TDIR"
fi

echo "Importing project (first run builds the .godot cache)..."
"$ROOT/tools/gd.sh" import >/dev/null 2>&1 || true
echo "Done. Try:  tools/gd.sh run      (play)"
echo "            tools/gd.sh test     (headless test suite)"
