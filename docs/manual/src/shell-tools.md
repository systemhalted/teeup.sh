# Shell tools

## zsh, without a framework

teeup makes `/bin/zsh` your login shell and configures it with plain scripts. The layers load in this order:

| File | Owner | What it does |
|---|---|---|
| `~/.zshenv`, `~/.zprofile`, `~/.zshrc` | You | Copied once. Load teeup's layer from the checkout. |
| `capabilities/zsh/default/` | teeup | `PATH`, the editor, history, completion, aliases, functions and tool setup. |
| `~/.config/zsh/local.zsh` | You | Loaded last, so anything here wins. Your aliases, exports and `PATH` entries go here. |

The layer adds [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) and zsh-completions, keeps 50,000 lines of shared history, and starts mise, Starship, zoxide and fzf. Starship reads `~/.config/starship.toml`, which teeup copies once (see [Dotfiles](dotfiles.md)).

## Commands teeup replaces

teeup replaces `ls` and `cd` with aliases and a function, and adds short aliases for git and a few other commands. Each one is only defined when its tool is installed.

### ls

The `ls` command is replaced by `eza`.
- `ls` and `ll` run `eza -lh --group-directories-first --icons=auto`.
- `la` and `lsa` add hidden files.
- `lt` runs `eza --tree --level=2 --long --icons --git` to show a directory tree.

The file and folder icons need a Nerd Font in the terminal. WezTerm has one; Terminal.app needs it set by hand (see [Terminal](terminal.md)).

If `eza` is not installed, `ll` and `la` fall back to plain `ls -lah` and `ls -lAh`.

<!-- SCREENSHOT: `ll` in a project directory in WezTerm, showing eza's icons and git status column. -->

### cd

The `cd` command is replaced by `zd`, a function that wraps `zoxide`.

A real directory path behaves like plain `cd`. Anything else is a `zoxide` jump. `zoxide` learns the directories you `cd` into. For example, `cd proj` jumps to the highest-ranked directory matching "proj" after you have visited it.

You can pick a directory interactively:
- `zi` opens an interactive picker using `fzf`.

If `zoxide` is not installed, `cd` remains the standard command.

### git, emacs, and macOS tools

- `g`, `gs`, `ga`, `gd`, `gp`, `gpl` run `git`, `git status`, `git add`, `git diff`, `git push`, `git pull`.
- `gcm`, `gcam`, `gco`, `gl` run `git commit -m`, `git commit -a -m`, `git checkout`, `git log --oneline --graph --decorate`.
- `lg` runs `lazygit`, if installed.
- `e` and `et` run `emacsclient -c` and `emacsclient -t`, if installed.
- `showhidden` and `hidehidden` show or hide dotfiles in macOS Finder.
- `..`, `...`, `....` go up one, two, or three directories.
- `c` and `cls` run `clear`.

### How to use the original commands

You can bypass aliases or functions to use the original commands:
- `command ls` ignores the alias and runs the external command.
- `builtin cd` ignores the function and runs the shell builtin.
- `\ls` temporarily escapes the alias.

### Changing or dropping replacements

To change or drop a replacement, edit `~/.config/zsh/local.zsh`. This file loads after teeup's aliases. Use `unalias` to drop an alias, or define a new one to override it:

```zsh
unalias ls
alias ll='ls -al'
```

## Tools installed alongside

These tools are installed alongside the built-ins and do not replace existing commands.

- `rg pattern`: Search file contents with ripgrep.
- `fd name`: Find files by name.
- `bat file`: Read files with syntax highlighting. `man` pages also open in bat.
- fzf: Fuzzy finder. Press Ctrl+R to search history, Ctrl+T to pick a file, or Alt+C to change directory. The key bindings come from fzf itself; teeup only loads them.
- `delta`: The pager for `git diff`, `git log` and `git show`.
- `lazygit`: Terminal UI for git.
- `btop`: Process and resource monitor.
- `tldr tar`: Read short, example-first help pages.
- `jq` and `yq`: Read and edit JSON and YAML.
- `dust`: View disk usage by directory.

The cli-tools capability also installs `tree`, `wget`, `curl` and `gnupg`. delta and lazygit come with the git capability.

## tmux

tmux installs when you type `tmux`. Its configuration, `~/.config/tmux/tmux.conf`, is copied once. It sets the prefix to Ctrl+A, turns the mouse on, and binds `|` and `-` to split. If you already have a `~/.tmux.conf`, teeup leaves it alone.
