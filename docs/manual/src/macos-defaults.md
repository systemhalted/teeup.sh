# macOS defaults

Two core capabilities change macOS: `macos-defaults` configures a list of preferences for development, and `keyboard` changes Caps Lock to Control.
You can undo the changes of each capability with `teeup remove`.

## The preferences

| Area | Setting | Value |
|---|---|---|
| Finder | Show every file extension | on |
| Finder | Show hidden files | on |
| Finder | Path bar | on |
| Finder | Default view | list |
| Finder | Warn when you change an extension | off |
| Dialogs | Save and Print panels | expanded |
| Keyboard | Key repeat rate | fastest (`KeyRepeat` 2) |
| Keyboard | Delay until repeat | shortest (`InitialKeyRepeat` 15) |
| Typing | Smart quotes, smart dashes | off |
| Typing | Automatic capitalisation, spelling correction | off |
| Dock | Automatically hide | on |
| Trackpad | Tap to click | on for the built-in trackpad |
| Screenshots | Save location | `~/Screenshots`. teeup creates this directory if it is missing |

teeup restarts Finder, the Dock or SystemUIServer only when it changed one of the settings of that application.
The two key-repeat settings apply only after you log out and log in again.

If you run `teeup configure macos-defaults` again, it does not change a value that is already correct, and if no value changes, it restarts nothing.

## Putting them back

When teeup writes a preference for the first time, it records the previous value.
`teeup remove macos-defaults` restores each recorded value, or deletes the setting if it did not exist before, and then restarts Finder, the Dock and SystemUIServer.
The `~/Screenshots` directory and its contents stay on your Mac.

If teeup cannot restore a preference, it shows the name of the preference and keeps `macos-defaults` marked as installed.
You can then correct the cause and run the removal command again.

Because the capability is in the core tier, the next `./bootstrap` configures the preferences again.
To keep the preferences off on one Mac, add the capability to `TEEUP_SKIP` in the machine file (read [Answers and machines](answers-and-machines.md)).

## Caps Lock as Control

The `keyboard` capability changes Caps Lock to Control directly with the macOS `hidutil` tool, without an extra application or a kernel extension.

| Piece | What it does |
|---|---|
| `hidutil property --set ...` | Applies the configuration immediately |
| LaunchAgent `sh.teeup.keyboard` | Applies the configuration again at every login |

To remove the capability, run this command:

```sh
teeup remove keyboard
```

This command unloads the LaunchAgent and removes the configuration immediately, so Caps Lock operates as Caps Lock again.

## Changing a preference yourself

You can change a preference in System Settings, but teeup writes each preference again when it configures `macos-defaults`, at bootstrap and during each `teeup update`.
teeup records the previous value only the first time.

If you change a value manually, the value resets on the next update.
To keep your own values, skip the capability with `TEEUP_SKIP`, as above, or remove the capability.
