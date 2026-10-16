# Terminal: пользовательский ~/.zshenv подключается как обычно
[[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
# Без «белого % / #» перед первым приглашением (маркер PROMPT_SP)
unsetopt PROMPT_SP 2>/dev/null
