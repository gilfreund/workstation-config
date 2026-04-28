#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[bootstrap]"

log()  { echo "${LOG_PREFIX} $*"; }
err()  { echo "${LOG_PREFIX} ERROR: $*" >&2; }
die()  { err "$@"; exit 1; }

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
