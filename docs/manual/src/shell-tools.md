# Shell tools

## zsh, without a framework

teeup makes `/bin/zsh` your login shell and configures it with plain scripts, not Oh My Zsh or another framework. The layers load in this order:

| File | Owner | What it does |
|---|---|---|
| `~/.zshenv`, `~/.zprofile`, `~/.zshrc` | You | Thin files, copied once, that load teeup's layer from the checkout. |
| `capabilities/zsh/default/` | teeup | `PATH`, the editor, history, completion, aliases, functions and tool setup. |
| `~/.config/zsh/local.zsh` | You | Loaded last, so anything here wins. Your aliases, exports and `PATH` entries go here. |

The layer adds [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) and zsh-completions, keeps 50,000 lines of shared history, and starts mise, Starship, zoxide and fzf. Starship reads `~/.config/starship.toml`, which teeup copies once (see [Dotfiles](dotfiles.md)).

## The tools

| Tool | Command | What it is for |
|---|---|---|
| ripgrep | `rg` | Search file contents, fast. |
| fd | `fd` | Find files by name. |
| fzf | `fzf` | Fuzzy finder. Ctrl+R searches history, Ctrl+T picks a file. |
| bat | `bat` | `cat` with syntax highlighting. It is also the man page viewer. |
| eza | `eza` | `ls` with colours, git status and icons. |
| zoxide | `z` | Jump to directories you visit often. |
| delta | `delta` | The pager for `git diff`, `git log` and `git show`. |
| lazygit | `lazygit` | A terminal UI for git. |
| btop | `btop` | A process and resource monitor. |
| tldr | `tldr` | Short, example-first help pages. |
| jq, yq | `jq`, `yq` | Read and edit JSON and YAML. |
| dust | `dust` | Disk usage by directory. |

The same capability also installs `tree`, `wget`, `curl` and `gnupg`. fzf's key bindings come from fzf itself; teeup only loads them.

## Aliases

| Alias | Runs |
|---|---|
| `ls`, `ll` | `eza -lh --group-directories-first --icons=auto` |
| `la`, `lsa` | the same, with hidden files (`eza -lha ...`) |
| `lt` | `eza --tree --level=2 --long --icons --git` |
| `cd` | `zd`: a real directory is a plain `cd`; anything else is a zoxide jump |
| `..`, `...`, `....` | Up one, two or three directories |
| `c`, `cls` | `clear` |
| `g`, `gs`, `ga`, `gd`, `gp`, `gpl` | `git`, `git status`, `git add`, `git diff`, `git push`, `git pull` |
| `gcm`, `gcam`, `gco` | `git commit -m`, `git commit -a -m`, `git checkout` |
| `gl` | `git log --oneline --graph --decorate` |
| `lg` | `lazygit` |
| `e`, `et` | `emacsclient -c`, `emacsclient -t` |
| `showhidden`, `hidehidden` | Show or hide dotfiles in Finder |

Each alias is only defined when its tool is installed. Without eza, `ll` and `la` fall back to plain `ls`.

The file and folder icons in `ls` need a Nerd Font in the terminal. WezTerm has one; Terminal.app needs it set by hand (see [Terminal](terminal.md)).

<!-- SCREENSHOT: `ll` in a project directory in WezTerm, showing eza's icons and git status column. -->

## tmux

tmux is lazy: type `tmux` and teeup offers to install it. Its configuration, `~/.config/tmux/tmux.conf`, is copied once and is yours. It sets the prefix to Ctrl+A, turns the mouse on, and binds `|` and `-` to split. If you already have a `~/.tmux.conf`, teeup leaves it alone and does not add its own.
