# Identity

teeup configures git, SSH, and GitHub using your name and personal email. Each machine has one git identity. A second SSH key for work is optional and lives in the machine file.

## git

| File | Owner | Holds |
|---|---|---|
| `~/.config/git/identity` | teeup | `user.name`, `user.email` and the signing key, from `TEEUP_NAME` and `TEEUP_EMAIL` |
| `~/.config/git/teeup-generated` | teeup | The editor, the pager, and whether commits are signed, based on what is installed |
| `~/.config/git/config` | You | Everything else: defaults, aliases, colours. It includes the two files above. |
| `~/.config/git/local` | You | Optional. Included last, so it wins over all of the above. |

teeup rewrites the two generated files whenever git is configured; change the answers instead of editing them. To change your name or email:

```sh
teeup config set TEEUP_EMAIL ada@example.com
teeup configure git
```

A repository that needs a different address gets its own setting, with `git config user.email ...` inside it. teeup does not switch identities by directory.

Commits are signed with your SSH key, not GPG. Signing turns on once the key exists; on a first bootstrap the SSH step creates the key and runs git's configuration again. The editor is `emacsclient -t` when Emacs is installed and `vim` otherwise, and the pager is delta when it is installed.

## SSH

| Item | Detail |
|---|---|
| Key | `~/.ssh/id_ed25519_personal`, an ed25519 key with your email as its comment |
| Passphrase | `ssh-keygen` asks for one. It goes into your login Keychain, so you type it once. |
| Config | `~/.ssh/config`, written only when you have none. It uses the key for `github.com`. |

If your own `~/.ssh/config` already names a key for GitHub, teeup uses that key instead of making a new one, and does not edit your config. When your config lacks a `Host` block teeup needs, it prints the block for you to add.

**teeup does not delete SSH keys.** `teeup uninstall`, even with `--identity`, only prints the commands that would remove a key (see [Uninstall](uninstall.md)). When teeup needs to replace an unusable key file, it moves the file aside as `<name>.teeup_backup_<timestamp>` instead of deleting it.

## GitHub

The `github` capability installs the GitHub CLI, `gh`, and then:

1. signs you in with `gh auth login --web --skip-ssh-key`, which opens your browser without asking about an SSH key;
2. asks once whether teeup may upload your public key, then uploads it as an authentication key and as a signing key;
3. sets `gh` to use SSH for git.

The upload question defaults to yes. teeup remembers the answer as `TEEUP_GITHUB_UPLOAD_PERSONAL` or `TEEUP_GITHUB_UPLOAD_WORK`. A saved `no` skips both uploads and leaves commit signing off for the personal identity. To change the personal choice later, run:

```sh
teeup config set TEEUP_GITHUB_UPLOAD_PERSONAL yes && teeup configure github
```

Use `TEEUP_GITHUB_UPLOAD_WORK` for the work identity. When teeup runs without a terminal and no answer is saved, it uploads the keys, matching the earlier behavior.

If setup cannot finish, for example because you closed the browser, it says so and you can run `teeup configure github` again. Keys already on your account are not uploaded twice.

## A work identity

A Mac you also use for work can have a second SSH key. Set it in the machine file, `~/.config/teeup/machines/<hostname>.conf` (see [Answers and machines](answers-and-machines.md)):

| Key | Meaning |
|---|---|
| `TEEUP_WORK_EMAIL` | Turns the work identity on. Required for the other two. |
| `TEEUP_WORK_GH_HOST` | The GitHub host for work, such as a GitHub Enterprise server. Defaults to `github.com`. |
| `TEEUP_WORK_GH_ACCOUNT` | The work GitHub login, when work is a second account on the same host as personal. |

With `TEEUP_WORK_EMAIL` set, teeup creates `~/.ssh/id_ed25519_work`, adds a `github.com-work` host to a new `~/.ssh/config`, and uploads the work key to the work host. Clone work repositories as `git@github.com-work:org/repo.git` to use it.

When work and personal share `github.com`, `gh` can only act as one account per host. teeup switches to `TEEUP_WORK_GH_ACCOUNT` for the upload and back afterwards; both accounts must already be signed in with `gh auth login --skip-ssh-key`. Without that key it refuses to upload the work key, rather than put it on your personal account.

git itself still has one identity. The work key changes which key SSH offers, not the email on your commits.
