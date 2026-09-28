# Company certificates

When your Mac is on a network that inspects traffic, such as a company office or VPN, a proxy signs every secure connection with a private certificate. If your administrator has installed that certificate into your macOS System keychain, browsers trust it, but command-line tools like Git, Homebrew, and Python do not because they use their own trust stores.

Teeup automatically fixes this. When it finds an administrator-trusted certificate in your System keychain, it builds a certificate bundle (a PEM file) containing your company's certificate and Apple's standard public roots. It then configures your shell and command-line tools to use that bundle.

## How it works

You do not need to do anything. Teeup builds the bundle during `./bootstrap` and refreshes it every time you run `teeup update`.

It configures the tools by setting these environment variables:

- `SSL_CERT_FILE`
- `GIT_SSL_CAINFO`
- `CURL_CA_BUNDLE`
- `REQUESTS_CA_BUNDLE`
- `NODE_EXTRA_CA_CERTS`
- `HOMEBREW_CURLRC`

## Overriding the bundle

Teeup only sets those variables if they are unset. If you need to point a tool at a different certificate, or if you need to turn the bundle off, you can set the variable yourself in `~/.config/zsh/local.zsh`.

For example, to clear Git's certificate setting:

```zsh
export GIT_SSL_CAINFO=""
```

## Troubleshooting

You can check whether the bundle is working and up to date by running `teeup doctor`.

If your proxy certificate changes and you cannot pull the latest teeup code because Git rejects the connection, you can rebuild the bundle manually:

```sh
teeup configure ca-bundle
```
