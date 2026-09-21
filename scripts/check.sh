#!/bin/bash
# Runs every check before a commit: tests, library and demo builds for each platform, and the docs site.
#
# Requires Xcode 26+. The docs step needs mkdocs on PATH (see requirements-docs.txt); pass --no-docs to skip it.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/.build/check"

# keep xcodebuild output here even when Xcode's build location is set to a custom folder
XCODE_OUTPUT=(SYMROOT="$BUILD/products" OBJROOT="$BUILD/intermediates" SHARED_PRECOMPS_DIR="$BUILD/intermediates/pch")

step() { printf '\n==> %s\n' "$1"; }

step "Tests (macOS)"
xcrun swift test

for platform in macOS iOS tvOS; do
    step "Library ($platform)"
    xcodebuild build -scheme SKTiled -destination "generic/platform=$platform" \
        -derivedDataPath "$BUILD/derived" "${XCODE_OUTPUT[@]}" -quiet
done

for destination in 'platform=macOS' 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator'; do
    step "Demo ($destination)"
    xcodebuild build -project Demo/SKTiledDemo.xcodeproj -scheme SKTiledDemo -destination "$destination" \
        -derivedDataPath "$BUILD/derived" "${XCODE_OUTPUT[@]}" CODE_SIGNING_ALLOWED=NO -quiet
done

if [[ "${1:-}" != "--no-docs" ]]; then
    step "Docs"
    scripts/build-docs.sh
fi

step "All checks passed"
