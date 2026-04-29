#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
EXPORT_DIR="${REPO_DIR}/exports/firefox"

FF_BASE="${HOME}/Library/Application Support/Firefox"
PROFILES_INI="${FF_BASE}/profiles.ini"

LOG_PREFIX="[export-firefox]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: ./scripts/export_firefox.sh [OPTIONS]

Export Firefox configuration (user prefs, extensions list, profile metadata).

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

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "  [dry-run] would run: $*"
    return 0
  fi
  "$@"
}

# Find the active profile directory
find_profile() {
  if [[ ! -f "${PROFILES_INI}" ]]; then
    err "No profiles.ini found at ${PROFILES_INI}"
    return 1
  fi

  # Find the Install section's Default= (the actively used profile)
  local profile_path
  profile_path=$(awk -F= '/^\[Install/{found=1} found && /^Default=/{print $2; exit}' "${PROFILES_INI}")

  if [[ -z "${profile_path}" ]]; then
    # Fallback: look for Default=1 in Profile sections
    profile_path=$(awk -F= '/^Default=1/{def=1} def && /^Path=/{print $2; exit} /^\[/{def=0}' "${PROFILES_INI}")
  fi

  if [[ -z "${profile_path}" ]]; then
    err "Could not determine active Firefox profile"
    return 1
  fi

  echo "${FF_BASE}/${profile_path}"
}

PROFILE_DIR="$(find_profile)" || exit 0

if [[ ! -d "${PROFILE_DIR}" ]]; then
  err "Profile directory not found: ${PROFILE_DIR}"
  exit 0
fi

log "Active profile: ${PROFILE_DIR}"
run mkdir -p "${EXPORT_DIR}"

# --- Export extensions list ---
log "Exporting extensions list..."
if [[ "${DRY_RUN}" == "true" ]]; then
  log "  [dry-run] would extract extensions from extensions.json"
else
  python3 -c "
import json, os, sys
p = os.path.join(sys.argv[1], 'extensions.json')
if not os.path.exists(p):
    print('No extensions.json found', file=sys.stderr)
    sys.exit(0)
data = json.load(open(p))
for ext in sorted(data.get('addons', []), key=lambda e: e.get('defaultLocale', {}).get('name', '')):
    if ext.get('type') == 'extension' and ext.get('location') == 'app-profile':
        name = ext.get('defaultLocale', {}).get('name', 'unknown')
        print(f\"{ext['id']}  # {name}\")
" "${PROFILE_DIR}" > "${EXPORT_DIR}/extensions.txt"
fi
log "  → ${EXPORT_DIR}/extensions.txt"

# --- Export user-modified prefs ---
log "Exporting user prefs..."
if [[ "${DRY_RUN}" == "true" ]]; then
  log "  [dry-run] would extract user prefs from prefs.js"
else
  python3 -c "
import re, sys, os

prefs_path = os.path.join(sys.argv[1], 'prefs.js')
if not os.path.exists(prefs_path):
    print('No prefs.js found', file=sys.stderr)
    sys.exit(0)

# Skip internal/transient prefs
skip = (
    'app.normandy', 'app.update', 'browser.aboutwelcome', 'browser.bookmarks',
    'browser.contextual-services', 'browser.contentblocking', 'browser.crashReports',
    'browser.download.lastDir', 'browser.download.viewableInternally',
    'browser.engagement',
    'browser.firefox-view', 'browser.laterrun', 'browser.migration',
    'browser.newtabpage.activity-stream', 'browser.pageActions',
    'browser.preonboarding', 'browser.proton', 'browser.region',
    'browser.rights', 'browser.safebrowsing', 'browser.sessionstore',
    'browser.shell', 'browser.slowStartup', 'browser.startup.couldRestore',
    'browser.startup.lastCold', 'browser.theme', 'browser.toolbars',
    'browser.topsites', 'browser.translations', 'browser.uiCustomization',
    'browser.urlbar.quicksuggest', 'browser.urlbar.recentsearches',
    'browser.urlbar.tipShown', 'captchadetection', 'datareporting',
    'devtools', 'distribution', 'doh-rollout', 'dom.push',
    'extensions.activeThemeID', 'extensions.blocklist', 'extensions.colorway',
    'extensions.databaseSchema', 'extensions.formautofill', 'extensions.getAddons',
    'extensions.lastApp', 'extensions.lastPlatform', 'extensions.pendingOperations',
    'extensions.systemAddon', 'extensions.webextensions', 'gecko.handlerService',
    'identity', 'media.gmp', 'network.trr', 'pdfjs', 'places', 'print',
    'privacy.purge_trackers', 'privacy.sanitize', 'reader', 'services',
    'signon', 'storage', 'telemetry', 'toolkit.startup', 'toolkit.telemetry',
    'widget',
)

with open(prefs_path) as f:
    for line in sorted(f):
        line = line.strip()
        if not line.startswith('user_pref('):
            continue
        m = re.match(r'user_pref\(\"([^\"]+)\"', line)
        if not m:
            continue
        key = m.group(1)
        if any(key.startswith(s) for s in skip):
            continue
        print(line)
" "${PROFILE_DIR}" > "${EXPORT_DIR}/user_prefs.txt"
fi
log "  → ${EXPORT_DIR}/user_prefs.txt"

# --- Export containers config ---
if [[ -f "${PROFILE_DIR}/containers.json" ]]; then
  log "Exporting containers config..."
  run cp "${PROFILE_DIR}/containers.json" "${EXPORT_DIR}/containers.json"
  log "  → ${EXPORT_DIR}/containers.json"
fi

# --- Export profile metadata ---
log "Exporting profiles.ini..."
run cp "${PROFILES_INI}" "${EXPORT_DIR}/profiles.ini"
log "  → ${EXPORT_DIR}/profiles.ini"

log "Done. Review ${EXPORT_DIR}/ for any sensitive data before committing."
