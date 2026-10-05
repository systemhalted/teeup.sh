# Emacs

Emacs is in the daily tier. teeup installs the GUI build and the `emacs-app` cask. This step puts `emacs` and `emacsclient` on your `PATH`. Emacs runs as a daemon from login. Git and the shell use `emacsclient` as their editor.

<!-- SCREENSHOT: An Emacs window opened with `e README.md` from WezTerm, showing the teeup starter layer with the current theme. -->

## The four flavors

The wizard asks which configuration to install. The answer is `TEEUP_EMACS_FLAVOR`.

| Flavor | What teeup does |
|---|---|
| `starter` | This flavor is the default. teeup creates a thin `~/.config/emacs/init.el` file. This file loads the small teeup layer from the checkout. The layer uses only the packages built into Emacs. teeup also creates `~/.config/emacs/local.el` for your personal settings. |
| `doom` | teeup clones [Doom Emacs](https://github.com/doomemacs/core) into `~/.config/emacs`. teeup runs `doom install --no-env`. Your private configuration is in `~/.config/doom`. |
| `spacemacs` | teeup clones Spacemacs into `~/.emacs.d`. Spacemacs completes its own configuration on the first start. Spacemacs writes the `~/.spacemacs` file. |
| `none` | teeup does not change your Emacs configuration. The daemon continues to run. See [Your own configuration and teeup's theme](#your-own-configuration-and-teeups-theme). |

If a directory is at the installation path, teeup renames it to `<name>.teeup_backup_<timestamp>` and does not delete it. For example, a starter configuration can be at the Doom installation path. Emacs reads `~/.emacs.el`, `~/.emacs`, and `~/.emacs.d` before `~/.config/emacs`. If one of these paths exists, teeup shows a warning that Emacs reads this path instead. teeup does not change the existing path.

## Your own configuration and teeup's theme

If you use the `none` flavor, you can add this code to your `init.el` file. This code configures Emacs to use the teeup theme and the teeup font. The code only reads the teeup files. The theme changes to the macOS light or dark mode when the daemon starts. The theme updates after you run `teeup theme set` or `teeup install font`.

```elisp
;; Follow teeup's theme and font. teeup calls (teeup-apply) on a running
;; daemon after every `teeup theme set` and `teeup install font`.
(require 'subr-x)
(defun teeup-apply ()
  (let* ((state (expand-file-name "~/.local/state/teeup/"))
         (dark (string= "Dark" (string-trim (shell-command-to-string
                 "defaults read -g AppleInterfaceStyle 2>/dev/null"))))
         (theme (expand-file-name (format "current/theme/%s/emacs.el"
                                          (if dark "dark" "light"))
                                  state))
         (font (expand-file-name "current/font" state)))
    (when (file-readable-p theme)
      (load theme nil t)
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme teeup-theme-name t))
    (when (and (display-graphic-p) (file-readable-p font))
      (set-face-attribute 'default nil :family
                          (string-trim (with-temp-buffer
                                         (insert-file-contents font)
                                         (buffer-string)))))))
(teeup-apply)
```

## The daemon and emacsclient

The LaunchAgent `sh.teeup.emacs` starts `Emacs --fg-daemon` at login. `launchd` restarts the daemon after a crash. `launchd` does not restart the daemon after you stop it manually.

| Command | What it opens |
|---|---|
| `e <file>` | This command opens a new Emacs window (`emacsclient -c`). |
| `et <file>` | This command opens a frame in the current terminal (`emacsclient -t`). |
| `$EDITOR` and `$VISUAL` | These variables use `emacsclient -t`. Git, `teeup config edit`, and other tools open in the terminal. |

If the daemon is not running, an `emacsclient` command from the shell starts a new daemon. The teeup shell sets an empty `ALTERNATE_EDITOR` variable to enable this function.

The daemon keeps the configuration that it reads when it starts. If you change the flavor or edit your configuration files, you must restart the daemon. Run this command to restart the daemon:

```sh
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

The `teeup configure emacs` command also shows this line.

## Changing the flavor

Set the answer, and then configure Emacs again. Run these commands:

```sh
teeup config set TEEUP_EMACS_FLAVOR doom
teeup configure emacs
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

The `teeup update` command also applies a changed flavor because the command configures the daily tier again. If your machine file pins `TEEUP_EMACS_FLAVOR`, `teeup config set` shows a warning. The warning tells you that the pinned value has priority. If the value is pinned, change the value in the machine file instead. See [Answers and machines](answers-and-machines.md).

## Doom's command line

If you use the `doom` flavor, the Doom CLI is in your `PATH`. The teeup shell adds `~/.config/emacs/bin` to the `PATH`. After you edit `~/.config/doom`, run this command:

```sh
doom sync
```

The `doom doctor` and `doom upgrade` commands work in the same way. teeup runs `doom install` only one time. teeup runs this command if `~/.config/doom/init.el` does not exist. teeup disables the default Doom template theme so the teeup theme applies. Your own `doom-theme` setting overrides the teeup theme.


## Removing Emacs

The `teeup remove emacs` command unloads the LaunchAgent of the daemon. The command also uninstalls the cask. teeup does not delete your configuration in `~/.config/emacs`, `~/.config/doom`, or `~/.emacs.d`. If Emacs does not start, see [Doctor and troubleshooting](doctor-and-troubleshooting.md). If the wrong build runs, see [Doctor and troubleshooting](doctor-and-troubleshooting.md).
