# Identity

teeup configures git, SSH, and GitHub with your name and personal email. Each machine has one git identity. A second SSH key for work is optional. This key is in the machine file.

## git

| File | Owner | Holds |
|---|---|---|
| `~/.config/git/identity` | teeup | `user.name`, `user.email` and the signing key, from `TEEUP_NAME` and `TEEUP_EMAIL`. |
| `~/.config/git/teeup-generated` | teeup | The editor, the pager, and whether git signs commits. teeup sets these from the software that is installed. |
| `~/.config/git/config` | You | Other settings: defaults, aliases, colours. This file includes the two files above. |
| `~/.config/git/local` | You | Optional. git includes this file last, so its settings have priority over all of the files above. |

teeup writes the two generated files again each time it configures git. Change the answers, and do not edit the two files. To change your name or email, run:

```sh
teeup config set TEEUP_EMAIL ada@example.com
teeup configure git
```

If a repository needs a different address, run `git config user.email ...` in that repository. teeup does not change identities by directory.

git signs commits with your SSH key, not with GPG. teeup enables signing when the key exists. During a first bootstrap, the SSH step creates the key and then configures git again. If Emacs is installed, the editor is `emacsclient -t`. If Emacs is not installed, the editor is `vim`. If delta is installed, the pager is delta.

## SSH

| Item | Detail |
|---|---|
| Key | `~/.ssh/id_ed25519_personal`, an ed25519 key with your email as its comment. |
| Passphrase | `ssh-keygen` asks for a passphrase. This passphrase goes into your login Keychain. You type the passphrase one time. |
| Config | `~/.ssh/config`. teeup writes this file only when the file does not exist. This file uses the key for `github.com`. |

If your `~/.ssh/config` file names a key for GitHub, teeup uses that key. teeup does not make a new key. teeup does not edit your configuration file. If your configuration file does not have a `Host` block that teeup needs, teeup prints the block for you to add.

**teeup does not delete SSH keys.** `teeup uninstall` only prints the commands to remove a key, also with `--identity`. Read [Uninstall](uninstall.md) for more information. When teeup must replace an unusable key file, teeup moves the file to `<name>.teeup_backup_<timestamp>` and does not delete it.

## GitHub

The `github` capability installs the GitHub CLI, `gh`, from Homebrew or MacPorts. teeup does not use a `gh` installation from mise as a substitute. Then the capability does these steps in this order:

1. teeup signs you in with `gh auth login --web --skip-ssh-key`. This command opens your browser. It does not ask for an SSH key.
2. teeup asks one time if it can upload your public key. If you agree, teeup uploads the key as an authentication key and as a signing key.
3. teeup configures `gh` to use SSH for git.

The default answer for the upload question is yes. teeup saves the answer as `TEEUP_GITHUB_UPLOAD_PERSONAL` or `TEEUP_GITHUB_UPLOAD_WORK`. A saved `no` skips both uploads. For the personal identity, a saved `no` also keeps commit signing off. Run this command to change the personal choice later:

```sh
teeup config set TEEUP_GITHUB_UPLOAD_PERSONAL yes && teeup configure github
```

Use `TEEUP_GITHUB_UPLOAD_WORK` for the work identity. When teeup runs without a terminal and no answer is saved, teeup uploads the keys. Earlier versions of teeup did the same.

If the configuration cannot finish, teeup tells you. One cause is that you closed the browser. You can run `teeup configure github` again. teeup does not upload a key that is already on your account.

If `teeup doctor github` reports that the mise `gh` is before the package-manager `gh` on `PATH`, remove the global mise selection and installation. Then rebuild the mise shims:

```sh
mise unuse -g gh && mise uninstall gh --all && mise reshim
```

teeup prints this command. teeup does not change your mise configuration.

## A work identity

If you also use a Mac for work, the Mac can have a second SSH key. Set these keys in the machine file, `~/.config/teeup/machines/<hostname>.conf`. Read [Answers and machines](answers-and-machines.md) for more information.

| Key | Meaning |
|---|---|
| `TEEUP_WORK_EMAIL` | Enables the work identity. This key is required for the other two keys. |
| `TEEUP_WORK_GH_HOST` | The GitHub host for work, for example a GitHub Enterprise server. The default value is `github.com`. |
| `TEEUP_WORK_GH_ACCOUNT` | The work GitHub login. Use this key when work is a second account on the same host as personal. |
| `TEEUP_PERSONAL_GH_ACCOUNT` | The personal GitHub login. Use this key when both accounts are on the same host. |

If you set `TEEUP_WORK_EMAIL`, teeup creates `~/.ssh/id_ed25519_work`. teeup adds the work SSH host alias to a new `~/.ssh/config`. teeup uploads the work key to the work host. Clone work repositories with the alias. For example, use `git@github.com-work:org/repo.git`.

When work and personal share `github.com`, `gh` can act as only one account per host. For the upload, teeup switches to `TEEUP_WORK_GH_ACCOUNT`, and to `TEEUP_PERSONAL_GH_ACCOUNT` if you set it. Then teeup switches back. Before this, you must sign in to both accounts with `gh auth login --skip-ssh-key`. If the correct account is not signed in, teeup does not upload the key. teeup does not put the key on your other account.

git still has one identity. The work key changes the key that SSH offers. The work key does not change the email on your commits.

## SSH host aliases

By default, teeup uses `github.com` as the SSH host alias for the personal identity. teeup uses `github.com-work` for the work identity. You can change these aliases. Set the aliases in your machine file (`~/.config/teeup/machines/<hostname>.conf`):

| Key | Meaning |
|---|---|
| `TEEUP_PERSONAL_SSH_HOST` | The SSH host alias for the personal identity. The default value is `github.com`. This alias applies to any Mac. |
| `TEEUP_WORK_SSH_HOST` | The SSH host alias for the work identity. The default value is `github.com-work`. |
