# Company certificates

When your Mac connects to a network that inspects traffic, a proxy signs every secure connection with a private certificate. A company office or a VPN is an example of this network. Your administrator installs that certificate in the macOS System keychain. Browsers then trust the certificate.

Command-line tools such as git, Homebrew's curl, mise, and Python's requests do not trust the certificate. These tools read their own lists of trusted certificates. They fail with errors such as "self signed certificate in certificate chain".

If the Mac has root certificates that an administrator trusts, teeup makes a certificate bundle. This bundle is a PEM file. teeup makes the bundle from Apple's public roots and the company certificates. teeup does not use a certificate if it has a Never Trust mark. teeup then configures your shell and teeup's commands to use the bundle. If a Mac does not have company certificates, teeup does nothing.

## How it works

You do not need to do anything. teeup makes the bundle during `./bootstrap`. teeup makes the bundle again at the start of every `teeup update`. teeup does this before it connects to the network. teeup puts the bundle in `~/.local/state/teeup/ca-bundle.pem`. The bundle works on every network because it has the public roots and the company certificates.

teeup configures the tools. teeup sets these environment variables:

- `SSL_CERT_FILE`
- `GIT_SSL_CAINFO`
- `CURL_CA_BUNDLE`
- `REQUESTS_CA_BUNDLE`
- `NODE_EXTRA_CA_CERTS`
- `HOMEBREW_CURLRC`

## Overriding the bundle

teeup sets a variable only if the variable is not set. To use a different file for one tool, set the variable for that tool in `~/.config/zsh/local.zsh`. This file loads after the teeup settings:

```zsh
export GIT_SSL_CAINFO="$HOME/certs/other.pem"
```

To remove the bundle entirely, run `teeup remove ca-bundle`.

## Troubleshooting

The `teeup doctor ca-bundle` command shows if this Mac needs a bundle. The command also shows if the bundle is available and current.

If your company replaces the company certificate and git fails again, run this command:

```sh
teeup configure ca-bundle
```
