#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
DEST_DIR="${REPO_DIR}/files/dotfiles"
HOME_DIR="${HOME}"

LOG_PREFIX="[export-dotfiles]"
log() { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARN: $*" >&2; }

usage() {
  cat <<EOF
Usage: ./scripts/export_dotfiles.sh [OPTIONS]

Export dotfiles, app configs, and vault-encrypted secrets from the current machine.

Options:
  -n, --dry-run   Show what would be exported without writing files
  -h, --help      Show this help message

Configuration: edit export.conf to toggle components.
Allowlists: edit FILES and DIRS arrays in this script.
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

# Wrapper: run a command unless in dry-run mode
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "  [dry-run] would run: $*"
    return 0
  fi
  "$@"
}

# Load export toggles
CONF="${REPO_DIR}/export.conf"
if [[ -f "${CONF}" ]]; then
  # shellcheck source=../export.conf
  source "${CONF}"
fi

# --- Allowlists ---
# Individual files to collect
FILES=(
  .zshrc
  .bashrc
  .gitconfig
  .gitignore_global
  .tmux.conf
  .vimrc
)

# Directories to collect (recursively)
DIRS=(
  .config/nvim
  .config/ghostty
  .config/gh
  .config/iterm2
  .config/karabiner
  .aws
  .kiro
)

# Patterns to EXCLUDE from directory copies (glob patterns relative to source dir)
EXCLUDE_PATTERNS=(
  "id_*"
  "*.pem"
  "*.key"
  "known_hosts"
  "authorized_keys"
  "credentials"
  "config"
  "*.sock"
  ".DS_Store"
  ".cli_bash_history"
  "sessions"
  "ssh-mcp-servers.json"
  "hosts.yml"
  ".gitconfig"
  "repos/"
  "amazonq/"
  "sso/"
  "cli/"
  "__pycache__"
  "*.pyc"
  "node_modules"
)

build_rsync_excludes() {
  local excludes=()
  for pat in "${EXCLUDE_PATTERNS[@]}"; do
    excludes+=(--exclude "${pat}")
  done
  echo "${excludes[@]}"
}

log "Collecting dotfiles from ${HOME_DIR} → ${DEST_DIR}/"

# --- Individual files ---
for f in "${FILES[@]}"; do
  src="${HOME_DIR}/${f}"
  if [[ -f "${src}" ]]; then
    dest="${DEST_DIR}/${f}"
    run mkdir -p "$(dirname "${dest}")"
    run cp "${src}" "${dest}"
    log "  ✓ ${f}"
  else
    warn "  ✗ ${f} not found, skipping."
  fi
done

# --- Directories ---
for d in "${DIRS[@]}"; do
  src="${HOME_DIR}/${d}"
  if [[ -d "${src}" ]]; then
    dest="${DEST_DIR}/${d}"
    run mkdir -p "${dest}"
    # Use rsync for selective copy with exclusions
    # shellcheck disable=SC2046
    run rsync -a --delete $(build_rsync_excludes) "${src}/" "${dest}/"
    log "  ✓ ${d}/"
  else
    warn "  ✗ ${d}/ not found, skipping."
  fi
done

# --- Application configs (macOS-specific paths) ---
APP_DIR="${REPO_DIR}/files/app-configs"
run mkdir -p "${APP_DIR}"

# VS Code
if [[ "${EXPORT_VSCODE:-true}" == "true" ]]; then
VSCODE_SRC="${HOME_DIR}/Library/Application Support/Code/User"
VSCODE_DEST="${APP_DIR}/vscode"
if [[ -d "${VSCODE_SRC}" ]]; then
  run mkdir -p "${VSCODE_DEST}"
  [[ -f "${VSCODE_SRC}/settings.json" ]] && run cp "${VSCODE_SRC}/settings.json" "${VSCODE_DEST}/"
  [[ -f "${VSCODE_SRC}/keybindings.json" ]] && run cp "${VSCODE_SRC}/keybindings.json" "${VSCODE_DEST}/"
  [[ -d "${VSCODE_SRC}/snippets" ]] && run rsync -a "${VSCODE_SRC}/snippets/" "${VSCODE_DEST}/snippets/"
  if command -v code &>/dev/null; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "  [dry-run] would run: code --list-extensions > extensions.txt"
    else
      code --list-extensions > "${VSCODE_DEST}/extensions.txt"
    fi
  fi
  log "  ✓ VS Code settings + extensions list"
else
  warn "  ✗ VS Code config not found, skipping."
fi
fi

# iTerm2 plist
if [[ "${EXPORT_ITERM2:-true}" == "true" ]]; then
ITERM_PLIST="${HOME_DIR}/Library/Preferences/com.googlecode.iterm2.plist"
if [[ -f "${ITERM_PLIST}" ]]; then
  run mkdir -p "${APP_DIR}/iterm2"
  run plutil -convert xml1 -o "${APP_DIR}/iterm2/com.googlecode.iterm2.plist" "${ITERM_PLIST}"
  log "  ✓ iTerm2 preferences (plist → xml)"
else
  warn "  ✗ iTerm2 plist not found, skipping."
fi
fi

# Hidden Bar
if [[ "${EXPORT_HIDDENBAR:-true}" == "true" ]]; then
HIDDENBAR_PLIST="${HOME_DIR}/Library/Preferences/com.dwarvesv.minimalbar.plist"
if [[ -f "${HIDDENBAR_PLIST}" ]]; then
  run mkdir -p "${APP_DIR}/hiddenbar"
  run plutil -convert xml1 -o "${APP_DIR}/hiddenbar/com.dwarvesv.minimalbar.plist" "${HIDDENBAR_PLIST}"
  log "  ✓ Hidden Bar preferences"
else
  warn "  ✗ Hidden Bar plist not found, skipping."
fi
fi

# Cyberduck
if [[ "${EXPORT_CYBERDUCK:-true}" == "true" ]]; then
CYBERDUCK_PLIST="${HOME_DIR}/Library/Preferences/ch.sudo.cyberduck.plist"
if [[ -f "${CYBERDUCK_PLIST}" ]]; then
  run mkdir -p "${APP_DIR}/cyberduck"
  run plutil -convert xml1 -o "${APP_DIR}/cyberduck/ch.sudo.cyberduck.plist" "${CYBERDUCK_PLIST}"
  log "  ✓ Cyberduck preferences"
else
  warn "  ✗ Cyberduck plist not found, skipping."
fi
fi

# --- Secrets (vault-encrypted) ---
SECRETS_DIR="${REPO_DIR}/files/secrets"
run mkdir -p "${SECRETS_DIR}"

encrypt_vault() {
  local file="$1" label="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "  [dry-run] would encrypt: ${label}"
    return 0
  fi
  local vault_pass_file="${HOME}/.secrets/ansible-workstation-config"
  if command -v ansible-vault &>/dev/null; then
    # Only pass --vault-password-file if ansible.cfg doesn't already set it
    local vault_args=()
    if [[ -f "${vault_pass_file}" ]] && ! grep -q 'vault_password_file' "${REPO_DIR}/ansible.cfg" 2>/dev/null; then
      vault_args+=(--vault-password-file "${vault_pass_file}")
    fi
    if [[ "$(head -c 14 "${file}" 2>/dev/null)" != '$ANSIBLE_VAULT' ]]; then
      ansible-vault encrypt ${vault_args[@]+"${vault_args[@]}"} "${file}"
      log "  ✓ ${label} (encrypted)"
    else
      log "  ✓ ${label} (already encrypted)"
    fi
  else
    warn "${label} saved but ansible-vault not found — encrypt manually!"
    warn "  Run: ansible-vault encrypt ${file}"
  fi
}

# .aws/credentials
if [[ "${EXPORT_AWS_VAULT:-true}" == "true" ]]; then
AWS_CREDS="${HOME_DIR}/.aws/credentials"
AWS_VAULT="${SECRETS_DIR}/aws_credentials.vault"
if [[ -f "${AWS_CREDS}" ]]; then
  run cp "${AWS_CREDS}" "${AWS_VAULT}"
  encrypt_vault "${AWS_VAULT}" ".aws/credentials → ${AWS_VAULT}"
else
  warn "  ✗ .aws/credentials not found, skipping."
fi

# .aws/config (contains account IDs, SSO URLs, org names)
AWS_CONFIG="${HOME_DIR}/.aws/config"
AWS_CONFIG_VAULT="${SECRETS_DIR}/aws_config.vault"
if [[ -f "${AWS_CONFIG}" ]]; then
  run cp "${AWS_CONFIG}" "${AWS_CONFIG_VAULT}"
  encrypt_vault "${AWS_CONFIG_VAULT}" ".aws/config → ${AWS_CONFIG_VAULT}"
else
  warn "  ✗ .aws/config not found, skipping."
fi
fi

# .ssh directory (tar + vault)
if [[ "${EXPORT_SSH_VAULT:-true}" == "true" ]]; then
SSH_SRC="${HOME_DIR}/.ssh"
SSH_VAULT="${SECRETS_DIR}/dot_ssh.vault"
if [[ -d "${SSH_SRC}" ]] && [[ -n "$(ls -A "${SSH_SRC}" 2>/dev/null)" ]]; then
  run tar cf "${SSH_VAULT}" -C "${HOME_DIR}" --exclude='.ssh/known_hosts' --exclude='.ssh/known_hosts.old' .ssh
  encrypt_vault "${SSH_VAULT}" ".ssh/ → ${SSH_VAULT}"
else
  warn "  ✗ .ssh/ not found or empty, skipping."
fi
fi

# .secrets directory (tar + vault)
SECRETS_SRC="${HOME_DIR}/.secrets"

# rclone.conf (contains tokens/passwords)

# Kiro SSH MCP servers (contains hostnames, usernames)
KIRO_SSH="${HOME_DIR}/.kiro/settings/ssh-mcp-servers.json"
KIRO_SSH_VAULT="${SECRETS_DIR}/kiro_ssh_servers.vault"
if [[ -f "${KIRO_SSH}" ]]; then
  run cp "${KIRO_SSH}" "${KIRO_SSH_VAULT}"
  encrypt_vault "${KIRO_SSH_VAULT}" "ssh-mcp-servers.json → ${KIRO_SSH_VAULT}"
else
  warn "  ✗ .kiro/settings/ssh-mcp-servers.json not found, skipping."
fi

# rclone.conf (contains tokens/passwords)
if [[ "${EXPORT_RCLONE_VAULT:-true}" == "true" ]]; then
RCLONE_CONF="${HOME_DIR}/.config/rclone/rclone.conf"
RCLONE_VAULT="${SECRETS_DIR}/rclone_conf.vault"
if [[ -f "${RCLONE_CONF}" ]]; then
  run cp "${RCLONE_CONF}" "${RCLONE_VAULT}"
  encrypt_vault "${RCLONE_VAULT}" "rclone.conf → ${RCLONE_VAULT}"
else
  warn "  ✗ rclone.conf not found, skipping."
fi
fi

# .secrets directory (tar + vault)
if [[ "${EXPORT_SECRETS_VAULT:-true}" == "true" ]]; then
SECRETS_VAULT="${SECRETS_DIR}/dot_secrets.vault"
if [[ -d "${SECRETS_SRC}" ]] && [[ -n "$(ls -A "${SECRETS_SRC}" 2>/dev/null)" ]]; then
  run tar cf "${SECRETS_VAULT}" -C "${HOME_DIR}" .secrets
  encrypt_vault "${SECRETS_VAULT}" ".secrets/ → ${SECRETS_VAULT}"
else
  warn "  ✗ .secrets/ not found or empty, skipping."
fi
fi

log "Done."

# --- Sanitize: replace home path with placeholder ---
if [[ "${DRY_RUN}" != "true" ]]; then
  log ""
  log "Sanitizing exported files (replacing ${HOME_DIR} → __USER_HOME__)..."
  find "${DEST_DIR}" "${APP_DIR}" -type f \( -name '*.json' -o -name '*.yml' -o -name '*.yaml' -o -name '*.plist' -o -name '*.cfg' -o -name '*.conf' -o -name '*.txt' \) -exec \
    sed -i '' "s|${HOME_DIR}|__USER_HOME__|g" {} +
  log "  ✓ Paths sanitized. Ansible restore will expand __USER_HOME__ back."
fi

log ""
log "IMPORTANT: Review ${DEST_DIR}/ before committing."
log "  - Verify no secrets were captured (private keys, tokens, etc.)"
log "  - .ssh/config is included but private keys are excluded by default"
log "  - .aws/config is included but credentials are vault-encrypted separately"
log "  - .secrets/ is tar-archived and vault-encrypted"
log "  - Edit the FILES and DIRS arrays in this script to customize"
