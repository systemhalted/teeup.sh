-- teeup's WezTerm layer, required by the thin ~/.config/wezterm/wezterm.lua.
-- This file is teeup's: edit it in the checkout, not in your home directory.
-- Ported from the pre-teeup dotfiles config; every binding is the same, the
-- font and the colours now come from teeup state instead of being hard-coded.

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- The thin config resolves TEEUP_STATE_DIR (env var, then ~/.config/teeup/env,
-- then this same fallback) and passes it into M.config/M.font_family/
-- M.color_schemes below. This module-level STATE is only used when one of
-- those is called without that argument, e.g. if this file is ever required
-- directly.
local state_home = os.getenv("XDG_STATE_HOME") or (wezterm.home_dir .. "/.local/state")
local STATE = state_home .. "/teeup"
local DEFAULT_FONT = "JetBrainsMono Nerd Font"

local function read_first_line(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  if not line then
    return nil
  end
  line = line:gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" then
    return nil
  end
  return line
end

-- The family `teeup install font` recorded. Watching the file means the
-- font-apply hook's touch is belt and braces rather than the only reload path.
function M.font_family(state_dir)
  local dir = state_dir or STATE
  local path = dir .. "/current/font"
  wezterm.add_to_config_reload_watch_list(path)
  return read_first_line(path) or DEFAULT_FONT
end

-- wezterm.gui does not exist in the mux server, so assume dark there.
function M.get_appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return "Dark"
end

function M.mode()
  if M.get_appearance():find("Dark") then
    return "dark"
  end
  return "light"
end

-- `teeup theme set` renders one colour-scheme table per mode. Both are
-- registered, so the system appearance switch (which makes WezTerm
-- re-evaluate this config) only has to pick the other name.
function M.color_schemes(state_dir)
  local dir = state_dir or STATE
  local schemes = {}
  local found = false
  for _, mode in ipairs({ "dark", "light" }) do
    local path = dir .. "/current/theme/" .. mode .. "/wezterm.lua"
    local ok, scheme = pcall(dofile, path)
    if ok and type(scheme) == "table" then
      schemes["teeup-" .. mode] = scheme
      wezterm.add_to_config_reload_watch_list(path)
      found = true
    end
  end
  if not found then
    return nil
  end
  return schemes
end

-- Tab title: the last component of the pane's cwd, with a dot on the active
-- tab. Falls back to the pane title when there is no cwd (ssh, a pager).
wezterm.on("format-tab-title", function(tab)
  local pane = tab.active_pane
  local title = pane.title
  local cwd = pane.current_working_dir
  if cwd then
    local path = cwd.file_path or ""
    local folder = path:match("([^/]+)/?$")
    if folder then
      title = folder
    end
  end
  if tab.is_active then
    return " ● " .. title .. " "
  end
  return " " .. title .. " "
end)

-- Right status: workspace name and the clock.
wezterm.on("update-right-status", function(window)
  local workspace = window:active_workspace()
  local time = wezterm.strftime("%H:%M")
  window:set_right_status(wezterm.format({
    { Text = "  " .. workspace .. "  │  " .. time .. "  " },
  }))
end)

-- Emacs-style bindings behind a CTRL+Space leader: C-x 2 / C-x 3 split,
-- C-x o cycles, C-x 0 closes, C-x 1 zooms, b/f/c/k move between tabs.
function M.keys(overrides)
  local keys = {
    { key = "p", mods = "CMD|SHIFT", action = act.ActivateCommandPalette },
    { key = "r", mods = "CMD|SHIFT", action = act.ReloadConfiguration },
    { key = "k", mods = "CMD", action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),
    }) },
    { key = "k", mods = "CTRL|SHIFT", action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),
    }) },

    -- Panes
    { key = "3", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "2", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "o", mods = "LEADER", action = act.ActivatePaneDirection("Next") },
    { key = "LeftArrow", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "DownArrow", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    { key = "UpArrow", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "RightArrow", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
    { key = "0", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "1", mods = "LEADER", action = act.TogglePaneZoomState },

    -- Tabs, as Emacs buffers
    { key = "b", mods = "LEADER", action = act.ActivateTabRelative(-1) },
    { key = "f", mods = "LEADER", action = act.ActivateTabRelative(1) },
    { key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "k", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },

    -- Workspaces
    { key = "w", mods = "LEADER", action = act.PromptInputLine({
      description = "Enter new workspace name:",
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
        end
      end),
    }) },
    { key = "s", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
    { key = "d", mods = "LEADER", action = act.SwitchToWorkspace({
      name = "default",
      spawn = { cwd = wezterm.home_dir },
    }) },

    -- Modes
    { key = "r", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
    { key = "v", mods = "LEADER", action = act.ActivateCopyMode },
    { key = "q", mods = "LEADER", action = act.QuickSelect },
  }

  for _, ws in ipairs(overrides.workspaces or {}) do
    table.insert(keys, {
      key = ws.key,
      mods = "LEADER",
      action = act.SwitchToWorkspace({ name = ws.name, spawn = { cwd = ws.cwd } }),
    })
  end

  return keys
end

function M.key_tables()
  return {
    resize_pane = {
      { key = "LeftArrow", action = act.AdjustPaneSize({ "Left", 2 }) },
      { key = "RightArrow", action = act.AdjustPaneSize({ "Right", 2 }) },
      { key = "UpArrow", action = act.AdjustPaneSize({ "Up", 2 }) },
      { key = "DownArrow", action = act.AdjustPaneSize({ "Down", 2 }) },
      { key = "Escape", action = "PopKeyTable" },
      { key = "Enter", action = "PopKeyTable" },
    },
  }
end

function M.hyperlink_rules(overrides)
  local rules = wezterm.default_hyperlink_rules()
  -- owner/repo#123 opens the issue or PR.
  table.insert(rules, {
    regex = [[\b([A-Za-z0-9_-]+/[A-Za-z0-9_.-]+)#(\d+)\b]],
    format = "https://github.com/$1/issues/$2",
  })
  for _, rule in ipairs(overrides.hyperlink_rules or {}) do
    table.insert(rules, rule)
  end
  return rules
end

function M.config(overrides, state_dir)
  overrides = overrides or {}
  state_dir = state_dir or STATE
  local config = wezterm.config_builder()

  -- Fonts. Ligatures on; Devanagari falls back to a system face.
  config.font = wezterm.font_with_fallback({
    { family = M.font_family(state_dir), weight = "Medium" },
    "Kohinoor Devanagari",
  })
  config.font_size = overrides.font_size or 16.0
  config.harfbuzz_features = { "calt=1", "clig=1", "liga=1" }

  -- Colours. The built-in Catppuccin schemes are the fallback for the window
  -- between installing WezTerm and the first `teeup theme set`.
  local schemes = M.color_schemes(state_dir)
  if schemes then
    config.color_schemes = schemes
    config.color_scheme = "teeup-" .. M.mode()
  elseif M.mode() == "dark" then
    config.color_scheme = "Catppuccin Mocha"
  else
    config.color_scheme = "Catppuccin Latte"
  end

  -- Window
  config.window_decorations = "TITLE | RESIZE"
  config.window_background_opacity = 0.92
  config.macos_window_background_blur = 20
  config.window_padding = { left = 12, right = 12, top = 12, bottom = 12 }
  config.text_background_opacity = 1.0
  config.inactive_pane_hsb = { saturation = 0.9, brightness = 0.8 }

  -- Tab bar. Always visible, so the tab workflow stays in muscle memory.
  config.use_fancy_tab_bar = true
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_max_width = 30
  config.show_new_tab_button_in_tab_bar = true

  -- Keys
  config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }
  config.keys = M.keys(overrides)
  config.key_tables = M.key_tables()

  -- General
  config.scrollback_lines = 10000
  config.enable_scroll_bar = false
  config.hyperlink_rules = M.hyperlink_rules(overrides)

  return config
end

return M
