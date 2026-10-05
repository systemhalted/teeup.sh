# Welcome to teeup

<p align="center"><img src="images/teeup_logo.png" alt="The teeup.sh logo: a golf ball on a tee over a terminal prompt" width="520"></p>

**Your Mac, ready to code.** teeup is an opinionated, reproducible macOS environment for developers. The `./bootstrap` command installs a set of developer tools. It configures them. It sets one colour [theme](themes.md) and one [font](fonts.md). The `teeup` command manages changes after the installation.

The idea comes from [Omarchy](https://omarchy.org). Omarchy is the environment of DHH for Arch Linux and Hyprland. Omarchy shows that a developer can distribute a personal environment with the defaults, a discovery menu, the lazy installations, and a manual. teeup brings this model to macOS. It runs on macOS only. If you run `./bootstrap` on other systems, the command stops.

## What you get

After you run the command for the first time, you get these items:

- A zsh login shell with the configuration of teeup, the [Starship prompt](prompt.md), and modern tools (ripgrep, fd, fzf, bat, eza, zoxide, and more).
- `git` with your identity, an ed25519 SSH key, and the signed-in GitHub CLI.
- `mise` for the language runtimes, WezTerm as the terminal, and the JetBrainsMono Nerd Font.
- AeroSpace to tile the windows, the Caps Lock key as the Control key, and the macOS preferences for development.
- If you agree to the installation, you receive Emacs.

All other tools wait until you request them. These tools include Zed, Obsidian, Firefox Developer Edition, Neovim, VS Code, Cursor, Docker through Colima, and the AI coding tools. If you type `docker` or `claude` for the first time, the command line asks you to install the tool.

<!-- SCREENSHOT: A WezTerm window on a freshly bootstrapped Mac, showing the Starship prompt and the output of `teeup status`. -->

## How it is built

Each piece of teeup is a *capability*. A capability is a directory with a metadata file, an `install` script, and a `configure` script. For example, `git`, `wezterm`, `emacs`, `keyboard`, and `macos-defaults` are capabilities. The `teeup` command installs, configures, updates, resets, and removes the capabilities one at a time. The `teeup list` command shows every capability.

teeup copies most configuration files once. These files belong to you. teeup keeps its defaults in its checkout directory. Updates improve the defaults, and they do not overwrite your changes. It is safe to run `./bootstrap` again because every step does a check before it runs. A second execution repairs an incomplete first execution.

## Who it is for

teeup is for the users who work in a terminal. It is for the users who want to rebuild a Mac completely in one session. These users prefer to read about a tool before they run it. Every command that modifies the system has a dry run mode. This mode prints the actions, but it does not run them.

teeup is an opinionated configuration. It selects zsh, WezTerm, and `mise` for you. It sets the macOS preferences. If you already keep your dotfiles in `chezmoi` or an older teeup, the `teeup migrate legacy` command removes that configuration. The [Migrating](migrating.md) page explains this procedure.

This manual describes teeup 0.2.0-beta.

## Reading this manual

The pages are short. Each page covers one topic. Part 1, The Basics, helps you convert a new Mac into a functional environment. It contains these pages:

- [Getting started](getting-started.md): This page describes the requirements, the first execution, and the configuration questions.
- [The teeup command](the-teeup-command.md): This page shows every verb in one table.
- [The menu](the-menu.md): This page shows the same actions in one keyboard-driven list.
- [Tiers](tiers.md): This page shows the items that install now, and the items that wait for you.

The later parts describe the applications, the configuration, how to migrate to and from the environment, and how to troubleshoot.
