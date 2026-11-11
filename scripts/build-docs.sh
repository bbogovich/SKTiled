#!/bin/bash
# Builds the documentation site: MkDocs guides in site/, DocC API reference in site/api/.
#
# Requires Xcode 26+ and the Python packages in requirements-docs.txt:
#   python3 -m venv .venv && .venv/bin/pip install -r requirements-docs.txt
#   PATH="$PWD/.venv/bin:$PATH" scripts/build-docs.sh
#
# Set HOSTING_BASE_PATH to the site's path on the web server (default: SKTiled/api for GitHub Pages).

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/.build/docs"
HOSTING_BASE_PATH="${HOSTING_BASE_PATH:-SKTiled/api}"

command -v mkdocs >/dev/null || { echo "error: mkdocs not found; see requirements-docs.txt" >&2; exit 1; }

echo "Building guides (MkDocs)…"
mkdocs build --clean

echo "Building API reference (DocC)…"
rm -rf "$BUILD"
xcodebuild docbuild \
    -scheme SKTiled \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD/derived" \
    SYMROOT="$BUILD/products" \
    OBJROOT="$BUILD/intermediates" \
    SHARED_PRECOMPS_DIR="$BUILD/intermediates/PrecompiledHeaders" \
    OTHER_DOCC_FLAGS="--warnings-as-errors" \
    -quiet

# SYMROOT/OBJROOT keep the output here even when Xcode's build location is set to a custom folder
ARCHIVE=$(find "$BUILD" -type d -name 'SKTiled.doccarchive' | head -1)
[ -n "$ARCHIVE" ] || { echo "error: SKTiled.doccarchive was not produced" >&2; exit 1; }

xcrun docc process-archive transform-for-static-hosting "$ARCHIVE" \
    --output-path "$ROOT/site/api" \
    --hosting-base-path "$HOSTING_BASE_PATH"

echo "Done: site/index.html (guides), site/api/documentation/sktiled/ (API reference)"
