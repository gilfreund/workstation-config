#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

LOG_PREFIX="[collect]"
log() { echo "${LOG_PREFIX} $*"; }

usage() {
  cat <<EOF
Usage: ./scripts/collect_current_state.sh [OPTIONS]

Collect configuration from the current machine (dotfiles, macOS settings,
Homebrew, app configs, vault-encrypted secrets).

Options:
  -n, --dry-run   Show what would be collected without writing files
  -h, --help      Show this help message

Configuration: edit export.conf to toggle components.
EOF
  exit 0
}

# Parse flags
DRY_RUN="${DRY_RUN:-false}"
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=true ;;
    --help|-h) usage ;;
  esac
done

# Load export toggles
CONF="${REPO_DIR}/export.conf"
if [[ -f "${CONF}" ]]; then
  # shellcheck source=../export.conf
  source "${CONF}"
fi

PLATFORM="$(uname -s)"
COLLECTED=()
SKIPPED=()

log "=== Workstation Configuration Collection ==="
if [[ "${DRY_RUN}" == "true" ]]; then
  log "*** DRY RUN — no files will be written ***"
fi
log "Platform: ${PLATFORM}"
log "Date: $(date -Iseconds)"
log ""

# --- Dotfiles (all platforms) ---
if [[ "${EXPORT_DOTFILES:-true}" == "true" ]]; then
  log "--- Collecting dotfiles ---"
  if DRY_RUN="${DRY_RUN}" bash "${SCRIPT_DIR}/export_dotfiles.sh"; then
    COLLECTED+=("dotfiles")
  else
    SKIPPED+=("dotfiles")
  fi
  echo ""
else
  log "Dotfiles export disabled in export.conf"
  SKIPPED+=("dotfiles")
fi

# --- macOS settings ---
if [[ "${PLATFORM}" == "Darwin" ]]; then
  if [[ "${EXPORT_MACOS_SETTINGS:-true}" == "true" ]]; then
    log "--- Collecting macOS settings ---"
    if DRY_RUN="${DRY_RUN}" bash "${SCRIPT_DIR}/export_macos_settings.sh"; then
      COLLECTED+=("macos-settings")
    else
      SKIPPED+=("macos-settings")
    fi
    echo ""

    log "--- Generating defaults report ---"
    if DRY_RUN="${DRY_RUN}" bash "${SCRIPT_DIR}/generate_defaults_report.sh"; then
      COLLECTED+=("defaults-report")
    else
      SKIPPED+=("defaults-report")
    fi
    echo ""
  else
    log "macOS settings export disabled in export.conf"
    SKIPPED+=("macos-settings" "defaults-report")
  fi
else
  log "Not macOS — skipping macOS settings export."
  SKIPPED+=("macos-settings" "defaults-report")
fi

# --- Homebrew ---
if [[ "${EXPORT_HOMEBREW:-true}" == "true" ]] && command -v brew &>/dev/null; then
  log "--- Collecting Homebrew state ---"
  if DRY_RUN="${DRY_RUN}" bash "${SCRIPT_DIR}/export_brew.sh"; then
    COLLECTED+=("homebrew")
  else
    SKIPPED+=("homebrew")
  fi
  echo ""
else
  log "Homebrew not installed — skipping."
  SKIPPED+=("homebrew")
fi

# --- Summary ---
log "=== Collection Summary ==="
log ""
if [[ ${#COLLECTED[@]} -gt 0 ]]; then
  log "Collected:"
  for item in "${COLLECTED[@]}"; do
    log "  ✓ ${item}"
  done
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  log "Skipped:"
  for item in "${SKIPPED[@]}"; do
    log "  ✗ ${item}"
  done
fi
log ""
log "Exports:  ${REPO_DIR}/exports/"
log "Dotfiles: ${REPO_DIR}/files/dotfiles/"
log "Brewfile: ${REPO_DIR}/Brewfile"
log ""
log "Next steps:"
log "  1. Review exported files for secrets or unwanted content"
log "  2. Update group_vars/ with values from exports/reports/"
log "  3. Commit the changes: git add -A && git commit -m 'Update config from source machine'"
