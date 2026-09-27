# AI tools

teeup includes five AI coding tools. `./bootstrap` does not install them. Each is a lazy capability. Typing its command installs it.

| Command | Tool | Capability | Installed through mise as |
|---|---|---|---|
| `claude` | Claude Code | `ai-claude` | `claude` |
| `codex` | Codex | `ai-codex` | `codex` |
| `gemini` | Gemini CLI | `ai-gemini` | `gemini-cli`, plus `node` |
| `copilot` | GitHub Copilot CLI | `ai-copilot` | `copilot` |
| `opencode` | OpenCode | `ai-opencode` | `opencode` |

`teeup install ai` installs all five as an explicit bundle:

```sh
teeup install ai
```

The menu has the same choices under Install, then AI.

## What happens on the first call

For example, running `claude` on a Mac that has never run it:

1. The lazy shim asks "claude is provided by capability ai-claude. Install now?". Say yes. (See [Tiers](tiers.md) for how shims work.)
2. The `ai-claude` capability writes a small wrapper script, `~/.local/bin/claude`. It downloads nothing yet.
3. The wrapper runs. It sees Claude Code is missing and prints `Installing Claude Code through mise (first run, can take a minute)...`, then installs it with mise.
4. The wrapper runs `claude` with the arguments you typed.

From then on `~/.local/bin/claude` is found first on your `PATH` and runs the tool through `mise x`. `teeup install ai-claude` does the first two steps without asking; the download still waits for the first call.

<!-- SCREENSHOT: WezTerm after typing `claude` on a fresh Mac, showing the "Install now?" prompt and then the "Installing Claude Code through mise (first run, can take a minute)..." line. -->

## The log

Every first-run download is written to `~/.local/state/teeup/logs/lazy.log`, with a timestamp and whether it finished. If a download is interrupted, call the command again to retry it.

## Updates

The tools live in your global mise configuration, `~/.config/mise/config.toml`. `teeup update` upgrades them with everything else mise manages (see [Updates](updates.md)).

## Removing a tool

```sh
teeup remove ai-codex
teeup remove ai    # all five
```

Removing a tool deletes the wrapper teeup wrote and drops the tool from the global mise configuration. A file at `~/.local/bin/<command>` that teeup did not write, such as Claude Code's own native launcher, is left alone, with a warning. Removing `ai-gemini` drops `gemini-cli` and leaves Node in the mise configuration.

If you installed the `ai` bundle, the five leaves are its requirements. `teeup remove ai-codex` refuses with "ai-codex is required by: ai". Remove `ai` to remove them all.

The shim stays after a removal. Typing the command later offers to install it again.

## Ollama and Herdr

Two AI capabilities are in the menu. Ollama runs models locally and Herdr is a terminal agent multiplexer. Both are covered in [Apps](apps.md).
