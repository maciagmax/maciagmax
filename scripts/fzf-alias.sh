#!/bin/bash

# Get all aliases, strip alias prefix, and use fzf to select one
selected=$(alias | sed 's/^alias //' | sed 's/=/ > /' | fzf)

# If an alias was selected, echo it
if [[ -n "$selected" ]]; then
    cmd=$(echo "$selected")
    echo "$cmd"
fi