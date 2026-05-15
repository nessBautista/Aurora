#!/usr/bin/env bash
#
# bump-tap.sh — The release ceremony. Moves the tap's git pointer forward
# with an empty commit so `brew upgrade --fetch-HEAD` notices that a new
# version exists. The formula is head-only and points at `main`, so brew
# actually installs whatever `origin/main` of the source repo points at
# when the user upgrades — NOT the SHA recorded in the bump commit message.
# That's why this script refuses to run from anywhere other than a clean,
# in-sync `main`: stamping a feature-branch SHA into the tap commit would
# silently ship `main`'s code under a misleading commit message.
#
# Reads TAP_REPO (absolute path to your local homebrew-aurora clone) from
# the repo's `.env` file. `.env` is gitignored — copy `.env.example` to
# `.env` on first setup and fill it in. You can also override per-invocation
# with `TAP_REPO=/other/path ./scripts/bump-tap.sh`.
#
# Exit codes:
#   0 — tap bumped and pushed.
#   non-zero — a guard failed (not on main, dirty tree, out of sync,
#              missing .env, missing TAP_REPO, bad tap path, push failed).
#
# Usage:
#   ./scripts/bump-tap.sh

set -euo pipefail

SOURCE_REPO="$(git rev-parse --show-toplevel)"                                   # absolute path to this (source) repo; used as the .env lookup root
ENV_FILE="$SOURCE_REPO/.env"                                                     # per-developer local config; gitignored

# --- Load TAP_REPO ----------------------------------------------------------

if [[ -z "${TAP_REPO:-}" ]]; then                                                # only load .env if TAP_REPO isn't already exported in the shell
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "✗ Missing .env at $ENV_FILE" >&2
        echo "  Copy .env.example to .env and set TAP_REPO to your homebrew-aurora clone path." >&2
        exit 1
    fi
    set -a                                                                       # auto-export anything sourced from .env so subshells (git, etc.) see it
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

if [[ -z "${TAP_REPO:-}" ]]; then                                                # .env existed but didn't define TAP_REPO (or left it blank)
    echo "✗ TAP_REPO is not set." >&2
    echo "  Define it in $ENV_FILE (see .env.example) or export it before running." >&2
    exit 1
fi

if [[ ! -d "$TAP_REPO/.git" ]]; then                                             # validate now so the error points at config, not at a confusing git error later
    echo "✗ TAP_REPO does not look like a git repo: $TAP_REPO" >&2
    exit 1
fi

# --- Source repo guards -----------------------------------------------------

BRANCH=$(git -C "$SOURCE_REPO" rev-parse --abbrev-ref HEAD)                      # current branch in the source repo
if [[ "$BRANCH" != "main" ]]; then
    echo "✗ bump-tap must run from 'main' (you're on '$BRANCH')." >&2
    echo "  Merge your feature first, then check out main and pull." >&2
    exit 1
fi

if [[ -n "$(git -C "$SOURCE_REPO" status --porcelain)" ]]; then                  # working tree must be clean — no untracked or uncommitted state
    echo "✗ uncommitted changes in source repo; commit or stash first." >&2
    exit 1
fi

git -C "$SOURCE_REPO" fetch origin main --quiet                                  # refresh origin/main so the comparison below is meaningful
LOCAL=$(git -C "$SOURCE_REPO" rev-parse main)
REMOTE=$(git -C "$SOURCE_REPO" rev-parse origin/main)
if [[ "$LOCAL" != "$REMOTE" ]]; then                                             # this is the guard that prevents the silent SHA mismatch
    echo "✗ local main ($LOCAL) is not in sync with origin/main ($REMOTE)." >&2
    echo "  Pull (or push) first so the SHA stamped into the tap matches what brew will fetch." >&2
    exit 1
fi

# --- Bump the tap -----------------------------------------------------------

SHORT_SHA=$(git -C "$SOURCE_REPO" rev-parse --short HEAD)                        # short SHA goes into the tap commit message for human-readable history

cd "$TAP_REPO"
git commit --allow-empty -m "Bump aurora to ${SHORT_SHA}"                        # empty commit moves the tap's pointer; brew compares THIS to decide upgrades
git push origin main

echo "✓ tap bumped to ${SHORT_SHA}"
