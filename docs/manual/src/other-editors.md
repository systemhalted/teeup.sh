# Other editors

Emacs is the editor that teeup configures for the shell and git. See [Emacs](emacs.md). Four more editors are available. All four are lazy. When you run these four editors for the first time, teeup installs them.

| Editor | Tier | How to get it | Capability |
|---|---|---|---|
| Zed | lazy | Type `zed`, `teeup launch Zed`, or `teeup install zed` | `zed` |
| Neovim | lazy | Type `nvim`, or `teeup install neovim` | `neovim` |
| VS Code | lazy | Type `code`, `teeup launch Visual Studio Code`, or `teeup install vscode` | `vscode` |
| Cursor | lazy | Type `cursor`, `teeup launch Cursor`, or `teeup install cursor` | `cursor` |

Zed, VS Code and Cursor are Homebrew casks. On a MacPorts machine, teeup cannot install them. teeup shows the download page of the vendor.

## Zed

teeup does not supply a `settings.json` file for Zed. teeup edits the `~/.config/zed/settings.json` file that Zed uses. teeup changes only the keys for the theme and the font, not the rest of the file. The edit removes comments inside the settings object. If the file has these comments, teeup makes a copy of the file before the edit. teeup never writes a settings file that is a symlink.

## VS Code

VS Code operates in the same way. teeup sets the theme, the font and the theme-extension keys in the `~/Library/Application Support/Code/User/settings.json` file. teeup installs the extension of the theme with the `code` command that the cask supplies.

## Neovim

The first installation copies the [LazyVim](https://www.lazyvim.org) starter layout into `~/.config/nvim`. The layout includes `init.lua`, `stylua.toml`, and the files in `lua/config` and `lua/plugins`. teeup does not change these files after the first copy. The layer of teeup follows the teeup theme. This layer stays in the checkout.

Neovim downloads the plugins on the first start. Run `nvim`. Then, run `:LazyHealth`. LazyVim needs Neovim 0.11.2 or a newer version. teeup warns you when the `nvim` program on your `PATH` is older.

The shell layer of teeup adds one shortcut for Neovim.

| Command | What it does |
|---|---|
| `n` | Open Neovim on the current directory |
| `n <file>` | Open Neovim on a file |

If you have an `init.vim` file and the new `init.lua` file, Neovim ignores the `init.vim` file. teeup tells you this. Move the configuration that you need into `lua/config/options.lua`.

## Cursor

Cursor needs macOS 12 or a newer version. teeup installs only the cask. teeup does not change the settings or the theme of Cursor. Run `teeup launch Cursor` to open Cursor. You can also run `cursor` in a project directory.

## Theme and font

The `teeup theme set` and `teeup install font` commands apply to Zed, VS Code and Neovim when they are installed. The commands tell a running copy to apply the change. teeup does not apply a theme to Cursor. [The teeup command](the-teeup-command.md) shows both commands.

<!-- SCREENSHOT: Zed and VS Code side by side after `teeup theme set`, both showing the same palette. -->
