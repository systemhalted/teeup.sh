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
| 2. Packages | Homebrew: `brew update` runs, and then `brew upgrade` upgrades only the packages and casks that teeup installed for the capabilities on this Mac. teeup does not upgrade other Homebrew packages: use `brew upgrade` for them. A package that a capability uses belongs to teeup, so teeup upgrades it even if you installed it before teeup. A future version will let you choose (issue #79). MacPorts: `port selfupdate` runs, and then `port upgrade` upgrades the ports that teeup installed. |
| 3. mise | `mise upgrade` runs for every tool in the global mise configuration, which includes the language runtimes and the AI tools. |
| 4. Migrations | teeup runs every migration script that this Mac did not run yet. |
| 5. Configure | The `configure` script runs again for every installed capability in the core tier, and then in the daily tier. |
| 6. Theme | If step 5 did not render the current theme, teeup renders it again. |
| 7. Hooks | Your `post-update` hooks run (see [Hooks and extending](hooks-and-extending.md)). |

The migrations run after the upgrades, because a migration adjusts a configuration file for a new tool version and must see the newly installed version.

Step 5 applies the changed answers. If you set a new Emacs flavor with `teeup config set`, `teeup update` applies it because Emacs is in the daily tier.

## What it leaves alone

- **Lazy capabilities.** Their `configure` step does not run again, because it can start a virtual machine (for example, Colima). Step 2 upgrades their packages.
- **Capabilities that you did not install on this Mac.** The update does not change these capabilities, or the capabilities that your machine file lists in `TEEUP_SKIP`. teeup prints a line for each one and continues.
- **Your files.** The `configure` step never overwrites a configuration file that you edited (see [Dotfiles](dotfiles.md)).

## When something goes wrong

Two problems stop the update at different points:

| Problem | When | What teeup says |
|---|---|---|
| The checkout has uncommitted changes | Before step 1, so no step ran yet. | "... has uncommitted changes, so teeup update will not pull." Commit, stash, or discard the changes, and then run the command again. |
| A migration fails | At step 4, after the pull, the package upgrades, and `mise upgrade` ran. | "Migration ... failed, so the migrations after it did not run." The configure, theme, and hook steps do not run. Fix the cause, and then run the command again. |

Every other problem is a warning, and the run continues. For example, the computer is offline, the checkout cannot move forward, a formula fails to build, or a `configure` step fails. At the end, teeup prints "teeup is up to date." or "teeup update finished, with the problems above.". If there were problems, the exit status is not zero.

## Release or main

`teeup update` follows releases by default. It moves the checkout to the newest release tag on `main`. teeup never moves the checkout back to an older commit. If the checkout is ahead of the newest release, it stays where it is until there is a newer release.

To follow `main`, run this command:

```sh
teeup update --main
```

The code on `main` is newer than the newest release, and it can be unstable. teeup saves the choice as `TEEUP_UPDATE_CHANNEL` in the answers file, so the next `teeup update` follows `main` too.

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
