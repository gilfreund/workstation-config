#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

LOG_PREFIX="[collect]"
log() { echo "${LOG_PREFIX} $*"; }

# Load export toggles
CONF="${REPO_DIR}/export.conf"
if [[ -f "${CONF}" ]]; then
  # shellcheck source=../export.conf
  source "${CONF}"
fi

usage() {
  cat <<EOF
Usage: ./scripts/collect_current_state.sh [OPTIONS]

Collect configuration from the current machine (dotfiles, macOS settings,
Homebrew, app configs, vault-encrypted secrets).

Options:
  -n, --dry-run       Show what would be collected without writing files
  -c, --show-config   Display active configuration and exit
  -h, --help          Show this help message

Configuration: edit export.conf to toggle components.
EOF
  exit 0
}

show_config() {
  echo "=== Collection Configuration ==="
  echo ""
  echo "Platform:       $(uname -s)"
  echo "Home:           ${HOME}"
  echo "Repo:           ${REPO_DIR}"
  echo "Config file:    ${CONF}"
  echo ""
  echo "--- Export Toggles (export.conf) ---"
  echo "  Dotfiles:         ${EXPORT_DOTFILES:-true}"
  echo "  macOS settings:   ${EXPORT_MACOS_SETTINGS:-true}"
  echo "  Dock apps:        ${EXPORT_MACOS_DOCK_APPS:-true}"
  echo "  Homebrew:         ${EXPORT_HOMEBREW:-true}"
  echo "  VS Code:          ${EXPORT_VSCODE:-true}"
  echo "  iTerm2:           ${EXPORT_ITERM2:-true}"
  echo "  Hidden Bar:       ${EXPORT_HIDDENBAR:-true}"
  echo "  Cyberduck:        ${EXPORT_CYBERDUCK:-true}"
  echo ""
  echo "--- Vault Exports ---"
  echo "  SSH:              ${EXPORT_SSH_VAULT:-true}"
  echo "  AWS:              ${EXPORT_AWS_VAULT:-true}"
  echo "  Secrets:          ${EXPORT_SECRETS_VAULT:-true}"
  echo "  Rclone:           ${EXPORT_RCLONE_VAULT:-true}"
  echo ""
  echo "--- Vault Password ---"
  local vp="${HOME}/.secrets/ansible-workstation-config"
  if [[ -f "${vp}" ]]; then
    echo "  File:             ${vp} (exists)"
  else
    echo "  File:             ${vp} (MISSING — vault encryption will prompt)"
  fi
  echo ""
  echo "--- Dotfile Allowlists ---"
  echo "  Files:            .zshrc .bashrc .gitconfig .gitignore_global .tmux.conf .vimrc"
  echo "  Directories:      .config/nvim .config/ghostty .config/gh .config/iterm2 .config/karabiner .aws .kiro"
  echo ""
  echo "--- Output Paths ---"
  echo "  Dotfiles:         ${REPO_DIR}/files/dotfiles/"
  echo "  App configs:      ${REPO_DIR}/files/app-configs/"
  echo "  Vault secrets:    ${REPO_DIR}/files/secrets/"
  echo "  macOS exports:    ${REPO_DIR}/exports/macos/"
  echo "  Brew exports:     ${REPO_DIR}/exports/brew/"
  echo "  Reports:          ${REPO_DIR}/exports/reports/"
  exit 0
}

# Parse flags
DRY_RUN="${DRY_RUN:-false}"
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=true ;;
    --show-config|-c) show_config ;;
    --help|-h) usage ;;
  esac
done

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
