-- teeup's Neovim layer, required by the thin ~/.config/nvim/init.lua through
-- lua/config/lazy.lua. This file is teeup's: edit it in the checkout, not in
-- your home directory.
--
-- What it does: read the colorscheme name `teeup theme set` rendered for the
-- current appearance, hand lazy.nvim the plugin that provides it, and set the
-- GUI font from `teeup install font`. M.apply() redoes both at runtime; the
-- theme-apply and font-apply hooks call it in every running instance.

local M = {}

local DEFAULT_FONT = "JetBrainsMono Nerd Font"
local DEFAULT_COLORSCHEME = "tokyonight"

local function state_dir()
  if vim.g.teeup_state_dir and vim.g.teeup_state_dir ~= "" then
    return vim.g.teeup_state_dir
  end
  local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
  return state_home .. "/teeup"
end

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

-- dark or light. A shell exports TEEUP_APPEARANCE (the zsh layer reads
-- AppleInterfaceStyle at shell start); without it, 'background', which
-- Neovim sets from the terminal's own colours.
function M.mode()
  local env = os.getenv("TEEUP_APPEARANCE")
  if env == "dark" or env == "light" then
    return env
  end
  if vim.o.background == "light" then
    return "light"
  end
  return "dark"
end

-- The rendered palette for one mode: { mode, colorscheme, colors }, or nil
-- before the first `teeup theme set`.
function M.theme(mode)
  local path = state_dir() .. "/current/theme/" .. (mode or M.mode()) .. "/neovim.lua"
  local ok, theme = pcall(dofile, path)
  if ok and type(theme) == "table" then
    return theme
  end
  return nil
end

function M.font_family()
  return read_first_line(state_dir() .. "/current/font") or DEFAULT_FONT
end

-- Which plugin provides a colorscheme, keyed on the name's first run of
-- %w characters (letters and digits; %w does not include "-"): teeup's
-- palettes name colorschemes ("catppuccin-mocha"), not repositories. LazyVim
-- already ships catppuccin and tokyonight; the rest are added on demand. A
-- name not listed here is still tried (a plugin you added yourself may
-- provide it), and LazyVim falls back to habamax with a message if not.
-- "rose-pine", "rose-pine-moon" and "rose-pine-dawn" all key on "rose" (I3:
-- a key of "rosepine" could never match, since the hyphen stops %w's run
-- before "pine").
M.colorscheme_plugins = {
  catppuccin = { "catppuccin/nvim", name = "catppuccin" },
  tokyonight = { "folke/tokyonight.nvim" },
  gruvbox = { "ellisonleao/gruvbox.nvim" },
  nord = { "shaunsingh/nord.nvim" },
  kanagawa = { "rebelot/kanagawa.nvim" },
  everforest = { "neanias/everforest-nvim" },
  rose = { "rose-pine/neovim", name = "rose-pine" },
}

function M.plugin_for(colorscheme)
  local key = (colorscheme or ""):match("^([%w]+)")
  if key then
    return M.colorscheme_plugins[key]
  end
  return nil
end

function M.colorscheme()
  local theme = M.theme()
  if theme and type(theme.colorscheme) == "string" and theme.colorscheme ~= "" then
    return theme.colorscheme
  end
  return DEFAULT_COLORSCHEME
end

-- Load the colorscheme for the current mode. Errors propagate on purpose:
-- LazyVim wraps its colorscheme call and falls back to habamax with a message.
function M.load()
  vim.o.background = M.mode()
  vim.cmd.colorscheme(M.colorscheme())
end

function M.apply_font()
  vim.o.guifont = M.font_family() .. ":h14"
end

-- Runtime reload, from the hooks: never raises.
function M.apply()
  local ok, err = pcall(M.load)
  if not ok then
    vim.notify("teeup: could not load colorscheme " .. M.colorscheme() .. ": " .. tostring(err), vim.log.levels.WARN)
  end
  M.apply_font()
end

-- lazy.nvim specs for lua/config/lazy.lua.
function M.specs()
  local specs = {}
  local plugin = M.plugin_for(M.colorscheme())
  if plugin then
    table.insert(specs, plugin)
  end
  table.insert(specs, {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        M.load()
        M.apply_font()
      end,
    },
  })
  return specs
end

return M
