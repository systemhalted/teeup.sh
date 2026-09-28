# Company CA bundle

Date: 2026-09-28. Status: approved in the implementation brief.

## Goal

Make teeup, Git, Homebrew curl, mise, Node, Python requests, and other
OpenSSL-compatible command-line tools trust the administrator-managed root
certificates that already secure the owner's work Mac. Macs without
administrator-domain trust settings keep their existing trust behavior.

## Design

`lib/certs.sh` owns discovery, bundle generation, process environment, and
removal. On macOS it first asks `security dump-trust-settings -d` whether the
administrator trust domain contains certificates. It exports that domain to a
temporary plist, converts the plist to XML with `plutil`, and reads the SHA-1
keys from `trustList`. Those hashes are matched against the records emitted by
`security find-certificate -a -Z -p /Library/Keychains/System.keychain`; only
matching PEM records enter the private-root part of the bundle. Public roots
come from `security find-certificate -a -p
/System/Library/Keychains/SystemRootCertificates.keychain`.

The complete bundle and Homebrew curl configuration are staged in the state
directory and moved into place only after every command succeeds and both
certificate sections are non-empty. Byte-identical output keeps the existing
file and its modification time. A confirmed empty administrator trust domain
removes teeup's generated files and clears only environment values that point
at those files. An export, conversion, or certificate-enumeration failure
leaves a previous bundle untouched.

The same library applies environment defaults when sourced. It sets only
unset variables and only when a non-empty bundle exists on macOS. `lib/all.sh`
loads it early for teeup and lazy shims. The generated teeup environment file
loads the same library for every zsh. A later export in
`~/.config/zsh/local.zsh` still wins.

## Lifecycle

`teeup update` rebuilds the bundle before the checkout pull. `bootstrap`
rebuilds it after the macOS preflight and before package-manager work. The
`ca-bundle` core capability follows `xcode-clt`, rebuilds during configure,
reports its state through doctor, and removes its generated bundle and curl
configuration. Whole-machine uninstall recognizes both state files as teeup
owned.

Doctor reports one of three useful states: the Mac has no administrator roots,
the generated files are present and newer than their source keychains, or the
files need `teeup configure ca-bundle`. The keychain files' modification times
are the observable proxy for certificates added since the last build.

When checkout pull output contains `certificate`, update explains that a
network proxy is re-signing HTTPS and names both the configure and doctor
commands.

## Verification

A mocked `security` and `plutil` exercise empty trust settings, selected-hash
extraction, exclusion of an untrusted System-keychain certificate, unchanged
content, failed and empty exports, environment precedence, doctor states,
removal, and update ordering. The changed suites run with the default Bash and
the project's Bash 3.2 test binary. Final gates include shellcheck, capability
metadata lint, the full suite, the slow bootstrap suite once, and mdBook.
