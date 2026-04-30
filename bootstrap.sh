#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[bootstrap]"

log()  { echo "${LOG_PREFIX} $*"; }
err()  { echo "${LOG_PREFIX} ERROR: $*" >&2; }
die()  { err "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: ./bootstrap.sh [OPTIONS]

Install prerequisites and run the Ansible playbook on a fresh machine.

Options:
  -n, --dry-run       Install prerequisites but run playbook in check mode
  --force-galaxy      Reinstall Ansible Galaxy collections even if present
  -c, --show-config   Display active configuration and exit
  -h, --help          Show this help message
  Additional flags are passed through to ansible-playbook.
EOF
  exit 0
}

show_config() {
  echo "=== Restore Configuration ==="
  echo ""
  echo "Platform:       $(uname -s)"
  echo "Home:           ${HOME}"
  echo "Repo:           ${REPO_DIR}"
  echo ""
  echo "--- Prerequisites ---"
  echo "  Xcode CLI Tools:  $(xcode-select -p &>/dev/null && echo 'installed' || echo 'will install')"
  echo "  Homebrew:         $(command -v brew &>/dev/null && echo 'installed' || echo 'will install')"
  echo "  Python3:          $(command -v python3 &>/dev/null && echo 'installed' || echo 'will install')"
  echo "  Ansible:          $(command -v ansible &>/dev/null && ansible --version | head -1 || echo 'will install')"
  echo ""
  echo "--- Ansible Config ---"
  echo "  Playbook:         ${REPO_DIR}/site.yml"
  echo "  Inventory:        ${REPO_DIR}/inventory/localhost.yml"
  echo "  Vault password:   $(grep vault_password_file "${REPO_DIR}/ansible.cfg" 2>/dev/null | awk -F= '{print $2}' | xargs)"
  echo ""
  echo "--- Roles ---"
  echo "  dotfiles          Copy/template dotfiles + deploy vault secrets"
  echo "  homebrew          Install packages from Brewfile"
  echo "  mac-settings      macOS defaults + Dock layout (macOS only)"
  echo "  app-settings      VS Code, iTerm2, Hidden Bar, Cyberduck"
  echo "  debian-common     apt packages + shell config (Debian only)"
  echo ""
  echo "--- Vault Files ---"
  local found_vault=false
  for f in "${REPO_DIR}"/files/secrets/*.vault; do
    if [[ -f "${f}" ]]; then
      echo "  $(basename "${f}")"
      found_vault=true
    fi
  done
  if [[ "${found_vault}" == "false" ]]; then
    echo "  (none — run collection first)"
  fi
  echo ""
  echo "--- Group Vars ---"
  for f in "${REPO_DIR}"/group_vars/*.yml; do
    echo "  $(basename "${f}")"
  done
  exit 0
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -f /etc/debian_version ]; then echo "debian"
      else die "Unsupported Linux distribution. Only Debian-based systems are supported."
      fi ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
}

install_homebrew() {
  if command -v brew &>/dev/null; then
    log "Homebrew already installed"
    return
  fi
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

ensure_brew_in_path() {
  if command -v brew &>/dev/null; then return; fi
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

bootstrap_macos() {
  log "Bootstrapping macOS..."

  # Xcode CLI tools (needed for git, compilers, Homebrew)
  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools..."
    # Use softwareupdate for non-interactive install when possible
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    local cli_pkg
    cli_pkg=$(softwareupdate -l 2>/dev/null \
      | grep -o '.*Command Line Tools.*' \
      | grep -v 'Finding' \
      | sed 's/^[* ]*//' \
      | sort -V \
      | tail -1)
    if [[ -n "${cli_pkg}" ]]; then
      log "Found package: ${cli_pkg}"
      softwareupdate -i "${cli_pkg}" --verbose
    else
      # Fallback to GUI prompt
      xcode-select --install
      log "Waiting for Xcode CLI tools installation to complete..."
      until xcode-select -p &>/dev/null; do
        sleep 5
      done
    fi
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    log "Xcode Command Line Tools installed."
  else
    log "Xcode Command Line Tools already installed."
  fi

  install_homebrew
  ensure_brew_in_path

  # Python 3 (macOS ships with it since Catalina, but ensure it)
  if ! command -v python3 &>/dev/null; then
    log "Installing Python 3 via Homebrew..."
    brew install python3
  fi

  # Ansible
  if ! command -v ansible &>/dev/null; then
    log "Installing Ansible via Homebrew..."
    brew install ansible
  fi
}

