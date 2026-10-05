# Migrating

If the old, single-script teeup configured this Mac, or if chezmoi manages its dotfiles, run `./bootstrap` first.
Then remove the old configuration with one command.
Preview the command before you run it:

```sh
DRY_RUN=true teeup migrate legacy   # read what it would do
teeup migrate legacy
teeup doctor                        # names anything still left over
```

The dry run changes nothing.
It ends with "Dry run finished: nothing was changed."
If the dry run finds a step that a real run will refuse, it tells you.
Read its warnings first.

<!-- SCREENSHOT: `DRY_RUN=true teeup migrate legacy` on a Mac with the old teeup and chezmoi, showing the "[DRY-RUN] Would ..." lines and the two lists of chezmoi files. -->

## What it does, in order

| Step | What happens |
|---|---|
| 1. The old teeup | teeup deletes `~/.teeup.common`, `~/.config/mac-setup`, and the `~/.teeupshrc` and `~/.shellrc.common` symlinks that the old script left. |
| 2. Old shell lines | teeup disables the lines that loaded those files. teeup also disables the Oh My Zsh, Powerlevel10k, and Antigen lines. The zsh layer of teeup and Starship replace these lines. |
| 3. Old runtime managers | teeup disables the SDKMAN, rbenv, and pyenv lines. These lines would put their versions before the versions of mise. |
| 4. chezmoi | teeup moves aside the files that chezmoi manages in your home directory. It asks you first. Then teeup installs its own versions in their place. |

Steps 2 and 3 edit `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, and `~/.profile`.
Before teeup edits a file, it copies the file to `<name>.teeup_backup_<timestamp>`.
A disabled line stays in the file with the `: # Disabled by teeup (...)` prefix, so you can see what changed.
The toolchains in `~/.sdkman`, `~/.rbenv`, and `~/.pyenv` stay on the disk.
teeup gives their names, so you can delete them when a new shell operates correctly.

## The chezmoi step

teeup lists the files that chezmoi manages in two groups.
The first group contains the files that teeup has its own version of.
The second group contains the files that teeup has no version of.
Only the backup copy will keep the files in the second group.
Then teeup asks one time: "Move the files above aside so teeup can take over this home directory?".
The default answer is no.

If you answer yes, teeup moves each file to `<name>.teeup_backup_<timestamp>` in the same directory.
teeup installs its own version again for each capability that is installed on this Mac.
Before the command finishes, `~/.zshrc` and the other shell files are in place again.
The next terminal then has the layer of teeup.
Copy personal data from the backups into your `local.*` files.
Refer to [Dotfiles](dotfiles.md).

If there is no terminal, teeup moves nothing.
teeup shows what a run from a terminal will move.
Then teeup stops.

Last, teeup asks to delete `~/.config/chezmoi`.
This configuration points chezmoi to its source.
This is the only item that the chezmoi step can delete.
The default answer is no.
If you keep it, a later `chezmoi apply` command replaces the files of teeup with the files of chezmoi.

## What it never does

- teeup never deletes the chezmoi source directory or its contents. This checkout can continue to serve other computers.
- teeup never runs `chezmoi purge`. teeup only asks chezmoi what it manages and where its source is.
- teeup never deletes or moves items outside your home directory, or inside a git checkout in your home directory. But teeup does edit your zsh files in the directory that `ZDOTDIR` gives. teeup makes a backup of each file first. teeup does not change a symlinked file.
- teeup never moves your shell files aside if the zsh layer of teeup is not installed. That move would leave you without a `~/.zshrc` file. Instead, teeup tells you this and tells you to run `teeup install zsh` first.

Every step runs to the end, also when an earlier step refused something.
The output names each item that teeup did not change.
Read that output.
Do not rely on the exit status.

A refused deletion or a refused move makes teeup exit with a non-zero status.
But the exit status is still 0 if teeup could not edit a zsh file.
The exit status is also 0 if you answered no to a chezmoi question.
It is also 0 if teeup could not ask a chezmoi question without a terminal.
After the migration, run `teeup doctor` to see the items that are still left.

## After migrating

Open a new terminal.
Run `teeup update` and `teeup doctor`.
`teeup doctor` names each item that is still left, with the command that fixes it.
These items can be:

- an Oh My Zsh directory
- Powerlevel10k files
- a shell file that still loads an old configuration
- chezmoi, if it still points to a source directory
- a `~/.gitconfig.local` file with a `[user]` block that git still reads
