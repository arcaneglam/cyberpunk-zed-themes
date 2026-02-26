#!/usr/bin/env bash
#
# publish-release.sh -- small helper to create a draft GitHub release (gh CLI) and open it in browser for one-click publish
#
# Features:
# - Zips the `themes/` directory into a release asset (optional)
# - Creates a draft release using `gh release create` so you can inspect and click "Publish"
# - Optionally attaches additional assets
# - Opens the release page in your browser for final approval
#
# Usage:
#   ./publish-release.sh --tag v1.0.0 [--title "Release title"] [--notes-file CHANGELOG.md]
#                        [--assets path/to/asset1 path/to/asset2 ...] [--zip-themes] [--prerelease] [--yes]
#
# Examples:
#   ./publish-release.sh --tag v1.0.0 --title "Initial release" --zip-themes
#   ./publish-release.sh --tag v1.0.1 --notes-file RELEASE_NOTES.md --assets builds/zed-themes.zip --yes
#
# Requirements:
# - `gh` CLI installed and authenticated (gh auth login)
# - `zip` available (only required if using --zip-themes)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
THEMES_DIR="$REPO_ROOT/themes"
DIST_DIR="$REPO_ROOT/dist"
DEFAULT_ZIP_NAME=""
DRY_RUN=false

# Defaults
TAG=""
TITLE=""
NOTES_FILE=""
ASSETS=()
ZIP_THEMES=false
DRAFT=true
PRERELEASE=false
ASSUME_YES=false
CLEANUP_AFTER=true

print_usage() {
  cat <<USAGE
publish-release.sh - Create a GitHub draft release for this repo and open it in the browser.

Usage:
  $(basename "$0") --tag <tag> [options]

Required:
  --tag <tag>                Release tag (e.g. v1.0.0)

Options:
  --title <title>            Release title (defaults to tag)
  --notes-file <file>        Path to a file containing release notes (markdown). If omitted, you can edit on GitHub.
  --assets <p1> [p2 ...]     Asset paths to upload (space-separated). Can be repeated; script also auto-attaches zip if --zip-themes.
  --zip-themes               Zip the local themes/ dir and upload as an asset (saved to dist/)
  --no-draft                 Create a published release immediately (NOT recommended)
  --prerelease               Mark the release as a prerelease
  --yes                      Assume yes for prompts (non-interactive)
  --no-cleanup               Keep generated zip files in dist/ (default: cleanup after uploading)
  --dry-run                  Print actions without performing them
  -h, --help                 Show this help
USAGE
}

# Arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"; shift 2 ;;
    --title)
      TITLE="$2"; shift 2 ;;
    --notes-file)
      NOTES_FILE="$2"; shift 2 ;;
    --assets)
      shift
      # collect all following args until one starts with --
      while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
        ASSETS+=("$1"); shift
      done
      ;;
    --zip-themes)
      ZIP_THEMES=true; shift ;;
    --no-draft)
      DRAFT=false; shift ;;
    --prerelease)
      PRERELEASE=true; shift ;;
    --yes)
      ASSUME_YES=true; shift ;;
    --no-cleanup)
      CLEANUP_AFTER=false; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      print_usage
      exit 2
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "Error: --tag is required" >&2
  print_usage
  exit 2
fi

if [[ -z "$TITLE" ]]; then
  TITLE="$TAG"
fi

# Helpers
confirm() {
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi
  printf "%s [y/N]: " "$1"
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] $*"
  else
    eval "$@"
  fi
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 3; }
}

# Validate environment
check_command gh

if [[ "$ZIP_THEMES" == "true" ]]; then
  check_command zip
  if [[ ! -d "$THEMES_DIR" ]]; then
    echo "Themes directory not found: $THEMES_DIR" >&2
    exit 4
  fi
fi

# Make dist dir
if [[ ! -d "$DIST_DIR" ]]; then
  run "mkdir -p \"$DIST_DIR\""
fi

# If a release with this tag already exists, warn and ask
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "A release with tag $TAG already exists on the remote."
  if ! confirm "Do you want to overwrite it (assets will be uploaded to existing release)?" ; then
    echo "Aborting."
    exit 0
  fi
fi

# Zip themes if requested
ZIP_ASSET=""
if [[ "$ZIP_THEMES" == "true" ]]; then
  SAFE_TAG="$(echo "$TAG" | tr -c 'A-Za-z0-9._-' '_')"
  ZIP_ASSET="$DIST_DIR/zed-themes-${SAFE_TAG}.zip"
  echo "Creating zip of themes/ -> $ZIP_ASSET"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] zip -r \"$ZIP_ASSET\" . -x \"*/.DS_Store\""
  else
    (cd "$THEMES_DIR" && zip -r "$ZIP_ASSET" . -x "*/.DS_Store") >/dev/null
    if [[ ! -f "$ZIP_ASSET" ]]; then
      echo "Failed to create zip asset: $ZIP_ASSET" >&2
      exit 5
    fi
  fi
  ASSETS+=("$ZIP_ASSET")
