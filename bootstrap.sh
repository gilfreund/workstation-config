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
  # Add brew to PATH for this session
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

bootstrap_macos() {
  log "Bootstrapping macOS..."

  # Xcode CLI tools (needed for git, compilers)
  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools..."
    xcode-select --install
    log "Waiting for Xcode CLI tools installation — press Enter when done."
    read -r
  fi

  install_homebrew

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
  log "Installing Ansible Galaxy requirements..."
  ansible-galaxy collection install -r "${REPO_DIR}/requirements.yml" --force
}

run_playbook() {
  log "Running Ansible playbook..."
  cd "${REPO_DIR}"

  local ask_become=""
  if [ "${PLATFORM}" = "debian" ]; then
    ask_become="-K"
  fi

  # shellcheck disable=SC2086
  ansible-playbook -i inventory/localhost.yml site.yml ${ask_become} "$@"
}

# --- Main ---
DRY_RUN=false
EXTRA_ARGS=()
for arg in "$@"; do
  case "${arg}" in
    --dry-run|-n) DRY_RUN=true ;;
    --show-config|-c) show_config ;;
    --help|-h) usage ;;
    *) EXTRA_ARGS+=("${arg}") ;;
  esac
done

PLATFORM="$(detect_platform)"
log "Detected platform: ${PLATFORM}"
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
