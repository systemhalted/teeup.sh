# Updates

One command keeps the whole Mac current:

```sh
teeup update
DRY_RUN=true teeup update    # the same, as a preview that changes nothing
```

`teeup update` also repairs. Every step checks before it acts, so running it after a bootstrap that stopped half way finishes the job.

## What runs, in order

| Step | What happens |
|---|---|
| 1. Pull | `git pull --ff-only` in the teeup checkout, which brings in the new version of teeup itself. |
| 2. Packages | Homebrew: `brew update`, `brew upgrade`, `brew upgrade --cask`. MacPorts: `port selfupdate`, `port upgrade outdated`. |
| 3. mise | `mise upgrade` for every tool in your global mise configuration: the language runtimes and the AI tools. |
| 4. Migrations | Any migration script this Mac has not run yet. |
| 5. Configure | `configure` again for every installed capability in the core tier, then the daily tier. |
| 6. Theme | The current theme is rendered again, if step 5 did not already do it. |
| 7. Hooks | Your `post-update` hooks (see [Hooks and extending](hooks-and-extending.md)). |

Migrations run after the upgrades on purpose. A migration adjusts a config file for a new version of a tool, so it has to see the version the upgrade just installed.

Step 5 is what applies a changed answer. If you set a new Emacs flavor with `teeup config set`, `teeup update` picks it up, because Emacs is in the daily tier.

## What it leaves alone

- **Lazy capabilities.** Their `configure` is not re-run, because configuring one can start a virtual machine, as Colima's does. Their packages are still upgraded in step 2, like everything else the package manager holds.
- **Capabilities this Mac never installed**, and ones your machine file lists in `TEEUP_SKIP`. teeup prints a line for each and moves on.
- **Your files.** Configure never overwrites a config file you edited (see [Dotfiles](dotfiles.md)).

## When something goes wrong

Two problems stop the update before it does anything else:

| Problem | What teeup says |
|---|---|
| The checkout has uncommitted changes | "... has uncommitted changes, so teeup update will not pull." Commit, stash or discard them, then run it again. |
| A migration fails | "Migration ... failed, so the migrations after it did not run." Fix the cause and run it again. |

Everything else is a warning, and the run goes on: being offline, a pull that cannot fast-forward, a formula that will not build, one capability's `configure` failing. At the end teeup says either "teeup is up to date." or "teeup update finished, with the problems above.", and the exit status is non-zero in the second case.

## One capability

```sh
teeup update wezterm
```

With a capability name, `teeup update` upgrades that capability's own packages and casks, or runs its own `update` script if it ships one, then runs its `configure` and your `post-update` hooks, which get the capability's name as their first argument. It does not pull the checkout or run migrations. The capability has to be installed; if it is not, teeup tells you to `teeup install` it.

## Migrations

A migration is a script in the checkout's `migrations/` directory, named after the time it was written (`migrations/<epoch>.sh`). Each one runs once per Mac. A fresh `./bootstrap` marks all existing migrations as done without running them, since a new machine already has the state they lead to.

A migration that ships a changed config file replaces only the copies you never edited. An edited copy is left as it is.
