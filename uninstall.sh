#!/usr/bin/env bash
#
# uninstall.sh - Helper to uninstall zed-themes for the current user.
#
# Behavior:
# - Attempts to restore the most recent backup created by the installer, if present.
# - If a symlink exists at ~/.config/zed/themes it will be removed.
# - If no backup is found and no symlink exists, will remove the target directory if present (with confirmation).
#
# This script is a small wrapper around the installer's uninstall logic; it calls
# the repo's install.sh with the `--uninstall` flag by default. It adds a small
# CLI for convenience and safety (dry-run, explicit confirmation).
#
# Usage:
#   ./uninstall.sh              # interactive uninstall
#   ./uninstall.sh --yes        # non-interactive (assume yes)
#   ./uninstall.sh --dry-run    # show what would happen
#   ./uninstall.sh --help
#

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$REPO_DIR/install.sh"
USER_TARGET="$HOME/.config/zed/themes"

DRY_RUN=false
ASSUME_YES=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --yes        Assume "yes" for any prompts (non-interactive).
  --dry-run    Show actions that would be performed without executing them.
  -h, --help   Show this help message.
EOF
  exit 1
}

# Simple arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) ASSUME_YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

confirm() {
  if [ "$ASSUME_YES" = true ]; then
    return 0
  fi
  printf "%s [y/N]: " "$1"
  read -r ans || return 1
  case "$ans" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# Prefer delegating to install.sh if it exists and is executable.
if [ -x "$INSTALL_SH" ]; then
  CMD="\"$INSTALL_SH\" --uninstall"
  if [ "$ASSUME_YES" = true ]; then
    CMD="$CMD --yes"
  fi
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would run: $CMD"
    exit 0
  else
    log "Running: $CMD"
    exec "$INSTALL_SH" --uninstall $( [ "$ASSUME_YES" = true ] && echo --yes || true )
  fi
fi

# Fallback: reimplement uninstall behavior locally if install.sh is missing.
log "install.sh not found or not executable at $INSTALL_SH — running fallback uninstall steps."

if [ -L "$USER_TARGET" ]; then
  LINK_TARGET="$(readlink "$USER_TARGET" || true)"
  if [ -z "$LINK_TARGET" ]; then
    LINK_TARGET="<unknown>"
  fi
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would remove symlink: $USER_TARGET -> $LINK_TARGET"
    exit 0
  fi
  if confirm "Remove symlink $USER_TARGET -> $LINK_TARGET ?" ; then
    rm -f "$USER_TARGET"
    log "Removed symlink $USER_TARGET"
    exit 0
  else
    log "Aborted by user."
    exit 0
  fi
fi

# Look for backups and restore the latest one if present.
DIR="$(dirname "$USER_TARGET")"
BASE="$(basename "$USER_TARGET")"
LATEST_BACKUP="$(ls -1dt "$DIR/${BASE}.backup."* 2>/dev/null || true | head -n1 || true)"

if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would restore backup: $LATEST_BACKUP -> $USER_TARGET"
    exit 0
  fi
  if confirm "Restore backup $LATEST_BACKUP -> $USER_TARGET ?" ; then
    rm -rf "$USER_TARGET" || true
    mv "$LATEST_BACKUP" "$USER_TARGET"
    log "Restored backup: $LATEST_BACKUP -> $USER_TARGET"
    exit 0
  else
    log "Aborted by user."
    exit 0
  fi
fi

# No symlink and no backup found. Offer to remove the target directory if it exists.
if [ -e "$USER_TARGET" ]; then
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would remove directory: $USER_TARGET"
    exit 0
  fi
  if confirm "No backup found. Remove $USER_TARGET (this will delete the directory) ?" ; then
    rm -rf "$USER_TARGET"
    log "Removed $USER_TARGET"
    exit 0
  else
    log "Aborted by user."
    exit 0
  fi
fi

log "Nothing to uninstall: $USER_TARGET does not exist and no backups were found."
exit 0