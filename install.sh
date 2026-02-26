#!/usr/bin/env bash
# install.sh - Installer / bootstrapper for zed-themes repo
#
# Responsibilities:
# - Install themes for the current user (symlink by default) into ~/.config/zed/themes
# - Optionally copy instead of symlink
# - Provide system-wide install (to /usr/local/share/zed/themes) if requested (requires sudo)
# - Create helper scripts in the repo: update.sh, uninstall.sh
# - Create a minimal validator script: scripts/validate_theme.py
# - Create README.md, LICENSE (MIT) and a GitHub Actions workflow for validation/releases
# - Optionally create and install a user launchd plist for quarterly auto-updates (macOS)
#
# Usage:
#   ./install.sh [--system] [--copy] [--dry-run] [--yes] [--bootstrap] [--uninstall] [--update] [--interval <seconds>]
#
# Typical:
#   ./install.sh                # symlink themes into ~/.config/zed/themes (per-user)
#   ./install.sh --copy         # copy themes into ~/.config/zed/themes
#   ./install.sh --system       # install into /usr/local/share/zed/themes (requires sudo)
#   ./install.sh --bootstrap   # create helper scripts, README, LICENSE, CI workflow, validator
#   ./install.sh --update      # pull and run installer (expects repo to be a git repo)
#   ./install.sh --uninstall   # restore backup or remove symlink
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$REPO_DIR/themes"
USER_TARGET="$HOME/.config/zed/themes"
SYSTEM_TARGET="/usr/local/share/zed/themes"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.zed.themes.autoupdate.plist"
AUTO_UPDATE_INTERVAL_SECONDS_DEFAULT=$(( 60 * 60 * 24 * 90 )) # ~quarterly (90 days)

MODE="symlink"   # or "copy"
SYSTEM=false
DRY_RUN=false
ASSUME_YES=false
BOOTSTRAP=false
DO_UPDATE=false
DO_UNINSTALL=false
AUTO_UPDATE_INTERVAL_SECONDS="$AUTO_UPDATE_INTERVAL_SECONDS_DEFAULT"

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --system             Install system-wide to $SYSTEM_TARGET (requires sudo)
  --copy               Copy files instead of creating symlinks (per-user or system)
  --dry-run            Print actions without performing them
  --yes                Assume yes for destructive actions (non-interactive)
  --bootstrap          Create helper scripts, README, LICENSE, CI workflow, validator
  --update             Run update (git pull && install)
  --uninstall          Uninstall: restore backup or remove symlink
  --interval <secs>    When used with --bootstrap, set auto-update interval (seconds). Defaults to quarterly (~90 days).
  -h, --help           Show this help
EOF
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --system) SYSTEM=true; shift ;;
    --copy) MODE="copy"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --bootstrap) BOOTSTRAP=true; shift ;;
    --update) DO_UPDATE=true; shift ;;
    --uninstall) DO_UNINSTALL=true; shift ;;
    --interval) shift; AUTO_UPDATE_INTERVAL_SECONDS="$1"; shift ;;
    -h|--help) usage ;;
    *) err "Unknown arg: $1"; usage ;;
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

run_or_echo() {
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] $*"
  else
    eval "$@"
  fi
}

ensure_source_exists() {
  if [ ! -d "$SOURCE_DIR" ]; then
    err "Themes source directory not found: $SOURCE_DIR"
    exit 2
  fi
}

backup_existing_target() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    local ts
    ts="$(date +%Y%m%dT%H%M%S)"
    local backup="${target}.backup.${ts}"
    log "Backing up existing $target -> $backup"
    run_or_echo "mv \"$target\" \"$backup\""
  fi
}

install_symlink() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    backup_existing_target "$target"
  elif [ -L "$target" ]; then
    log "Removing existing symlink $target"
    run_or_echo "rm -f \"$target\""
  fi
  log "Creating symlink: $target -> $SOURCE_DIR"
  run_or_echo "ln -s \"$SOURCE_DIR\" \"$target\""
}

install_copy() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup_existing_target "$target"
  fi
  log "Copying themes from $SOURCE_DIR -> $target"
  run_or_echo "mkdir -p \"$target\""
  run_or_echo "cp -a \"$SOURCE_DIR/\"* \"$target/\""
}

