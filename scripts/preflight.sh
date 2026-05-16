#!/usr/bin/env bash
#
# preflight.sh — Last check before bumping the Homebrew tap.
# Builds and tests a fresh clone of the repo in a stripped environment,
# so anything that only works because of the local state will fail here
# instead of on a collaborator's machine.
#
# Exit codes:
#   0 — preflight clean; safe to bump the tap.
#   non-zero — one of the steps below failed; investigate before bumping.
#
# Usage:
#   ./scripts/preflight.sh

# fail fast: any error, unset var, or broken pipe aborts the script
set -euo pipefail

# create a unique tempdir under $TMPDIR for the rehearsal clone
PREFLIGHT_DIR=$(mktemp -d -t aurora-preflight-XXXXXX)
# always clean up the tempdir on exit, even if the script fails
trap 'rm -rf "$PREFLIGHT_DIR"' EXIT

# clone committed state only — --no-local forces a real clone, no hardlinks back to .git/
git clone --no-local "file://$(git rev-parse --show-toplevel)" "$PREFLIGHT_DIR/aurora"
# operate inside the fresh clone, not the working tree
cd "$PREFLIGHT_DIR/aurora"

# strip the environment; pass only the minimum swift needs to run
env -i HOME="$HOME" PATH="$PATH" SHELL="$SHELL" bash -c '
    # log the toolchain version so the failure log shows which swift built it
    swift --version | head -1
    # same command Homebrew runs — if this breaks, brew install will too
    swift build -c release --disable-sandbox
    # full test suite, no --filter — preflight runs everything
    swift test
'

echo "✓ preflight passed; safe to bump tap"
