#!/bin/sh
# Copyright (c) 2026 Mattia Cabrini
# SPDX-License-Identifier: MIT
#
# uninstall.sh -- remove the framework, the cron entry, and (after a prompt) the
# configuration. The spool and any deposited .noeml are left untouched. Root only.

set -u

PREFIX=${1:-/usr/local}
LIBEXEC="$PREFIX/libexec/nel"
CONF="$PREFIX/etc/nel.conf"
CRONTAB="/etc/crontab"
MARK="# net-expandable-logger"

[ "$(id -u)" = "0" ] || { echo "uninstall.sh: must be run as root" >&2; exit 1; }

# --- drop our cron line -----------------------------------------------------
# Rewrite the crontab keeping every line except our marked one.
tmpc=$(mktemp)
grep -v "$MARK" "$CRONTAB" > "$tmpc" 2>/dev/null || true
install -m 0644 "$tmpc" "$CRONTAB"
rm -f "$tmpc"
echo "Removed cron entry from $CRONTAB"

# --- remove the installed framework -----------------------------------------
rm -rf "$LIBEXEC"
echo "Removed $LIBEXEC"

# --- optionally remove the configuration ------------------------------------
printf 'Also remove %s? [y/N]: ' "$CONF"
IFS= read -r reply
case "$reply" in
y|Y) rm -f "$CONF"; echo "Removed $CONF" ;;
*)   echo "Kept $CONF" ;;
esac

echo "Spool and deposited .noeml were left in place."
