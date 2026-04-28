#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
EXPORT_DIR="${REPO_DIR}/exports/brew"
BREWFILE="${REPO_DIR}/Brewfile"

LOG_PREFIX="[export-brew]"
log() { echo "${LOG_PREFIX} $*"; }
err() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

DRY_RUN="${DRY_RUN:-false}"
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
