#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
EXPORT_DIR="${REPO_DIR}/exports/thunderbird"

SECRETS_DIR="${REPO_DIR}/files/secrets"

TB_BASE="${HOME}/Library/Thunderbird"
PROFILES_INI="${TB_BASE}/profiles.ini"

LOG_PREFIX="[export-thunderbird]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: ./scripts/export_thunderbird.sh [OPTIONS]

Export Thunderbird configuration (accounts, identities, servers, signatures,
message filters, and profiles metadata). Does NOT export mail data.

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

encrypt_vault() {
  local file="$1" label="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "  [dry-run] would encrypt: ${label}"
    return 0
  fi
  if command -v ansible-vault &>/dev/null; then
    if [[ "$(head -c 14 "${file}" 2>/dev/null)" != '$ANSIBLE_VAULT' ]]; then
      ansible-vault encrypt "${file}" 2>/dev/null
      log "  ✓ ${label} (encrypted)"
    else
      log "  ✓ ${label} (already encrypted)"
    fi
  else
    log "  WARN: ansible-vault not found — ${label} saved unencrypted!"
  fi
}

find_profile() {
  if [[ ! -f "${PROFILES_INI}" ]]; then
    err "No profiles.ini found at ${PROFILES_INI}"
    return 1
  fi

  local profile_path
  profile_path=$(awk -F= '/^\[Install/{found=1} found && /^Default=/{print $2; exit}' "${PROFILES_INI}")

  if [[ -z "${profile_path}" ]]; then
    profile_path=$(awk -F= '/^Default=1/{def=1} def && /^Path=/{print $2; exit} /^\[/{def=0}' "${PROFILES_INI}")
  fi

  if [[ -z "${profile_path}" ]]; then
    err "Could not determine active Thunderbird profile"
    return 1
  fi

  echo "${TB_BASE}/${profile_path}"
}

# --- Main ---
if [[ ! -d "${TB_BASE}" ]]; then
  log "Thunderbird not found at ${TB_BASE} — skipping."
  exit 0
fi

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
    print('No extensions.json found', file=sys.stderr); sys.exit(0)
data = json.load(open(p))
for ext in sorted(data.get('addons', []), key=lambda e: e.get('defaultLocale', {}).get('name', '')):
    if ext.get('type') == 'extension' and ext.get('location') == 'app-profile':
        name = ext.get('defaultLocale', {}).get('name', 'unknown')
        print(f\"{ext['id']}  # {name}\")
" "${PROFILE_DIR}" > "${EXPORT_DIR}/extensions.txt"
fi
log "  → ${EXPORT_DIR}/extensions.txt"

# --- Export mail prefs (accounts, identities, servers, SMTP, signatures) ---
log "Exporting mail prefs (vault-encrypted)..."
VAULT_PREFS="${SECRETS_DIR}/thunderbird_mail_prefs.vault"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "  [dry-run] would extract mail prefs from prefs.js"
else
  mkdir -p "${SECRETS_DIR}"
  grep -E '^user_pref\("(mail\.(account|identity|server|smtpserver|smtp|accountmanager)|ldap_2)' \
    "${PROFILE_DIR}/prefs.js" | sort > "${VAULT_PREFS}"
  encrypt_vault "${VAULT_PREFS}" "thunderbird_mail_prefs.vault"
fi
log "  → ${VAULT_PREFS}"

# --- Export message filters (vault-encrypted) ---
log "Exporting message filters (vault-encrypted)..."
VAULT_FILTERS="${SECRETS_DIR}/thunderbird_filters.vault"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "  [dry-run] would archive msgFilterRules.dat files"
else
  TMPDIR_FILTERS="$(mktemp -d)"
  FILTER_COUNT=0
  while IFS= read -r -d '' filt; do
    rel="${filt#"${PROFILE_DIR}/"}"
    dest="${TMPDIR_FILTERS}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    cp "${filt}" "${dest}"
    FILTER_COUNT=$((FILTER_COUNT + 1))
  done < <(find "${PROFILE_DIR}" -name "msgFilterRules.dat" -print0 2>/dev/null)
  tar czf "${VAULT_FILTERS}" -C "${TMPDIR_FILTERS}" .
  rm -rf "${TMPDIR_FILTERS}"
  encrypt_vault "${VAULT_FILTERS}" "thunderbird_filters.vault"
fi
log "  → ${VAULT_FILTERS} (${FILTER_COUNT:-0} filter files)"

# --- Export profiles.ini ---
log "Exporting profiles.ini..."
run cp "${PROFILES_INI}" "${EXPORT_DIR}/profiles.ini"
log "  → ${EXPORT_DIR}/profiles.ini"

log "Done. Review ${EXPORT_DIR}/ for any sensitive data before committing."
