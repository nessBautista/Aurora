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

# absolute path to this (source) repo; used as the .env lookup root
SOURCE_REPO="$(git rev-parse --show-toplevel)"
# per-developer local config; gitignored
ENV_FILE="$SOURCE_REPO/.env"

# --- Load TAP_REPO ----------------------------------------------------------

# only load .env if TAP_REPO isn't already exported in the shell
if [[ -z "${TAP_REPO:-}" ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "✗ Missing .env at $ENV_FILE" >&2
        echo "  Copy .env.example to .env and set TAP_REPO to your homebrew-aurora clone path." >&2
        exit 1
    fi
    # auto-export anything sourced from .env so subshells (git, etc.) see it
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# .env existed but didn't define TAP_REPO (or left it blank)
if [[ -z "${TAP_REPO:-}" ]]; then
    echo "✗ TAP_REPO is not set." >&2
    echo "  Define it in $ENV_FILE (see .env.example) or export it before running." >&2
    exit 1
fi

# validate now so the error points at config, not at a confusing git error later
if [[ ! -d "$TAP_REPO/.git" ]]; then
    echo "✗ TAP_REPO does not look like a git repo: $TAP_REPO" >&2
    exit 1
fi

# --- Source repo guards -----------------------------------------------------

# current branch in the source repo
BRANCH=$(git -C "$SOURCE_REPO" rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "✗ bump-tap must run from 'main' (you're on '$BRANCH')." >&2
    echo "  Merge your feature first, then check out main and pull." >&2
    exit 1
fi

# working tree must be clean — no untracked or uncommitted state
if [[ -n "$(git -C "$SOURCE_REPO" status --porcelain)" ]]; then
    echo "✗ uncommitted changes in source repo; commit or stash first." >&2
    exit 1
fi

# refresh origin/main so the comparison below is meaningful
git -C "$SOURCE_REPO" fetch origin main --quiet
LOCAL=$(git -C "$SOURCE_REPO" rev-parse main)
REMOTE=$(git -C "$SOURCE_REPO" rev-parse origin/main)
# this is the guard that prevents the silent SHA mismatch
if [[ "$LOCAL" != "$REMOTE" ]]; then
    echo "✗ local main ($LOCAL) is not in sync with origin/main ($REMOTE)." >&2
    echo "  Pull (or push) first so the SHA stamped into the tap matches what brew will fetch." >&2
    exit 1
fi

# --- Bump the tap -----------------------------------------------------------

# short SHA goes into the tap commit message for human-readable history
SHORT_SHA=$(git -C "$SOURCE_REPO" rev-parse --short HEAD)

cd "$TAP_REPO"
# empty commit moves the tap's pointer; brew compares THIS to decide upgrades
git commit --allow-empty -m "Bump aurora to ${SHORT_SHA}"
git push origin main

echo "✓ tap bumped to ${SHORT_SHA}"
