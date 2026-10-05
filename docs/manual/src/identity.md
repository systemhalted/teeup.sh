# Identity

teeup configures git, SSH, and GitHub with your name and personal email. Each machine has one git identity. A second SSH key for work is optional. This key is in the machine file.

## git

| File | Owner | Holds |
|---|---|---|
| `~/.config/git/identity` | teeup | `user.name`, `user.email` and the signing key, from `TEEUP_NAME` and `TEEUP_EMAIL`. |
| `~/.config/git/teeup-generated` | teeup | The editor, the pager, and commit signature settings. These settings come from installed software. |
| `~/.config/git/config` | You | Other settings: defaults, aliases, colours. This file includes the two files above. |
| `~/.config/git/local` | You | Optional. git includes this file last. This file overwrites the files above. |

teeup rewrites the two generated files when it configures git. Change the configuration answers. Do not edit the files. Change your name or email with these commands:

```sh
teeup config set TEEUP_EMAIL ada@example.com
teeup configure git
```

A repository that requires a different address gets a custom setting. Run `git config user.email ...` in the repository. teeup does not change identities by directory.

git signs commits with your SSH key when the key exists, not GPG. During a first bootstrap, the SSH step creates the key. Then, the SSH step configures git again. The editor is `emacsclient -t` when you install Emacs. The editor is `vim` when you do not install Emacs. The pager is delta when you install delta.

## SSH

| Item | Detail |
|---|---|
| Key | `~/.ssh/id_ed25519_personal`, an ed25519 key with your email as its comment. |
| Passphrase | `ssh-keygen` asks for a passphrase. This passphrase goes into your login Keychain. You type the passphrase one time. |
| Config | `~/.ssh/config`. teeup writes this file only when you have no configuration file. This file uses the key for `github.com`. |

If your `~/.ssh/config` file names a key for GitHub, teeup uses that key. teeup does not make a new key. teeup does not edit your configuration file. When your configuration file lacks a required `Host` block, teeup prints the block. You must add the block manually.

**teeup does not delete SSH keys.** `teeup uninstall` with `--identity` only prints the commands to remove a key. Read [Uninstall](uninstall.md) for more data. When teeup must replace an unusable key file, teeup renames the file to `<name>.teeup_backup_<timestamp>`. teeup does not delete the file.

## GitHub

The `github` capability installs the GitHub CLI, `gh`, from Homebrew or MacPorts. teeup does not use a `gh` installation from mise as a substitute. teeup does these tasks:

1. teeup signs you in with `gh auth login --web --skip-ssh-key`. This command opens your browser. It does not ask for an SSH key.
2. teeup asks if it can upload your public key. Then, teeup uploads the key as an authentication key and as a signing key.
3. teeup configures `gh` to use SSH for git.

The default answer for the upload question is yes. teeup saves the answer as `TEEUP_GITHUB_UPLOAD_PERSONAL` or `TEEUP_GITHUB_UPLOAD_WORK`. A saved `no` skips the uploads. A saved `no` stops commit signing for the personal identity. Run this command to change the personal choice later:

```sh
teeup config set TEEUP_GITHUB_UPLOAD_PERSONAL yes && teeup configure github
```

Use `TEEUP_GITHUB_UPLOAD_WORK` for the work identity. When teeup runs without a terminal and no answer is saved, teeup uploads the keys.

If configuration cannot finish because you closed the browser, teeup shows a message. You can run `teeup configure github` again. teeup does not upload keys twice.

If `teeup doctor github` shows the mise `gh` is ahead on `PATH`, remove the global mise selection. Then, rebuild the shims:

```sh
mise unuse -g gh && mise uninstall gh --all && mise reshim
```

teeup prints this command. teeup does not change your mise configuration.

## A work identity

A Mac that you use for work can have a second SSH key. Set the key in the machine file, `~/.config/teeup/machines/<hostname>.conf`. Read [Answers and machines](answers-and-machines.md):

| Key | Meaning |
|---|---|
| `TEEUP_WORK_EMAIL` | Enables the work identity. This key is required for the other two keys. |
| `TEEUP_WORK_GH_HOST` | The GitHub host for work, for example a GitHub Enterprise server. The default value is `github.com`. |
| `TEEUP_WORK_GH_ACCOUNT` | The work GitHub login. Use this key when work is a second account on the same host as personal. |
| `TEEUP_PERSONAL_GH_ACCOUNT` | The personal GitHub login. Use this key when both accounts are on the same host. |

If you set `TEEUP_WORK_EMAIL`, teeup creates `~/.ssh/id_ed25519_work`. teeup adds the work SSH host alias to a new `~/.ssh/config`. teeup uploads the work key to the work host. Clone work repositories with the alias. For example, use `git@github.com-work:org/repo.git`.

When work and personal share `github.com`, `gh` operates as one account per host. teeup switches to `TEEUP_WORK_GH_ACCOUNT` for the upload and switches back afterwards. If you set `TEEUP_PERSONAL_GH_ACCOUNT`, teeup uses it. You must sign in to both accounts with `gh auth login --skip-ssh-key`. If you do not sign in to the correct account, teeup does not upload the key. teeup does not put the key on your other account.

git has one identity. The work key changes the key that SSH offers. The work key does not change the email on your commits.

## SSH host aliases

By default, teeup uses `github.com` as the SSH host alias for the personal identity. teeup uses `github.com-work` for the work identity. You can change these aliases. Set the aliases in your machine file (`~/.config/teeup/machines/<hostname>.conf`):

| Key | Meaning |
|---|---|
| `TEEUP_PERSONAL_SSH_HOST` | The SSH host alias for the personal identity. The default value is `github.com`. This alias applies to any Mac. |
| `TEEUP_WORK_SSH_HOST` | The SSH host alias for the work identity. The default value is `github.com-work`. |
