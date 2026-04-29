#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
EXPORT_DIR="${REPO_DIR}/exports/macos"

LOG_PREFIX="[export-macos]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: ./scripts/export_macos_settings.sh [OPTIONS]

Export macOS preference domains, key summary, and Dock app layout.

Options:
  -n, --dry-run   Show what would be exported without writing files
  -h, --help      Show this help message
EOF
  exit 0
}

DRY_RUN="${DRY_RUN:-false}"
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=true ;;
    --help|-h) usage ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This script only runs on macOS."
  exit 1
fi

# Domains to export
DOMAINS=(
  com.apple.dock
  com.apple.finder
  com.apple.driver.AppleBluetoothMultitouch.trackpad
  com.apple.AppleMultitouchTrackpad
  com.apple.screencapture
  com.apple.systemuiserver
  NSGlobalDomain
)

mkdir -p "${EXPORT_DIR}"

if [[ "${DRY_RUN}" == "true" ]]; then
  log "*** DRY RUN — listing domains that would be exported ***"
  for domain in "${DOMAINS[@]}"; do
    log "  would export: ${domain}"
  done
  log "  would export: key_summary.txt, dock_apps.txt"
  exit 0
fi

log "Exporting macOS preference domains to ${EXPORT_DIR}/"

for domain in "${DOMAINS[@]}"; do
  safe_name="${domain//\./_}"
  outfile="${EXPORT_DIR}/${safe_name}.txt"

  log "  Reading ${domain}..."
  if defaults read "${domain}" > "${outfile}" 2>/dev/null; then
    log "    → ${outfile}"
  else
    log "    ⚠ Domain ${domain} not found or empty, skipping."
    rm -f "${outfile}"
  fi
done

# Export a summary of commonly managed keys
SUMMARY="${EXPORT_DIR}/key_summary.txt"
log "Generating key summary..."
{
  echo "# macOS Settings Key Summary"
  echo "# Generated: $(date -Iseconds)"
  echo ""

  echo "## Dock"
  for key in autohide tilesize orientation mineffect show-recents; do
    val=$(defaults read com.apple.dock "${key}" 2>/dev/null || echo "<not set>")
    echo "  com.apple.dock ${key} = ${val}"
  done

  echo ""
  echo "## Finder"
  for key in AppleShowAllFiles ShowPathbar ShowStatusBar FXPreferredViewStyle; do
    val=$(defaults read com.apple.finder "${key}" 2>/dev/null || echo "<not set>")
    echo "  com.apple.finder ${key} = ${val}"
  done

  echo ""
  echo "## Trackpad"
  for key in Clicking TrackpadThreeFingerDrag; do
    val=$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad "${key}" 2>/dev/null || echo "<not set>")
    echo "  com.apple.driver.AppleBluetoothMultitouch.trackpad ${key} = ${val}"
  done

  echo ""
  echo "## Keyboard"
  for key in KeyRepeat InitialKeyRepeat; do
    val=$(defaults read NSGlobalDomain "${key}" 2>/dev/null || echo "<not set>")
    echo "  NSGlobalDomain ${key} = ${val}"
  done

  echo ""
  echo "## Screenshots"
  for key in location type disable-shadow; do
    val=$(defaults read com.apple.screencapture "${key}" 2>/dev/null || echo "<not set>")
    echo "  com.apple.screencapture ${key} = ${val}"
  done

  echo ""
  echo "## Global"
  for key in AppleShowAllExtensions com.apple.swipescrolldirection; do
    val=$(defaults read NSGlobalDomain "${key}" 2>/dev/null || echo "<not set>")
    echo "  NSGlobalDomain ${key} = ${val}"
  done
} > "${SUMMARY}"

log "Key summary → ${SUMMARY}"

# Export Dock app layout
DOCK_APPS="${EXPORT_DIR}/dock_apps.txt"
log "Exporting Dock app layout..."
defaults read com.apple.dock persistent-apps | grep -oE '"file-label" = "?[^";]+"?' | sed 's/"file-label" = //; s/"//g' > "${DOCK_APPS}"
log "  → ${DOCK_APPS}"
log "  Copy these into dock_apps in group_vars/macos.yml"

log "Done. Review ${EXPORT_DIR}/ and update group_vars/macos.yml accordingly."
log ""
log "Tip: To inspect a specific key:"
log "  defaults read com.apple.finder ShowPathbar"
log "  defaults read-type com.apple.dock tilesize"
