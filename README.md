# Workstation Config

> **⚠️ Warning:** This project has not been tested on a fresh machine yet. Review scripts and playbooks before running.

> **Note:** This repository was generated and iteratively refined using an LLM (Kiro CLI with Claude). See [PROMPT.md](PROMPT.md) for the original prompt and the sequence of updates.

Ansible-based backup and restore system for macOS and Debian workstations. Collects your current machine's configuration and replays it on a fresh machine.

## Supported Platforms

- **macOS** (primary) — dotfiles, Homebrew, system preferences, app settings
- **Debian** (secondary) — dotfiles, common CLI tooling

## Architecture

```
Collection (source machine)          Restore (fresh machine)
─────────────────────────            ──────────────────────
scripts/collect_current_state.sh     bootstrap.sh
  ├── export_macos_settings.sh         ├── install prerequisites
  ├── export_brew.sh                   ├── install Ansible
  └── export_dotfiles.sh               └── ansible-playbook site.yml
                                            ├── dotfiles role
                                            ├── homebrew role
                                            ├── mac-settings role
                                            ├── app-settings role
                                            └── debian-common role
```

## Quick Start

### Collect from current machine

```bash
git clone <this-repo> workstation-config
cd workstation-config
chmod +x scripts/*.sh
./scripts/collect_current_state.sh
```

This exports:
- macOS preference domains → `exports/macos/`
- Homebrew packages → `Brewfile` + `exports/brew/`
- Selected dotfiles → `files/dotfiles/`
- Vault-encrypted secrets → `files/secrets/`
- Human-readable report → `exports/reports/`

### Restore on a fresh machine

```bash
git clone <this-repo> workstation-config
cd workstation-config
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script:
1. Detects macOS or Debian
2. Installs Homebrew (macOS) or apt dependencies (Debian)
3. Installs Ansible
4. Installs Galaxy collections
5. Runs the full playbook

**Important:** Before running on a fresh machine, recreate the vault password file:
```bash
mkdir -p ~/.secrets && chmod 700 ~/.secrets
# Paste the same password used on the source machine:
echo 'your-vault-password' > ~/.secrets/ansible-workstation-config
chmod 600 ~/.secrets/ansible-workstation-config
```

### Manual playbook runs

```bash
# Dry-run to preview changes
ansible-playbook -i inventory/localhost.yml site.yml --check --diff

# Run with sudo password prompt (Debian)
ansible-playbook -i inventory/localhost.yml site.yml -K

