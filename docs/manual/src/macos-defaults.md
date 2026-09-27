# macOS defaults

Two core capabilities change macOS: `macos-defaults` sets a list of preferences for development, and `keyboard` turns Caps Lock into Control. Both can be undone with `teeup remove`.

## The preferences

| Area | Setting | Value |
|---|---|---|
| Finder | Show every file extension | on |
| Finder | Show hidden files | on |
| Finder | Path bar | on |
| Finder | Default view | list |
| Finder | Warn when changing an extension | off |
| Dialogs | Save and Print panels | expanded |
| Keyboard | Key repeat rate | fastest (`KeyRepeat` 2) |
| Keyboard | Delay until repeat | shortest (`InitialKeyRepeat` 15) |
| Typing | Smart quotes, smart dashes | off |
| Typing | Automatic capitalisation, spelling correction | off |
| Dock | Automatically hide | on |
| Trackpad | Tap to click | on, for the built-in trackpad |
| Screenshots | Save location | `~/Screenshots`, created if missing |

teeup restarts Finder and the Dock when it changed one of their settings. The two key-repeat settings take effect after you log out and back in.

Running `teeup configure macos-defaults` again changes nothing that already has the right value, and restarts nothing.

## Putting them back

The first time teeup writes a preference, it records the value it replaced. `teeup remove macos-defaults` writes each recorded value back, or deletes the setting if it did not exist before, then restarts Finder and the Dock. `~/Screenshots` stays, with whatever is in it.

If a preference cannot be restored, teeup names it and keeps `macos-defaults` marked installed, so you can fix the cause and run the removal again.

Because `macos-defaults` is in the core tier, the next `./bootstrap` sets the preferences again. To keep them off on one Mac, add it to `TEEUP_SKIP` in the machine file (see [Answers and machines](answers-and-machines.md)).

## Caps Lock as Control

The `keyboard` capability maps Caps Lock to Control with macOS's own `hidutil`. It maps it directly without an extra app or kernel extension.

| Piece | What it does |
|---|---|
| `hidutil property --set ...` | Applies the mapping now |
| LaunchAgent `sh.teeup.keyboard` | Applies it again at every login |

To undo it:

```sh
teeup remove keyboard
```

That unloads the LaunchAgent and clears the mapping at once, and Caps Lock is Caps Lock again.

## Changing a preference yourself

Change it in System Settings as usual. teeup writes a preference when `macos-defaults` is configured, which happens at bootstrap and on each `teeup update`, and it only records the value it replaced the first time. A value you change by hand resets on the next update. If you want to keep your own values, skip the capability as above, or remove it.
