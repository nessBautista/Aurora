#!/usr/bin/env bash
#
# pre-push.sh — Runs automatically on `git push` via .git/hooks/pre-push.
# Blocks the push if the working tree is dirty, unit tests fail, or the
# release build + integration tests fail. Local CI; trust it.
#
# Exit codes:
#   0 — gate passed; push proceeds.
#   non-zero — dirty tree, build failure, or test failure; push is aborted.
#
# Usage:
#   ./scripts/pre-push.sh    # manual dry-run
#   (otherwise invoked automatically by git)

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
