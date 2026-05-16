#!/usr/bin/env bash
#
# post-install-smoke.sh — Run AFTER bump-tap.sh.
# Installs (or upgrades) aurora via Homebrew the same way a user would,
# then runs the installed binary and asserts on its output. This is the
# only gate that exercises Homebrew's install sandbox end-to-end — what
# preflight simulates locally, this gate runs for real.
#
# Exit codes:
#   0 — brew install/upgrade succeeded and the binary produced expected output.
#   non-zero — brew failed, binary missing from PATH, or output mismatched.
#
# Usage:
#   ./scripts/post-install-smoke.sh

set -euo pipefail

# user/tap/formula — per-project, not per-developer, so hardcoded
FORMULA="nessbautista/aurora/aurora"

# clear error before the script tries to use brew below
if ! command -v brew >/dev/null 2>&1; then
    echo "✗ Homebrew not found on PATH. Install brew first, then re-run." >&2
    exit 1
fi

# upgrade if installed, else first-time install — both need --HEAD/--fetch-HEAD for head-only formulas
brew upgrade --fetch-HEAD "$FORMULA" || brew install --HEAD "$FORMULA"

# run the freshly-installed binary; proves it landed on PATH, launches, and links correctly
ACTUAL=$(aurora hello smoke)
EXPECTED="Hello, smoke!"
# exact match — any other output is a real failure to investigate
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo "✗ smoke output mismatch" >&2
    echo "  expected: $EXPECTED" >&2
    echo "  got:      $ACTUAL" >&2
    exit 1
fi

echo "✓ post-install smoke passed"
