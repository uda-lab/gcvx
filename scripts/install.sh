#!/bin/sh
# Install gcvx into the user's home directory.
#
#   scripts/install.sh [--force]
#
# Installs:
#   ~/.local/bin/gcvx                    the wrapper CLI
#   ~/.local/bin/gcvx-teammate           teammate launcher for `gcvx team`
#   ~/.config/gcvx/config.example       reference configuration
#   ~/.local/share/gcvx/plugin/         the Claude Code plugin
#
# Existing files are preserved unless --force is supplied. Shell profile
# files are never modified.

set -eu

force=0
case "${1:-}" in
    --force) force=1 ;;
    "") ;;
    *) printf 'usage: %s [--force]\n' "$0" >&2; exit 2 ;;
esac

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

bin_dir="$HOME/.local/bin"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gcvx"
share_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gcvx"
plugin_dir="$share_dir/plugin"

install_file() {
    # install_file <src> <dest> <mode>
    if [ -e "$2" ] && [ "$force" -ne 1 ]; then
        printf 'keep     %s (exists; use --force to overwrite)\n' "$2"
        return 0
    fi
    mkdir -p "$(dirname -- "$2")"
    cp "$1" "$2"
    chmod "$3" "$2"
    printf 'install  %s\n' "$2"
}

install_file "$repo_root/bin/gcvx" "$bin_dir/gcvx" 755

# gcvx-teammate must sit next to gcvx: it locates gcvx relative to its own
# path. It holds no user state, so it is always refreshed -- a stale copy
# beside a fresh gcvx is worse than no copy at all.
mkdir -p "$bin_dir"
cp "$repo_root/bin/gcvx-teammate" "$bin_dir/gcvx-teammate"
chmod 755 "$bin_dir/gcvx-teammate"
printf 'install  %s\n' "$bin_dir/gcvx-teammate"
install_file "$repo_root/config/config.example" "$config_dir/config.example" 644

if [ -d "$plugin_dir" ] && [ "$force" -ne 1 ]; then
    printf 'keep     %s (exists; use --force to overwrite)\n' "$plugin_dir"
else
    rm -rf "$plugin_dir"
    mkdir -p "$share_dir"
    cp -R "$repo_root/plugin" "$plugin_dir"
    chmod 755 "$plugin_dir/scripts/gcvx-companion"
    printf 'install  %s\n' "$plugin_dir"
fi

printf '\n'
case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) printf 'NOTE: %s is not on your PATH.\n' "$bin_dir" ;;
esac
cat <<EOF
Next steps:
  1. Run: gcvx init
  2. Load the plugin in Claude Code:
       claude --plugin-dir "$plugin_dir"
     (or add it permanently via your plugin configuration)
EOF
