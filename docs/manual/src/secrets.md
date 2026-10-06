# Secrets

API tokens and passwords belong in the macOS Keychain. `teeup secret` stores them there, and `teeup-env` exports one to a shell when you need it.

| Command | What it does |
|---|---|
| `teeup secret set <name>` | Asks for the value, does not show it, and stores it. |
| `teeup secret get <name>` | Shows the value. |
| `teeup secret rm <name>` | Deletes the secret. |
| `teeup-env <name>` | Exports the secret to the current shell only. |
| `teeup-env <name> <VARIABLE>` | Does the same, with a variable name that you select. |

```sh
teeup secret set openai-api-key
teeup-env openai-api-key           # exports OPENAI_API_KEY
teeup-env openai-api-key MY_TOKEN  # exports MY_TOKEN
```

## Where they live

Each secret is a generic password in your login Keychain, with the service `teeup` and the account set to the name of the secret. Keychain Access shows the secrets under that name, and the macOS `security` command reads them:

```sh
security find-generic-password -s teeup -a openai-api-key -w
```

The secret value never goes through the command line of another process. teeup gives the value to `security` on standard input, so it does not show in `ps` output.

## Names

The first character of a name is a letter or a digit, and the other characters are letters, digits, dots, underscores, and dashes. `teeup secret set` does not accept an empty value.

If you do not specify a variable name, `teeup-env` makes one from the secret name. It changes the name to uppercase letters and changes each character that is not a letter, digit, or underscore to an underscore (`_`). If the first character is a digit, it adds a leading underscore. For example, `my.api-key` becomes `MY_API_KEY`.

## Using a secret

`teeup-env` is a shell function, so it changes only the shell where you run it and the programs that you start in that shell. New terminals do not have the variable, and your shell history never records the secret value.

To use a secret in only one command, read it inline:

```sh
GITHUB_TOKEN="$(teeup secret get github-token)" some-command
```

## Previewing

`DRY_RUN=true teeup secret set <name>` prints the `security` command, with `<value>` in place of the secret, but does not run it or ask you for input.
