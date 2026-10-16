# Terminal: если у пользователя есть свой ~/.zshrc — используем его; иначе аккуратные настройки по умолчанию
if [[ -f "$HOME/.zshrc" ]]; then
  source "$HOME/.zshrc"
else
  autoload -Uz compinit && compinit -u 2>/dev/null
  setopt PROMPT_SUBST HIST_IGNORE_DUPS SHARE_HISTORY AUTO_CD
  HISTFILE="$HOME/.zsh_history"; HISTSIZE=5000; SAVEHIST=5000
  bindkey -e
  bindkey '^[[3~' delete-char; bindkey '^[[H' beginning-of-line; bindkey '^[[F' end-of-line
  bindkey '^[[1;5C' forward-word; bindkey '^[[1;5D' backward-word
  zstyle ':completion:*' menu select
  alias ls='ls --color=auto' 2>/dev/null; alias ll='ls -lah'; alias la='ls -A'
  if [[ $EUID -eq 0 ]]; then
    PROMPT='%B%F{red}%n%f%b@%m %F{blue}%~%f %B%F{red}#%f%b '
  else
    PROMPT='%B%F{green}%n%f%b@%m %F{blue}%~%f %B%F{green}$%f%b '
  fi
fi
