# Paths
export WORK="$HOME/Developer"
export ZSH="$HOME/.oh-my-zsh"
export DOTFILES="$HOME/.dotfiles"
export SCRIPTS="$DOTFILES/scripts"

# Alias List
alias all=". $SCRIPTS/fzf-alias.sh"
alias work=". $SCRIPTS/fzf-projects.sh"
alias home="cd $HOME"
alias dot="cd $DOTFILES"
alias c="clear"
alias reload="source $HOME/.zshrc"

# User configuration
export LANG=en_US.UTF-8 

# FZF config
source $ZSH/oh-my-zsh.sh
source <(fzf --zsh)
export FZF_DEFAULT_OPTS='--preview="bat --color=always {}" --layout=reverse --border'


# ZSH Styles
export ZSH_THEME="af-magic"
export COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
export COMPLETION_WAITING_DOTS="true"
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'

# OMZ Plugins
plugins=( git zsh-autosuggestions zsh-npm-scripts-autocomplete fzf)
