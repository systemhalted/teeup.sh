#!/usr/bin/env bash
# Split the old five-command ai capability into one lazy capability per command.
# A fresh bootstrap has current metadata and marks this migration applied. On an
# existing machine, cap-ai says the old configure completed; each command path
# says which leaf setup still exists. A symlink target is not teeup's to
# inspect or change here, but a teeup-owned wrapper at that path is refreshed
# below so it stops running the retired aggregate's implementation.

if cap_exists ai-claude; then
  if state_done check cap-ai; then
    ai_split_complete=true
    for ai_split_pair in \
      ai-claude:claude \
      ai-codex:codex \
      ai-gemini:gemini \
      ai-copilot:copilot \
      ai-opencode:opencode
    do
      ai_split_leaf="${ai_split_pair%%:*}"
      ai_split_command="${ai_split_pair#*:}"
      ai_split_path="$HOME/.local/bin/$ai_split_command"
      if [[ -e "$ai_split_path" || -L "$ai_split_path" ]]; then
        state_done mark "cap-$ai_split_leaf"
        # The path existing only proves the leaf's old command still works,
        # not that its wrapper carries the current implementation: the
        # aggregate `ai` capability last wrote it, so it predates the
        # per-leaf progress line, retry and lazy log. migration_refresh runs
        # the leaf's own configure (mise_wrapper_write), which rewrites only
        # a teeup-owned wrapper and leaves a foreign file alone; it is also
        # the DRY_RUN guard, since a preview mark leaves the leaf undone and
        # migration_refresh then has nothing to refresh.
        migration_refresh "$ai_split_leaf"
      else
        ai_split_complete=false
        warn "The legacy ai setup has no $ai_split_path, so $ai_split_leaf was left unmarked."
      fi
    done
    if [[ "$ai_split_complete" != "true" ]]; then
      state_done clear cap-ai
      warn "The legacy ai setup is incomplete. Its working commands were kept; repair the bundle with: teeup install ai"
    fi
  fi
fi

# Existing teeup-runtime state may contain `lazy-run ai <command>` shims. The
# current configure regenerates managed shims from the five leaf provides= rows
# and leaves foreign files alone. Fixture trees used by CLI tests may omit it.
if cap_exists teeup-runtime; then
  migration_refresh teeup-runtime
fi
