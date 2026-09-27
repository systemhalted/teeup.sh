<p align="center">
  <img src="assets/teeup_logo.png" alt="teeup.sh logo" width="520">
</p>

<h1 align="center">
  <img src="assets/teeup_emoji.png" alt="" width="32" height="32">
  teeup.sh
</h1>

<p align="center">
  <strong>Your Mac, ready to code.</strong><br>
  An opinionated, reproducible macOS environment for developers.
</p>

teeup sets up a Mac and manages it afterwards. It installs command-line tools, language runtimes, editors and GUI applications, while keeping its configuration isolated from your own dotfiles.

## Requirements

- **macOS 13 or later**
- No package manager is required beforehand; `bootstrap` installs **Homebrew** automatically. If you use **MacPorts** instead, it must be installed beforehand.
- **bash 3.2** (which ships with macOS) is enough.

## Installation

```bash
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run     # preview everything it would do
./bootstrap               # run it
```

`~/.local/bin` joins your `PATH` automatically, so `teeup` is ready to use in your next terminal session.

## Everyday commands

| Command | What it does |
|---|---|
| `teeup menu` | Every teeup action as a keyboard-driven list. |
| `teeup status` | See what is installed on this Mac. |
| `teeup list` | List every capability teeup knows. |
| `teeup install <name>` | Install one capability and its dependencies. |
| `teeup update` | Update the whole machine, including packages, tools and configurations. |
| `teeup theme set catppuccin` | Switch every app's colours, light and dark. |

## Documentation

The full reference manual is at [https://teeup.systemhalted.in](https://teeup.systemhalted.in). It covers everything from the initial setup to themes, lazy capabilities, keeping the Mac up to date, and migrating from older setups.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a capability, write a theme, or test your changes.

## License

teeup is open source under the MIT License.
