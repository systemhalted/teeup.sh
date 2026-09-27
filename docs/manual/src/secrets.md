# Secrets

API tokens and passwords belong in the macOS Keychain. `teeup secret` stores them there, and `teeup-env` loads one into a shell when you need it.

| Command | What it does |
|---|---|
| `teeup secret set <name>` | Asks for the value, without showing it, and stores it |
| `teeup secret get <name>` | Prints the value |
| `teeup secret rm <name>` | Deletes it |
| `teeup-env <name>` | Exports it into the current shell only |
| `teeup-env <name> <VARIABLE>` | The same, under a variable name you choose |

```sh
teeup secret set openai-api-key
teeup-env openai-api-key           # exports OPENAI_API_KEY
teeup-env openai-api-key MY_TOKEN  # exports MY_TOKEN
```

## Where they live

Each secret is a generic password in your login Keychain, with the service `teeup` and the account set to the secret's name. Keychain Access shows them under that name, and macOS's own `security` command reads them:

```sh
security find-generic-password -s teeup -a openai-api-key -w
```

The value never passes through the command line of another process: teeup hands it to `security` on standard input, so it does not show up in `ps`.

## Names

A name starts with a letter or a digit, and then uses letters, digits, dots, underscores and dashes. `teeup secret set` refuses an empty value.

Without a variable name, `teeup-env` builds one from the secret's name: it upper-cases it, turns every character that is not a letter, digit or underscore into `_`, and adds a leading `_` when the name starts with a digit. So `my.api-key` becomes `MY_API_KEY`.

## Using a secret

`teeup-env` is a shell function, so it changes only the shell you run it in and the programs you start from it. New terminals do not have the variable, and the value never appears in your shell history.

To use a secret in one command only, read it inline:

```sh
GITHUB_TOKEN="$(teeup secret get github-token)" some-command
```

## Previewing

`DRY_RUN=true teeup secret set <name>` prints the `security` command it would run, with `<value>` in place of the secret, and asks for nothing.
