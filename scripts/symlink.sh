#!/usr/bin/env bash
#
# Symlink tracked config out of this repo and into the places the tools expect.
#
# Idempotent: a link that already points at the right file is left alone, so
# this is safe to re-run. Anything real that sits in the way is moved to a
# timestamped .backup.* beside it first — nothing is deleted.
#
#   ./scripts/symlink.sh            link everything
#   ./scripts/symlink.sh --dry-run  show what would happen, touch nothing

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
VSCODE_USER="$HOME/Library/Application Support/Code/User"
CLAUDE_SKILLS="$HOME/.claude/skills"
STAMP="backup.$(date +%Y%m%d%H%M%S)"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

run() { [ "$DRY_RUN" -eq 1 ] && return 0; "$@"; }

# Resolve a path through any symlinks, without requiring GNU coreutils
# (macOS ships BSD readlink, which has no -f). Relative link targets are
# resolved against the directory the link itself lives in.
resolve() {
  local p="$1" target hops=0
  while [ -L "$p" ] && [ "$hops" -lt 40 ]; do
    target="$(readlink "$p")"
    case "$target" in
      /*) p="$target" ;;
      *)  p="$(dirname "$p")/$target" ;;
    esac
    hops=$((hops + 1))
  done
  [ -e "$p" ] || { printf '%s' "$p"; return; }
  if [ -d "$p" ]; then (cd "$p" && pwd -P); else
    printf '%s/%s' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
  fi
}

link() {
  local src="$1" dest="$2"

  if [ ! -e "$src" ]; then
    printf '  skip    %s\n          (not in this repo)\n' "$dest"
    return 0
  fi

  if [ -L "$dest" ] && [ "$(resolve "$dest")" = "$(resolve "$src")" ]; then
    printf '  ok      %s\n' "$dest"
    return 0
  fi

  run mkdir -p "$(dirname "$dest")"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    printf '  BACKUP  %s\n          -> %s.%s\n' "$dest" "$dest" "$STAMP"
    run mv "$dest" "$dest.$STAMP"
  fi

  printf '  link    %s\n          -> %s\n' "$dest" "$src"
  run ln -s "$src" "$dest"
}

[ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing will be changed)"
echo "Linking from $DOTFILES"

# Shell. In setup.sh this must run *after* the oh-my-zsh installer, which
# writes its own ~/.zshrc and would otherwise clobber the link.
link "$DOTFILES/.zshrc" "$HOME/.zshrc"

# VS Code. Heads up: if you already have settings.json on this machine it is
# backed up, not merged — the repo copy wins. Diff the backup afterwards if
# you have been editing settings in the GUI.
link "$DOTFILES/config/vscode/settings.json" "$VSCODE_USER/settings.json"
link "$DOTFILES/config/vscode/snippets"      "$VSCODE_USER/snippets"

# Claude Code skills. Linked per skill, not as a whole directory, so skills
# managed elsewhere (e.g. ~/.agents/skills) keep working alongside these.
for skill in "$DOTFILES"/config/claude/skills/*/; do
  [ -d "$skill" ] || continue
  link "${skill%/}" "$CLAUDE_SKILLS/$(basename "$skill")"
done

echo "Done."