perform_install() {
  ensure_source_exists
  if [ "$SYSTEM" = true ]; then
    log "System-wide install to $SYSTEM_TARGET"
    if [ "$MODE" = "symlink" ]; then
      # For system-wide, prefer copying to avoid symlinks pointing into user's repo
      log "System install with symlink requested; will copy instead for safety."
    fi
    if [ "$DRY_RUN" = true ]; then
      log "[DRY RUN] sudo mkdir -p \"$SYSTEM_TARGET\""
      log "[DRY RUN] sudo cp -a \"$SOURCE_DIR/\"* \"$SYSTEM_TARGET/\""
    else
      if [ "$ASSUME_YES" = false ]; then
        confirm "This will modify $SYSTEM_TARGET (requires sudo). Continue?" || { log "Aborting."; exit 0; }
      fi
      sudo mkdir -p "$SYSTEM_TARGET"
      sudo rm -rf "$SYSTEM_TARGET"
      sudo mkdir -p "$SYSTEM_TARGET"
      sudo cp -a "$SOURCE_DIR/." "$SYSTEM_TARGET/"
      log "Installed to $SYSTEM_TARGET"
      log "To make these available for current user, you can symlink:"
      log "  rm -rf \"$USER_TARGET\" && ln -s \"$SYSTEM_TARGET\" \"$USER_TARGET\""
    fi
    return 0
  fi

  # Per-user
  if [ "$MODE" = "symlink" ]; then
    if [ -e "$USER_TARGET" ] && [ ! -L "$USER_TARGET" ]; then
      if [ "$ASSUME_YES" = false ]; then
        confirm "Will backup existing $USER_TARGET before creating symlink. Continue?" || { log "Aborting."; exit 0; }
      fi
    fi
    install_symlink "$USER_TARGET"
  else
    if [ "$ASSUME_YES" = false ]; then
      confirm "Will copy themes into $USER_TARGET (existing will be backed up). Continue?" || { log "Aborting."; exit 0; }
    fi
    install_copy "$USER_TARGET"
  fi

  log "Install complete. Restart Zed if it's running."
}

perform_uninstall() {
  # Attempt to restore a backup if one exists (pick the latest)
  if [ -L "$USER_TARGET" ]; then
    local link_target
    link_target="$(readlink "$USER_TARGET" || true)"
    if [ "$ASSUME_YES" = false ]; then
      confirm "Remove symlink $USER_TARGET -> $link_target ?" || { log "Aborting."; exit 0; }
    fi
    run_or_echo "rm -f \"$USER_TARGET\""
    log "Removed symlink $USER_TARGET"
    return 0
  fi

  # Look for backups
  local dir
  dir="$(dirname "$USER_TARGET")"
  local base
  base="$(basename "$USER_TARGET")"
  local latest
  latest="$(ls -1dt "$dir/${base}.backup."* 2>/dev/null || true | head -n1 || true)"
  if [ -n "$latest" ] && [ -d "$latest" ]; then
    if [ "$ASSUME_YES" = false ]; then
      confirm "Restore backup $latest -> $USER_TARGET ?" || { log "Aborting."; exit 0; }
    fi
    run_or_echo "rm -rf \"$USER_TARGET\""
    run_or_echo "mv \"$latest\" \"$USER_TARGET\""
    log "Restored backup $latest -> $USER_TARGET"
    return 0
  fi

  if [ -e "$USER_TARGET" ]; then
    if [ "$ASSUME_YES" = false ]; then
      confirm "Remove $USER_TARGET ?" || { log "Aborting."; exit 0; }
    fi
    run_or_echo "rm -rf \"$USER_TARGET\""
    log "Removed $USER_TARGET"
  else
    log "Nothing to uninstall at $USER_TARGET"
  fi
}

perform_update() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    err "Repository at $REPO_DIR is not a git repo. Cannot update."
    exit 3
  fi
  log "Updating repository (git pull origin)"
  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] (cd \"$REPO_DIR\" && git pull --ff-only)"
  else
    (cd "$REPO_DIR" && git pull --ff-only)
  fi
  log "Running install after update..."
  perform_install
}

# BOOTSTRAP: create helper scripts and support files
bootstrap_create_update_sh() {
  cat > "$REPO_DIR/update.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"
git pull --ff-only
exec "$REPO_DIR/install.sh" --yes
SH
  chmod +x "$REPO_DIR/update.sh"
  log "Created update.sh"
}

bootstrap_create_uninstall_sh() {
  cat > "$REPO_DIR/uninstall.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$REPO_DIR/install.sh" --uninstall --yes
SH
  chmod +x "$REPO_DIR/uninstall.sh"
  log "Created uninstall.sh"
}

bootstrap_create_validator() {
  mkdir -p "$REPO_DIR/scripts"
  cat > "$REPO_DIR/scripts/validate_theme.py" <<'PY'
#!/usr/bin/env python3
"""
Simple validator for Zed theme files.
- Checks JSON files under themes/ (recursively)
- Ensures they are valid JSON and contain at least a "name" key.
Usage: ./scripts/validate_theme.py [themes/]
"""
import json
import sys
from pathlib import Path

def validate_file(p: Path):
    try:
        data = json.loads(p.read_text(encoding='utf-8'))
    except Exception as e:
        print(f"INVALID JSON: {p}: {e}")
        return False
    if not isinstance(data, dict):
        print(f"INVALID STRUCTURE (not object): {p}")
        return False
    if "name" not in data:
        print(f"MISSING 'name' KEY: {p}")
        return False
    return True

def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('themes')
    if not root.exists():
        print(f"No themes directory at {root}")
        sys.exit(1)
    ok = True
    for p in sorted(root.rglob('*.json')):
        if not validate_file(p):
            ok = False
    if not ok:
        sys.exit(2)
    print("All theme JSON files look good.")
    sys.exit(0)

if __name__ == '__main__':
    main()
PY
  chmod +x "$REPO_DIR/scripts/validate_theme.py"
  log "Created scripts/validate_theme.py"
}

