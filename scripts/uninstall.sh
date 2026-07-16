#!/bin/sh
# Uninstall gcvx from the user's home directory.
#
#   scripts/uninstall.sh [--purge]
#
# Removes the CLI and the installed plugin. The configuration directory is
# kept unless --purge is supplied.

set -eu

purge=0
case "${1:-}" in
    --purge) purge=1 ;;
    "") ;;
    *) printf 'usage: %s [--purge]\n' "$0" >&2; exit 2 ;;
esac

bin="$HOME/.local/bin/gcvx"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gcvx"
share_dir="${XDG_DATA_HOME:-$HOME/.local/share}/gcvx"

remove() {
    if [ -e "$1" ]; then
        rm -rf "$1"
        printf 'removed  %s\n' "$1"
    fi
}

remove "$bin"
remove "$share_dir"

if [ "$purge" -eq 1 ]; then
    remove "$config_dir"
else
    [ -d "$config_dir" ] && printf 'kept     %s (use --purge to remove)\n' "$config_dir"
fi
