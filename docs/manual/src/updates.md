# Updates

The `teeup update` command updates the Mac:

```sh
teeup update
DRY_RUN=true teeup update    # the same, as a preview that changes nothing
```

The `teeup update` command updates the Mac and configures the installed capabilities. The command does not complete a bootstrap. Run the `./bootstrap` script again to complete a bootstrap (see [Getting started](getting-started.md)).

## Update sequence

| Step | What happens |
|---|---|
| 1. Pull | The `git pull --ff-only` command runs in the teeup checkout. This command downloads the new version of teeup. |
| 2. Packages | Homebrew: The `brew update` command runs. The `brew upgrade` command upgrades only the packages and casks that teeup installed on this Mac. You must upgrade the other Homebrew packages manually. A package that a capability uses belongs to teeup, and teeup upgrades the package even if you installed the package before teeup. We plan to offer a choice (issue #79). MacPorts: The `port selfupdate` command runs, and the `port upgrade` command upgrades the ports that teeup installed. |
| 3. mise | The `mise upgrade` command runs for every tool in the global mise configuration. These tools include the language runtimes and the AI tools. |
| 4. Migrations | If this Mac did not run a migration script before, the script runs. |
| 5. Configure | The `configure` script runs again for every installed capability in the core tier. Then, the script runs for the capabilities in the daily tier. |
| 6. Theme | If step 5 did not render the current theme, the command renders the theme again. |
| 7. Hooks | Your `post-update` hooks run (see [Hooks and extending](hooks-and-extending.md)). |

The migrations run after the upgrades. A migration adjusts a configuration file for a new tool version. The migration must see the newly installed version.

Step 5 applies the changed answers. If you set a new Emacs flavor with the `teeup config set` command, the `teeup update` command applies the flavor. The command applies the flavor because Emacs is in the daily tier.

## What the update does not change

- **Lazy capabilities.** The `configure` step does not run again because the step starts a virtual machine (like Colima). Step 2 upgrades the packages for the lazy capabilities.
- **Capabilities that you did not install on this Mac.** The update does not change these capabilities. The update also does not change the capabilities that your machine file lists in `TEEUP_SKIP`. teeup prints a line for each capability and continues.
- **Your files.** The `configure` step never overwrites a configuration file that you edited (see [Dotfiles](dotfiles.md)).

## If a problem occurs

Two problems stop the update at different points:

| Problem | When | What teeup says |
|---|---|---|
| The checkout has uncommitted changes | The problem occurs before step 1. No step ran yet. | "... has uncommitted changes, so teeup update will not pull." Commit, stash, or discard the changes. Then, run the command again. |
| A migration fails | The problem occurs at step 4. The pull, the package upgrades, and the `mise upgrade` command ran already. | "Migration ... failed, so the migrations after it did not run." The configure, theme, and hook steps do not run. Fix the cause. Then, run the command again. |

Every other problem is a warning. The run continues. For example, the computer is offline, a pull does not fast-forward, a formula fails to build, or a `configure` step fails. At the end, teeup prints "teeup is up to date." or "teeup update finished, with the problems above.". If problems occurred, the exit status is not zero.

## One capability

```sh
teeup update wezterm
```

If you provide a capability name, the `teeup update` command updates the packages and casks for that capability. If the capability has an `update` script, the command runs the script. Then, the command runs the `configure` script and your `post-update` hooks. The hooks get the name of the capability as the first argument. The command does not pull the checkout or run the migrations.

You must install the capability. If you did not install the capability, teeup tells you to run the `teeup install` command.

## Migrations

A migration is a script in the `migrations/` directory. The script has the name `migrations/<epoch>.sh`. Each migration runs one time per Mac. A new `./bootstrap` command marks all existing migrations as done. The command does not run the migrations. The new machine already has the state that the migrations produce.

If a migration provides a changed configuration file, the migration replaces only the copies that you did not edit. The migration does not change an edited copy.
