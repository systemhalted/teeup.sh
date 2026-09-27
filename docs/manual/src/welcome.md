# Welcome to teeup

teeup treats your Mac the way a Linux distribution treats a computer. One command, `./bootstrap`, installs a considered set of developer tools, writes their configuration, gives them one colour [theme](themes.md) and one [font](fonts.md), and leaves you with a single command, `teeup`, for everything you want to change afterwards.

The idea comes from [Omarchy](https://omarchy.org), DHH's opinionated setup for Arch Linux and Hyprland. Omarchy showed that a personal setup can be packaged like a product: sensible defaults, a menu for discovering what is there, lazy installs for the things you use once a month, and a manual. teeup brings that shape to macOS. It runs on macOS only; `./bootstrap` stops on any other system.

## What you get

After the first run you have:

- a zsh login shell with teeup's own configuration, the [Starship prompt](prompt.md), and a modern command-line set (ripgrep, fd, fzf, bat, eza, zoxide and more);
- git with your identity, an ed25519 SSH key, and the GitHub CLI signed in;
- mise for language runtimes, WezTerm as the terminal, the JetBrainsMono Nerd Font, AeroSpace for tiling windows, Caps Lock as Control, and a set of macOS preferences for development;
- if you say yes to it, Emacs, Zed, Firefox Developer Edition and Obsidian.

Everything else, such as Neovim, VS Code, Cursor, Docker through Colima, and the AI coding tools, waits until you ask for it. Typing `docker` or `claude` for the first time offers to install it.

<!-- SCREENSHOT: A WezTerm window on a freshly bootstrapped Mac, showing the Starship prompt and the output of `teeup status`. -->

## How it is built

Each piece of teeup is a *capability*: a directory with a short metadata file and an `install` and `configure` script. `git`, `wezterm` and `emacs` are capabilities; so are `keyboard` and `macos-defaults`. The `teeup` command installs, configures, updates, resets and removes them one at a time, and `teeup list` shows every one of them.

Most configuration files are copied into place once and are yours from then on. teeup keeps its own defaults in its checkout, so an update can improve them without overwriting what you changed. Running `./bootstrap` again is safe: every step checks before it acts, which also makes a second run the way to repair a first run that stopped half way.

## Who it is for

teeup suits you if you work in a terminal, want a Mac you can rebuild from scratch in one sitting, and would rather read what a tool will do before it does it. Every command that changes the machine has a dry run that prints the commands instead of running them.

It is an opinionated setup. It picks zsh, WezTerm and mise for you, and it sets macOS preferences. If you already keep your dotfiles in chezmoi or an older teeup, `teeup migrate legacy` retires that wiring; [Migrating](migrating.md) covers it.

This manual describes teeup 0.1.0-beta.

## Reading this manual

The pages are short and each covers one topic. Part 1, The Basics, gets you from a new Mac to a working setup:

- [Getting started](getting-started.md): requirements, the first run, and the setup questions.
- [The teeup command](the-teeup-command.md): every verb in one table.
- [The menu](the-menu.md): the same actions behind one keyboard-driven list.
- [Tiers](tiers.md): what installs now, and what waits for you.

The later parts cover the applications, configuration, moving in and out, and troubleshooting.
