#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ uncommitted changes; commit or stash before pushing." >&2
    exit 1
fi

# Loop 1: unit tests
swift test --filter auroraTests

# Loop 2: release build + integration tests
swift build -c release --disable-sandbox
swift test --filter auroraIntegrationTests

echo "✓ pre-push gate passed"
