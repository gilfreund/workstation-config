
if [ "$(sysctl -n sysctl.proc_translated)" = "1" ]; then
    local brew_path="/usr/local/homebrew/bin"
    export HOMEBREW_CELLAR="/usr/local/Cellar"
else
    local brew_path="/opt/homebrew/bin"
fi
export PATH="${brew_path}:${PATH}"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY		# Share history between all sessions.
setopt INC_APPEND_HISTORY	# Write to the history file immediately, not when the shell exits.
setopt HIST_EXPIRE_DUPS_FIRST    # Expire a duplicate event first when trimming history.
setopt HIST_IGNORE_DUPS          # Do not record an event that was just recorded again.
setopt HIST_IGNORE_ALL_DUPS      # Delete an old recorded event if a new event is a duplicate.
setopt HIST_FIND_NO_DUPS         # Do not display a previously found event.
setopt HIST_IGNORE_SPACE         # Do not record an event starting with a space.
setopt HIST_SAVE_NO_DUPS         # Do not write a duplicate event to the history file.
setopt HIST_VERIFY               # Do not execute immediately upon history expansion.
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit
complete -C $(which aws_completer) aws

bindkey -e
bindkey '\e\e[C' forward-word
bindkey '\e\e[D' backward-word 

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"
