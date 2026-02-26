#!/usr/bin/env bash
# update.sh - Pull latest changes for the zed-themes repo and run install.sh
#
# Usage:
#   ./update.sh             # pull current branch (fast-forward only) and run install.sh --yes
#   ./update.sh --branch X  # pull branch X
#   ./update.sh --remote R  # pull from remote R (default: origin)
#   ./update.sh --dry-run   # show actions without performing them
#   ./update.sh --no-install # update repo but do not run install.sh
#   ./update.sh --help
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE="origin"
DRY_RUN=false
NO_INSTALL=false
ASSUME_YES=true
BRANCH=""
LOG_DIR="$REPO_DIR/logs"
LOG_FILE="$LOG_DIR/update-$(date +%Y%m%dT%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

err() {
  printf 'ERROR: %s\n' "$*" | tee -a "$LOG_FILE" >&2
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --remote <name>     Remote name to pull from (default: origin)
  --branch <name>     Branch to pull (default: current checked-out branch)
  --dry-run           Show actions but don't perform them
  --no-install        Do not run install.sh after updating
  --help              Show this help
USAGE
  exit 1
}

# Simple arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      shift
      REMOTE="${1:-}"
      if [ -z "$REMOTE" ]; then err "--remote requires a value"; usage; fi
      shift
      ;;
    --branch)
      shift
      BRANCH="${1:-}"
      if [ -z "$BRANCH" ]; then err "--branch requires a value"; usage; fi
      shift
      ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --no-install)
      NO_INSTALL=true; shift ;;
    --help|-h)
      usage ;;
    *)
      err "Unknown argument: $1"
      usage
      ;;
  esac
done

cd "$REPO_DIR"

if [ ! -d ".git" ]; then
  err "Not a git repository: $REPO_DIR"
  exit 2
fi

# Determine branch if not provided
if [ -z "$BRANCH" ]; then
  # Use git symbolic-ref; fallback to rev-parse in detached HEAD
  if BR="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"; then
    BRANCH="$BR"
  else
    BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
  fi
fi

log "Repository: $REPO_DIR"
log "Remote: $REMOTE"
log "Branch: $BRANCH"
log "Dry run: $DRY_RUN"
log "No install: $NO_INSTALL"
log "Log file: $LOG_FILE"
log "----"

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] $*"
  else
    log "[RUN] $*"
    eval "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

# Fetch and attempt fast-forward pull
run_cmd "git fetch --prune \"$REMOTE\""

# Ensure the branch exists on remote before pulling (best-effort)
if ! git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
  log "Warning: branch '$BRANCH' not found on remote '$REMOTE'. Attempting to pull anyway (may fail)."
fi

# Do a fast-forward-only pull
if [ "$DRY_RUN" = true ]; then
  run_cmd "git merge --ff-only \"$REMOTE/$BRANCH\""
else
  # Use git pull --ff-only which is equivalent to fetch + merge --ff-only
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # Ensure we're on the branch before pulling
    current="$(git symbolic-ref --quiet --short HEAD || echo '')"
    if [ "$current" != "$BRANCH" ]; then
      log "Switching to branch $BRANCH"
      git checkout "$BRANCH" 2>&1 | tee -a "$LOG_FILE"
    fi
  else
    log "Local branch $BRANCH does not exist. Creating tracking branch from $REMOTE/$BRANCH (if available)."
    if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
      git checkout -b "$BRANCH" "$REMOTE/$BRANCH" 2>&1 | tee -a "$LOG_FILE"
    else
      err "Cannot create local branch $BRANCH because $REMOTE/$BRANCH does not exist."
      exit 3
    fi
  fi

  log "Pulling updates (fast-forward only) from $REMOTE/$BRANCH..."
  if ! git pull --ff-only "$REMOTE" "$BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
    err "git pull failed (non-fast-forward or other error). Aborting update."
    exit 4
  fi
fi

log "Update complete."

if [ "$NO_INSTALL" = false ]; then
  INSTALL_SCRIPT="$REPO_DIR/install.sh"
  if [ ! -x "$INSTALL_SCRIPT" ]; then
    if [ -f "$INSTALL_SCRIPT" ]; then
      log "Making install.sh executable"
      run_cmd "chmod +x \"$INSTALL_SCRIPT\""
    else
      err "install.sh not found in repo; skipping install step."
      exit 0
    fi
  fi

  log "Running install.sh --yes"
  if [ "$DRY_RUN" = true ]; then
    run_cmd "\"$INSTALL_SCRIPT\" --yes"
  else
    # Use exec so the install script's exit code becomes this script's exit code
    "$INSTALL_SCRIPT" --yes 2>&1 | tee -a "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]:-0}
    if [ "$EXIT_CODE" -ne 0 ]; then
      err "install.sh exited with code $EXIT_CODE"
      exit "$EXIT_CODE"
    fi
  fi
else
  log "Skipping install step as requested."
fi

log "All done."
exit 0