bootstrap_debian() {
  log "Bootstrapping Debian..."

  log "Installing system dependencies..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3 python3-pip python3-venv git curl

  # Install Ansible via pipx (user-local, clean)
  if ! command -v ansible &>/dev/null; then
    log "Installing Ansible via pipx..."
    if ! command -v pipx &>/dev/null; then
      sudo apt-get install -y -qq pipx
      pipx ensurepath
      export PATH="$HOME/.local/bin:$PATH"
    fi
    pipx install ansible
  fi
}

install_ansible_requirements() {
  local collections_dir="${REPO_DIR}/.ansible/collections"
  if [ "${FORCE_GALAXY}" != "true" ] && [ -d "${collections_dir}/ansible_collections/community/general" ]; then
    log "Ansible Galaxy collections already installed, skipping (use --force-galaxy to reinstall)"
    return
  fi
  log "Installing Ansible Galaxy requirements..."
  ANSIBLE_COLLECTIONS_PATH="${collections_dir}" ansible-galaxy collection install -r "${REPO_DIR}/requirements.yml" -p "${collections_dir}" --force
}

run_playbook() {
  log "Running Ansible playbook..."
  cd "${REPO_DIR}"

  local ask_become=""
  local pass_file="" vars_file=""
  if [ -n "${BECOME_PASS:-}" ]; then
    pass_file=$(mktemp)
    chmod 600 "${pass_file}"
    echo "${BECOME_PASS}" > "${pass_file}"
    vars_file=$(mktemp)
    chmod 600 "${vars_file}"
    echo "ansible_become_password: '${BECOME_PASS}'" > "${vars_file}"
    ask_become="--become-password-file=${pass_file} -e @${vars_file}"
  fi

  # shellcheck disable=SC2086
  ansible-playbook -i inventory/localhost.yml site.yml ${ask_become} "$@"
  local rc=$?
  [ -n "${pass_file:-}" ] && rm -f "${pass_file}"
  [ -n "${vars_file:-}" ] && rm -f "${vars_file}"
  return $rc
}

# --- Main ---
DRY_RUN=false
FORCE_GALAXY=false
EXTRA_ARGS=()
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=true ;;
    --force-galaxy) FORCE_GALAXY=true ;;
    --show-config|-c) show_config ;;
    --help|-h) usage ;;
    *) EXTRA_ARGS+=("${arg}") ;;
  esac
done

PLATFORM="$(detect_platform)"
log "Detected platform: ${PLATFORM}"

# Prompt for sudo password once, reuse for bootstrap and Ansible
read -rsp "[bootstrap] BECOME password (sudo): " BECOME_PASS
echo
if [[ "${DRY_RUN}" == "true" ]]; then
  log "*** DRY RUN — bootstrap will install prerequisites but playbook runs in check mode ***"
fi

case "${PLATFORM}" in
  macos)  bootstrap_macos ;;
  debian) bootstrap_debian ;;
esac

install_ansible_requirements

if [[ "${DRY_RUN}" == "true" ]]; then
  run_playbook --check --diff "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
else
  run_playbook "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
fi

log "Bootstrap complete!"
log ""
log "To apply PATH changes to your current shell, run:"
log "  exec zsh -l"
log ""
log "=== Post-migration manual steps ==="
log ""
log "1. Sign into your Apple ID (System Settings → Apple ID)"
log "   → Enables iCloud Keychain sync (passwords, Wi-Fi, Safari)"
log ""
log "2. Sign into these apps (accounts cannot be migrated automatically):"
log "   - Microsoft 365: sign into ONE app (e.g. Teams) per account —"
log "     other M365 apps (Office, Outlook, OneDrive) will pick up the session."
log "     Repeat for each M365 account (personal, work, etc.)"
log "   - Firefox (Sync)"
log "   - Thunderbird (mail accounts)"
log "   - Signal (requires phone to re-link)"
log "   - Slack (per-workspace sign-in)"
log "   - Zoom"
log ""
log "3. Install casks that failed due to sudo (if any were reported above):"
log "   brew install --cask <name>"
log ""
log "4. Re-run Dock setup if apps were not yet installed during first run:"
log "   ansible-playbook -i inventory/localhost.yml site.yml --tags mac-settings"
log ""
log "5. Enable system extensions if prompted:"
log "   - Karabiner-Elements (keyboard remapping)"
log "   - macFUSE (filesystem extensions)"
log "   - Tailscale / NetBird / OpenVPN (network extensions)"
log ""
log "6. Configure Login Items (System Settings → General → Login Items):"
log "   - Hidden Bar, Karabiner-Elements, Tailscale, etc."
log ""
log "7. Configure Notification settings per app (System Settings → Notifications)"
log ""
log "8. Restart to apply all macOS settings (Dock, Finder, trackpad, keyboard)"
