# Aurora — task runner
# Run `just` with no args to see available recipes.

# Show available recipes (default target)
default:
    @just --list

# Install the local pre-push git hook (idempotent; safe to re-run)
# `.git/hooks/` is untracked and per-clone, so this has to run once per
# fresh clone. `push` depends on this, so you usually don't call it directly.
install-hooks:
    @chmod +x scripts/pre-push.sh
    @ln -sf ../../scripts/pre-push.sh .git/hooks/pre-push
    @echo "✓ pre-push hook installed at .git/hooks/pre-push"

# Run Gate 1 manually (release build + integration tests).
# Use when you want to sanity-check a change without committing to a push.
gate:
    ./scripts/pre-push.sh

# Push the current branch, ensuring the pre-push hook is wired up first.
# Forwards extra args to git push (e.g. `just push --force-with-lease`).
push *ARGS: install-hooks
    git push {{ARGS}}
