# backup-gate

**Time Machine backups that stop when your Mac might be compromised.**

Time Machine keeps a limited history. If malware installs itself and goes unnoticed, every
hourly backup copies it in, and Time Machine gradually deletes the older, clean backups to make
room. By the time you notice, there may be no clean backup left to restore.

backup-gate lets Time Machine back up only when nothing that can run code at startup has changed
since you last approved it. When something changes (a new LaunchAgent, a login item, an edited
`.zshrc`, a new sudoers rule...), backups pause and you get a notification. You look at the
change and approve it, or investigate it. Either way, your older backups stay clean.

It's a single bash script with a LaunchDaemon. It has no dependencies and doesn't use the network.

```
$ backup-gate status
Last successful backup: 2026-11-12 09:56
Recent log:
  2026-11-12 13:58:02 starting backup to 4F1A9C2E-…
  2026-11-12 13:58:41 backup finished (2026-11-12-135804)
  2026-11-12 17:30:52 BLOCKED: 2 line(s) changed since the last approval
Pending changes (< removed, > added):
> btm	501	app|com.example.agent|…
> launch	/Users/you/Library/LaunchAgents/com.example.agent.plist	you:staff:644	9f2c…
```

## How it works

Every 30 minutes a root LaunchDaemon runs `backup-gate run`:

1. If the last successful backup is less than 4 hours old, it stops (nothing is written).
2. If the screen is locked or nobody is logged in, it skips and tries again later. Time Machine
   can't finish a backup while the Mac is locked (`BACKUP_FAILED_DEVICE_LOCKED`).
3. It builds an inventory of the Mac's persistence points (below) and compares it with the
   approved allowlist.
