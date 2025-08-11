#!/bin/bash

# reference https://github.com/stephansama/scripts/blob/cf23b2173d2a0ae0a6328f3e994156975ee5fe26/fzf-projects.sh
query=$(
	find "$WORK" -type d -mindepth 1 -maxdepth 1 | sed "s@$WORK/@@g" | fzf
)

if [[ -z $query ]]; then
	return
fi

cd "$WORK/$query" || exit