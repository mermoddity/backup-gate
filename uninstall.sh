#!/bin/bash
# Remove backup-gate. Your Time Machine backups are not touched.
#   sudo ./uninstall.sh
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo $0" >&2; exit 1; }

launchctl bootout system/local.backup-gate 2>/dev/null || true
rm -f /Library/LaunchDaemons/local.backup-gate.plist /usr/local/sbin/backup-gate
rm -rf /usr/local/etc/backup-gate /var/db/backup-gate /var/run/backup-gate.lock
echo "Removed the gate. The log is kept: /var/log/backup-gate.log"

printf 'Turn automatic Time Machine backups back on? [y/N] '
read -r ans
case "$ans" in y|Y|yes) tmutil enable && echo "Automatic backups are on." ;;
  *) echo "Left off. Turn on later with: sudo tmutil enable" ;; esac
