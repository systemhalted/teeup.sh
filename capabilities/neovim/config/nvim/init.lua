-- ~/.config/nvim/init.lua - yours. teeup installed it once and will not
-- overwrite it. It is the LazyVim starter's init.lua plus the lines that find
-- the teeup checkout and put its Neovim layer on package.path; the thick layer
-- itself (capabilities/neovim/default/teeup/neovim.lua) lives in the checkout
-- and is upgraded by `teeup update`. Your plugins go in lua/plugins/.

-- A shell exports TEEUP_PATH and TEEUP_STATE_DIR (the zsh layer sources
-- ~/.config/teeup/env), so Neovim started from a terminal has both. Started
-- any other way it reads that env file itself. teeup-runtime writes every
-- value through bash's `printf %q`, which produces a backslash-escaped word
-- for plain paths and ANSI-C `$'...'` quoting (octal byte escapes) for
-- non-ASCII ones; unescape_word undoes both, byte by byte, the way the shell
-- reassembles a word.
local home = os.getenv("HOME") or ""

local function unescape_word(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "'" then
      local j = s:find("'", i + 1, true)
      if not j then return nil end
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    elseif c == '"' then
      local j, buf, closed = i + 1, {}, false
      while j <= n do
        local cj = s:sub(j, j)
        if cj == '"' then closed = true; break end
        local nx = s:sub(j + 1, j + 1)
        if cj == "\\" and (nx == "$" or nx == "`" or nx == '"' or nx == "\\" or nx == "\n") then
          buf[#buf + 1] = nx; j = j + 2
        else
          buf[#buf + 1] = cj; j = j + 1
        end
      end
      if not closed then return nil end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "$" and s:sub(i + 1, i + 1) == "'" then
      local j, buf, closed = i + 2, {}, false
      local simple = { a = "\a", b = "\b", e = "\27", E = "\27", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v" }
      while j <= n do
        local cj = s:sub(j, j)
        if cj == "'" then closed = true; break end
        if cj == "\\" then
          local nx = s:sub(j + 1, j + 1)
          local oct = s:sub(j + 1, j + 3):match("^[0-7][0-7]?[0-7]?")
          local hex = nx == "x" and s:sub(j + 2, j + 3):match("^%x%x?")
          if oct then
            buf[#buf + 1] = string.char(tonumber(oct, 8) % 256); j = j + 1 + #oct
          elseif hex then
            buf[#buf + 1] = string.char(tonumber(hex, 16)); j = j + 2 + #hex
          elseif simple[nx] then
            buf[#buf + 1] = simple[nx]; j = j + 2
          elseif nx == "" then
            return nil
          else
            buf[#buf + 1] = nx; j = j + 2
          end
        else
          buf[#buf + 1] = cj; j = j + 1
        end
      end
      if not closed then return nil end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "\\" then
      local nx = s:sub(i + 1, i + 1)
      if nx == "" then return nil end
      out[#out + 1] = nx
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local env_file = config_home .. "/teeup/env"

local function env_or_file(key, fallback)
  local from_env = os.getenv(key)
  if from_env and from_env ~= "" then
    return from_env
  end
  local f = io.open(env_file, "r")
  if f then
    local pattern = "^export " .. key .. "=(.+)$"
    for line in f:lines() do
      local value = line:match(pattern)
      if value and value ~= "" then
        f:close()
        return unescape_word(value) or fallback
      end
    end
    f:close()
  end
  return fallback
end

local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local teeup_root = env_or_file("TEEUP_PATH", home .. "/.local/share/teeup")
local teeup_state = env_or_file("TEEUP_STATE_DIR", state_home .. "/teeup")

-- Three tiers, highest priority first: generated theme files, your own
-- lua/ directory, then teeup's default layer. The user tier is on the
-- runtimepath already; naming it here keeps the order explicit.
package.path = table.concat({
  teeup_state .. "/current/theme/?.lua",
  config_home .. "/nvim/lua/?.lua",
  teeup_root .. "/capabilities/neovim/default/?.lua",
}, ";") .. ";" .. package.path

-- vim is nil under a plain Lua interpreter (the test harness); Neovim's
-- globals only exist from here on.
if vim then
  vim.g.teeup_path = teeup_root
  vim.g.teeup_state_dir = teeup_state
  -- bootstrap lazy.nvim, LazyVim and your plugins
  require("config.lazy")
end
