# Migrating

If this Mac was set up by the old, single-script teeup, or its dotfiles are managed by chezmoi, run `./bootstrap` first, then remove the old setup with one command. Preview it before you run it:

```sh
DRY_RUN=true teeup migrate legacy   # read what it would do
teeup migrate legacy
teeup doctor                        # names anything still left over
```

The dry run changes nothing and ends with "Dry run finished: nothing was changed." If it would refuse something on a real run, it says so, so read its warnings first.

<!-- SCREENSHOT: `DRY_RUN=true teeup migrate legacy` on a Mac with the old teeup and chezmoi, showing the "[DRY-RUN] Would ..." lines and the two lists of chezmoi files. -->

## What it does, in order

| Step | What happens |
|---|---|
| 1. The old teeup | Deletes `~/.teeup.common`, `~/.config/mac-setup`, and the `~/.teeupshrc` and `~/.shellrc.common` symlinks the old script left. |
| 2. Old shell lines | Disables the lines that loaded those files, and the Oh My Zsh, Powerlevel10k and Antigen lines that teeup's zsh layer and Starship replace. |
| 3. Old runtime managers | Disables the SDKMAN, rbenv and pyenv lines that would put their versions ahead of mise's. |
| 4. chezmoi | Moves the files chezmoi manages in your home directory aside, after asking, and installs teeup's own versions in their place. |

Steps 2 and 3 edit `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bashrc`, `~/.bash_profile` and `~/.profile`. A file is copied to `<name>.teeup_backup_<timestamp>` before teeup edits it, and a disabled line stays in the file, prefixed with `: # Disabled by teeup (...)`, so you can see what changed. The toolchains in `~/.sdkman`, `~/.rbenv` and `~/.pyenv` stay on disk; teeup names them so you can delete them once a new shell works.

## The chezmoi step

teeup lists the files chezmoi manages in two groups: the ones teeup ships its own version of, and the ones it does not, which only the backup copy will hold. Then it asks once, "Move the files above aside so teeup can take over this home directory?". The default is no.

When you say yes, each file is moved to `<name>.teeup_backup_<timestamp>` beside where it was, and teeup reinstalls its own version for every capability installed here. `~/.zshrc` and the other shell files are back before the command finishes, so the next terminal has teeup's layer. Copy anything personal out of the backups into your `local.*` files (see [Dotfiles](dotfiles.md)).

Without a terminal, teeup moves nothing: it prints what a run from a terminal would move and stops.

Last, it offers to delete `~/.config/chezmoi`, the config that points chezmoi at its source. That is the only thing the chezmoi step can delete, and the default is no. If you keep it, a later `chezmoi apply` puts chezmoi's files back over teeup's.

## What it never does

- Delete the chezmoi source directory, or anything in it. That checkout may still serve other machines.
- Run `chezmoi purge`. teeup only ever asks chezmoi what it manages and where its source is.
- Delete or move anything outside your home directory, or inside any git checkout in it. (It does edit your zsh files where `ZDOTDIR` puts them, backing each one up first, and it leaves a symlinked one alone.)
- Move your shell files aside when teeup's zsh layer is not installed, which would leave you with no `~/.zshrc`. It says so and tells you to run `teeup install zsh` first.

Every step runs to the end even when an earlier one refused something, and the output names each thing it left alone. Read that output rather than relying on the exit status: a refused deletion or move makes it exit non-zero, but a zsh file it could not edit, or a chezmoi question you answered no to (or that could not be asked without a terminal), still ends with exit status 0. Run `teeup doctor` afterwards to see anything still left over.

## After migrating

Open a new terminal, then run `teeup update` and `teeup doctor`. Doctor names what is still left over, with the command that fixes each one: an Oh My Zsh directory, Powerlevel10k files, a shell file that still loads an old setup, chezmoi still pointing at a source directory, or a `~/.gitconfig.local` whose `[user]` block git still reads.
