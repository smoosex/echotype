#!/usr/bin/env bash
set -euo pipefail

APP_NAME="EchoType"
APP_BUNDLE_ID="com.smoose.echotype"
APP_PATH="/Applications/EchoType.app"
APP_SUPPORT_PATH="${HOME}/Library/Application Support/echotype"
APP_CACHE_PATH="${HOME}/Library/Caches/echotype"
PREFERENCES_PATH="${HOME}/Library/Preferences/${APP_BUNDLE_ID}.plist"

ASSUME_YES=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/uninstall.sh [--yes] [--dry-run]

Fully uninstall EchoType from current user:
- stop EchoType processes
- uninstall Homebrew cask `echotype` if installed
- remove /Applications/EchoType.app
- remove app data under ~/Library/Application Support/echotype
- remove cache data under ~/Library/Caches/echotype
- remove preferences plist
- remove temporary echotype-* files under /tmp and /var/folders

Options:
  --yes      Skip confirmation prompt.
  --dry-run  Print actions without deleting anything.
  -h, --help Show this help.
EOF
}

log() {
  printf '[echotype-uninstall] %s\n' "$*"
}

run() {
  if $DRY_RUN; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

remove_path_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    log "Removing: $path"
    run rm -rf "$path"
  else
    log "Skip (not found): $path"
  fi
}

stop_process_if_running() {
  local pattern="$1"
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    log "Stopping process pattern: $pattern"
    if $DRY_RUN; then
      printf '[dry-run] %q %q %q\n' pkill -f "$pattern"
    else
      pkill -f "$pattern" || true
    fi
  fi
}

cleanup_temp_files() {
  log "Cleaning temporary EchoType files"
  if $DRY_RUN; then
    echo "[dry-run] rm -rf /tmp/echotype-runtime-*"
    echo "[dry-run] find /var/folders -type f -name 'echotype-recording-*.wav' -delete"
    return 0
  fi

  rm -rf /tmp/echotype-runtime-* 2>/dev/null || true
  find /var/folders -type f -name 'echotype-recording-*.wav' -delete 2>/dev/null || true
}

for arg in "$@"; do
  case "$arg" in
    --yes)
      ASSUME_YES=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

if ! $ASSUME_YES; then
  cat <<EOF
This will fully uninstall ${APP_NAME} from this machine:
- ${APP_PATH}
- ${APP_SUPPORT_PATH}
- ${APP_CACHE_PATH}
- ${PREFERENCES_PATH}
- temporary EchoType files in /tmp and /var/folders
EOF
  read -r -p "Type YES to continue: " confirm
  if [[ "$confirm" != "YES" ]]; then
    log "Cancelled."
    exit 0
  fi
fi

stop_process_if_running "EchoType.app/Contents/MacOS/echotype"
stop_process_if_running "/Applications/EchoType.app"

if command -v brew >/dev/null 2>&1; then
  if brew list --cask echotype >/dev/null 2>&1; then
    log "Uninstalling Homebrew cask: echotype"
    run brew uninstall --cask echotype || true
  fi
fi

remove_path_if_exists "$APP_PATH"
remove_path_if_exists "$APP_SUPPORT_PATH"
remove_path_if_exists "$APP_CACHE_PATH"
remove_path_if_exists "$PREFERENCES_PATH"
cleanup_temp_files

log "Uninstall complete."
