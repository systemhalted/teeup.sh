# Other editors

Emacs is the editor teeup wires into the shell and git (see [Emacs](emacs.md)). Four more are available. Zed comes with the daily tier; the rest are lazy and install when you first reach for them.

| Editor | Tier | How to get it | Capability |
|---|---|---|---|
| Zed | daily | Say yes to the daily set, or `teeup install zed` | `zed` |
| Neovim | lazy | Type `nvim`, or `teeup install neovim` | `neovim` |
| VS Code | lazy | Type `code`, `teeup launch Visual Studio Code`, or `teeup install vscode` | `vscode` |
| Cursor | lazy | Type `cursor`, `teeup launch Cursor`, or `teeup install cursor` | `cursor` |

Zed, VS Code and Cursor are Homebrew casks. On a MacPorts machine teeup cannot install them and points you at the vendor's download page instead.

## Zed

teeup does not ship a `settings.json` for Zed. It edits the one Zed already uses, `~/.config/zed/settings.json`, and sets only the keys for the theme and the font. Everything else in the file is yours. Comments inside the settings object do not survive that edit, so teeup backs up a file that has them first, and it never writes a settings file that is a symlink.

## VS Code

VS Code works the same way. teeup sets the theme, font and theme-extension keys in `~/Library/Application Support/Code/User/settings.json`, and installs the theme's extension with the `code` command the cask provides.

## Neovim

The first install copies the [LazyVim](https://www.lazyvim.org) starter layout into `~/.config/nvim`: `init.lua`, `stylua.toml`, and the files under `lua/config` and `lua/plugins`. Every one of them is yours after that first copy. teeup's own layer, which follows the teeup theme, stays in the checkout.

Neovim downloads its plugins on the first start. Run `nvim`, then `:LazyHealth`. LazyVim needs Neovim 0.11.2 or later, and teeup warns you when the `nvim` on your `PATH` is older.

teeup's shell adds one shortcut for it:

| Command | What it does |
|---|---|
| `n` | Open Neovim on the current directory |
| `n <file>` | Open Neovim on a file |

If you have an `init.vim` next to the new `init.lua`, Neovim ignores it and teeup tells you so; move what you need into `lua/config/options.lua`.

## Cursor

Cursor needs macOS 12 or newer. teeup installs the cask and nothing else: it does not change Cursor's settings or theme. Open it with `teeup launch Cursor`, or run `cursor` in a project directory.

## Theme and font

`teeup theme set` and `teeup install font` reach Zed, VS Code and Neovim when they are installed, and tell a running copy to pick up the change. Cursor is not themed. *Themes* and *Fonts*, in Part 2, cover both commands.

<!-- SCREENSHOT: Zed and VS Code side by side after `teeup theme set`, both showing the same palette. -->