# Run specific roles only
ansible-playbook -i inventory/localhost.yml site.yml --tags dotfiles
ansible-playbook -i inventory/localhost.yml site.yml --tags homebrew
ansible-playbook -i inventory/localhost.yml site.yml --tags mac-settings
```

## What Gets Collected

### Plain-text dotfiles (individual files)

| File | Description |
|------|-------------|
| `.zshrc` | Zsh configuration |
| `.bashrc` | Bash configuration |
| `.gitconfig` | Git configuration |
| `.gitignore_global` | Global gitignore |
| `.tmux.conf` | Tmux configuration |
| `.vimrc` | Vim configuration |

### Plain-text directories (recursive copy)

| Directory | Description |
|-----------|-------------|
| `.config/nvim` | Neovim configuration |
| `.config/ghostty` | Ghostty terminal config |
| `.config/gh` | GitHub CLI config |
| `.config/iterm2` | iTerm2 preferences |
| `.config/karabiner` | Karabiner-Elements key remapping |
| `.aws` | AWS config (excluding credentials) |
| `.kiro` | Kiro CLI agents, settings, steering (excluding sessions) |

### Vault-encrypted secrets

| Source | Vault file | Reason |
|--------|-----------|--------|
| `~/.ssh/` | `dot_ssh.vault` | Private keys, certificates |
| `~/.secrets/` | `dot_secrets.vault` | API keys, tokens |
| `~/.aws/credentials` | `aws_credentials.vault` | AWS access keys |
| `~/.config/rclone/rclone.conf` | `rclone_conf.vault` | Remote storage tokens |

### Application configs (macOS)

| App | What's collected | Restore method |
|-----|-----------------|----------------|
| VS Code | settings.json, keybindings, snippets, extensions list | Copy + `code --install-extension` |
| iTerm2 | Preferences plist (converted to XML) | `defaults import` |
| Hidden Bar | Preferences plist | `defaults import` |
| Cyberduck | Preferences plist | `defaults import` |

Stored in `files/app-configs/<app>/`. Plists are exported as XML for readability and diffability.

All vault files are encrypted with `ansible-vault` using the password in `~/.secrets/ansible-workstation-config`.

## Repository Layout

```
workstation-config/
├── README.md
├── bootstrap.sh               # Fresh-machine entry point
├── ansible.cfg                 # Ansible config (vault password path)
├── requirements.yml            # Galaxy dependencies
├── site.yml                    # Main playbook
├── Brewfile                    # Homebrew package manifest
├── inventory/
│   └── localhost.yml
├── group_vars/
│   ├── all.yml                 # Dotfile lists, vault toggles
│   ├── macos.yml               # macOS preferences variables
│   └── debian.yml              # Debian packages list
├── roles/
│   ├── dotfiles/               # Copy dotfiles + deploy vaults
│   ├── homebrew/               # Brew bundle install
│   ├── mac-settings/           # macOS defaults + restart handlers
│   ├── app-settings/           # Mackup restore
│   └── debian-common/          # apt install + shell config
├── scripts/
│   ├── collect_current_state.sh
│   ├── export_dotfiles.sh      # Dotfiles + vault exports
│   ├── export_macos_settings.sh
│   ├── export_brew.sh
│   └── generate_defaults_report.sh
├── files/
│   ├── dotfiles/               # Plain-text dotfile sources
│   ├── secrets/                # Vault-encrypted files (*.vault)
│   └── mackup/                 # Mackup configuration
└── exports/                    # Machine-specific exports (gitignored)
    ├── macos/
    ├── brew/
    └── reports/
```

## Customization

### Adding dotfiles

Edit `dotfiles_allowlist` (files) or `dotfiles_dirs` (directories) in `group_vars/all.yml`, and add the same entries to the `FILES` or `DIRS` arrays in `scripts/export_dotfiles.sh`.

### Adding vault-encrypted items

Add export logic in `scripts/export_dotfiles.sh` using the `encrypt_vault` helper, and a corresponding restore task in `roles/dotfiles/tasks/main.yml`.

### Adding macOS preference domains

Edit `mac_settings_domains` in `group_vars/macos.yml` and add `community.general.osx_defaults` tasks in `roles/mac-settings/tasks/main.yml`.

### Vault password management

The vault password lives at `~/.secrets/ansible-workstation-config` (outside the repo). Keep a copy in a password manager for fresh-machine restores.

```bash
# Edit an encrypted file
ansible-vault edit files/secrets/aws_credentials.vault

# Re-encrypt with a new password
ansible-vault rekey files/secrets/*.vault
```

### Mackup

Mackup handles application preferences that are tedious to manage with Ansible (e.g., IDE settings, terminal profiles). See `files/mackup/.mackup.cfg` for configuration.

What Mackup is good for: app preferences with well-known config paths (VS Code, iTerm2, etc.)
What to handle elsewhere: system-level settings (use mac-settings role), dotfiles you want templated (use dotfiles role).

## Caveats

- Some macOS settings require a logout/restart to take effect
- SIP-protected preferences cannot be changed programmatically
- Dock app layout requires `dockutil` (installed via Brewfile); the restore clears and rebuilds the Dock
- FileVault, firmware passwords, and MDM settings are out of scope
- Keyboard repeat rate and trackpad settings are system-level (`NSGlobalDomain`) and may behave slightly differently across hardware generations; Karabiner key remappings are portable
- `--check` mode cannot fully predict `osx_defaults` changes
- Mackup requires its storage backend (iCloud, Dropbox, etc.) to be configured first
- Vault-encrypted files require the same password on source and target machines

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
