-- ~/.config/wezterm/wezterm.lua - yours. teeup installed it once and will not
-- overwrite it. The thick layer lives in the teeup checkout and is upgraded by
-- `teeup update`; put your own settings in ~/.config/wezterm/local.lua, or
-- below the `local config = ...` line here.
local wezterm = require("wezterm")

-- WezTerm launched from the Dock or Spotlight has launchd's environment, not a
-- login shell's, so TEEUP_PATH and TEEUP_STATE_DIR are usually missing.
-- ~/.config/teeup/env is the one-line-per-variable file teeup-runtime writes
-- for exactly this case.
--
-- teeup-runtime runs every value through bash's `printf '%q'` before writing
-- it (capabilities/teeup-runtime/configure), which backslash-escapes spaces
-- and shell metacharacters rather than wrapping the whole value in quotes:
-- `export TEEUP_PATH=/Users/ada/My\ Code/teeup`. Undo that escaping once the
-- whole line has matched, or a checkout path with a space would come back
-- truncated at the first escaped character.
local function read_env_value(path, key)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local pattern = "^export " .. key .. "=(.+)$"
  for line in f:lines() do
    local value = line:match(pattern)
    if value and value ~= "" then
      value = value:gsub("\\(.)", "%1")
      f:close()
      return value
    end
  end
  f:close()
  return nil
end

local config_home = os.getenv("XDG_CONFIG_HOME") or (wezterm.home_dir .. "/.config")
local env_file = config_home .. "/teeup/env"

local function teeup_path()
  local from_env = os.getenv("TEEUP_PATH")
  if from_env and from_env ~= "" then
    return from_env
  end
  local from_file = read_env_value(env_file, "TEEUP_PATH")
  if from_file then
    return from_file
  end
  return wezterm.home_dir .. "/.local/share/teeup"
end

local function teeup_state_dir()
  local from_env = os.getenv("TEEUP_STATE_DIR")
  if from_env and from_env ~= "" then
    return from_env
  end
  local from_file = read_env_value(env_file, "TEEUP_STATE_DIR")
  if from_file then
    return from_file
  end
  local state_home = os.getenv("XDG_STATE_HOME") or (wezterm.home_dir .. "/.local/state")
  return state_home .. "/teeup"
end

local teeup_root = teeup_path()
local teeup_state = teeup_state_dir()

-- Three tiers, highest priority first: generated theme files, your own
-- ~/.config/wezterm, then teeup's default layer. The first tier is there so a
-- theme can ship a require-able Lua module later; today's rendered colour
-- scheme is loaded by path with dofile, from the default layer.
local teeup_search_path = table.concat({
  teeup_state .. "/current/theme/?.lua",
  wezterm.config_dir .. "/?.lua",
  teeup_root .. "/capabilities/wezterm/default/?.lua",
}, ";")
package.path = teeup_search_path .. ";" .. package.path

-- Machine-specific settings. local.lua may set font_size, workspaces and
-- hyperlink_rules; see the comments in that file.
local overrides = {}
local ok, loaded = pcall(dofile, wezterm.config_dir .. "/local.lua")
if ok and type(loaded) == "table" then
  overrides = loaded
else
  -- The pre-teeup dotfiles repo kept this table in ~/.wezterm_local.lua.
  local ok_legacy, legacy = pcall(dofile, wezterm.home_dir .. "/.wezterm_local.lua")
  if ok_legacy and type(legacy) == "table" then
    overrides = legacy
  end
end

-- If the default layer cannot be found (no TEEUP_PATH, no ~/.config/teeup/env,
-- and the checkout is not at ~/.local/share/teeup) fall back to a terminal that
-- still works, and say where we looked. An uncaught error here means WezTerm
-- silently drops to its own defaults with nothing pointing at the cause.
local ok_layer, layer = pcall(require, "teeup.wezterm")
local config
if ok_layer then
  config = layer.config(overrides, teeup_state)
else
  wezterm.log_error(
    "teeup: could not load teeup.wezterm (" .. tostring(layer) .. "). Searched: "
      .. teeup_search_path
      .. " -- set TEEUP_PATH or re-run: teeup configure teeup-runtime"
  )
  config = wezterm.config_builder()
  config.font = wezterm.font_with_fallback({ "JetBrainsMono Nerd Font" })
  config.font_size = overrides.font_size or 16.0
end

-- Your own settings go below this line.

return config
