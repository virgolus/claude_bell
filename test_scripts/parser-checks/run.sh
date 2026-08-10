#!/bin/bash
# Regression checks for TranscriptParser.
#
# `swift test` needs XCTest (or swift-testing), which ships with Xcode — not
# with the Command Line Tools alone. This compiles the real parser source
# together with the check harness so the suite runs on any machine that can
# already `swift build` the app.
#
# Usage: test_scripts/parser-checks/run.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

swiftc -O \
    -o "$build_dir/parser-checks" \
    "$repo_root/Sources/Transcript/TranscriptParser.swift" \
    "$script_dir/main.swift"

"$build_dir/parser-checks"
