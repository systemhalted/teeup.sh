# AI tools

teeup has five AI coding tools.
`./bootstrap` does not install them, because each one is a lazy capability: teeup installs a tool the first time you run its command.

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

The menu shows the same choices under Install > AI.

## What happens on the first call

This example shows what happens when you run `claude` for the first time on a Mac:

1. The lazy shim shows the prompt "claude is provided by capability ai-claude. Install now?". Type yes.
2. The `ai-claude` capability writes a small wrapper script, `~/.local/bin/claude`, but does not download the tool yet.
3. The wrapper script runs and does not find Claude Code, so it shows `Installing Claude Code through mise (first run, can take a minute)...`.
4. The wrapper script installs Claude Code with mise.
5. The wrapper script runs `claude` with the arguments that you typed.

Read [Tiers](tiers.md) for how shims work.

After the first call, your shell finds `~/.local/bin/claude` first on your `PATH`, and the wrapper script runs the tool through `mise x`.

`teeup install ai-claude` does steps 1 and 2 without the prompt, but the download still waits for the first call of the command.

<!-- SCREENSHOT: WezTerm after typing `claude` on a fresh Mac, showing the "Install now?" prompt and then the "Installing Claude Code through mise (first run, can take a minute)..." line. -->

## The log

teeup records every first-run download in `~/.local/state/teeup/logs/lazy.log`, with a timestamp and whether the download finished.
If a download stops early, run the command again to start it again.

## Updates

The tools are in your global mise configuration file, `~/.config/mise/config.toml`, so `teeup update` upgrades them with all other tools that mise manages.
Read [Updates](updates.md) for more information.

## Removing a tool

```sh
teeup remove ai-codex
teeup remove ai    # all five
```

When you remove a tool, teeup deletes the wrapper script that it wrote and removes the tool from the global mise configuration.
When you remove `ai-gemini`, teeup removes `gemini-cli` but leaves Node in the mise configuration.

If teeup did not write `~/.local/bin/<command>` (for example, the native launcher of Claude Code), teeup does not change it and shows a warning.

If you installed the `ai` bundle, the bundle requires the five tools, so `teeup remove ai-codex` stops with the message "ai-codex is required by: ai".
To remove all tools, run `teeup remove ai`.

The shim stays after a removal, so if you run the command later, it offers to install the tool again.

## Ollama and Herdr

The menu has two other AI capabilities: Ollama runs models on your local system, and Herdr is a terminal agent multiplexer.
Read [Apps](apps.md) for information about them.
