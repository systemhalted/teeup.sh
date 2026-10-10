# Identity

teeup configures git, SSH, and GitHub with your name and personal email. Each machine has one git identity. You can add a second SSH key for work in the machine file.

## git

| File | Owner | Holds |
|---|---|---|
| `~/.config/git/identity` | teeup | `user.name`, `user.email` and the signing key, from `TEEUP_NAME` and `TEEUP_EMAIL`. |
| `~/.config/git/teeup-generated` | teeup | The pager, and whether git signs commits, from the software that is installed. |
| `~/.config/git/config` | You | Other settings: defaults, aliases, colours. It includes the two files above. |
| `~/.config/git/local` | You | Optional. git includes this file last, so its settings have priority over all of the files above. |

teeup writes the two generated files again each time it configures git, so change the answers and do not edit the files. To change your name or email, run:

```sh
teeup config set TEEUP_EMAIL ada@example.com
teeup configure git
```

If a repository needs a different address, run `git config user.email ...` in that repository. teeup does not change identities by directory.

git signs commits with your SSH key, not with GPG. teeup enables signing when the key exists, and during a first bootstrap the SSH step creates the key and then configures git again. git uses the editor that the shell selects (read [Editors](shell-tools.md#editors)). If delta is installed, the pager is delta.

## SSH

| Item | Detail |
|---|---|
| Key | `~/.ssh/id_ed25519_personal`, an ed25519 key with your email as its comment. |
| Passphrase | `ssh-keygen` asks for a passphrase. It goes into your login Keychain, so you type it one time. |
| Config | `~/.ssh/config`, which teeup writes only if the file does not exist. It uses the key for `github.com`. |

If your `~/.ssh/config` file names a key for GitHub, teeup uses that key and does not make a new key or edit your file. If your file does not have a `Host` block that teeup needs, teeup prints the block for you to add.

**teeup does not delete SSH keys.** `teeup uninstall`, also with `--identity`, only prints the commands to remove a key (read [Uninstall](uninstall.md)). When teeup must replace an unusable key file, it moves the file to `<name>.teeup_backup_<timestamp>` and does not delete it.

## GitHub

The `github` capability installs the GitHub CLI, `gh`, from Homebrew or MacPorts, and does not use a `gh` from mise as a substitute. Then it does these steps in this order:

1. teeup signs you in with `gh auth login --web --skip-ssh-key`, which opens your browser and does not ask for an SSH key.
2. teeup asks one time if it can upload your public key. If you agree, teeup uploads the key as an authentication key and as a signing key.
3. teeup configures `gh` to use SSH for git.

The default answer for the upload question is yes, and teeup saves the answer as `TEEUP_GITHUB_UPLOAD_PERSONAL` or `TEEUP_GITHUB_UPLOAD_WORK`. A saved `no` skips both uploads and, for the personal identity, also keeps commit signing off. To change the personal choice later, run:

```sh
teeup config set TEEUP_GITHUB_UPLOAD_PERSONAL yes && teeup configure github
```

Use `TEEUP_GITHUB_UPLOAD_WORK` for the work identity. When teeup runs without a terminal and no answer is saved, teeup uploads the keys, as earlier versions did.

If the configuration cannot finish (for example, because you closed the browser), teeup tells you, and you can run `teeup configure github` again. teeup does not upload a key that is already on your account.

If `teeup doctor github` reports that the mise `gh` is before the package-manager `gh` on `PATH`, run this command. It removes the global mise selection and installation, and rebuilds the mise shims:

```sh
mise unuse -g gh && mise uninstall gh --all && mise reshim
```

teeup prints this command but does not change your mise configuration.

## A work identity

If you also use a Mac for work, it can have a second SSH key. Set these keys in the machine file, `~/.config/teeup/machines/<hostname>.conf`. Read [Answers and machines](answers-and-machines.md) for more information.

| Key | Meaning |
|---|---|
| `TEEUP_WORK_EMAIL` | Enables the work identity. This key is required for the other two keys. |
| `TEEUP_WORK_GH_HOST` | The GitHub host for work, for example a GitHub Enterprise server. The default value is `github.com`. |
| `TEEUP_WORK_GH_ACCOUNT` | The work GitHub login, if work is a second account on the same host as personal. |
| `TEEUP_PERSONAL_GH_ACCOUNT` | The personal GitHub login, if both accounts are on the same host. |

If you set `TEEUP_WORK_EMAIL`, teeup creates `~/.ssh/id_ed25519_work` and uploads it to the work host. It also adds the work SSH host alias to a new `~/.ssh/config`. Clone work repositories with the alias, for example `git@github.com-work:org/repo.git`.

When work and personal share `github.com`, `gh` can act as only one account per host. For the upload, teeup switches to `TEEUP_WORK_GH_ACCOUNT` (and to `TEEUP_PERSONAL_GH_ACCOUNT` if you set it), and then switches back. You must sign in to both accounts first, with `gh auth login --skip-ssh-key`. If the correct account is not signed in, teeup does not upload the key, rather than put it on your other account.

git still has one identity: the work key changes the key that SSH offers, not the email on your commits.

## SSH host aliases

By default, teeup uses `github.com` as the SSH host alias for the personal identity, and `github.com-work` for the work identity. To change these aliases, set them in your machine file (`~/.config/teeup/machines/<hostname>.conf`):

| Key | Meaning |
|---|---|
| `TEEUP_PERSONAL_SSH_HOST` | The SSH host alias for the personal identity. The default value is `github.com`. This alias applies to any Mac. |
| `TEEUP_WORK_SSH_HOST` | The SSH host alias for the work identity. The default value is `github.com-work`. |
