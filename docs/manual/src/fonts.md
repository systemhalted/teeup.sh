# Fonts

teeup sets up Nerd Fonts. A Nerd Font patches programming fonts with icons from Material Design, FontAwesome, and other sets. The icons show up in file listings, prompts, and editors.

| Command | What it does |
|---|---|
| `teeup install font <name>` | Download and set a Nerd Font for every tool. |
| `teeup install font list` | Show all the Nerd Fonts you can install. |

When you install a font, it reaches WezTerm, Zed, VS Code, Neovim, and Emacs.

Terminal.app uses the recorded font too. When teeup generates its theme profile for Terminal.app, it sets the font to the one you chose, at 13 pt. If you use a different terminal, you will need to set its font to your Nerd Font yourself to see the icons.