bootstrap_create_readme_and_license() {
  cat > "$REPO_DIR/README.md" <<'MD'
# zed-themes

Repository of Zed editor themes.

Quick install (per-user, symlink):
```bash
git clone <repo_url> ~/zed-themes
cd ~/zed-themes
./install.sh
```

Options:
- `--copy` : copy themes into `~/.config/zed/themes` instead of symlinking
- `--system`: install system-wide to `/usr/local/share/zed/themes` (requires sudo)
- `--bootstrap`: create helper scripts and CI files
- `--update`: run `git pull` and reinstall
- `--uninstall`: restore previous backup or remove symlink

Auto-update:
- You can enable quarterly auto-updates using the `--bootstrap` option (it will create a launchd plist).
MD

  cat > "$REPO_DIR/LICENSE" <<'LIC'
MIT License

Copyright (c) YEAR Your Name

Permission is hereby granted, free of charge, to any person obtaining a copy
...
(replace this with full MIT text in real repo)
LIC

  log "Created README.md and LICENSE (placeholder)"
}

bootstrap_create_github_workflow() {
  mkdir -p "$REPO_DIR/.github/workflows"
  cat > "$REPO_DIR/.github/workflows/validate-and-release.yml" <<'YML'
name: Validate themes & Release

on:
  push:
    tags:
      - 'v*'
  pull_request:
    paths:
      - 'themes/**'
      - 'scripts/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.x'
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      - name: Validate theme JSON
        run: |
          python3 scripts/validate_theme.py themes || (echo "Validation failed" && exit 1)

  release:
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - uses: actions/checkout@v4
      - name: Create release assets
        run: |
          echo "Packaging themes into zip"
          zip -r zed-themes-${{ github.ref_name }} themes || true
      - name: Upload release asset
        uses: softprops/action-gh-release@v1
        with:
          name: zed-themes-${{ github.ref_name }}.zip
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
YML

  log "Created GitHub Actions workflow .github/workflows/validate-and-release.yml"
}

bootstrap_create_launchd_plist() {
  # create plist content but don't load it automatically unless user runs install with permission
  cat > "$REPO_DIR/com.zed.themes.autoupdate.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.zed.themes.autoupdate</string>
    <key>ProgramArguments</key>
    <array>
      <string>$REPO_DIR/update.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>$AUTO_UPDATE_INTERVAL_SECONDS</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$REPO_DIR/logs/autoupdate.out.log</string>
    <key>StandardErrorPath</key>
    <string>$REPO_DIR/logs/autoupdate.err.log</string>
  </dict>
</plist>
PLIST
  log "Created com.zed.themes.autoupdate.plist in repo. To install for user run:"
  log "  cp \"$REPO_DIR/com.zed.themes.autoupdate.plist\" \"$LAUNCHD_PLIST\" && launchctl load -w \"$LAUNCHD_PLIST\""
}

bootstrap_create_gitignore() {
  cat > "$REPO_DIR/.gitignore" <<GIT
# backups and logs
*.backup.*
logs/
GIT
  log "Created .gitignore"
}

bootstrap_all() {
  bootstrap_create_update_sh
  bootstrap_create_uninstall_sh
  bootstrap_create_validator
  bootstrap_create_readme_and_license
  bootstrap_create_github_workflow
  bootstrap_create_launchd_plist
  bootstrap_create_gitignore
  log "Bootstrap completed. Review and commit the newly created files."
  log "Recommended next steps:"
  log "  cd \"$REPO_DIR\" && git add . && git commit -m \"bootstrap zed-themes repo\""
  log "  (optional) create remote and push: git remote add origin <url> && git push -u origin main"
}

# Main dispatch
if [ "$BOOTSTRAP" = true ]; then
  log "Bootstrapping helper files..."
  bootstrap_all
  # Do not exit here if user also wants install; but if they did only bootstrap, we can exit.
fi

if [ "$DO_UPDATE" = true ]; then
  perform_update
  exit 0
fi

if [ "$DO_UNINSTALL" = true ]; then
  perform_uninstall
  exit 0
fi

# Default action: perform install
perform_install

# If bootstrap was requested earlier, also remind about launchd installation
if [ "$BOOTSTRAP" = true ]; then
  log ""
  log "If you want to enable quarterly auto-updates (launchd), run:"
  log "  cp \"$REPO_DIR/com.zed.themes.autoupdate.plist\" \"$LAUNCHD_PLIST\""
  log "  launchctl load -w \"$LAUNCHD_PLIST\""
  log "You can adjust the interval by editing the plist's StartInterval value before loading."
fi

exit 0