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

# Resolve to the worktree root via git rather than the script's own $0.
# When invoked via .git/hooks/pre-push (a symlink), $0 is the symlink path,
# so `dirname/..` would land us in .git/ — not a worktree. `rev-parse
# --show-toplevel` is correct for both the hook and manual invocations.
cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ uncommitted changes; commit or stash before pushing." >&2
    exit 1
fi

# Loop 1: unit tests
#
# Note: there is no `auroraTests` target — `AuroraCLI` is an
# executableTarget and Xcode cannot run XCTest tests linked against an
# executable target, so CLI coverage lives only in the integration suite
# below. Library targets (e.g. AuroraKeychain/AuroraConfig/AuroraSettings
# from WOR-52 onward) have their own filtered test targets and should be
# added here once they exist on `main`.

# Loop 2: release build + integration tests
# --disable-sandbox is required for parity with `brew install`, which runs the
# same command. SwiftPM's sandbox-exec nests poorly inside Homebrew's own
# build sandbox, so brew disables SwiftPM's; we mirror that locally so a
# local pass implies a brew pass. 
swift build -c release --disable-sandbox
swift test --filter auroraIntegrationTests

echo "✓ pre-push gate passed"
