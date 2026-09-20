# migrations

One-off changes for machines that already run teeup. Each file is
`<unix-epoch>.sh`, created with `teeup dev add-migration`, and
`teeup update` runs the pending ones oldest first, once per machine.

A migration runs as `bash -eu` with `lib/all.sh` loaded and the answers
sourced, so `run_cmd`, `log`, `warn`, `answers_get` and the capability
helpers are available. Every mutation goes through `run_cmd` or a
primitive with its own dry-run guard, because a dry run
(`DRY_RUN=true teeup update`) must change nothing.

A shipped config file changed? Call `migration_refresh <capability>`: it
re-runs that capability's `configure` with the stock-checksum rule in
force, so a copy nobody edited is replaced (rendered by the same code
that installed it) and an edited one is left alone. Patch an edited file
minimally, after `backup_copy <file>`.

A fresh `./bootstrap` marks every migration here applied without running
it: the capabilities have just installed the state they lead to.
