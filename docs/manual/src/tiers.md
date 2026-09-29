# Tiers

Every capability belongs to one of three tiers. The tier decides when it gets installed.

| Tier | Installed | Examples |
|---|---|---|
| core | Always, by `./bootstrap` | zsh, Starship, git, SSH, mise, WezTerm, the Nerd Font, AeroSpace, the theme |
| daily | By `./bootstrap`, if you said yes to the daily set | Emacs |
| lazy | The first time you use it, or when you ask | Zed, Obsidian, Firefox Developer Edition, Neovim, VS Code, Cursor, Chrome, Docker through Colima, tmux, Ollama, Herdr, the AI tools |

See the full list, with each capability's tier, with `teeup list`, or one tier at a time:

```sh
teeup list --tier lazy
```

<!-- SCREENSHOT: Output of `teeup list --tier lazy`, showing the "[on first: ...]" and "launch: ..." column. -->

## Core

The core tier is what every terminal session needs. `capabilities/core.list` fixes the order, and each entry only needs what comes before it. A core capability that fails stops `./bootstrap`, because what follows depends on it.

## Daily

The daily tier holds larger applications. The wizard asks, "Install the daily set too (Emacs)?". It records the answer as `TEEUP_DAILY`. `./bootstrap --skip-daily` skips the tier for one run. If a daily capability fails, it prints a warning and the run continues.

`teeup update` configures the core and daily tiers again. If you remove a core or daily capability with `teeup remove`, the next `./bootstrap` installs it again, unless your machine file lists it in `TEEUP_SKIP`:

```sh
# ~/.config/teeup/machines/<hostname>.conf
TEEUP_SKIP="aerospace"
```

## Lazy

A lazy capability installs when you use it. There are three ways to install one.

| You do this | teeup does this |
|---|---|
| Type its command, such as `docker`, `nvim`, `tmux` or `claude` | A shim asks whether to install it, then runs your command. |
| `teeup launch Cursor` | Installs the app if it is missing, then opens it. |
| `teeup install colima` | Installs it straight away. |

### What a shim does

For every command a lazy capability provides, teeup writes a small script, a *shim*, into `~/.local/state/teeup/shims`. That directory is the last entry on your `PATH`, so a shim only runs when nothing else on the machine provides the command.

The first time you type the command at a terminal, the shim asks:

```text
docker is provided by capability colima. Install now?
```

The default answer is yes. teeup installs the capability and its requirements. It then runs `docker` with your arguments. The real command is found first on future runs. The shim does not run again. The install output is written to `~/.local/state/teeup/logs/lazy.log`.

<!-- SCREENSHOT: Typing `docker ps` on a fresh Mac, showing the "docker is provided by capability colima. Install now?" prompt in gum. -->

If you say no, nothing is installed and teeup tells you the command for later:

```text
Not installed. When you want it: teeup install colima
```

A shim does not wait for an answer without a terminal. Called from a script or an editor, it prints the `teeup install` command and exits with status 127.

The AI tools add a second step. The shim for `claude` installs the `ai-claude` capability; the tool itself is then downloaded through mise the first time it runs. [AI tools](ai-tools.md) covers them.

### Lazy capabilities and the rest of teeup

- `teeup update` leaves lazy capabilities alone. Configuring one can start a virtual machine, as Colima does.
- `teeup remove` of a lazy capability keeps its shim, so typing the command offers to install it again.
- `teeup status` lists the shims under "Lazy shims".