4. **Anything differs:** it logs `BLOCKED`, sends a notification, and doesn't back up.
5. **Everything matches:** it runs `tmutil startbackup` and records a success only if a new
   completed backup snapshot appears on the destination. (`tmutil` exits 0 even when the
   backup fails, so its exit code isn't trusted.)
6. If no backup has succeeded for 48 hours, it notifies you.

### What's in the inventory

- **Launch items:** `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/StartupItems`
  and each user's `~/Library/LaunchAgents` (path, owner, mode, SHA-256)
- **Background and login items** registered with macOS (`sfltool dumpbtm`)
- **Shell and SSH files** for each user and root: `.zshrc`, `.zprofile`, `.zshenv`, `.zlogin`,
  `.bash*`, `.profile`, `~/.ssh/authorized_keys`, `config`, `environment`, `rc`
- **System files:** `/etc/zsh*`, `/etc/profile`, `/etc/paths(.d)`, `/etc/hosts`, `sudoers(.d)`,
  `pam.d/sudo(_local)`, `crontab` and `/var/at` jobs, `periodic`, `sshd_config(.d)`,
  `PrivilegedHelperTools`, `/Library/Extensions`, `SecurityAgentPlugins`, `ScriptingAdditions`
- **Login and logout hooks**, **configuration profiles**, **system extensions**
- **The gate itself:** its script and config, so changes to the gate need approval too

Some problems always block, and `approve` refuses to accept them:

- a `com.Apple.*` name (a common way for malware to pose as Apple)
- a launch item under `/Library` that isn't owned by `root:wheel`
- a gate file that isn't root-owned, or is writable by others
- an inventory error (for example, the background-items list can't be read)

## Requirements

- macOS (tested on macOS 27 on Apple silicon), and an admin account
- A **local** Time Machine destination: an APFS disk over USB or Thunderbolt. Encrypting it is
  recommended. Network destinations aren't supported, because success is read from the
  disk's APFS snapshots.
- `/usr/local` must be root-owned and not writable by other users, because the gate refuses to run
  from a folder that malware could write to. Apple silicon Homebrew uses `/opt/homebrew`, so this
  is usually already true. If an old Intel Homebrew install changed the owner, the installer
  tells you.

## Install

1. Add your backup disk in **System Settings › General › Time Machine** (choose to encrypt it).
   You don't need to wait for the first backup.
2. Clone the repo and run the preflight. It makes no changes and doesn't need sudo:

   ```sh
   git clone https://github.com/mermoddity/backup-gate.git
   cd backup-gate
   ./install.sh --check
   ```

3. Read `backup-gate` before you install it. It runs as root.
4. Install:

   ```sh
   sudo ./install.sh
   ```

   The installer copies the files, writes the config for your destination, and turns off
   Time Machine's automatic backups (backups now go through the gate). It then shows the full
   inventory of your Mac and asks you to type `APPROVE`. **Only approve if you trust the Mac's
   current state.** On a Mac you think may already be infected, clean it up first.
5. Run the first backup:

   ```sh
   sudo /usr/local/sbin/backup-gate run now
   ```

To upgrade, `git pull` and run `sudo ./install.sh` again. Your config and allowlist are kept,
and you approve the new gate files.

## Daily use

`sudo` doesn't search `/usr/local/sbin`, so use the full path.

| Command | What it does |
|---|---|
| `/usr/local/sbin/backup-gate status` | last backup, recent log, problems, pending changes |
| `sudo /usr/local/sbin/backup-gate approve` | show the changes since the last approval; type `APPROVE` to accept them |
| `sudo /usr/local/sbin/backup-gate run now` | back up now (still checks the lock and the allowlist) |
| `sudo /usr/local/sbin/backup-gate inventory` | refresh the inventory without backing up |
| `cat /var/log/backup-gate.log` | full history |

**After installing or updating something** (an app, a Homebrew service, a macOS update, an edit
to `.zshrc`...), expect a "N change(s) since the last approval" notification. Run `status`,
check that every line is something you did, then `approve`. If you see a change you didn't
make, don't approve it: find out what it is first.

The notification is sent with `osascript`, so macOS shows it as coming from Script Editor.
Allow its notifications in System Settings › Notifications.

## Configuration

`/usr/local/etc/backup-gate/config` (root-owned; the gate parses it and never runs it):

| Key | Default | Meaning |
|---|---|---|
| `DEST_ID` | set by the installer | Time Machine destination (`tmutil destinationinfo`) |
| `DEST_VOLUME` | set by the installer | APFS volume UUID of the destination |
| `MIN_HOURS` | `4` | back up when the last success is older than this |
| `STALE_HOURS` | `48` | notify when the last success is older than this |
| `UNMOUNT_AFTER` | `0` | unmount the disk after each backup. Leave it at 0 for an encrypted disk, because Time Machine can't unlock it again by itself |

The check interval (30 minutes) is `StartInterval` in `/Library/LaunchDaemons/local.backup-gate.plist`.

The gate also excludes `node_modules` and `.venv` folders in home directories from backups
when it finds them. macOS doesn't let the daemon read Desktop, Documents, Downloads and
the other privacy-protected folders, so it can't exclude folders inside them.

## Limits

backup-gate protects your backup history. It doesn't stop or remove malware.

- **Malware with root access can turn the gate off.** The gate checks its own files and treats
  any change to them as a change to approve, but anything running as root can bypass that.
  Keep the admin password to yourself, and never type it into a dialog you didn't open.
  A real-time persistence monitor such as [BlockBlock](https://objective-see.org/products/blockblock.html)
  is a good companion, and so is a periodic scan with [KnockKnock](https://objective-see.org/products/knockknock.html).
- **The gate only watches persistence.** Malware that runs once and leaves nothing behind
  doesn't trigger it. Neither does a change to your documents, for example by ransomware.
- **It needs you.** Backups stay paused until you approve. If you ignore the notifications,
  your backups go stale. The 48-hour warning is there to remind you.
- **The Mac must sometimes be unlocked while the disk is connected.** Time Machine won't
  back up a locked Mac.
- **An always-connected disk is reachable by malware.** Unplugging the disk is the best offline
  protection. Keep a second, offline copy of anything you can't lose.

## Uninstall

```sh
sudo ./uninstall.sh
```

This removes the daemon, the script, the config and the state, and asks whether to turn
automatic Time Machine backups back on. Your backups and the log are kept.

## Tests

```sh
bash tests/run.sh
```

The tests run the gate's decision logic with stand-ins for `tmutil`, `diskutil`, `ioreg` and
`id`. They don't need root and don't touch your system. They also run in CI on each push.

## License

MIT
