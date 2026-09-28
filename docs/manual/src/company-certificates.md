# Company certificates

When your Mac is on a network that inspects traffic, such as a company office or VPN, a proxy signs every secure connection with a private certificate. Your administrator installs that certificate in the macOS System keychain, so browsers trust it. Command-line tools such as git, Homebrew's curl, mise and Python's requests do not, because they read their own lists of trusted certificates. They fail with errors such as "self signed certificate in certificate chain".

When the Mac has certificates an administrator trusts as a root, teeup builds a certificate bundle (a PEM file) from Apple's public roots and those certificates. A certificate marked Never Trust is left out. teeup then points your shell and teeup's own commands at the bundle. On a Mac without company certificates it does nothing.

## How it works

You do not need to do anything. teeup builds the bundle during `./bootstrap` and rebuilds it at the start of every `teeup update`, before it contacts the network. The bundle lives in `~/.local/state/teeup/ca-bundle.pem`. It works on every network, because it holds both the public roots and the company ones.

It configures the tools by setting these environment variables:

- `SSL_CERT_FILE`
- `GIT_SSL_CAINFO`
- `CURL_CA_BUNDLE`
- `REQUESTS_CA_BUNDLE`
- `NODE_EXTRA_CA_CERTS`
- `HOMEBREW_CURLRC`

## Overriding the bundle

teeup only sets a variable that is not already set. To point one tool at a different file, set its variable in `~/.config/zsh/local.zsh`, which loads after teeup's settings:

```zsh
export GIT_SSL_CAINFO="$HOME/certs/other.pem"
```

To turn the bundle off entirely, run `teeup remove ca-bundle`.

## Troubleshooting

`teeup doctor ca-bundle` says whether this Mac needs a bundle, and whether the bundle is present and current.

If your company replaces its certificate and git starts failing again, rebuild the bundle:

```sh
teeup configure ca-bundle
```
