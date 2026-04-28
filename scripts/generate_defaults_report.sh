#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
REPORT_DIR="${REPO_DIR}/exports/reports"
REPORT="${REPORT_DIR}/defaults_report.md"

LOG_PREFIX="[defaults-report]"
log() { echo "${LOG_PREFIX} $*"; }

DRY_RUN="${DRY_RUN:-false}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "Not macOS — skipping defaults report."
  exit 0
fi

mkdir -p "${REPORT_DIR}"

log "Generating macOS defaults report..."

if [[ "${DRY_RUN}" == "true" ]]; then
  log "[dry-run] would generate report → ${REPORT}"
  exit 0
fi

{
  echo "# macOS Defaults Report"
  echo ""
  echo "Generated: $(date -Iseconds)"
  echo "Host: $(scutil --get ComputerName 2>/dev/null || hostname)"
  echo "macOS: $(sw_vers -productVersion)"
  echo ""

  echo "## Automation-Friendly Settings"
  echo ""
  echo "These settings are good candidates for \`osx_defaults\` / \`defaults write\`:"
  echo ""
  echo "| Domain | Key | Current Value | Type |"
  echo "|--------|-----|---------------|------|"

  # Key/domain pairs that are safe and useful to automate
  while IFS='|' read -r domain key; do
    val=$(defaults read "${domain}" "${key}" 2>/dev/null || echo "N/A")
    dtype=$(defaults read-type "${domain}" "${key}" 2>/dev/null | sed 's/Type is //' || echo "unknown")
    echo "| ${domain} | ${key} | ${val} | ${dtype} |"
  done <<'KEYS'
com.apple.dock|autohide
com.apple.dock|tilesize
com.apple.dock|orientation
com.apple.dock|show-recents
com.apple.finder|AppleShowAllFiles
com.apple.finder|ShowPathbar
com.apple.finder|ShowStatusBar
com.apple.finder|FXPreferredViewStyle
NSGlobalDomain|AppleShowAllExtensions
NSGlobalDomain|KeyRepeat
NSGlobalDomain|InitialKeyRepeat
com.apple.screencapture|location
com.apple.screencapture|type
com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking
KEYS

  echo ""
  echo "## Settings That Require Manual Configuration"
  echo ""
  echo "These typically cannot be fully automated:"
  echo ""
  echo "- Apple ID and iCloud settings"
  echo "- FileVault encryption"
  echo "- Touch ID fingerprints"
  echo "- Notification preferences per app"
  echo "- Login items (partially automatable via \`osascript\`)"
  echo "- Dock app layout (which apps appear in the Dock)"
  echo "- Desktop wallpaper (automatable but path-dependent)"
  echo "- Wi-Fi saved networks"
  echo "- Bluetooth device pairings"
  echo ""
  echo "## How to Add More Settings"
  echo ""
  printf '1. Find the domain: `defaults domains | tr "," "\\n" | grep -i <keyword>`\n'
  echo "2. Read all keys: \`defaults read <domain>\`"
  echo "3. Read one key: \`defaults read <domain> <key>\`"
  echo "4. Check type: \`defaults read-type <domain> <key>\`"
  echo "5. Add to \`group_vars/macos.yml\` and \`roles/mac-settings/tasks/main.yml\`"
} > "${REPORT}"

log "Report → ${REPORT}"
log "Review it to decide which settings to add to your Ansible variables."
