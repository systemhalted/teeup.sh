# AI tools

teeup has five AI coding tools.
`./bootstrap` does not install these tools.
Each tool is a lazy capability.
If you run the command for a tool, teeup installs the tool.

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

The teeup menu shows the same choices.
Select Install in the teeup menu.
Select AI.

## What happens on the first call

This example shows what happens when you run `claude` for the first time on a Mac:

1. The lazy shim shows the prompt "claude is provided by capability ai-claude. Install now?". Type yes.
2. The `ai-claude` capability writes a small wrapper script, `~/.local/bin/claude`. It does not download the tool yet.
3. The wrapper script runs. It does not find Claude Code, so it shows `Installing Claude Code through mise (first run, can take a minute)...`.
4. The wrapper script installs Claude Code with mise.
5. The wrapper script runs `claude` with the arguments that you typed.

Read [Tiers](tiers.md) for information about shims.

After the first call, your shell finds `~/.local/bin/claude` first on your `PATH`.
The wrapper script runs the tool through `mise x`.

`teeup install ai-claude` does steps 1 and 2 and does not show the prompt.
The download waits for the first call of the command.

<!-- SCREENSHOT: WezTerm after typing `claude` on a fresh Mac, showing the "Install now?" prompt and then the "Installing Claude Code through mise (first run, can take a minute)..." line. -->

## The log

teeup writes information about every first-run download to `~/.local/state/teeup/logs/lazy.log`.
Each entry has a timestamp and records whether the download finished.
If a download stops early, run the command again to start the download again.

## Updates

The tools are in your global mise configuration file, `~/.config/mise/config.toml`.
`teeup update` upgrades the tools together with all other tools that mise manages.
Read [Updates](updates.md) for more information.

## Removing a tool

```sh
teeup remove ai-codex
teeup remove ai    # all five
```

When you remove a tool, teeup deletes the wrapper script that teeup wrote.
teeup also removes the tool from the global mise configuration.
When you remove `ai-gemini`, teeup removes `gemini-cli`.
teeup leaves Node in the mise configuration.

If teeup did not write the file at `~/.local/bin/<command>`, teeup does not change it and shows a warning.
An example is the native launcher of Claude Code.

If you installed the `ai` bundle, the bundle requires the five tools.
Then `teeup remove ai-codex` stops with the message "ai-codex is required by: ai".
To remove all tools, run `teeup remove ai`.

The shim remains after a removal.
If you run the command later, the shim offers to install the tool again.

## Ollama and Herdr

The menu has two other AI capabilities.
Ollama runs models on your local system.
Herdr is a terminal agent multiplexer.
Read [Apps](apps.md) for information about Ollama and Herdr.
