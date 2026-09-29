# Welcome to teeup

<p align="center"><img src="images/teeup_logo.png" alt="The teeup.sh logo: a golf ball on a tee over a terminal prompt" width="520"></p>

**Your Mac, ready to code.** teeup is an opinionated, reproducible macOS environment for developers. The `./bootstrap` command installs a set of developer tools, configures them, and sets one colour [theme](themes.md) and one [font](fonts.md). The `teeup` command manages changes after installation.

The idea comes from [Omarchy](https://omarchy.org), DHH's setup for Arch Linux and Hyprland. Omarchy demonstrated that a personal setup can be distributed with defaults, a discovery menu, lazy installs, and a manual. teeup brings this model to macOS. It runs on macOS only; `./bootstrap` exits on other systems.

## What you get

After the first run you have:

- a zsh login shell with teeup's own configuration, the [Starship prompt](prompt.md), and a modern command-line set (ripgrep, fd, fzf, bat, eza, zoxide and more);
- git with your identity, an ed25519 SSH key, and the GitHub CLI signed in;
- mise for language runtimes, WezTerm as the terminal, the JetBrainsMono Nerd Font, AeroSpace for tiling windows, Caps Lock as Control, and a set of macOS preferences for development;
- if you say yes to it, Emacs, Zed, Firefox Developer Edition and Obsidian.

Everything else, such as Neovim, VS Code, Cursor, Docker through Colima, and the AI coding tools, waits until you ask for it. Typing `docker` or `claude` for the first time offers to install it.

<!-- SCREENSHOT: A WezTerm window on a freshly bootstrapped Mac, showing the Starship prompt and the output of `teeup status`. -->

## How it is built

Each piece of teeup is a *capability*: a directory with a metadata file, an `install` script, and a `configure` script. `git`, `wezterm`, and `emacs` are capabilities; so are `keyboard` and `macos-defaults`. The `teeup` command installs, configures, updates, resets, and removes them one at a time. `teeup list` shows every capability.

Most configuration files are copied once and remain yours. teeup keeps its defaults in its checkout. Updates improve defaults without overwriting your changes. Running `./bootstrap` again is safe. Every step checks before acting. A second run repairs a partial first run.

## Who it is for

teeup is for users who work in a terminal, want to rebuild a Mac from scratch in one sitting, and prefer reading what a tool does before running it. Every modifying command has a dry run that prints the actions instead of running them.

It is an opinionated setup. It picks zsh, WezTerm and mise for you, and it sets macOS preferences. If you already keep your dotfiles in chezmoi or an older teeup, `teeup migrate legacy` retires that wiring; [Migrating](migrating.md) covers it.

This manual describes teeup 0.1.0-beta.

## Reading this manual

The pages are short and each covers one topic. Part 1, The Basics, gets you from a new Mac to a working setup:

- [Getting started](getting-started.md): requirements, the first run, and the setup questions.
- [The teeup command](the-teeup-command.md): every verb in one table.
- [The menu](the-menu.md): the same actions behind one keyboard-driven list.
- [Tiers](tiers.md): what installs now, and what waits for you.

The later parts cover the applications, configuration, moving in and out, and troubleshooting.
