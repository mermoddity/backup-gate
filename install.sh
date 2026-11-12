#!/bin/bash
# Install or upgrade backup-gate.
#
#   ./install.sh --check            preflight only, no changes, no sudo needed
#   sudo ./install.sh               install, or upgrade an existing install (keeps config and allowlist)
#   sudo ./install.sh --dest ID     pick the Time Machine destination when there are several
#   sudo ./install.sh --reconfigure rewrite the config (destination) of an existing install
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C

SRC=$(cd "$(dirname "$0")" && pwd)
SBIN=/usr/local/sbin
SELF=$SBIN/backup-gate
ETC=/usr/local/etc/backup-gate
CONFIG=$ETC/config
ALLOW=$ETC/allowlist
STATE=/var/db/backup-gate
LABEL=local.backup-gate
PLIST=/Library/LaunchDaemons/$LABEL.plist

CHECK=0 RECONFIGURE=0 DEST=
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --reconfigure) RECONFIGURE=1 ;;
    --dest) DEST=${2:-}; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 64 ;;
  esac
  shift
done

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
die()  { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

echo "backup-gate $(sed -n 's/^VERSION=//p' "$SRC/backup-gate") installer"
echo "Preflight:"

[ "$(uname -s)" = Darwin ] || die "macOS only"
ok "macOS $(sw_vers -productVersion)"

# The gate refuses to run if any folder on its path is writable by non-root users
# (otherwise malware could swap the script). Intel Homebrew installs often chown /usr/local.
for d in /usr/local /usr/local/sbin /usr/local/etc; do
  [ -e "$d" ] || continue
  m=$(stat -f %Lp "$d")
  if [ "$(stat -f %Su "$d")" != root ] || case "${m: -2}" in *[2367]*) true;; *) false;; esac; then
    die "$d is owned by $(stat -f %Su:%Sg "$d") mode $m. It must be root-owned and not group/other-writable (see README, 'Requirements')."
  fi
done
ok "/usr/local is root-owned"

# Time Machine destination: local destinations only (success is read from the volume's APFS snapshots)
dests=$(tmutil destinationinfo 2>/dev/null | awk -F' *: *' '
  /^Kind/ { kind = $2 } /^Mount Point/ { mnt = $2 }
  /^ID/   { print $2 "\t" kind "\t" mnt; kind = mnt = "" }')
existing=0; [ -f "$CONFIG" ] && [ "$RECONFIGURE" = 0 ] && existing=1
if [ "$existing" = 1 ]; then
  ok "existing config kept: $CONFIG"
else
  [ -n "$dests" ] || die "no Time Machine destination. Add one first: System Settings > General > Time Machine (encrypt it), then rerun."
  if [ -n "$DEST" ]; then
    line=$(printf '%s\n' "$dests" | awk -F'\t' -v d="$DEST" '$1 == d')
    [ -n "$line" ] || die "--dest $DEST is not a Time Machine destination (see: tmutil destinationinfo)"
  elif [ "$(printf '%s\n' "$dests" | wc -l)" -gt 1 ]; then
    printf '%s\n' "$dests" | sed 's/^/        /'
    die "several destinations; pick one with --dest ID"
  else
    line=$dests
  fi
  dest_id=$(printf '%s' "$line" | cut -f1); kind=$(printf '%s' "$line" | cut -f2); mnt=$(printf '%s' "$line" | cut -f3)
  [ "$kind" = Local ] || die "destination $dest_id is '$kind'. Only local (USB/Thunderbolt APFS) destinations are supported."
  [ -n "$mnt" ] && [ -d "$mnt" ] || die "destination $dest_id is not mounted. Plug in and unlock the disk, then rerun."
  vol_uuid=$(diskutil info "$mnt" | sed -n 's/^ *Volume UUID: *//p')
  [ -n "$vol_uuid" ] || die "could not read the volume UUID of $mnt"
  ok "Time Machine destination $dest_id on $mnt (volume $vol_uuid)"
fi

if [ "$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2>/dev/null || echo 1)" = 0 ]; then
  ok "automatic Time Machine backups are off"
else
  warn "automatic Time Machine backups are on; the installer will turn them off (tmutil disable)"
fi

if [ -f "$SELF" ]; then ok "upgrade from $("$SELF" version 2>/dev/null || echo 'an older version')"; else ok "fresh install"; fi

if [ "$CHECK" = 1 ]; then
  echo "Preflight passed. Install with: sudo $0"
  exit 0
fi
[ "$(id -u)" -eq 0 ] || die "run with sudo: sudo $0"
[ -t 0 ] || die "run from an interactive Terminal: the last step asks you to approve the baseline"

echo "Installing:"
launchctl bootout "system/$LABEL" 2>/dev/null || true   # no scheduled run during the upgrade
install -d -o root -g wheel -m 755 "$SBIN" "$ETC" "$STATE"
install -o root -g wheel -m 755 "$SRC/backup-gate" "$SELF"
install -o root -g wheel -m 644 "$SRC/$LABEL.plist" "$PLIST"
ok "$SELF, $PLIST"
if [ "$existing" = 0 ]; then
  sed -e "s/__DEST_ID__/$dest_id/" -e "s/__DEST_VOLUME__/$vol_uuid/" "$SRC/config.example" > "$CONFIG.tmp"
  install -o root -g wheel -m 644 "$CONFIG.tmp" "$CONFIG"; rm -f "$CONFIG.tmp"
  ok "$CONFIG"
fi
touch /var/log/backup-gate.log; chown root:wheel /var/log/backup-gate.log; chmod 644 /var/log/backup-gate.log
if [ "$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2>/dev/null || echo 1)" != 0 ]; then
  tmutil disable && ok "automatic Time Machine backups turned off (backups now go through the gate)"
fi

echo
if [ -f "$ALLOW" ]; then
  echo "Approve the changes since your last approval (the new gate files show up here):"
else
  echo "Last step: approve the baseline. Read the inventory below; everything in it will be"
  echo "trusted from now on. If you see anything you don't recognize, answer no and investigate."
fi
if ! "$SELF" approve; then
  echo "Not approved, so the daemon was not started. When ready: sudo $SELF approve, then sudo $0"
  exit 1
fi
launchctl bootstrap system "$PLIST"
ok "daemon $LABEL loaded (checks every 30 minutes)"
echo
echo "Done. First backup now: sudo $SELF run now"
echo "Status any time:        $SELF status"
