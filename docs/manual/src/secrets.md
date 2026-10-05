# Secrets

API tokens and passwords belong in the macOS Keychain. The `teeup secret` command stores the secrets in the macOS Keychain. The `teeup-env` command exports a secret to a shell.

| Command | What it does |
|---|---|
| `teeup secret set <name>` | This command asks you to enter the value, but the command does not show the value. This command stores the value. |
| `teeup secret get <name>` | This command shows the value. |
| `teeup secret rm <name>` | This command deletes the secret. |
| `teeup-env <name>` | This command exports the secret to the current shell only. |
| `teeup-env <name> <VARIABLE>` | This command exports the secret to the variable name that you select. |

```sh
teeup secret set openai-api-key
teeup-env openai-api-key           # exports OPENAI_API_KEY
teeup-env openai-api-key MY_TOKEN  # exports MY_TOKEN
```

## Where they live

Each secret is a generic password in your login Keychain. The service is `teeup`. The account is the name of the secret. The Keychain Access application shows the secrets under that name. The macOS `security` command reads the secrets:

```sh
security find-generic-password -s teeup -a openai-api-key -w
```

The secret value is not in the command line of another process. The `teeup` command gives the value to the `security` command on standard input. As a result, the value does not show in the `ps` command output.

## Names

The first character of a name is a letter or a digit. The other characters are letters, digits, dots, underscores, and dashes. The `teeup secret set` command does not accept an empty value.

If you do not specify a variable name, the `teeup-env` command makes a variable name from the secret name. The command changes the name to uppercase letters. If a character is not a letter, digit, or underscore, the command changes the character to an underscore (`_`). If the first character is a digit, the command adds a leading underscore (`_`). For example, `my.api-key` becomes `MY_API_KEY`.

## Using a secret

The `teeup-env` command is a shell function. As a result, the command changes only the shell where you run the command. The command also changes the programs that you start in that shell. New terminals do not have the variable. The secret value never shows in your shell history.

If you want to use a secret in only one command, read the secret inline:

```sh
GITHUB_TOKEN="$(teeup secret get github-token)" some-command
```

## Previewing

The `DRY_RUN=true teeup secret set <name>` command prints the `security` command that it runs. The output shows `<value>`, not the secret. The command does not ask you for input.
