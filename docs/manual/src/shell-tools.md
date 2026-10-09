# Shell tools

## zsh, without a framework

teeup sets `/bin/zsh` as your login shell and configures it with plain scripts. The layers load in this order:

| File | Owner | What it does |
|---|---|---|
| `~/.zshenv`, `~/.zprofile`, `~/.zshrc` | You | teeup copies these files one time. They load the teeup layer from the checkout. |
| `capabilities/zsh/default/` | teeup | This layer configures `PATH`, the editor, history, completion, aliases, functions, and tools. |
| `~/.config/zsh/local.zsh` | You | This file loads last, so its settings override other settings. Put your aliases, exports, and `PATH` entries here. |

The layer adds [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting), and zsh-completions. It keeps 50,000 lines of shared history and starts mise, Starship, zoxide, and fzf. Starship reads `~/.config/starship.toml`, which teeup copies one time (read [Dotfiles](dotfiles.md)).

## Editors

The teeup shell sets `EDITOR`, `VISUAL`, and `SUDO_EDITOR` to the same editor. Tools such as `teeup config edit`, `crontab -e`, and `git commit` open that editor. Two answers select it:

| Answer | Used | Examples |
|---|---|---|
| `TEEUP_EDITOR` | In a local session | `emacsclient -c`, `zed --wait`, `nvim` |
| `TEEUP_TERMINAL_EDITOR` | Over SSH, and in a local session when `TEEUP_EDITOR` has no value | `emacsclient -t`, `nvim`, `vim` |

The wizard asks for both. To change one, run `teeup config set TEEUP_EDITOR zed --wait`, and then open a new terminal. If the first word is not a command on `PATH`, teeup saves the value and shows a warning.

If neither answer has a value, the shell uses `emacsclient -t` when it finds `emacsclient`, then `nvim`, then `vim`. An `EDITOR` or `VISUAL` value from outside teeup stays as it is. To use a different editor in one shell, set `EDITOR` in `~/.config/zsh/local.zsh`.

teeup does not set `core.editor` for git, so git uses the same editor. To give git a different editor, set `core.editor` in `~/.config/git/local`.

## Commands teeup replaces

