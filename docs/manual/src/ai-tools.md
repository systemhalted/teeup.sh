# AI tools

teeup has five AI tools.
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

When you run `claude` for the first time, these events occur:

1. The lazy shim shows the prompt "claude is provided by capability ai-claude. Install now?".
2. Type yes.
3. The `ai-claude` capability writes the `~/.local/bin/claude` wrapper script.
4. The capability does not download the tool.
5. The wrapper script runs.
6. The wrapper script does not find Claude Code.
7. The wrapper script shows `Installing Claude Code through mise (first run, can take a minute)...`.
8. The wrapper script installs the tool with mise.
9. The wrapper script runs `claude` with your arguments.

Read [Tiers](tiers.md) for information about shims.

When you run the command again, your system finds `~/.local/bin/claude` first on your `PATH`.
The wrapper script runs the tool through `mise x`.

If you run `teeup install ai-claude`, teeup writes the wrapper script.
teeup does not show the installation prompt.
The download waits until you run the command for the first time.

<!-- SCREENSHOT: WezTerm after typing `claude` on a fresh Mac, showing the "Install now?" prompt and then the "Installing Claude Code through mise (first run, can take a minute)..." line. -->

## The log

teeup writes information about every first-run download to `~/.local/state/teeup/logs/lazy.log`.
The log includes a timestamp.
The log records if the download is complete.
If a download stops early, run the command again to start the download again.

## Updates

The tools are in your global mise configuration file, `~/.config/mise/config.toml`.
`teeup update` upgrades the tools and all other mise components.
Read [Updates](updates.md) for more information.

## Remove a tool

```sh
teeup remove ai-codex
teeup remove ai    # all five
```

When you remove a tool, teeup deletes the wrapper script.
teeup removes the tool from the global mise configuration.
When you remove `ai-gemini`, teeup removes `gemini-cli`.
teeup leaves Node in the mise configuration.

If you have a file at `~/.local/bin/<command>` that teeup did not write, teeup does not delete the file.
Claude Code has a native launcher that teeup does not delete.
teeup shows a warning for these files.

If you install the `ai` bundle, the bundle requires the five tools.
If you run `teeup remove ai-codex`, teeup does not accept the command.
teeup shows the message "ai-codex is required by: ai".
To remove all tools, run `teeup remove ai`.

The shim remains after a removal.
If you run the command again, the shim shows the installation prompt.

## Ollama and Herdr

The menu has two other AI capabilities.
Ollama runs models on your local system.
Herdr is a terminal agent multiplexer.
Read [Apps](apps.md) for information about Ollama and Herdr.