fi

# Build gh release args
GHTITLE_ARG="--title \"$TITLE\""
GHNOTES_ARG=""
if [[ -n "$NOTES_FILE" ]]; then
  if [[ ! -f "$NOTES_FILE" ]]; then
    echo "Notes file not found: $NOTES_FILE" >&2
    exit 6
  fi
  GHNOTES_ARG="--notes-file \"$NOTES_FILE\""
fi

DRAFT_ARG=""
if [[ "$DRAFT" == "true" ]]; then
  DRAFT_ARG="--draft"
fi

PRERELEASE_ARG=""
if [[ "$PRERELEASE" == "true" ]]; then
  PRERELEASE_ARG="--prerelease"
fi

# Prepare assets string for command
ASSET_ARGS=()
for a in "${ASSETS[@]}"; do
  ASSET_ARGS+=( "\"$a\"" )
done

echo "About to create GitHub release:"
echo "  tag:    $TAG"
echo "  title:  $TITLE"
if [[ -n "$NOTES_FILE" ]]; then echo "  notes:  $NOTES_FILE"; fi
if [[ "${#ASSETS[@]}" -gt 0 ]]; then
  echo "  assets:"
  for a in "${ASSETS[@]}"; do echo "    - $a"; done
fi
echo "  draft:  $DRAFT"
echo "  prerelease: $PRERELEASE"
echo ""

if [[ "$ASSUME_YES" != "true" ]]; then
  if ! confirm "Proceed to create the release as a draft and open it in your browser for approval?" ; then
    echo "Aborted."
    exit 0
  fi
fi

# Construct gh command
# Use an array to avoid issues with spaces
GH_CMD=(gh release create "$TAG")
if [[ -n "$TITLE" ]]; then
  GH_CMD+=(--title "$TITLE")
fi
if [[ -n "$NOTES_FILE" ]]; then
  GH_CMD+=(--notes-file "$NOTES_FILE")
fi
if [[ "$DRAFT" == "true" ]]; then
  GH_CMD+=(--draft)
fi
if [[ "$PRERELEASE" == "true" ]]; then
  GH_CMD+=(--prerelease)
fi
for asset in "${ASSETS[@]}"; do
  GH_CMD+=(--attach "$asset")
done

# Execute gh command
echo "Running: ${GH_CMD[*]}"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] ${GH_CMD[*]}"
else
  # Create or update release (gh will error out if identical)
  if ! "${GH_CMD[@]}"; then
    echo "gh release create failed. Attempting to attach assets to existing release if present..."
    # If release exists, try to upload assets to it instead of creating a new one
    if gh release view "$TAG" >/dev/null 2>&1; then
      for asset in "${ASSETS[@]}"; do
        echo "Uploading asset: $asset"
        if ! gh release upload "$TAG" "$asset" --clobber; then
          echo "Failed to upload asset: $asset" >&2
        fi
      done
    else
      echo "No existing release found to attach assets to. Exiting." >&2
      exit 7
    fi
  fi
fi

# Open the release page in the browser for final approval
echo "Opening the release page in your browser so you can inspect and hit 'Publish release'..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] gh release view --web \"$TAG\""
else
  gh release view --web "$TAG" || {
    echo "Failed to open release page with gh. Attempting to open GitHub URL in default browser..."
    # Try to construct URL and open via OS
    # Determine repo URL
    REPO_URL="$(git -C "$REPO_ROOT" config --get remote.origin.url || true)"
    # Normalize SSH -> https if needed
    if [[ "$REPO_URL" == git@github.com:* ]]; then
      REPO_URL="${REPO_URL/git@github.com:/https://github.com/}"
    fi
    # Ensure https form
    REPO_URL="${REPO_URL%.git}"
    if [[ -n "$REPO_URL" ]]; then
      RELEASE_URL="${REPO_URL}/releases/tag/${TAG}"
      if command -v open >/dev/null 2>&1; then
        open "$RELEASE_URL"
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$RELEASE_URL"
      else
        echo "Open this URL in your browser: $RELEASE_URL"
      fi
    else
      echo "Could not determine repo remote URL; please run: gh release view --web $TAG"
    fi
  }
fi

# Optionally cleanup generated zip if requested
if [[ "$CLEANUP_AFTER" == "true" && -n "$ZIP_ASSET" && "$DRY_RUN" != "true" ]]; then
  # Cleanup only if the file exists and wasn't requested to be kept
  if [[ -f "$ZIP_ASSET" ]]; then
    echo "Keeping generated asset until you confirm publish. To remove it now run:"
    echo "  rm -f \"$ZIP_ASSET\""
    # We choose to keep by default because users might want a local copy. If you prefer auto-delete, uncomment:
    # rm -f "$ZIP_ASSET"
  fi
fi

echo "Done. Inspect the draft release in your browser and click 'Publish release' when ready."
exit 0