# Changelog

Every update changes the gate's own files, so after upgrading, `approve` lists them as
changes to accept. This file says what you are approving.

## 3.2.0 (unreleased)

- Releases on GitHub: a source tarball with its SHA-256 and a signed build provenance
  attestation, so you can check that what you download was built from this repository.
- Homebrew: `brew install mermoddity/tap/backup-gate`. Homebrew only downloads the files;
  `sudo …/install.sh` installs the root-owned copy, as before.
- `status` says when Homebrew has downloaded a newer version that isn't installed yet. It reads
  only the version number from Homebrew's folder (a regular file, at most 64 KB), suggests no
  command pointing there, and doesn't use the network.
- The Homebrew formula is Apple silicon only: Intel Homebrew owns `/usr/local/sbin`, where the
  gate must be root-owned.
- README: how to verify a download, FAQ.
- SECURITY.md: how to report a vulnerability.

## 3.1.2 (2026-11-12)

- `approve` shows what can be checked about an item first: when its file was created, its
  owner, the installer package that put it there (when macOS has a receipt), and the command
  it runs. Built-in macOS programs are labeled as such, because their Apple signature says
  nothing about who added the item.

## 3.1.1 (2026-11-12)

- `approve` says which program a signature belongs to, so an item that runs a built-in macOS
  tool no longer reads as if Apple added it.

## 3.1.0 (2026-11-12)

- `approve` and `status` list changes as items instead of a raw diff: what kind of item, added,
  removed or changed, the command a launch item runs, who signed the program (checked against
  Apple's certificate chain), and warnings for unsigned or missing programs, script
  interpreters, and temporary or hidden folders. `RAW` still shows the diff.
- A duplicate of an approved item shows up as a change.
- Terminal control characters are stripped from everything shown.

## 3.0.0 (2026-11-12)

- First published version: a LaunchDaemon that backs up with Time Machine only when the
  inventory of persistence points matches the approved allowlist; success is a new APFS
  backup snapshot on the destination; `install.sh --check` preflight; upgrade in place.
