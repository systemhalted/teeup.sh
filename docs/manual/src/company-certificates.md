# Company certificates

On a network that inspects traffic, such as a company office or a VPN, a proxy signs every secure connection with a private certificate. Your administrator installs that certificate in the macOS System keychain, so browsers trust it.

Command-line tools such as git, Homebrew's curl, mise, and Python's requests do not trust the certificate, because they read their own lists of trusted certificates. They fail with errors such as "self signed certificate in certificate chain".

If the Mac has certificates that an administrator trusts as roots, teeup makes a PEM certificate bundle from Apple's public roots and these certificates. It does not use a certificate marked Never Trust. Then it configures your shell and its own commands to use the bundle. On a Mac without company certificates, teeup does nothing.

## How it works

You do not need to do anything. teeup makes the bundle during `./bootstrap`, and makes it again at the start of every `teeup update`, before it connects to the network. teeup puts the bundle in `~/.local/state/teeup/ca-bundle.pem`. The bundle works on every network because it has the public roots and the company certificates.

teeup sets these environment variables to configure the tools:

- `SSL_CERT_FILE`
- `GIT_SSL_CAINFO`
- `CURL_CA_BUNDLE`
- `REQUESTS_CA_BUNDLE`
- `NODE_EXTRA_CA_CERTS`
- `HOMEBREW_CURLRC`

## Overriding the bundle

teeup sets a variable only if it does not have a value. To use a different file for one tool, set its variable in `~/.config/zsh/local.zsh`, which loads after the teeup settings:

```zsh
export GIT_SSL_CAINFO="$HOME/certs/other.pem"
```

To remove the bundle entirely, run `teeup remove ca-bundle`.

## Installing teeup on such a network

Before teeup makes its bundle, curl and git do not trust the company certificate. On such a network, the one-line installer and `git clone` can fail with a certificate error. Run the installer on a different network, for example a phone hotspot. Or clone teeup by hand on a different network, and then run `./bootstrap` (see [Getting started](getting-started.md#the-first-run)). After `./bootstrap` makes the bundle, teeup works on the company network.

## Troubleshooting

`teeup doctor ca-bundle` shows if this Mac needs a bundle, and if the bundle is available and current.

If your company replaces its certificate and git fails again, make the bundle again:

```sh
teeup configure ca-bundle
```