teeup replaces `ls` and `cd` with aliases and a function. The [Aliases](#aliases) section shows other shortcuts.

### ls

`eza` replaces `ls`.
- `ls` and `ll` run `eza -lh --group-directories-first --icons=auto`.
- `la` and `lsa` show hidden files.
- `lt` runs `eza --tree --level=2 --long --icons --git` to show a directory tree.

The file and folder icons need a Nerd Font in the terminal. WezTerm includes one, but you must configure Terminal.app manually to use one (read [Terminal](terminal.md)).

If the system does not have `eza`, `ll` runs `ls -lah` and `la` runs `ls -lAh`.

<!-- SCREENSHOT: `ll` in a project directory in WezTerm, showing eza's icons and git status column. -->

### cd

`zd`, a function that wraps `zoxide`, replaces `cd`.

If you give a real directory path, `cd` works like the standard command, and any other input starts a `zoxide` jump. `zoxide` records the directories that you go into with `cd`. For example, `cd proj` jumps to the highest-ranked directory that matches "proj" after you visit that directory.

You can select a directory interactively:
- `zi` opens an interactive picker with `fzf`.

If the system does not have `zoxide`, `cd` runs the standard command.

### How to use the original commands

You can ignore aliases or functions to use the original commands:
- `command ls` ignores the alias and runs the external command.
- `builtin cd` ignores the function and runs the shell builtin.
- `\ls` temporarily ignores the alias.

## Aliases

teeup defines aliases in `~/.local/share/teeup/capabilities/zsh/default/aliases`, and replaces them when you run `teeup update`. It defines an alias only if the tool for that alias is installed. Oh My Zsh `plugins=(...)` lines have no effect with teeup, but teeup already loads `zsh-autosuggestions` and `zsh-syntax-highlighting`.

Type `alias name` (for example, `alias grv`) to view the command of an alias. To change or remove an alias, edit `~/.config/zsh/local.zsh`, which loads after the teeup aliases. In that file, use `unalias name` to remove an alias, or define a new alias to override it.

| Alias | Runs | Needs |
|---|---|---|
| **Listing** | | |
| `ls`, `ll` | `eza -lh --group-directories-first --icons=auto` (runs `ls -lah` if the system does not have `eza`) | eza |
| `la`, `lsa` | `eza -lha --group-directories-first --icons=auto` (runs `ls -lAh` if the system does not have `eza`) | eza |
| `lt` | `eza --tree --level=2 --long --icons --git` | eza |
| **Navigation** | | |
| `..`, `cd..` | `cd ..` | |
| `...` | `cd ../..` | |
| `....` | `cd ../../..` | |
| `cd` | `zd` | zoxide |
| **git** | | |
| `g` | `git` | git |
| `gs` | `git status` | git |
| `ga` | `git add` | git |
| `gcm` | `git commit -m` | git |
| `gcam` | `git commit -a -m` | git |
| `gco` | `git checkout` | git |
| `gd` | `git diff` | git |
| `gl` | `git log --oneline --graph --decorate` (unlike OMZ where `gl` runs `git pull`) | git |
| `gp` | `git push` | git |
| `gpl` | `git pull` | git |
| `grv` | `git remote -v` | git |
| `lg` | `lazygit` | lazygit |
| **Editors** | | |
| `e` | `emacsclient -c` | emacsclient |
| `et` | `emacsclient -t` | emacsclient |
| **macOS** | | |
| `showhidden` | `defaults write com.apple.finder AppleShowAllFiles YES; killall Finder` | macOS |
| `hidehidden` | `defaults write com.apple.finder AppleShowAllFiles NO; killall Finder` | macOS |
| **Other** | | |
| `c`, `cls` | `clear` | |
| `pse` | `ps -ef` | |
| `colima-start` | `colima start` | colima |
| `colima-stop` | `colima stop` | colima |

## Tools installed alongside

teeup installs these tools in addition to the built-in commands, and they do not replace existing commands.

- `rg pattern`: Search file contents with ripgrep.
- `fd name`: Find files by name.
- `bat file`: Read files with syntax highlighting. `man` pages also open in bat.
- fzf: Fuzzy finder. Press Ctrl+R to search the history, Ctrl+T to select a file, or Alt+C to change the directory. These key bindings come from fzf, and teeup only loads them.
- `delta`: The pager for `git diff`, `git log`, and `git show`.
- `lazygit`: Terminal user interface for git.
- `btop`: Process monitor and resource monitor.
- `tldr tar`: Read short help pages that show examples first.
- `jq` and `yq`: Read and edit JSON files and YAML files.
- `dust`: View the disk usage by directory.

The cli-tools capability also installs `tree`, `wget`, `curl`, and `gnupg`, and the git capability installs delta and lazygit.

## Lazygit

Lazygit is a terminal user interface for git. Type `lg` or `lazygit` in a git repository to open Lazygit.

teeup installs Lazygit, but does not supply a custom configuration or theme for it.

### Basic Keybindings

These are the primary keys to start:
- `?`: Open the keybindings menu.
- `h` and `l` (or left arrow and right arrow): Switch panels.
- `j` and `k` (or up arrow and down arrow): Move in a panel.
- `space`: Toggle the file inclusion (stage or unstage).
- `c`: Commit (this opens a prompt for the commit message).
- `p`: Pull.
- `P`: Push.
- `q` or `Esc`: Quit or cancel.

For the full list of shortcuts and documentation, read the [Lazygit documentation](https://github.com/jesseduffield/lazygit/blob/master/docs/keybindings/Keybindings_en.md).

## tmux

teeup installs tmux when you type `tmux`, and copies its configuration file, `~/.config/tmux/tmux.conf`, one time. The configuration sets the prefix to Ctrl+A, enables the mouse, and binds `|` and `-` to split the window. If you already have a `~/.tmux.conf` file, teeup does not change it.
