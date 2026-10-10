# Updates

`teeup update` keeps the Mac current:

```sh
teeup update
DRY_RUN=true teeup update    # the same, as a preview that changes nothing
```

`teeup update` updates the Mac and configures the installed capabilities, but it does not finish an incomplete bootstrap. To finish one, run `./bootstrap` again (see [Getting started](getting-started.md)).

## What runs, in order

| Step | What happens |
|---|---|
| 1. Checkout | `git fetch` downloads the new releases and commits of teeup. Then teeup moves the checkout forward on its channel: to the newest release, or to the newest commit on `main`. See [Release or main](#release-or-main). |
| 2. Packages | `brew update` runs (with MacPorts, `port selfupdate`). If step 1 moved the checkout to a new commit, `brew upgrade` (with MacPorts, `port upgrade`) upgrades only the packages and casks that teeup installed. If the checkout did not move, their versions stay as they are. teeup does not upgrade other Homebrew packages: use `brew upgrade` for them. A package that a capability uses belongs to teeup, so teeup upgrades it even if you installed it before teeup. A future version will let you choose (issue #79). |
| 3. mise | `mise upgrade` runs for every tool in the global mise configuration, which includes the language runtimes and the AI tools. |
| 4. Pinned tools | For every installed capability, teeup installs the tools that `share/teeup/tools.lock` names, at the versions of the release, and links them into `~/.local/bin`. See [Tool versions](#tool-versions). |
| 5. Migrations | teeup runs every migration script that this Mac did not run yet. |
| 6. Configure | The `configure` script runs again for every installed capability in the core tier, and then in the daily tier. |
| 7. Theme | If step 6 did not render the current theme, teeup renders it again. |
| 8. Hooks | Your `post-update` hooks run (see [Hooks and extending](hooks-and-extending.md)). |

The migrations run after the upgrades, because a migration adjusts a configuration file for a new tool version and must see the newly installed version.

Step 6 applies the changed answers. If you set a new Emacs flavor with `teeup config set`, `teeup update` applies it because Emacs is in the daily tier.

## What it leaves alone

- **Lazy capabilities.** Their `configure` step does not run again, because it can start a virtual machine (for example, Colima). Steps 2 and 4 upgrade their packages and their pinned tools.
- **Capabilities that you did not install on this Mac.** The update does not change these capabilities, or the capabilities that your machine file lists in `TEEUP_SKIP`. teeup prints a line for each one and continues.
- **Your files.** The `configure` step never overwrites a configuration file that you edited (see [Dotfiles](dotfiles.md)).

## Tool versions

A teeup release sets the version of each tool that comes from mise. The file `share/teeup/tools.lock` records these versions. The tools change only when `teeup update` moves teeup to a release with a different file. If teeup stays on the same release, `teeup update` installs no new tool versions.

When a release changes a version, step 4 installs the new version and changes the link in `~/.local/bin`. The old version stays installed. Run `mise prune` to remove the versions that nothing uses.

Homebrew cannot keep a formula at a fixed version. Thus teeup upgrades the packages that it installed only when the checkout moves to a new commit. On the release channel, this is a new release. On `main`, this is a new commit.

## When something goes wrong

Two problems stop the update at different points:

| Problem | When | What teeup says |
|---|---|---|
| The checkout has uncommitted changes | Before step 1, so no step ran yet. | "... has uncommitted changes, so teeup update will not pull." Commit, stash, or discard the changes, and then run the command again. |
| A migration fails | At step 5, after the pull, the package upgrades, `mise upgrade`, and the pinned tools ran. | "Migration ... failed, so the migrations after it did not run." The configure, theme, and hook steps do not run. Fix the cause, and then run the command again. |

Every other problem is a warning, and the run continues. For example, the computer is offline, the checkout cannot move forward, a formula fails to build, or a `configure` step fails. At the end, teeup prints "teeup is up to date." or "teeup update finished, with the problems above.". If there were problems, the exit status is not zero.

## Release or main

`teeup update` follows releases by default. It moves the checkout to the newest release tag on `main`. teeup never moves the checkout back to an older commit. If the checkout is ahead of the newest release, it stays where it is until there is a newer release.

To follow `main`, run this command:

```sh
teeup update --main
```

The code on `main` is newer than the newest release, and it can be unstable. teeup saves the choice as `TEEUP_UPDATE_CHANNEL` in the answers file, so the next `teeup update` follows `main` too.

If a release is withdrawn, a Mac that already has it stays on it until a newer release exists. A Mac that does not have it never moves to it.

To follow releases again, run `teeup update --release`. This does not move the checkout back. The checkout stays on its commit on `main` until there is a newer release.

Before teeup 0.3.0-beta, every installation followed `main`. If `TEEUP_UPDATE_CHANNEL` has no value and the checkout is on the branch `main`, `teeup update` shows this notice: "teeup now follows releases. To keep following main, run: teeup update --main".

After you select a channel with `--main` or `--release`, the notice stops. If your machine file sets `TEEUP_UPDATE_CHANNEL`, the machine file wins, and teeup shows a warning. You cannot use `--main` or `--release` with a capability name, because `teeup update <capability>` does not move the checkout.

## One capability

```sh
teeup update wezterm
```

If you give a capability name, `teeup update` upgrades the packages and casks for that capability, or runs its own `update` script if it has one. Then it runs the `configure` script and your `post-update` hooks, which get the name of the capability as the first argument. It does not pull the checkout or run the migrations.

The capability must be installed, and if it is not, teeup tells you to run `teeup install`.

## Migrations

A migration is a script in the `migrations/` directory, with the name `migrations/<epoch>.sh`. Each migration runs one time per Mac. The first `./bootstrap` run on a Mac marks all existing migrations as done but does not run them. The new machine already has the state that they produce.

If a migration provides a changed configuration file, it replaces only the copies that you did not edit, and does not change an edited copy.
