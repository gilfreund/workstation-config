#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
EXPORT_DIR="${REPO_DIR}/exports/internet-accounts"

LOG_PREFIX="[export-internet-accounts]"
log() { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARN: $*" >&2; }

DRY_RUN="${DRY_RUN:-false}"
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: ./scripts/export_internet_accounts.sh [--dry-run|-n]"
      echo "Export a human-readable inventory of macOS Internet Accounts."
      exit 0 ;;
  esac
done

ACCOUNTS_DB="${HOME}/Library/Accounts/Accounts4.sqlite"
if [[ ! -f "${ACCOUNTS_DB}" ]]; then
  warn "Accounts database not found at ${ACCOUNTS_DB}"
  exit 1
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  log "[dry-run] would export internet accounts inventory to ${EXPORT_DIR}/"
  exit 0
fi

mkdir -p "${EXPORT_DIR}"
OUTPUT="${EXPORT_DIR}/accounts_inventory.md"

# Decode NSKeyedArchiver bplist values to plain text
decode_bplist_hex() {
  local xml
  xml=$(echo "$1" | xxd -r -p | plutil -convert xml1 -o - -- - 2>/dev/null) || return
  # Try string value first
  local val
  val=$(echo "${xml}" | grep '<string>' \
    | grep -v 'NSKeyedArchiver\|NSString\|\$class\|\$archiver\|\$top\|\$objects\|\$version\|\$null' \
    | sed 's/.*<string>//;s/<\/string>.*//' | head -1)
  if [[ -n "${val}" ]]; then echo "${val}"; return; fi
  # Try integer
  val=$(echo "${xml}" | grep '<integer>' | sed 's/.*<integer>//;s/<\/integer>.*//' | head -1)
  if [[ -n "${val}" ]]; then echo "${val}"; return; fi
  # Try boolean
  if echo "${xml}" | grep -q '<true/>'; then echo "true"; return; fi
  if echo "${xml}" | grep -q '<false/>'; then echo "false"; return; fi
}

# Dump accounts and properties to temp files
ACCT_TMP="$(mktemp)"
PROP_TMP="$(mktemp)"
trap 'rm -f "${ACCT_TMP}" "${PROP_TMP}"' EXIT

sqlite3 -separator '|' "${ACCOUNTS_DB}" "
SELECT
  ZACCOUNTTYPE.ZACCOUNTTYPEDESCRIPTION,
  COALESCE(ZACCOUNT.ZUSERNAME, ''),
  COALESCE(ZACCOUNT.ZACCOUNTDESCRIPTION, ''),
  COALESCE(ZACCOUNT.ZAUTHENTICATIONTYPE, ''),
  ZACCOUNT.Z_PK
FROM ZACCOUNT
LEFT JOIN ZACCOUNTTYPE ON ZACCOUNT.ZACCOUNTTYPE = ZACCOUNTTYPE.Z_PK
WHERE ZACCOUNT.ZACTIVE = 1
ORDER BY ZACCOUNTTYPE.ZACCOUNTTYPEDESCRIPTION, ZACCOUNT.ZUSERNAME;
" > "${ACCT_TMP}"

# Pre-fetch all relevant properties with hex-encoded values
sqlite3 -separator '|' "${ACCOUNTS_DB}" "
SELECT ZOWNER, ZKEY, hex(ZVALUE) FROM ZACCOUNTPROPERTY
WHERE ZKEY IN (
  'Hostname','DAAccountHost','DAAccountPort','PortNumber',
  'SSLEnabled','DAAccountUseSSL','useSSL',
  'email-address','AccountURL',
  'DAAccountPrincipalPath','serverName','serverRootPath',
  'EWSExternalURL','SubCalCalDAVURL'
)
ORDER BY ZOWNER, ZKEY;
" > "${PROP_TMP}"

cat > "${OUTPUT}" <<'HEADER'
# macOS Internet Accounts Inventory

> Auto-generated — use as a checklist when setting up a fresh machine.
> Passwords and tokens are NOT included (they live in Keychain and are non-transferable).

HEADER

total=0
while IFS='|' read -r type username description auth_type pk; do
  case "${type}" in
    IDMS|CloudKit|"Device Locator"|"Find My Friends"|"Game Center"|Messages|"On My Device"|"Holiday Calendar") continue ;;
  esac

  echo "## ${type}" >> "${OUTPUT}"
  [[ -n "${description}" ]] && echo "- **Description:** ${description}" >> "${OUTPUT}"
  [[ -n "${username}" ]] && echo "- **Username:** ${username}" >> "${OUTPUT}"
  [[ -n "${auth_type}" && "${auth_type}" != "parent" ]] && echo "- **Auth type:** ${auth_type}" >> "${OUTPUT}"

  # Decode properties for this account
  grep "^${pk}|" "${PROP_TMP}" | while IFS='|' read -r _owner key hexval; do
    decoded=$(decode_bplist_hex "${hexval}" 2>/dev/null || true)
    [[ -n "${decoded}" ]] && echo "- **${key}:** ${decoded}" >> "${OUTPUT}"
  done || true

  echo "" >> "${OUTPUT}"
  total=$((total + 1))
done < "${ACCT_TMP}"

log "Exported ${total} account(s) → ${OUTPUT}"
log "Review the file and use it as a post-migration checklist."
