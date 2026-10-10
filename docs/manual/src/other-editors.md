# Other editors

If Emacs is installed and you do not select a different editor, the shell and git use Emacs (read [Editors](shell-tools.md#editors)). Four more editors are available. They are all lazy, so teeup installs each one the first time you run it.

| Editor | Tier | How to get it | Capability |
|---|---|---|---|
| Zed | lazy | Type `zed`, `teeup launch Zed`, or `teeup install zed` | `zed` |
| Neovim | lazy | Type `nvim`, or `teeup install neovim` | `neovim` |
| VS Code | lazy | Type `code`, `teeup launch Visual Studio Code`, or `teeup install vscode` | `vscode` |
| Cursor | lazy | Type `cursor`, `teeup launch Cursor`, or `teeup install cursor` | `cursor` |

Zed, VS Code and Cursor are Homebrew casks. On a MacPorts machine, teeup cannot install them, so it shows the download page of the vendor.

## Zed

teeup does not supply a `settings.json` file for Zed. Instead, it edits the `~/.config/zed/settings.json` file that Zed uses, and changes only the keys for the theme and the font. The edit removes comments inside the settings object, so if the file has these comments, teeup makes a copy of it first. teeup never writes a settings file that is a symlink.

## VS Code

VS Code works in the same way. teeup sets the theme, the font and the theme-extension keys in `~/Library/Application Support/Code/User/settings.json`, and installs the theme extension with the `code` command that the cask supplies.

## Neovim

The first installation copies the [LazyVim](https://www.lazyvim.org) starter layout into `~/.config/nvim`: `init.lua`, `stylua.toml`, and the files in `lua/config` and `lua/plugins`. teeup does not change these files after the first copy. The teeup layer, which follows the teeup theme, stays in the checkout.

Neovim downloads the plugins on the first start. Run `nvim`, and then `:LazyHealth` inside it. LazyVim needs Neovim 0.11.2 or a newer version, and teeup warns you when the `nvim` on your `PATH` is older.

The teeup shell layer adds one shortcut for Neovim:

| Command | What it does |
|---|---|
| `n` | Open Neovim on the current directory |
| `n <file>` | Open Neovim on a file |

If you have an `init.vim` file next to the new `init.lua` file, Neovim ignores `init.vim`, and teeup tells you this. Move the configuration that you need into `lua/config/options.lua`.

## Cursor

Cursor needs macOS 12 or a newer version. teeup installs only the cask, and does not change the settings or the theme of Cursor. To open it, run `teeup launch Cursor`, or run `cursor` in a project directory.

## Theme and font

`teeup theme set` and `teeup install font` apply to Zed, VS Code and Neovim when they are installed, and tell a running copy to apply the change. teeup does not apply a theme to Cursor. [The teeup command](the-teeup-command.md) shows both commands.

<!-- SCREENSHOT: Zed and VS Code side by side after `teeup theme set`, both showing the same palette. -->
