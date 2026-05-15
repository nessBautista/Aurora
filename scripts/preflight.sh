#!/usr/bin/env bash
#
# preflight.sh — Gate 2. Last check before bumping the Homebrew tap.
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

set -euo pipefail                                                                # fail fast: any error, unset var, or broken pipe aborts the script

PREFLIGHT_DIR=$(mktemp -d -t aurora-preflight-XXXXXX)                            # create a unique tempdir under $TMPDIR for the rehearsal clone
trap 'rm -rf "$PREFLIGHT_DIR"' EXIT                                              # always clean up the tempdir on exit, even if the script fails

git clone --no-local "file://$(git rev-parse --show-toplevel)" "$PREFLIGHT_DIR/aurora"  # clone committed state only — --no-local forces a real clone, no hardlinks
cd "$PREFLIGHT_DIR/aurora"                                                       # operate inside the fresh clone, not the working tree

env -i HOME="$HOME" PATH="$PATH" SHELL="$SHELL" bash -c '                        # strip the environment; pass only the minimum swift needs to run
    swift --version | head -1                                                    # log the toolchain version so the failure log shows which swift built it
    swift build -c release --disable-sandbox                                     # same command Homebrew runs — if this breaks, brew install will too
    swift test                                                                   # full test suite, no --filter — preflight runs everything
'

echo "✓ preflight passed; safe to bump tap"
