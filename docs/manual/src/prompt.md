# Prompt

teeup uses [Starship](https://starship.rs/) for the shell prompt.
This prompt shows the current directory, the git status, the command duration, and other context.

The Starship configuration file is `~/.config/starship.toml`.

## How teeup manages it

When teeup installs Starship, teeup copies its own `starship.toml` file to this location one time.
After this step, teeup does not change the file again.
Because teeup uses a copy-once rule, the `teeup update` command never replaces your changes.
If you want the newest teeup version, run `teeup reset starship`.
teeup makes a copy of your file first.

## The theme palette

There are two exceptions to the copy-once rule.
The `~/.config/starship.toml` file contains a palette block between these markers:

```toml
# teeup:theme-palette:start
[palettes.teeup-dark]
blue = "#89b4fa"
# ...
# teeup:theme-palette:end
```

Also, the root `palette = ...` setting controls the active palette.
Each time you run `teeup theme set`, teeup updates the root `palette` setting.
teeup also writes the lines between the markers again.
These changes make sure that the prompt uses your current theme.

If you want to configure your prompt, change the other settings in the file.
Put your changes outside the markers.
Do not change the root `palette` setting.
If you obey these rules, teeup does not replace your settings.
