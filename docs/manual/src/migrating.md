# Migrating

If the old, single-script `teeup` configured this Mac, or if `chezmoi` manages its dotfiles, run `./bootstrap` first.
Then, remove the old configuration with one command.
Before you run the command, read the output of the dry run:

```sh
DRY_RUN=true teeup migrate legacy   # read what it would do
teeup migrate legacy
teeup doctor                        # names anything still left over
```

The dry run changes nothing.
The dry run prints a message when it finishes.
If the command refuses a step on a real run, the output shows a warning.
Read the warnings first.

<!-- SCREENSHOT: `DRY_RUN=true teeup migrate legacy` on a Mac with the old teeup and chezmoi, showing the "[DRY-RUN] Would ..." lines and the two lists of chezmoi files. -->

## What it does, in order

| Step | What happens |
|---|---|
| 1. The old `teeup` | `teeup` deletes `~/.teeup.common`, `~/.config/mac-setup`, and the `~/.teeupshrc` and `~/.shellrc.common` symlinks that the old script installed. |
| 2. Old shell lines | `teeup` disables the lines that load those files. `teeup` disables the Oh My Zsh, Powerlevel10k, and Antigen lines. The zsh layer of `teeup` and Starship replace these lines. |
| 3. Old runtime managers | `teeup` disables the SDKMAN, `rbenv`, and `pyenv` lines. These lines put their versions before the versions of `mise`. |
| 4. `chezmoi` | `teeup` moves the files that `chezmoi` manages in your home directory. It asks you first. Then, `teeup` installs its own versions in their location. |

Steps 2 and 3 edit `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, and `~/.profile`.
Before `teeup` edits the file, it copies the file to `<name>.teeup_backup_<timestamp>`.
A disabled line stays in the file with the `: # Disabled by teeup (...)` prefix to help you see the changes.
The toolchains in `~/.sdkman`, `~/.rbenv`, and `~/.pyenv` stay on the disk.
`teeup` shows their names.
When a new shell operates correctly, delete them.

## The chezmoi step

`teeup` lists the files that `chezmoi` manages in two groups.
The first group contains the files that `teeup` replaces with its own versions.
The second group contains the files that only the backup copy keeps.
Then, `teeup` asks, "Move the files above aside so teeup can take over this home directory?".
The default answer is no.

When you reply yes, `teeup` moves each file to `<name>.teeup_backup_<timestamp>` in the same directory.
`teeup` installs its own version for each capability that you install here.
Before the command finishes, `teeup` restores `~/.zshrc` and the other shell files.
The next terminal has the layer of `teeup`.
Copy personal data from the backups into your `local.*` files.
Refer to [Dotfiles](dotfiles.md).

If you do not have a terminal, `teeup` does not move the files.
`teeup` shows what a run from a terminal moves.
Then, `teeup` stops.

Finally, `teeup` asks to delete `~/.config/chezmoi`.
This configuration points `chezmoi` to its source.
This is the only item that the `chezmoi` step can delete.
The default answer is no.
If you keep it, a later `chezmoi apply` command replaces the files of `teeup` with the files of `chezmoi`.

## What it never does

- `teeup` never deletes the `chezmoi` source directory or its contents. This checkout can continue to serve other computers.
- `teeup` never runs `chezmoi purge`. `teeup` only asks `chezmoi` what it manages and where its source is.
- `teeup` never deletes or moves items outside your home directory or inside a git checkout in your home directory. `teeup` edits your zsh files in the `ZDOTDIR` directory. `teeup` makes a backup of each file first. `teeup` does not change a symlinked file.
- `teeup` never moves your shell files when you do not install the zsh layer of `teeup`. This condition leaves you without a `~/.zshrc` file. `teeup` shows a message. `teeup` tells you to run `teeup install zsh` first.

Every step completes.
A refused change in a prior step does not stop the execution.
The output shows the name of each item that `teeup` did not change.
Read the output.
Do not rely on the exit status.

A refused deletion or a refused move causes a non-zero exit status.
But, an unedited zsh file or a negative answer to a `chezmoi` question causes an exit status of 0.
A `chezmoi` question that `teeup` cannot ask without a terminal also causes an exit status of 0.
After the migration, run `teeup doctor` to see the remaining items.

## After migrating

Open a new terminal.
Run `teeup update` and `teeup doctor`.
The doctor command shows the remaining items and the command to fix each item.
These items include an Oh My Zsh directory or Powerlevel10k files.
They also include a shell file that loads an old configuration.
Other items are `chezmoi` that points to a source directory, or a `~/.gitconfig.local` file with a `[user]` block that `git` reads.
