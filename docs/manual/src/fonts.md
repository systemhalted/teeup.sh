# Fonts

teeup installs and configures Nerd Fonts. A Nerd Font patches programming fonts with icons from Material Design, FontAwesome, and other sets, and these icons show in file listings, prompts, and editors.

| Command | What it does |
|---|---|
| `teeup install font <name>` | Download and set a Nerd Font for every tool. |
| `teeup install font list` | Show all the Nerd Fonts that you can install. |

When you install a font, teeup configures WezTerm, Zed, VS Code, Neovim, and Emacs.

Terminal.app also uses the recorded font. When teeup generates its theme profile for Terminal.app, it sets the font to the one that you chose, at 13 pt. If you use a different terminal, teeup does not set its font, so set it to your Nerd Font to see the icons.
