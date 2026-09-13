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
-- it (capabilities/teeup-runtime/configure). `%q` does not always produce
-- the simple backslash-escaped form (`/Users/ada/My\ Code/teeup`): any
-- non-ASCII byte in the value makes bash 3.2 switch to ANSI-C `$'...'`
-- quoting with octal byte escapes (`$'/Users/caf\303\251/teeup'`), and a
-- word can freely mix plain text, '...'  and "..." segments back to back
-- (that's just how shell words work). bash_unescape_word below is a small
-- decoder for one such word: it walks the raw text once, byte by byte,
-- handling each quoting style in turn and concatenating the decoded
-- segments, the same way the shell itself would reassemble the word before
-- using it.
local function bash_unescape_word(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "'" then
      -- '...' - everything up to the next ' is literal, no escapes at all.
      local j = s:find("'", i + 1, true)
      if not j then
        return nil
      end
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    elseif c == '"' then
      -- "..." - backslash keeps its meaning only before $ ` " \ or a
      -- newline; anywhere else the backslash is itself literal.
      local j, buf = i + 1, {}
      local closed = false
      while j <= n do
        local cj = s:sub(j, j)
        if cj == '"' then
          closed = true
          break
        elseif cj == "\\" then
          local nx = s:sub(j + 1, j + 1)
          if nx == "$" or nx == "`" or nx == '"' or nx == "\\" or nx == "\n" then
            buf[#buf + 1] = nx
            j = j + 2
          else
            buf[#buf + 1] = cj
            j = j + 1
          end
        else
          buf[#buf + 1] = cj
          j = j + 1
        end
      end
      if not closed then
        return nil
      end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "$" and s:sub(i + 1, i + 1) == "'" then
      -- $'...' (ANSI-C quoting) - \NNN (1-3 octal digits) and \xHH decode to
      -- a raw byte via string.char; a run of these is how %q re-encodes a
      -- multi-byte UTF-8 character, so decoding byte by byte reassembles it.
      local j, buf = i + 2, {}
      local closed = false
      while j <= n do
        local cj = s:sub(j, j)
        if cj == "'" then
          closed = true
          break
        elseif cj == "\\" then
          local nx = s:sub(j + 1, j + 1)
          local oct = s:sub(j + 1, j + 3):match("^[0-7][0-7]?[0-7]?")
          local hex = nx == "x" and s:sub(j + 2, j + 3):match("^%x%x?")
          if oct and oct ~= "" then
            buf[#buf + 1] = string.char(tonumber(oct, 8) % 256)
            j = j + 1 + #oct
          elseif hex then
            buf[#buf + 1] = string.char(tonumber(hex, 16))
            j = j + 2 + #hex
          elseif nx == "a" then buf[#buf + 1] = "\a"; j = j + 2
          elseif nx == "b" then buf[#buf + 1] = "\b"; j = j + 2
          elseif nx == "e" or nx == "E" then buf[#buf + 1] = "\27"; j = j + 2
          elseif nx == "f" then buf[#buf + 1] = "\f"; j = j + 2
          elseif nx == "n" then buf[#buf + 1] = "\n"; j = j + 2
          elseif nx == "r" then buf[#buf + 1] = "\r"; j = j + 2
          elseif nx == "t" then buf[#buf + 1] = "\t"; j = j + 2
          elseif nx == "v" then buf[#buf + 1] = "\v"; j = j + 2
          elseif nx == "\\" or nx == "'" or nx == '"' then buf[#buf + 1] = nx; j = j + 2
          elseif nx == "" then
            return nil
          else
            buf[#buf + 1] = nx
            j = j + 2
          end
        else
          buf[#buf + 1] = cj
          j = j + 1
        end
      end
      if not closed then
        return nil
      end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "\\" then
      -- Unquoted backslash: the next byte is literal (this is the plain
      -- form %q uses when nothing in the value needs ANSI-C quoting).
      local nx = s:sub(i + 1, i + 1)
      if nx == "" then
        return nil
      end
      out[#out + 1] = nx
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function read_env_value(path, key)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local pattern = "^export " .. key .. "=(.+)$"
  for line in f:lines() do
    local value = line:match(pattern)
    if value and value ~= "" then
      f:close()
      -- An unterminated quote means the word did not decode; fall back
      -- exactly as if this key had not been found at all.
      return bash_unescape_word(value)
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
