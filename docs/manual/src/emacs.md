# Emacs

Emacs is in the daily tier. teeup installs the GUI build and the `emacs-app` cask, which puts `emacs` and `emacsclient` on your `PATH`. Emacs runs as a daemon from login, and git and the shell use `emacsclient` as their editor.

<!-- SCREENSHOT: An Emacs window opened with `e README.md` from WezTerm, showing the teeup starter layer with the current theme. -->

## The four flavors

The wizard asks which configuration to install, and keeps the answer in `TEEUP_EMACS_FLAVOR`.

| Flavor | What teeup does |
|---|---|
| `starter` | The default. teeup creates a thin `~/.config/emacs/init.el` file that loads the small teeup layer from the checkout, which uses only the packages built into Emacs. teeup also creates `~/.config/emacs/local.el` for your personal settings. |
| `doom` | teeup clones [Doom Emacs](https://github.com/doomemacs/core) into `~/.config/emacs` and runs `doom install --no-env`. Your private configuration is in `~/.config/doom`. |
| `spacemacs` | teeup clones Spacemacs into `~/.emacs.d`. On the first start, Spacemacs completes its own configuration and writes `~/.spacemacs`. |
| `none` | teeup does not change your Emacs configuration, but the daemon still runs. See [Your own configuration and teeup's theme](#your-own-configuration-and-teeups-theme). |

If a directory blocks the install (for example, a starter configuration where Doom must go), teeup renames it to `<name>.teeup_backup_<timestamp>` and does not delete it. Emacs reads `~/.emacs.el`, `~/.emacs`, and `~/.emacs.d` before `~/.config/emacs`. If one of these paths exists, teeup warns that Emacs reads it instead, and does not change it.

## Your own configuration and teeup's theme

If you use the `none` flavor, you can add this code to your `init.el` file to use the teeup theme and font. The code only reads the teeup files. The theme follows the macOS light or dark mode when the daemon starts, and updates after each `teeup theme set` or `teeup install font`.

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

The LaunchAgent `sh.teeup.emacs` starts `Emacs --fg-daemon` at login. `launchd` restarts the daemon after a crash, but not after you stop it on purpose.

| Command | What it opens |
|---|---|
| `e <file>` | A new Emacs window (`emacsclient -c`) |
| `et <file>` | A frame in the current terminal (`emacsclient -t`) |
| `$EDITOR` and `$VISUAL` | `emacsclient -t`, so git, `teeup config edit`, and other tools open in the terminal |

If the daemon is not running, `emacsclient` from the shell starts a new daemon, because the teeup shell sets an empty `ALTERNATE_EDITOR`.

The daemon keeps the configuration that it reads when it starts. After you change the flavor or edit your configuration files, restart the daemon:

```sh
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

`teeup configure emacs` also shows this line.

## Changing the flavor

Set the answer, then configure Emacs again:

```sh
teeup config set TEEUP_EMACS_FLAVOR doom
teeup configure emacs
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

`teeup update` also applies a changed flavor, because it configures the daily tier again. If your machine file pins `TEEUP_EMACS_FLAVOR`, `teeup config set` warns you that the pinned value has priority. Change the value in the machine file instead (see [Answers and machines](answers-and-machines.md)).

## Doom's command line

If you use the `doom` flavor, the Doom CLI is on your `PATH`, because the teeup shell adds `~/.config/emacs/bin`. After you edit `~/.config/doom`, run:

```sh
doom sync
```

`doom doctor` and `doom upgrade` work in the same way. teeup runs `doom install` only one time, when `~/.config/doom/init.el` does not exist. teeup disables the default Doom template theme so that the teeup theme applies, but your own `doom-theme` setting overrides it.


## Removing Emacs

`teeup remove emacs` unloads the LaunchAgent of the daemon and uninstalls the cask. teeup does not delete your configuration in `~/.config/emacs`, `~/.config/doom`, or `~/.emacs.d`. If Emacs does not start or the wrong build runs, see [Doctor and troubleshooting](doctor-and-troubleshooting.md).
