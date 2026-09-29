# Updates

The `teeup update` command keeps the Mac current:

```sh
teeup update
DRY_RUN=true teeup update    # the same, as a preview that changes nothing
```

`teeup update` refreshes a Mac. It configures installed capabilities. It does not finish an incomplete bootstrap; run `./bootstrap` again for that (see [Getting started](getting-started.md)).

## What runs, in order

| Step | What happens |
|---|---|
| 1. Pull | `git pull --ff-only` in the teeup checkout, which brings in the new version of teeup itself. |
| 2. Packages | Homebrew: `brew update`, then `brew upgrade` only for the packages and casks teeup installed for the capabilities on this Mac. Other Homebrew packages are left to you (`brew upgrade`). A package a capability uses counts as teeup's even if you installed it before teeup, so it is upgraded too (letting you choose is planned: issue #79). MacPorts: `port selfupdate`, then `port upgrade` for the ports teeup installed. |
| 3. mise | `mise upgrade` for every tool in your global mise configuration: the language runtimes and the AI tools. |
| 4. Migrations | Any migration script this Mac has not run yet. |
| 5. Configure | `configure` again for every installed capability in the core tier, then the daily tier. |
| 6. Theme | The current theme is rendered again, if step 5 did not already do it. |
| 7. Hooks | Your `post-update` hooks (see [Hooks and extending](hooks-and-extending.md)). |

Migrations run after upgrades. A migration adjusts a config file for a new tool version. It must see the newly installed version.

Step 5 applies changed answers. If you set a new Emacs flavor with `teeup config set`, `teeup update` applies it because Emacs is in the daily tier.

## What it leaves alone

- **Lazy capabilities.** Their `configure` step does not re-run, as configuring one can start a virtual machine (like Colima). Their packages are upgraded in step 2.
- **Capabilities this Mac never installed**, and ones your machine file lists in `TEEUP_SKIP`. teeup prints a line for each and moves on.
- **Your files.** Configure never overwrites a config file you edited (see [Dotfiles](dotfiles.md)).

## When something goes wrong

Two problems stop the update, at different points:

| Problem | When | What teeup says |
|---|---|---|
| The checkout has uncommitted changes | Before step 1, so nothing has run yet | "... has uncommitted changes, so teeup update will not pull." Commit, stash or discard them, then run it again. |
| A migration fails | At step 4, after the pull, the package upgrades and `mise upgrade` have already run | "Migration ... failed, so the migrations after it did not run." The configure, theme and hook steps do not run. Fix the cause and run it again. |

Everything else is a warning, and the run continues. Examples include being offline, a pull that cannot fast-forward, a formula that fails to build, or a failed `configure` step. At the end, teeup prints "teeup is up to date." or "teeup update finished, with the problems above.". The exit status is non-zero if there were problems.

## One capability

```sh
teeup update wezterm
```

With a capability name, `teeup update` upgrades that capability's own packages and casks, or runs its own `update` script if it ships one, then runs its `configure` and your `post-update` hooks, which get the capability's name as their first argument. It does not pull the checkout or run migrations. The capability has to be installed; if it is not, teeup tells you to `teeup install` it.

## Migrations

A migration is a script in the `migrations/` directory, named `migrations/<epoch>.sh`. Each runs once per Mac. A fresh `./bootstrap` marks all existing migrations as done without running them. The new machine already has the state they produce.

A migration that ships a changed config file replaces only the copies you never edited. An edited copy is left as it is.
