-- ~/.config/wezterm/local.lua - machine-specific WezTerm settings.
-- Return a table. Everything is optional. This file is yours; teeup ships it
-- once with every entry commented out and never touches it again.
return {
  -- Font size for this machine. The family itself comes from
  -- `teeup install font <name>`, so it is not set here.
  -- font_size = 13.0,

  -- Quick-switch workspaces, reached with the leader key (CTRL+Space) and the
  -- single letter in `key`.
  -- workspaces = {
  --   { key = "e", name = "work", cwd = "/Users/you/Work" },
  --   { key = "p", name = "personal", cwd = "/Users/you/Personal" },
  -- },

  -- Extra Cmd+Click patterns, appended to WezTerm's defaults and teeup's
  -- GitHub shorthand rule. Issue-tracker rules belong here, not in the repo.
  -- hyperlink_rules = {
  --   { regex = [[\b(PROJ-\d+)\b]], format = "https://example.atlassian.net/browse/$1" },
  -- },
}
