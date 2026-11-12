# Security

backup-gate runs as root and is meant to protect your backups from malware, so security
problems in it matter. Thank you for reporting them.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately on GitHub:
[Security › Report a vulnerability](https://github.com/mermoddity/backup-gate/security/advisories/new).

Include what you did, what happened, and the macOS version. You'll get an answer within a
week. Once a fix is released, the advisory is published, with credit to you if you want it.

## Supported versions

Only the latest release gets fixes. See [Upgrade](README.md#upgrade) in the README.

## What counts

The [Limits](README.md#limits) section of the README is the threat model. In particular,
malware with root access can turn the gate off; that's a known limit, not a vulnerability.

Examples of what is a vulnerability:

- a way for a process **without root** to start a backup with unapproved changes, change the
  allowlist, or change what the gate runs
- a persistence item the gate should catch, by the README's list, that doesn't show up as a change
- a file name, plist or signature that makes `approve` show something different from
  what's on disk, or that runs code when shown
- a problem in `install.sh` or `uninstall.sh` that weakens the Mac's security
- a release whose contents don't match its tag

## Verifying a release

Each release has a SHA-256 checksum and a build provenance attestation signed by GitHub Actions:

```sh
shasum -a 256 -c SHA256SUMS
gh attestation verify backup-gate-X.Y.Z.tar.gz --repo mermoddity/backup-gate
```
