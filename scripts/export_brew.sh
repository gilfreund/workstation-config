#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
EXPORT_DIR="${REPO_DIR}/exports/brew"
BREWFILE="${REPO_DIR}/Brewfile"

LOG_PREFIX="[export-brew]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

usage() {
  cat <<EOF
Usage: ./scripts/export_brew.sh [OPTIONS]

Export Homebrew state (Brewfile, formulae, casks, taps).

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

if ! command -v brew &>/dev/null; then
  err "Homebrew is not installed. Skipping."
  exit 0
fi

run mkdir -p "${EXPORT_DIR}"

log "Dumping Brewfile..."
run brew bundle dump --force --describe --file="${BREWFILE}"
log "  → ${BREWFILE}"

log "Exporting formula list..."
run bash -c "brew list --formula > '${EXPORT_DIR}/formulae.txt'"
log "  → ${EXPORT_DIR}/formulae.txt"

log "Exporting cask list..."
run bash -c "brew list --cask > '${EXPORT_DIR}/casks.txt' 2>/dev/null || true"
log "  → ${EXPORT_DIR}/casks.txt"

log "Exporting tap list..."
run bash -c "brew tap > '${EXPORT_DIR}/taps.txt'"
log "  → ${EXPORT_DIR}/taps.txt"

log "Done. Brewfile is the canonical restore artifact."
log "Review ${BREWFILE} and remove anything you don't want on a fresh machine."

# Detect which casks require sudo (pkg-based installers)
log "Detecting casks requiring sudo..."
SUDO_CASKS="${REPO_DIR}/files/brew_casks_sudo.txt"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "  [dry-run] would query cask metadata for pkg detection"
else
  : > "${SUDO_CASKS}"
  while IFS= read -r cask; do
    if brew info --json=v2 --cask "${cask}" 2>/dev/null | grep -q '"pkg"'; then
      echo "${cask}" >> "${SUDO_CASKS}"
    fi
  done < <(grep '^cask ' "${BREWFILE}" | sed 's/^cask "\([^"]*\)".*/\1/')
  log "  → ${SUDO_CASKS} ($(wc -l < "${SUDO_CASKS}" | tr -d ' ') casks need sudo)"
fi
