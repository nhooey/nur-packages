#!/bin/bash
# A script to idempotently clone/update a git repository.

set -euo pipefail

REPO_URL="$1"
DEST_DIR="$2"
REF="$3"

# If the git repository already exists
if [ -d "$DEST_DIR/.git" ]; then
  cd "$DEST_DIR"
  GIT_REMOTE="$(git remote -v | head -n 1 | awk '{print $2}')"

  # Confirm it's the correct git repository directory, for safety
  if [ "$GIT_REMOTE" = "$REPO_URL" ]; then
    git fetch origin

    # Check if the ref is a branch or a tag
    REMOTE_BRANCH="origin/$REF"
    if git rev-parse --verify "$REMOTE_BRANCH" >/dev/null 2>&1; then
        echo "Resetting to remote branch: $REMOTE_BRANCH"
        git reset --hard "$REMOTE_BRANCH"
    elif git rev-parse --verify "refs/tags/$REF" >/dev/null 2>&1; then
        echo "Resetting to tag: $REF"
        git reset --hard "$REF"
    else
        echo "Error: '$REF' is not a known remote branch or tag."
        exit 1
    fi
    git checkout "$REF"
    git clean -dfx
  else
    print "Error: git remote: '$GIT_REMOTE' of git directory: '$GIT_DIR' does not match specified repo URL: '$REPO_URL'. Aborting because unsafe." 1>&2
    exit 1
  fi
# Clone beause the git directory doesn't exist yet
else
  git clone --branch "$REF" "$REPO_URL" "$DEST_DIR"
fi
