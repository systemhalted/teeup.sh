# Prompt

teeup uses [Starship](https://starship.rs/) for the shell prompt, which shows the current directory, the git status, the command duration, and other context.

The Starship configuration file is `~/.config/starship.toml`.

## How teeup manages it

When teeup installs Starship, it copies its own `starship.toml` file there one time, and does not change the file after that.
Because of this copy-once rule, `teeup update` never replaces your changes.
To get the newest teeup version back, run `teeup reset starship`, which makes a copy of your file first.

## The theme palette

There are two exceptions to the copy-once rule.
The first is a palette block between these markers:

```toml
# teeup:theme-palette:start
[palettes.teeup-dark]
blue = "#89b4fa"
# ...
# teeup:theme-palette:end
```

The second is the root `palette = ...` setting, which controls the active palette.
Each time you run `teeup theme set`, teeup updates the root `palette` setting and rewrites the lines between the markers, so the prompt uses your theme.

To configure your prompt, change the other settings in the file.
Put your changes outside the markers, and do not change the root `palette` setting.
If you do this, teeup does not replace your settings.
