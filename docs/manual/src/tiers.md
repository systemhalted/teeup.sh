# Tiers

Every capability belongs to one of three tiers, and the tier decides when teeup installs it.

| Tier | Installed | Examples |
|---|---|---|
| core | Always, by `./bootstrap` | zsh, Starship, git, SSH, mise, WezTerm, the Nerd Font, AeroSpace, the theme |
| daily | By `./bootstrap`, if you answer yes to the daily set | Emacs |
| lazy | The first time you use the capability, or when you ask for it | Zed, Obsidian, Firefox Developer Edition, Neovim, VS Code, Cursor, Chrome, Docker through Colima, tmux, Ollama, Herdr, the AI tools |

To see the full list with the tier of each capability, run `teeup list`, or see one tier at a time:

```sh
teeup list --tier lazy
```

<!-- SCREENSHOT: Output of `teeup list --tier lazy`, showing the "[on first: ...]" and "launch: ..." column. -->

## Core

Every terminal session needs the core tier. `capabilities/core.list` sets the sequence, and each entry needs only the entries that come before it. If a core capability fails, `./bootstrap` stops, because the entries after it depend on it.

## Daily

The daily tier contains larger applications. The wizard asks "Install the daily set too (Emacs)?" and records the answer as `TEEUP_DAILY`. `./bootstrap --skip-daily` skips the daily tier for one run. If a daily capability fails, teeup prints a warning and the run continues.

`teeup update` configures the core and daily tiers again. If you remove a core or daily capability with `teeup remove`, the next `./bootstrap` installs it again. To stop this, add the capability to `TEEUP_SKIP` in your machine file:

```sh
# ~/.config/teeup/machines/<hostname>.conf
TEEUP_SKIP="aerospace"
```

## Lazy

teeup installs a lazy capability when you use it, in one of three ways.

| You do this | teeup does this |
|---|---|
| Run the command of the capability, for example, `docker`, `nvim`, `tmux` or `claude` | A shim asks to install the capability, and then teeup runs your command. |
| `teeup launch Cursor` | teeup installs the application if it is missing, and then opens it. |
| `teeup install colima` | teeup installs the capability immediately. |

### What a shim does

For every command that a lazy capability provides, teeup writes a small script, a *shim*, into `~/.local/state/teeup/shims`. That directory is the last entry on your `PATH`, so a shim runs only when no other program on the machine provides the command.

When you run the command in a terminal for the first time, the shim asks:

```text
docker is provided by capability colima. Install now?
```

The default selection is yes. teeup installs the capability and its requirements, and then runs `docker` with your arguments. On future runs, your shell finds the real command first, so the shim does not run again. teeup writes the install output to `~/.local/state/teeup/logs/lazy.log`.

<!-- SCREENSHOT: Typing `docker ps` on a fresh Mac, showing the "docker is provided by capability colima. Install now?" prompt in gum. -->

If you answer no, teeup does not install the capability, but shows the command for future use:

```text
Not installed. When you want it: teeup install colima
```

If there is no terminal, a shim does not wait for an answer. If a script or an editor runs the shim, it prints the `teeup install` command and exits with status 127.

The AI tools have a second step. The shim for `claude` installs the `ai-claude` capability, and mise downloads the tool when it runs for the first time. For more information, see [AI tools](ai-tools.md).

### Lazy capabilities and the rest of teeup

- `teeup update` does not configure lazy capabilities, because the configuration of a lazy capability can start a virtual machine, as Colima does.
- `teeup remove` removes a lazy capability but keeps its shim, so if you run the command again, the shim offers to install the capability.
- `teeup status` lists the shims under "Lazy shims".
