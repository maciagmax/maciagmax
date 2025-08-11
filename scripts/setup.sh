#!/bin/bash

# Add code folder
[ -d "$HOME/Developer" ] || mkdir -p "$HOME/Developer"

# reference https://github.com/stephansama/scripts/blob/cf23b2173d2a0ae0a6328f3e994156975ee5fe26/setup-terminal.sh

# Install ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# ohmyzsh External plugins
plugins=(
	"pnpm https://github.com/ntnyq/omz-plugin-pnpm.git"
	"zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git"
	"zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git"
	"zsh-npm-scripts-autocomplete https://github.com/grigorii-zander/zsh-npm-scripts-autocomplete.git"
)

for plugin in "${plugins[@]}"; do
	key="${plugin%% *}"  # Extract key (before the first space)
	value="${plugin#* }" # Extract value (after the first space)
	git clone --depth=1 "$value" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$key"
done