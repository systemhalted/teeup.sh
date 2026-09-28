# Company CA bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and maintain a macOS PEM bundle containing Apple's public roots plus only administrator-trusted System-keychain certificates, then expose it safely to teeup and command-line tools.

**Architecture:** A new `lib/certs.sh` is the single owner of trust discovery, atomic generation, environment defaults, freshness checks, and removal. A core `ca-bundle` capability presents that library through teeup's lifecycle, while `bootstrap` and `teeup update` call it before network access. Teeup's persisted environment sources the same library so shells and lazy shims share the rules.

**Tech Stack:** Bash 3.2, macOS `security` and `plutil`, BSD/POSIX text tools, teeup's capability and doctor APIs, mdBook, and the shell mock harness.

**Spec:** `docs/superpowers/specs/2026-09-28-company-ca-bundle-design.md`

## Global Constraints

- Preserve Bash 3.2 and macOS BSD-tool compatibility.
- Set certificate environment variables only when they are unset.
- Never treat every certificate in `/Library/Keychains/System.keychain` as trusted.
- A failed or empty export never replaces a working bundle.
- Generated files are staged and moved within `$TEEUP_STATE_DIR`.
- Tests write only below their temporary home and mock every macOS-only command on Linux.
- Prose follows the repository's plain-language rules and avoids the patterns banned by the supplied `AGENTS.md`.
- Commit messages contain no attribution trailers.

## Review Focus

1. A non-trusted certificate from `System.keychain` must not enter the bundle.
2. A partial `security` or `plutil` failure must not truncate a previous bundle.
3. User-set empty or non-empty environment variables must remain untouched.
4. Update must rebuild before `git pull`, including when the existing bundle is stale.
5. A Mac whose administrator trust domain becomes empty must stop exporting teeup's paths.

---

### Task 1: Specify bundle extraction and environment behavior

**Files:**
- Create: `tests/capabilities/ca-bundle.sh`
- Modify: `tests/helper.sh`

**Interfaces:**
- Consumes: the test harness's temporary `HOME`, `MOCK_BIN`, and command mocks.
- Produces: fixtures for `security dump-trust-settings -d`, `security trust-settings-export -d`, both `find-certificate` forms, and `plutil`; behavioral tests for the public library API.

- [ ] Add tests whose hand-written fixtures contain one system root, two System-keychain certificates, and one trusted SHA-1 hash.
- [ ] Assert that no administrator roots produce neither generated files nor environment exports.
- [ ] Assert that one administrator root produces the public root plus only the matching private root and a curl configuration pointing at the bundle.
- [ ] Assert that a second byte-identical build preserves mtime.
- [ ] Assert that failed and empty exports preserve an existing known-good bundle.
- [ ] Assert that a user-set environment variable, including an explicitly empty value, is not overwritten.
- [ ] Run `bash tests/capabilities/ca-bundle.sh` and confirm failure because the library and capability do not exist.

### Task 2: Implement the library and capability lifecycle

**Files:**
- Create: `lib/certs.sh`
- Modify: `lib/all.sh`
- Create: `capabilities/ca-bundle/capability`
- Create: `capabilities/ca-bundle/install`
- Create: `capabilities/ca-bundle/configure`
- Create: `capabilities/ca-bundle/doctor`
- Create: `capabilities/ca-bundle/remove`
- Modify: `capabilities/core.list`
- Modify: `lib/uninstall.sh`

**Interfaces:**
- Produces: `ca_bundle_path`, `ca_bundle_curlrc_path`, `ca_bundle_rebuild`, `ca_bundle_apply_env`, `ca_bundle_remove`, and `ca_bundle_is_current`.
- Consumes: `is_macos`, `run_cmd`, doctor reporting helpers, and `$TEEUP_STATE_DIR`.

- [ ] Parse SHA-1 trust-list keys from the exported admin-domain plist after `plutil` conversion.
- [ ] Filter `security find-certificate -a -Z -p` PEM records by those hashes.
- [ ] Stage validated bundle and curlrc content beside their destinations, compare with existing content, and move only changed files.
- [ ] Remove generated state only after a successful empty-domain determination.
- [ ] Apply the six certificate variables only when their names are unset and their generated files exist.
- [ ] Add the capability after `xcode-clt`, including doctor and remove behavior, and register the two top-level state files with uninstall.
- [ ] Run the new suite until it passes.

### Task 3: Integrate early refresh and certificate-specific update guidance

**Files:**
- Modify: `bootstrap`
- Modify: `bin/teeup`
- Modify: `capabilities/teeup-runtime/configure`
- Modify: `tests/cli.sh`
- Modify: `tests/bootstrap.sh`

**Interfaces:**
- Consumes: `ca_bundle_rebuild` and the source-time environment behavior from Task 2.
- Produces: refresh-before-network ordering for update/bootstrap and persisted shell loading through `$TEEUP_CONFIG_DIR/env`.

- [ ] Add a CLI test whose `security` mock records rebuild work and whose `git` mock proves pull happens later.
- [ ] Add a CLI test whose failed pull includes `certificate` and assert proxy/configure/doctor guidance.
- [ ] Add a bootstrap ordering test that proves trust export precedes package-manager work.
- [ ] Run the changed CLI/bootstrap tests and confirm their intended failures.
- [ ] Call rebuild at the beginning of update and before bootstrap's package-manager step.
- [ ] Capture failed pull text and print the certificate-specific explanation while preserving ordinary failure behavior.
- [ ] Make the generated teeup environment source `lib/certs.sh`.
- [ ] Run the changed tests until green.

### Task 4: Document behavior and run release gates

**Files:**
- Create: `docs/manual/src/company-certificates.md`
- Modify: `docs/manual/src/SUMMARY.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Documents: automatic behavior, generated paths, all environment variables, `local.zsh` overrides, and repair commands.

- [ ] Add the manual page under Configuration and the unreleased changelog entry.
- [ ] Run `tests/docs.sh`, the ca-bundle suite, CLI, and bootstrap under default Bash and the Bash 3.2 test path; run bootstrap only once at the final stage.
- [ ] Run shellcheck at warning severity on every changed shell file.
- [ ] Run `git diff --check` and `./bin/teeup commands --check`.
- [ ] Run `TEEUP_TEST_JOBS=2 ./tests/run.sh` once.
- [ ] Run `mise exec mdbook@latest -- mdbook build docs/manual`.
- [ ] Review the complete branch, fix Important or Critical findings through a failing test, and commit the finished work without trailers.
