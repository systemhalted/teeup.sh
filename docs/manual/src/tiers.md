# Tiers

Every capability belongs to one of three tiers. The tier decides when teeup installs the capability.

| Tier | Installed | Examples |
|---|---|---|
| core | Always, by `./bootstrap` | zsh, Starship, git, SSH, mise, WezTerm, the Nerd Font, AeroSpace, the theme |
| daily | By `./bootstrap`, if you select the daily set | Emacs |
| lazy | The first time you use the capability, or when you run the command | Zed, Obsidian, Firefox Developer Edition, Neovim, VS Code, Cursor, Chrome, Docker through Colima, tmux, Ollama, Herdr, the AI tools |

To view the full list with the tier of each capability, run `teeup list`. You can also view one tier at a time:

```sh
teeup list --tier lazy
```

<!-- SCREENSHOT: Output of `teeup list --tier lazy`, showing the "[on first: ...]" and "launch: ..." column. -->

## Core

Every terminal session needs the core tier. `capabilities/core.list` sets the sequence. Each entry requires only the capabilities before it. If a core capability fails, `./bootstrap` stops, because the subsequent capabilities depend on the failed capability.

## Daily

The daily tier contains larger applications. The wizard asks: "Install the daily set too (Emacs)?". teeup records the answer as `TEEUP_DAILY`. `./bootstrap --skip-daily` skips the daily tier for one run. If a daily capability fails, teeup prints a warning. The run continues.

`teeup update` configures the core tier and the daily tier again. If you remove a core capability or a daily capability with `teeup remove`, the next `./bootstrap` installs the capability again. If you do not want to install the capability again, add the capability to `TEEUP_SKIP` in your machine file:

```sh
# ~/.config/teeup/machines/<hostname>.conf
TEEUP_SKIP="aerospace"
```

## Lazy

teeup installs a lazy capability when you use the capability. There are three procedures to install a lazy capability.

| You do this | teeup does this |
|---|---|
| Run the command of the capability, for example, `docker`, `nvim`, `tmux` or `claude` | A shim asks to install the capability. Then teeup runs your command. |
| `teeup launch Cursor` | If the application is missing, teeup installs the application. Then teeup opens the application. |
| `teeup install colima` | teeup installs the capability immediately. |

### What a shim does

For every command that a lazy capability provides, teeup writes a shim into `~/.local/state/teeup/shims`. A shim is a small script. That directory is the last entry on your `PATH`. A shim runs only when no other application provides the command.

When you run the command in a terminal for the first time, the shim asks:

```text
docker is provided by capability colima. Install now?
```

The default selection is yes. teeup installs the capability and the requirements of the capability. teeup then runs `docker` with your arguments. On future runs, the system finds the real command first. The shim does not run again. teeup writes the install output to `~/.local/state/teeup/logs/lazy.log`.

<!-- SCREENSHOT: Typing `docker ps` on a fresh Mac, showing the "docker is provided by capability colima. Install now?" prompt in gum. -->

If you answer no, teeup does not install the capability. teeup shows the command for future use:

```text
Not installed. When you want it: teeup install colima
```

If there is no terminal, a shim does not wait for an answer. If a script or an editor runs the shim, the shim prints the `teeup install` command. The shim then exits with status 127.

The AI tools have a second step. The shim for `claude` installs the `ai-claude` capability. When the tool runs for the first time, mise downloads the tool. For more information, see [AI tools](ai-tools.md).

### Lazy capabilities and the rest of teeup

- `teeup update` does not configure lazy capabilities. If you configure a lazy capability, it can start a virtual machine. For example, Colima starts a virtual machine.
- `teeup remove` removes a lazy capability, but it keeps the shim. If you run the command again, the shim offers to install the capability.
- `teeup status` lists the shims under "Lazy shims".
