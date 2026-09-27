# Prompt

teeup uses [Starship](https://starship.rs/) for the shell prompt. It provides a fast, customisable prompt that shows the current directory, git status, command duration, and other context.

Starship's configuration lives at `~/.config/starship.toml`.

## How teeup manages it

When teeup installs Starship, it copies its own `starship.toml` there exactly once. After that, the file is yours. Because of teeup's copy-once rules, `teeup update` will never overwrite your changes. If you want teeup's latest version back, you can run `teeup reset starship` to restore it (your copy will be backed up first).

## The theme palette

There are two exceptions to the copy-once rule. `~/.config/starship.toml` contains a palette block surrounded by markers:

```toml
# teeup:theme-palette:start
[palettes.teeup-dark]
blue = "#89b4fa"
# ...
# teeup:theme-palette:end
```

Additionally, the root `palette = ...` setting determines which palette is active. Every time you run `teeup theme set`, it updates the root `palette` setting and rewrites the lines between the markers. This is how the prompt follows your current theme.

To customise your prompt, change anything else in the file. Keep your changes outside the markers and away from the root `palette` setting, and teeup will leave them alone.
