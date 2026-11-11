#!/bin/bash
# Copies the Lode Runner assets used by the demo's game view from a Retro2Arcade checkout into Demo/LodeRunner/.
#
# The assets are extracted from the original 1983 disk image and are copyrighted by their publisher. They are for
# private study only: Demo/LodeRunner/ is ignored by git (except its README) so they are never committed.
#
# Usage: scripts/import-lode-runner-assets.sh [path/to/Retro2Arcade]   (default: ../Retro2Arcade)

set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE="${1:-../Retro2Arcade}/LodeRunner/assets"
DEST="Demo/LodeRunner"

[ -d "$SOURCE" ] || { echo "error: $SOURCE not found; pass the path to a Retro2Arcade checkout" >&2; exit 1; }

mkdir -p "$DEST/maps" "$DEST/tiles" "$DEST/sprites" "$DEST/audio"

# the map keeps its Tiled layout: maps/level_001.tmx references ../tiles/lode_runner_tiles.tsx
cp "$SOURCE/maps/level_001.tmx" "$DEST/maps/"
cp "$SOURCE/tiles/lode_runner_tiles.tsx" "$SOURCE/tiles/lode_runner_tiles.png" "$DEST/tiles/"
cp "$SOURCE/sprites/runner.png" "$SOURCE/sprites/guard.png" "$SOURCE/sprites/shapes.png" "$SOURCE/sprites/font.png" "$DEST/sprites/"
cp "$SOURCE"/audio/*.wav "$DEST/audio/"

echo "Copied Lode Runner assets into $DEST:"
find "$DEST" -type f ! -name README.md | sort | sed 's/^/  /'
