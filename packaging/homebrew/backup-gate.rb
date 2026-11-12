# Homebrew formula for backup-gate. The release workflow fills in @VERSION@ and @SHA256@ and
# attaches the result to the GitHub release; copy it to Formula/ in mermoddity/homebrew-tap.
class BackupGate < Formula
  desc "Time Machine backups that pause when macOS persistence points change"
  homepage "https://github.com/mermoddity/backup-gate"
  url "https://github.com/mermoddity/backup-gate/releases/download/v@VERSION@/backup-gate-@VERSION@.tar.gz"
  sha256 "@SHA256@"
  license "MIT"

  depends_on :macos

  # Nothing is linked into Homebrew's bin on purpose: Homebrew's folders are writable by your
  # user account, so the gate must never run from here as root. install.sh copies it to the
  # root-owned /usr/local/sbin, and that copy is the one that runs.
  def install
    libexec.install "backup-gate", "install.sh", "uninstall.sh", "config.example", "local.backup-gate.plist"
  end

  def caveats
    <<~EOS
      backup-gate runs as root, so Homebrew only downloads it. To install or upgrade
      (after every `brew upgrade backup-gate`), run:
        #{opt_libexec}/install.sh --check
        sudo #{opt_libexec}/install.sh

      Then use the installed copy, not this one:
        sudo /usr/local/sbin/backup-gate approve

      To remove it, run this before `brew uninstall backup-gate`:
        sudo #{opt_libexec}/uninstall.sh
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{libexec}/backup-gate version")
  end
end
