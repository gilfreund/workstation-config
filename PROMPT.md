# LLM Generation Prompt

This repository was generated and iteratively refined using an LLM (Kiro CLI with Claude). The original prompt and subsequent update requests are documented below for reproducibility and transparency.

---

## Original Prompt

> Build a complete macOS + Debian configuration backup/restore system.
>
> Create a production-ready Git repository that backs up and restores a user's workstation configuration using Ansible.
>
> The solution must support:
> - macOS as the primary platform
> - Debian as the optional secondary platform
> - Current-machine data collection from the source machine
> - Bootstrap from a fresh machine to a restored machine
> - Idempotent re-runs
> - Separation of portable config vs OS-specific config
>
> The repository must both:
> 1. Collect/export configuration from the current machine
> 2. Reapply/restore configuration to a new machine
>
> Categories to manage:
> 1. **Dotfiles and directories** — `.zshrc`, `.bashrc`, `.gitconfig`, `.gitignore_global`, `.tmux.conf`, `.config/nvim`, `.config/ghostty`, `.ssh/config`
> 2. **Homebrew configuration** — export and restore via `Brewfile`
> 3. **macOS System Settings** — Dock, Finder, Trackpad, keyboard, screenshots via `osx_defaults`
> 4. **App preference backup** — Mackup integration
> 5. **Fresh machine bootstrap** — single `./bootstrap.sh` command
>
> Design principles:
> - Ansible as main orchestration
> - Small shell bootstrap to install Ansible itself
> - Platform detection (macOS vs Debian)
> - Idempotent and safe to re-run
> - Clear separation of collection vs restore flows
> - No hardcoded credentials
> - Explicit allowlists over recursive home-directory backup

---

## Iterative Updates

The following changes were requested after the initial generation:

1. **Add `.aws` support** — Include `.aws/config` as a plain-text dotfile directory. Store `.aws/credentials` as an ansible-vault encrypted file. Exclude `sso/cache/` and `cli/cache/`.

2. **Add `.secrets` as a vault** — Tar and vault-encrypt the entire `~/.secrets/` directory.

3. **Configure vault password** — Generate a random vault password, save it to `~/.secrets/ansible-workstation-config`, and wire up `ansible.cfg` and the export script to use it automatically.

4. **Move `.ssh` to vault** — Remove `.ssh` from plain-text export. Tar and vault-encrypt the entire `~/.ssh/` directory (keys, config, everything). Restore with correct permissions (700 dirs, 600 files, 644 `.pub`).

5. **Add `.kiro`** — Include `.kiro` as a plain-text dotfile directory (agents, extensions, hooks, powers, settings, skills, steering). Exclude sessions and CLI history.

6. **Add `.config/gh`, `.config/iterm2`, `.config/karabiner`** — Plain-text dotfile directories.

7. **Vault-encrypt `rclone`** — `.config/rclone/rclone.conf` contains tokens, so store it as `rclone_conf.vault` instead of plain text.

8. **Update documentation** — Rewrite README with complete inventory tables for plain-text dotfiles, vault-encrypted secrets, vault password management, and fresh-machine restore instructions.
