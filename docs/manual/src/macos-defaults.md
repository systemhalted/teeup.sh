# macOS defaults

Two core capabilities change macOS.
The `macos-defaults` capability configures a list of preferences for development.
The `keyboard` capability changes Caps Lock to Control.
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

teeup restarts Finder or the Dock only when it changed one of the settings of that application.
To apply the two key-repeat settings, log out.
Then, log in again.

If you run `teeup configure macos-defaults` again, it does not change a value that is already correct.
If no value changes, the command restarts nothing.

## Putting them back

When teeup writes a preference for the first time, teeup records the previous value.
The `teeup remove macos-defaults` command restores each recorded value.
If the setting did not exist before, the command deletes the setting.
Then, the command restarts Finder and the Dock.
The `~/Screenshots` directory and its contents remain on your Mac.

If teeup cannot restore a preference, teeup shows the name of the preference.
teeup keeps `macos-defaults` marked as installed.
You can correct the cause.
Then, run the removal command again.

Because the capability is in the core tier, the next `./bootstrap` configures the preferences again.
If you want to keep the preferences off on one Mac, add the capability to `TEEUP_SKIP` in the machine file.
Read [Answers and machines](answers-and-machines.md) for more information.

## Caps Lock as Control

The `keyboard` capability changes Caps Lock to Control with the macOS `hidutil` tool.
The capability changes the key directly.
It does not use an extra application or a kernel extension.

| Piece | What it does |
|---|---|
| `hidutil property --set ...` | Applies the configuration immediately |
| LaunchAgent `sh.teeup.keyboard` | Applies the configuration again at every login |

To remove the capability, run this command:

```sh
teeup remove keyboard
```

The command unloads the LaunchAgent and removes the configuration immediately.
Caps Lock operates as Caps Lock again.

## Changing a preference yourself

You can change a preference in System Settings.
teeup writes a preference each time it configures `macos-defaults`.
teeup configures `macos-defaults` at bootstrap and during each `teeup update`.
teeup only records the previous value the first time.

If you manually change a value, the value resets on the next update.
If you want to keep your own values, skip the capability with `TEEUP_SKIP`, as above.
You can also remove the capability.
